import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multipart_uploader/multipart_uploader.dart';

// Widget Components
import 'widgets/file_selection_widget.dart';
import 'widgets/upload_controls_widget.dart';
import 'widgets/status_message_widgets.dart';
import 'widgets/upload_dialogs.dart';

/// Cấu hình Dio với baseUrl và token từ environment variables
/// Bạn cần cấu hình BASE_URL và TOKEN khi build ứng dụng
const baseUrl = String.fromEnvironment('BASE_URL');
const token = String.fromEnvironment('TOKEN');
final option = BaseOptions(
  baseUrl: baseUrl,
  headers: {'Authorization': 'Bearer $token'},
);

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  // Cấu hình S3 Uploader - Đây là phần chính cần demo
  final _uploader = MultipartUploader();

  // UI State
  File? _selectedFile;
  bool _isUploading = false;
  bool _canContinue = false;
  int _uploadProgress = 0;
  String? _uploadedUrl;
  String? _errorMessage;
  int duration = 0;

  /// Lấy link upload từ server
  /// Trả về UploadResponse chứa thông tin upload lên S3
  Future<UploadResponse> _getUploadLink(File file) async {
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();
    final query = {
      'resourceName': Uri.encodeComponent(fileName),
      'size': fileSize
    };
    final response = await Dio(option).get(
      '/api/project-assignment/upload-link',
      queryParameters: query,
    );

    print(response.data);

    return UploadResponse.fromJson(response.data['data']);
  }

  /// Upload file lên S3
  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _errorMessage = null;
      _uploadedUrl = null;
      _canContinue = false;
    });

    try {
      final uploadResponse = await _getUploadLink(_selectedFile!);
      final startTime = DateTime.now();

      // Upload file với progress callback và auto-tuning
      final uploadedUrl = await _uploader.uploadFileOptimizedWithAutoTuning(
        _selectedFile!,
        uploadResponse: uploadResponse,
        onProgress: (progress) => setState(() => _uploadProgress = progress),
        onError: (error, st) => print('Upload error: $error\n$st'),
      );

      duration = DateTime.now().difference(startTime).inSeconds;

      // Upload thành công
      setState(() {
        _uploadedUrl = uploadedUrl;
        _isUploading = false;
        _canContinue = false;
      });
    } catch (e, st) {
      // Kiểm tra xem có phải lỗi network timeout không
      final isNetworkTimeout =
          e.toString().contains('Network appears to be down') ||
              e.toString().contains('continueUpload');

      print('Upload thất bại: $e\n$st');
      setState(() {
        _errorMessage = 'Upload thất bại: $e\n$st';
        _isUploading = false;
        _canContinue =
            isNetworkTimeout && _uploader.status == UploaderStatus.failed;
      });

      if (_canContinue) {
        _showContinueDialog();
      }
    }
  }

  /// Continue upload sau khi bị dừng do network timeout
  Future<void> _continueUpload() async {
    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _canContinue = false;
    });

    try {
      final uploadedUrl =
          await _uploader.continueUpload(onProgress: (progress) {
        setState(() {
          _uploadProgress = progress;
        });
      });

      // Upload thành công
      setState(() {
        _uploadedUrl = uploadedUrl;
        _isUploading = false;
      });
    } catch (e) {
      // Kiểm tra xem có phải lỗi network timeout không
      final isNetworkTimeout =
          e.toString().contains('Network appears to be down') ||
              e.toString().contains('continueUpload');

      setState(() {
        _errorMessage = 'Continue upload thất bại: $e';
        _isUploading = false;
        _canContinue =
            isNetworkTimeout && _uploader.status == UploaderStatus.failed;
      });

      if (_canContinue) {
        _showContinueDialog();
      }
    }
  }

  /// Hiển thị dialog cho phép user continue upload
  void _showContinueDialog() {
    UploadDialogs.showContinueDialog(
      context: context,
      onContinue: _continueUpload,
      onCancel: () {
        setState(() {
          _isUploading = false;
          _canContinue = false;
        });
      },
    );
  }

  /// Reset trạng thái upload
  void _resetUpload() {
    setState(() {
      _selectedFile = null;
      _uploadProgress = 0;
      _uploadedUrl = null;
      _errorMessage = null;
      _isUploading = false;
    });
  }

  @override
  void dispose() {
    _uploader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text('BASE_URL: $baseUrl'),
              // File Selection Widget
              FileSelectionWidget(
                selectedFile: _selectedFile,
                isUploading: _isUploading,
                onFileSelected: (file) {
                  setState(() {
                    _selectedFile = file;
                    _uploadedUrl = null;
                    _errorMessage = null;
                    _uploadProgress = 0;
                  });
                },
                onResetUpload: _resetUpload,
              ),

              const SizedBox(height: 20),

              // Upload Indicator
              if (_isUploading || _uploadedUrl != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Upload Progress Details',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                                'Speed: ${_uploader.speed.toStringAsFixed(2)} MB/s'),
                            Text(
                                'File Size: ${(_uploader.fileSize / 1024 / 1024).toStringAsFixed(2)} MB'),
                            Text(
                              'Parts: ${_uploader.parts.length} ${_uploader.status == UploaderStatus.completed ? '(Completed in ${duration}s)' : ''}',
                            ),
                            UploadIndicatorWidget(
                              parts: _uploader.parts,
                              fileSize: _uploader.fileSize,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),

              // Upload Controls
              if (_selectedFile != null)
                UploadControlsWidget(
                  isUploading: _isUploading,
                  uploadProgress: _uploadProgress,
                  onUpload: _uploadFile,
                ),

              const SizedBox(height: 20),

              // Error Message
              if (_errorMessage != null)
                ErrorMessageWidget(
                  errorMessage: _errorMessage!,
                  onContinueUpload: _canContinue ? _continueUpload : null,
                ),

              // Success Message
              if (_uploadedUrl != null)
                SuccessMessageWidget(uploadedUrl: _uploadedUrl!),
            ],
          ),
        ),
      ),
    );
  }
}
