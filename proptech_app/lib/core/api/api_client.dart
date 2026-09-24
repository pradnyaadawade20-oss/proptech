import 'package:dio/dio.dart';
import 'token_store.dart';

/// Single Dio instance the whole app uses to talk to the Go backend.
///
/// Backend is deployed on Render; every platform (web, emulator, physical
/// device, APK) hits this same public HTTPS URL.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String _baseUrl = 'https://proptech-ozo0.onrender.com';

  late final Dio dio = _buildDio();

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStore.instance.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          // Centralized place to handle 401s later (e.g. force logout).
          handler.next(error);
        },
      ),
    );

    return dio;
  }
}