import 'package:flutter/material.dart';

class UploadControlsWidget extends StatelessWidget {
  final bool isUploading;
  final int uploadProgress;
  final VoidCallback onUpload;

  const UploadControlsWidget({
    super.key,
    required this.isUploading,
    required this.uploadProgress,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
            if (isUploading) ...[
              LinearProgressIndicator(
                value: uploadProgress / 100,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Đang upload... $uploadProgress%',
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 12),

            // Upload Button
            ElevatedButton.icon(
              onPressed: isUploading ? null : onUpload,
              icon: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(
                isUploading ? 'Đang Upload...' : 'Upload Video',
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
    );
  }
}
