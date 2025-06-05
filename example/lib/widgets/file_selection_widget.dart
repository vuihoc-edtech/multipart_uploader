import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class FileSelectionWidget extends StatelessWidget {
  final File? selectedFile;
  final bool isUploading;
  final Function(File file) onFileSelected;
  final VoidCallback onResetUpload;

  const FileSelectionWidget({
    super.key,
    this.selectedFile,
    required this.isUploading,
    required this.onFileSelected,
    required this.onResetUpload,
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
              'Chọn Video',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (selectedFile == null)
              ElevatedButton.icon(
                onPressed: isUploading
                    ? null
                    : () async {
                        final file = await pickVideoFile(context);
                        if (file != null) {
                          onFileSelected(file);
                        }
                      },
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
                        const Icon(Icons.videocam, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedFile!.path.split('/').last,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              FutureBuilder<int>(
                                future: selectedFile!.length(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    final size = (snapshot.data! / 1024 / 1024)
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
                          onPressed: isUploading ? null : onResetUpload,
                          icon: const Icon(Icons.close, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Static helper method to pick a file
  static Future<File?> pickVideoFile(BuildContext context) async {
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
        return await asset.file;
      }
    } catch (e) {
      // Let the caller handle the error
      print('Error picking file: $e');
    }
    return null;
  }
}
