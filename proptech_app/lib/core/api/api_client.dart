import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'token_store.dart';

/// Single Dio instance the whole app uses to talk to the Go backend.
///
/// Base URL notes:
/// - Android emulator can't reach the host machine's "localhost" — it must
///   use 10.0.2.2, which Android maps back to the host.
/// - A physical device (like Pradnya's Vivo, connected over the same
///   Wi-Fi) can't use 10.0.2.2 either — that address only exists inside
///   the emulator's virtual network. It must use the host machine's
///   actual LAN IP instead.
/// - Update [_baseUrl] below once you know how you're running the app.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  // Host machine's LAN IP (from `ipconfig` -> IPv4 Address under the
  // "Wireless LAN adapter Wi-Fi" section specifically — NOT any Ethernet,
  // vEthernet, or WSL adapter, those aren't reachable from the phone).
  // Physical device and PC must be on the same Wi-Fi network.
  // Swap this if the PC's IP changes (e.g. new network, DHCP renewal).
  static const String _lanIp = '192.168.1.30'; // TODO verify this is the Wi-Fi adapter's IP, not a virtual one
  static const int _port = 9091;

  static String get _baseUrl {
    if (kIsWeb) return 'http://localhost:$_port';
    // NOTE: 10.0.2.2 only works for the Android *emulator*, not a real
    // phone. Testing on a physical device (USB or Wi-Fi) always needs the
    // host's actual LAN IP below.
    return 'http://$_lanIp:$_port';
  }

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