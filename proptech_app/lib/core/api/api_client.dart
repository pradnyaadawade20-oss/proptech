import 'package:dio/dio.dart';
import '../../app/router/app_router.dart';
import '../../app/router/route_names.dart';
import '../../features/call/call_service.dart';
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

  /// Public so the call socket (wss://) can reuse the same host.
  static String get baseUrl => _baseUrl;

  late final Dio dio = _buildDio();
  bool _redirectingToLogin = false;

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
          // 401 on a protected call = the saved login is expired/invalid, OR it
          // is gone entirely (secure storage was reset -> no Authorization header
          // at all). Either way: clear it and send the user to login, once.
          final isAuthCall = error.requestOptions.path.startsWith('/api/auth');
          if (error.response?.statusCode == 401 && !isAuthCall && !_redirectingToLogin) {
            final here = appRouter.routerDelegate.currentConfiguration.uri.path;
            const publicPaths = {
              RouteNames.splash,
              RouteNames.onboarding,
              RouteNames.login,
              RouteNames.otpVerification,
              RouteNames.forgotPassword,
            };
            if (!publicPaths.contains(here)) {
              _redirectingToLogin = true;
              try {
                await CallService.instance.disconnect();
                await TokenStore.instance.clear();
                UserSession.instance.reset();
                appRouter.go(RouteNames.login);
              } finally {
                Future.delayed(const Duration(seconds: 2), () => _redirectingToLogin = false);
              }
            }
          }
          handler.next(error);
        },
      ),
    );

    return dio;
  }
}