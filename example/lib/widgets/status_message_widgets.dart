import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ErrorMessageWidget extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onContinueUpload;

  const ErrorMessageWidget({
    super.key,
    required this.errorMessage,
    this.onContinueUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
            if (onContinueUpload != null)
              ElevatedButton(
                onPressed: onContinueUpload,
                child: const Text('Continue Upload'),
              ),
            Text(errorMessage),
          ],
        ),
      ),
    );
  }
}

class SuccessMessageWidget extends StatelessWidget {
  final String uploadedUrl;

  const SuccessMessageWidget({
    Key? key,
    required this.uploadedUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
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
              uploadedUrl,
              onTap: () => Clipboard.setData(
                ClipboardData(text: uploadedUrl),
              ),
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
