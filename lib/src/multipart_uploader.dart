import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:multipart_uploader/src/helper.dart';
import 'package:multipart_uploader/src/semaphore.dart';

import 'model/enum.dart';
import 'model/upload_part.dart';
import 'model/upload_response.dart';
import 'network_metrics.dart';

class MultipartUploader {
  final Dio _dio;
  final int defaultMaxConcurrentUploads;
  final _networkMetrics = NetworkMetrics();

  int get speed => _networkMetrics.averageSpeedMBps.round();

  final List<UploadPart> parts = [];
  int fileSize = 0;

  // Lưu thông tin upload session để có thể continue
  File? _currentFile;
  String? _s3Link;

  // Trạng thái toàn cục của uploader
  UploaderStatus _status = UploaderStatus.idle;
  int _remainingRetries = 0;

  // Circuit breaker để tránh retry storm
  int _consecutiveFailures = 0;
  DateTime? _lastFailureTime;
  DateTime? _circuitBreakerOpenTime;
  static const int _maxConsecutiveFailures = 5;
  static const Duration _circuitBreakerCooldown = Duration(seconds: 10);
  static const Duration _maxCircuitBreakerWait = Duration(seconds: 10);

  UploaderStatus get status => _status;
  int get remainingRetries => _remainingRetries;

  // Progress tracking optimization
  DateTime _lastProgressUpdate = DateTime.now();
  static const _progressUpdateInterval = Duration(milliseconds: 100);

  MultipartUploader({
    Dio? dio,
    this.defaultMaxConcurrentUploads = 3,
  }) : _dio = dio ?? dioDownloader;

  /// Upload file to S3 với progress callback và giới hạn số upload song song
  Future<String> uploadFile(
    File file, {
    required UploadResponse uploadResponse,
    Function(int progress)? onProgress,
    Function(Exception error)? onError,
    int? maxConcurrentUploads,
    int maxRetries = 3,
  }) async {
    final concurrentLimit = maxConcurrentUploads ?? defaultMaxConcurrentUploads;

    // Setup upload session
    _status = UploaderStatus.uploading;
    _remainingRetries = maxRetries;
    _currentFile = file;
    _s3Link = uploadResponse.s3Link;

    fileSize = await file.length();
    parts.clear();
    parts.addAll(uploadResponse.s3UploadUrl);

    try {
      await _uploadParts(file, parts, onProgress, concurrentLimit, maxRetries);

      _status = UploaderStatus.completed;
      _clearSession();
      return uploadResponse.s3Link;
    } catch (e, st) {
      _status = UploaderStatus.failed;
      final exception = Exception('Upload failed: $e');

      if (kDebugMode) {
        print('Error during file upload: $e\n$st');
      }

      // Gọi onError callback nếu có
      if (onError != null) {
        onError(exception);
      }

      throw exception;
    }
  }

  /// Tính toán số lượng upload song song tối ưu dựa trên kích thước file
  static int calculateOptimalConcurrency(int fileSizeBytes) {
    // File nhỏ (< 10MB): upload tuần tự để tránh overhead
    if (fileSizeBytes < 10 * 1024 * 1024) {
      return 1;
    }
    // File trung bình (10MB - 100MB): upload song song vừa phải
    else if (fileSizeBytes < 100 * 1024 * 1024) {
      return 3;
    }
    // File lớn (100MB - 1GB): tăng song song để tăng tốc
    else if (fileSizeBytes < 1024 * 1024 * 1024) {
      return 5;
    }
    // File rất lớn (> 1GB): upload song song cao nhất
    else {
      return 8;
    }
  }

  /// Upload file với auto-tuning số lượng upload song song
  Future<String> uploadFileOptimized(
    File file, {
    required UploadResponse uploadResponse,
    Function(int progress)? onProgress,
    Function(Exception error)? onError,
    int maxRetries = 3,
  }) async {
    fileSize = await file.length();
    final optimalConcurrency = calculateOptimalConcurrency(fileSize);

    return uploadFile(
      file,
      uploadResponse: uploadResponse,
      onProgress: onProgress,
      onError: onError,
      maxConcurrentUploads: optimalConcurrency,
      maxRetries: maxRetries,
    );
  }

