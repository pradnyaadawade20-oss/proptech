import 'package:dio/dio.dart';
import '../../app/router/app_router.dart';
import '../../app/router/route_names.dart';
import '../session/user_session.dart';
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
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
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
        onError: (error, handler) async {
          // Saved login expired/invalid (401 on a call that carried a token,
          // not a login call) -> clear it and send the user to login.
          final sentToken = error.requestOptions.headers['Authorization'] != null;
          final isAuthCall = error.requestOptions.path.startsWith('/api/auth');
          if (error.response?.statusCode == 401 && sentToken && !isAuthCall) {
            await TokenStore.instance.clear();
            UserSession.instance.reset();
            appRouter.go(RouteNames.login);
          }
          handler.next(error);
        },
      ),
    );

    return dio;
  }
}