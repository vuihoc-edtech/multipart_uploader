import 'package:dio/dio.dart';

Dio get dioDownloader => Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 120),
        persistentConnection: true,
        maxRedirects: 3,
        headers: {
          'Connection': 'keep-alive',
          'Keep-Alive': 'timeout=30, max=100',
        },
      ),
    );