  /// Upload file với auto-tuning động dựa trên network speed
  Future<String> uploadFileOptimizedWithAutoTuning(
    File file, {
    required UploadResponse uploadResponse,
    Function(int progress)? onProgress,
    Function(Exception error)? onError,
    int maxRetries = 3,
  }) async {
    fileSize = await file.length();
    final baseConcurrency = calculateOptimalConcurrency(fileSize);

    // Bắt đầu với base concurrency thay vì dynamic
    int currentConcurrency = baseConcurrency;

    // Nếu có metrics từ trước, áp dụng ngay
    if (_networkMetrics.hasMetrics) {
      currentConcurrency = _calculateDynamicConcurrency(baseConcurrency);
    }

    if (kDebugMode) {
      print('File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
      print('Base concurrency: $baseConcurrency');
      if (_networkMetrics.hasMetrics) {
        print('Dynamic concurrency: $currentConcurrency');
        print(
            'Average network speed: ${_networkMetrics.averageSpeedMBps.toStringAsFixed(2)} MB/s');
      } else {
        print(
            'No network metrics available, starting with base concurrency: $currentConcurrency');
      }
    }

    return uploadFile(
      file,
      uploadResponse: uploadResponse,
      onProgress: onProgress,
      onError: onError,
      maxConcurrentUploads: currentConcurrency,
      maxRetries: maxRetries,
    );
  }

  /// Upload từng part của file với Semaphore và retry thông minh
  Future<void> _uploadParts(
    File file,
    List<UploadPart> parts,
    Function(int progress)? onProgress,
    int maxConcurrentUploads,
    int maxRetries,
  ) async {
    var currentConcurrency = maxConcurrentUploads;
    final semaphore = Semaphore(currentConcurrency);

    // Lấy các parts cần upload (chưa bắt đầu hoặc bị fail, KHÔNG bao gồm inProgress)
    final partsToUpload = parts
        .where((part) =>
            part.status == PartStatus.notStarted ||
            part.status == PartStatus.failed)
        .toList();

    if (partsToUpload.isEmpty) {
      return; // Tất cả parts đã completed hoặc đang inProgress
    }

    if (kDebugMode) {
      print(
          'Uploading ${partsToUpload.length} parts (remaining retries: $maxRetries)');
    }

    // Function để update progress với throttling
    void updateProgress() {
      if (onProgress != null) {
        final now = DateTime.now();
        if (now.difference(_lastProgressUpdate) >= _progressUpdateInterval) {
          final totalUploaded = parts.fold(
            0,
            (sum, part) => sum + part.uploadedBytes,
          );
          final percent = ((totalUploaded * 100) / fileSize).round();
          onProgress(percent.clamp(0, 100));
          _lastProgressUpdate = now;
        }
      }
    }

    // Adaptive concurrency adjustment
    int uploadedPartsCount = 0;
    void checkAndAdjustConcurrency() {
      uploadedPartsCount++;

      // Sau khi upload được 2-3 parts, điều chỉnh concurrency
      if (uploadedPartsCount >= 2 && _networkMetrics.hasMetrics) {
        final baseConcurrency = calculateOptimalConcurrency(fileSize);
        final newConcurrency = _calculateDynamicConcurrency(baseConcurrency);

        if (newConcurrency != currentConcurrency) {
          if (kDebugMode) {
            print(
                'Adjusting concurrency from $currentConcurrency to $newConcurrency '
                'based on network speed: ${_networkMetrics.averageSpeedMBps.toStringAsFixed(2)} MB/s');
          }
          // Update semaphore capacity
          semaphore.updateCapacity(newConcurrency);
          currentConcurrency = newConcurrency;
        }
      }
    }

    // Kiểm tra circuit breaker trước khi bắt đầu upload batch
    if (_isCircuitBreakerOpen()) {
      if (kDebugMode) {
        print('Circuit breaker is open, skipping upload attempts...');
      }

      // Đánh dấu tất cả parts là failed để trigger retry logic
      for (final part in partsToUpload) {
        part.status = PartStatus.failed;
      }

      // Check timeout ngay lập tức
      if (_isCircuitBreakerTimeout()) {
        _status = UploaderStatus.failed;
        throw Exception(
            'Network appears to be down. Upload paused after ${_maxCircuitBreakerWait.inSeconds} seconds. '
            'Please check your connection and use continueUpload() to resume.');
      }

      // Nếu chưa timeout, return để trigger retry logic bên dưới
      return;
    }

    // Upload parts song song với semaphore
    final futures = partsToUpload.map((part) async {
      await semaphore.acquire();
      try {
        await _uploadSinglePartWithRetry(file, part, () => updateProgress());
        part.status = PartStatus.completed;
        part.isUploaded = true;

        // Reset consecutive failures khi thành công
        _consecutiveFailures = 0;

        // Reset network metrics nếu đã recovery từ network issues
        _resetNetworkMetricsIfNeeded();

        // Check và điều chỉnh concurrency sau mỗi part thành công
        checkAndAdjustConcurrency();
      } catch (e) {
        part.status = PartStatus.failed;
        _consecutiveFailures++;
        _lastFailureTime = DateTime.now();

        if (kDebugMode) {
          print(
              'Part ${part.id} failed: $e (consecutive failures: $_consecutiveFailures)');
        }
      } finally {
        semaphore.release();
      }
    }).toList();

    await Future.wait(futures);

    // Check xem còn failed parts không
    final failedParts =
        parts.where((part) => part.status == PartStatus.failed).toList();

    if (failedParts.isNotEmpty) {
      if (maxRetries > 0) {
        // Check circuit breaker trước khi retry
        if (_isCircuitBreakerOpen()) {
          if (kDebugMode) {
            print('Circuit breaker is open, checking timeout...');
          }

          // Check xem đã quá thời gian chờ chưa (10 giây)
          if (_isCircuitBreakerTimeout()) {
            _status = UploaderStatus.failed;
            throw Exception(
                'Network appears to be down. Upload paused after ${_maxCircuitBreakerWait.inSeconds} seconds. '
                'Please check your connection and use continueUpload() to resume.');
          }

          // Nếu chưa timeout, chờ cooldown và retry
          if (kDebugMode) {
            print(
                'Circuit breaker waiting for cooldown (${_circuitBreakerCooldown.inSeconds}s)...');
          }
          await Future.delayed(_circuitBreakerCooldown);
        }

        // Giảm retry và gọi đệ quy
        _remainingRetries = maxRetries - 1;

        if (kDebugMode) {
          print(
              '${failedParts.length} parts failed, retrying... (${maxRetries - 1} retries left)');
        }

        // Tăng delay theo số lần retry để tránh retry storm
        final backoffDelay = Duration(seconds: (4 - maxRetries) * 2 + 1);
        await Future.delayed(backoffDelay);

        // Gọi đệ quy với maxRetries giảm đi 1
        await _uploadParts(
            file, parts, onProgress, maxConcurrentUploads, maxRetries - 1);
      } else {
        // Hết retry attempts, set status failed
        _status = UploaderStatus.failed;
        throw Exception(
          'Upload failed after all retry attempts. Failed parts: ${failedParts.map((p) => p.id).join(', ')}',
        );
      }
    } else {
      // Tất cả parts đã thành công
      if (onProgress != null) {
        onProgress(100);
      }
    }
  }

  /// Upload một part với retry logic và exponential backoff
  Future<void> _uploadSinglePartWithRetry(
    File file,
    UploadPart part,
    Function() onProgress, {
    int maxRetries = 2, // Giảm từ 3 xuống 2 vì có retry ở level cao hơn
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        part.status = PartStatus.inProgress;
        final startTime = DateTime.now();

        await _uploadSinglePartStreaming(file, part, (sent) {
          part.uploadedBytes = sent;
          onProgress();
        });

        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        _networkMetrics.updateSpeed(part.length, duration);

        return; // Success
      } catch (e) {
        if (attempt == maxRetries) {
          throw Exception(
            'Failed to upload part ${part.id} after $maxRetries retries: $e',
          );
        }

        // Exponential backoff với randomization để tránh thundering herd
        final baseDelay = 1000 * (1 << attempt);
        final jitter = (baseDelay *
                0.1 *
                (DateTime.now().millisecondsSinceEpoch % 100) /
                100)
            .round();
        final delay = Duration(milliseconds: baseDelay + jitter);

        if (kDebugMode) {
          print(
            'Retry ${attempt + 1}/$maxRetries for part ${part.id} after ${delay.inMilliseconds}ms',
          );
        }
        await Future.delayed(delay);

        // Reset progress on retry
        part.uploadedBytes = 0;
        part.status = PartStatus.notStarted;
      }
    }
  }

