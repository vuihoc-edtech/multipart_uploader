import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multipart_uploader/multipart_uploader.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  // Cấu hình S3 Uploader
  final _uploader = MultipartUploader();

  // UI State
  File? _selectedFile;
  bool _isUploading = false;
  bool _canContinue = false; // Thêm flag để biết có thể continue không
  int _uploadProgress = 0;
  String? _uploadedUrl;
  String? _errorMessage;

  final baseUrl = 'https://devapi.vuihoc.vn';
  final token =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTY5ODYsImlhdCI6MTc0NzEyODU4MywiZXhwIjoxNzUyMzEyNTgzfQ.BU_2bVPdRXi8t5COoEA1hXQFBiVpUAGQhVIiffgfRyo';

  Future<UploadResponse> _getUploadLink(File file) async {
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();

    final response = await Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {'Authorization': 'Bearer $token'},
      ),
    ).get(
      '/api/project-assignment/upload-link',
      queryParameters: {
        'resourceName': Uri.encodeComponent(fileName),
        'size': fileSize,
      },
    );

    return UploadResponse.fromJson(response.data['data']);
  }

  /// Chọn video từ device
  Future<void> _pickFile() async {
    try {
      final List<AssetEntity>? result = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          maxAssets: 1,
          requestType: RequestType.video,
          textDelegate: AssetPickerTextDelegate(),
        ),
      );

      if (result != null && result.isNotEmpty) {
        final AssetEntity asset = result.first;
        final File? file = await asset.file;

        if (file != null) {
          setState(() {
            _selectedFile = file;
            _uploadedUrl = null;
            _errorMessage = null;
            _uploadProgress = 0;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi chọn file: $e';
      });
    }
  }

  Map<int, int> _speedMap = {};

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
      print(
        uploadResponse.s3UploadUrl.map((e) => e.toJson()).toList().join('\n'),
      );

      final limitConcurrentUploads = 5;
      final startTime = DateTime.now();
      // Upload file với progress callback và auto-tuning
      final uploadedUrl = await _uploader.uploadFileOptimizedWithAutoTuning(
        _selectedFile!,
        uploadResponse: uploadResponse,
        onProgress: (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      );
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inSeconds;
      _speedMap[limitConcurrentUploads] = duration;

      print(
        'Upload SPEEDMAP:\n${_speedMap.entries.map((e) => '${e.key} uploads: ${e.value}s').join('\n')}',
      );

      // Upload thành công
      setState(() {
        _uploadedUrl = uploadedUrl;
        _isUploading = false;
        _canContinue = false;
      });

      _showSuccessDialog();
    } catch (e) {
      // Kiểm tra xem có phải lỗi network timeout không
      final isNetworkTimeout =
          e.toString().contains('Network appears to be down') ||
              e.toString().contains('continueUpload');

      setState(() {
        _errorMessage = 'Upload thất bại: $e';
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
      final uploadedUrl = await _uploader.continueUpload(
        onProgress: (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      // Upload thành công
      setState(() {
        _uploadedUrl = uploadedUrl;
        _isUploading = false;
      });

      _showSuccessDialog();
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kết nối mạng không ổn định'),
        content: const Text(
          'Upload đã bị tạm dừng do mất kết nối mạng. '
          'Vui lòng kiểm tra kết nối và bấm "Tiếp tục" để resume upload.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _isUploading = false;
                _canContinue = false;
              });
            },
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _continueUpload();
            },
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
  }

  /// Hiển thị dialog lỗi
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lỗi'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Hiển thị dialog thành công
  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Thành Công!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('File đã được upload thành công.'),
            const SizedBox(height: 8),
            const Text('URL:', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(_uploadedUrl ?? ''),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
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

              // File Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chọn Video',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedFile == null)
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _pickFile,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Chọn Video'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.videocam,
                                      color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedFile!.path.split('/').last,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        FutureBuilder<int>(
                                          future: _selectedFile!.length(),
                                          builder: (context, snapshot) {
                                            if (snapshot.hasData) {
                                              final size =
                                                  (snapshot.data! / 1024 / 1024)
                                                      .toStringAsFixed(2);
                                              return Text(
                                                'Kích thước: ${size} MB',
                                              );
                                            }
                                            return const Text(
                                              'Đang tính kích thước...',
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed:
                                        _isUploading ? null : _resetUpload,
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              // Upload Indicator
              UploadIndicatorWidget(
                parts: _uploader.parts,
                fileSize: _uploader.fileSize,
              ),
              Text('${_uploader.speed} MB/s'),
              const SizedBox(height: 20),

              // Upload Section
              if (_selectedFile != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Upload',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Progress Bar
                        if (_isUploading) ...[
                          LinearProgressIndicator(
                            value: _uploadProgress / 100,
                            backgroundColor: Colors.grey[300],
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Đang upload... $_uploadProgress%',
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Upload Button
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _uploadFile,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: Text(
                            _isUploading ? 'Đang Upload...' : 'Upload Video',
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Results
              if (_errorMessage != null)
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Lỗi',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () {
                            // Continue upload logic
                          },
                          child: const Text('Continue Upload'),
                        ),
                        Text(_errorMessage!),
                      ],
                    ),
                  ),
                ),

              if (_uploadedUrl != null)
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Thành Công',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('File URL:'),
                        const SizedBox(height: 4),
                        SelectableText(
                          _uploadedUrl!,
                          onTap: () => Clipboard.setData(
                            ClipboardData(text: _uploadedUrl!),
                          ),
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
