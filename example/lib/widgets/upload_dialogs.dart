import 'package:flutter/material.dart';

class UploadDialogs {
  /// Hiển thị dialog cho phép user continue upload
  static void showContinueDialog({
    required BuildContext context,
    required VoidCallback onContinue,
    required VoidCallback onCancel,
  }) {
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
              onCancel();
            },
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onContinue();
            },
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
  }

  /// Hiển thị dialog lỗi
  static void showErrorDialog({
    required BuildContext context,
    required String message,
  }) {
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
}