  /// Upload một part với streaming để tiết kiệm memory
  Future<void> _uploadSinglePartStreaming(
    File file,
    UploadPart part,
    Function(int sent)? onProgress,
  ) async {
    final stream = file.openRead(part.offset, part.offset + part.length);

    await _dio.put(
      part.url,
      data: stream,
      options: Options(
        headers: {
          'Content-Type': _getContentType(file.path),
          'Content-Length': part.length.toString(),
        },
      ),
      onSendProgress: (sent, total) {
        if (onProgress != null) {
          onProgress(sent);
        }
      },
    );
  }

  /// Auto-tuning concurrency dựa trên network speed
  int _calculateDynamicConcurrency(int baseConcurrency) {
    if (!_networkMetrics.hasMetrics) {
      return baseConcurrency;
    }

    final speed = _networkMetrics.averageSpeedMBps;

    // Nếu có quá nhiều failures liên tiếp, giảm concurrency mạnh
    if (_consecutiveFailures >= 3) {
      return 1;
    }

    if (speed < 1.0) {
      // Mạng chậm - giảm concurrency
      return max(1, (baseConcurrency * 0.7).round());
    } else if (speed > 5.0) {
      // Mạng nhanh - tăng concurrency
      return min(10, (baseConcurrency * 1.3).round());
    }

    return baseConcurrency;
  }

