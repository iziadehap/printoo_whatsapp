import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  static final _dio = Dio(
    BaseOptions(
      baseUrl: 'http://localhost:3000',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint(
            '[API →] ${options.method} ${options.uri}',
          );
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '[API ✓] ${response.statusCode} ${response.requestOptions.method} '
            '${response.requestOptions.uri}',
          );
          handler.next(response);
        },
        onError: (DioException err, handler) {
          final method = err.requestOptions.method;
          final uri = err.requestOptions.uri;
          final status = err.response?.statusCode ?? 'no-response';
          final msg = err.message ?? err.type.name;
          final body = err.response?.data;

          debugPrint(
            '[API ✗] $method $uri  →  status=$status  message=$msg',
          );
          if (body != null) {
            debugPrint('[API ✗]   response body: $body');
          }

          handler.next(err);
        },
      ),
    );

  static Dio get dio => _dio;
}