  /// Check xem circuit breaker có đang mở không
  bool _isCircuitBreakerOpen() {
    if (_consecutiveFailures < _maxConsecutiveFailures) {
      return false;
    }

    if (_lastFailureTime == null) {
      return false;
    }

    // Lần đầu mở circuit breaker, ghi lại thời gian (chỉ set một lần)
    if (_circuitBreakerOpenTime == null) {
      _circuitBreakerOpenTime =
          _lastFailureTime; // Dùng thời gian của failure cuối cùng
      if (kDebugMode) {
        print('Circuit breaker opened at: $_circuitBreakerOpenTime');
      }
    }

    final timeSinceLastFailure = DateTime.now().difference(_lastFailureTime!);
    return timeSinceLastFailure < _circuitBreakerCooldown;
  }

  /// Check xem đã quá thời gian chờ circuit breaker chưa (10 giây)
  bool _isCircuitBreakerTimeout() {
    if (_circuitBreakerOpenTime == null) {
      return false;
    }

    final timeSinceOpen = DateTime.now().difference(_circuitBreakerOpenTime!);
    final hasTimedOut = timeSinceOpen >= _maxCircuitBreakerWait;

    if (kDebugMode && hasTimedOut) {
      print(
          'Circuit breaker timeout reached: ${timeSinceOpen.inSeconds}s >= ${_maxCircuitBreakerWait.inSeconds}s');
    }

    return hasTimedOut;
  }

  /// Reset network metrics khi phát hiện mạng đã ổn định trở lại
  void _resetNetworkMetricsIfNeeded() {
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      if (kDebugMode) {
        print('Resetting network metrics due to network recovery');
      }
      _networkMetrics.reset();
      _consecutiveFailures = 0;
    }
  }

  /// Xác định content type dựa trên file extension
  String _getContentType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      // Images
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';

      // Videos
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      case 'flv':
        return 'video/x-flv';

      // Audio
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'aac':
        return 'audio/aac';

      // Documents
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

      default:
        return 'application/octet-stream';
    }
  }

  /// Lấy progress hiện tại (0-100)
  int get currentProgress {
    if (parts.isEmpty || fileSize == 0) return 0;

    final totalUploaded = parts.fold(
      0,
      (sum, part) => sum + part.uploadedBytes,
    );
    return ((totalUploaded * 100) / fileSize).round().clamp(0, 100);
  }

  /// Hàm continue để thử lại upload khi status là failed
  Future<String> continueUpload({
    Function(int progress)? onProgress,
    Function(Exception error)? onError,
    int? maxConcurrentUploads,
  }) async {
    if (_status != UploaderStatus.failed) {
      throw Exception('Cannot continue upload. Current status: $_status');
    }

    if (parts.isEmpty || _currentFile == null || _s3Link == null) {
      throw Exception('No upload session found to continue');
    }

    // Reset circuit breaker state khi user chủ động continue
    _consecutiveFailures = 0;
    _lastFailureTime = null;
    _circuitBreakerOpenTime = null;

    // Reset status và thử lại với 1 retry
    _status = UploaderStatus.uploading;
    _remainingRetries = 1;

    final concurrentLimit = maxConcurrentUploads ?? defaultMaxConcurrentUploads;

    try {
      await _uploadParts(_currentFile!, parts, onProgress, concurrentLimit, 1);

      _status = UploaderStatus.completed;
      final s3Link = _s3Link!;
      _clearSession();

      return s3Link;
    } catch (e, st) {
      _status = UploaderStatus.failed;
      if (kDebugMode) {
        print('Error during continue upload: $e\n$st');
      }

      final exception = Exception('Continue upload failed: $e');

      // Gọi onError callback nếu có
      if (onError != null) {
        onError(exception);
      }

      throw exception;
    }
  }

  /// Clear upload session
  void _clearSession() {
    _currentFile = null;
    _s3Link = null;
    _remainingRetries = 0;
    _consecutiveFailures = 0;
    _lastFailureTime = null;
    _circuitBreakerOpenTime = null;
  }

  /// Resource cleanup
  void dispose() {
    _dio.close();
    parts.clear();
    _clearSession();
  }
}
