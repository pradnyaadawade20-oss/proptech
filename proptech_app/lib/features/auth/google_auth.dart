import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';
import '../properties/property_store.dart';
import 'auth_service.dart' show AuthResult;

/// Web OAuth client ID (Firebase console -> Authentication -> Sign-in method
/// -> Google -> Web SDK configuration; also the client with client_type 3 in
/// google-services.json). Paste it here or pass
/// --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
const String kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '544072846065-o5b43q1sd2jbk0hkea2sg408htpkfpc1.apps.googleusercontent.com',
);

class GoogleAuth {
  GoogleAuth._();
  static final GoogleAuth instance = GoogleAuth._();

  bool get configured => !kGoogleWebClientId.startsWith('PASTE_');

  /// Returns null when the person closed the account picker.
  Future<AuthResult?> signIn() async {
    try {
      final google = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: kGoogleWebClientId,
      );
      // Forget the last account so the picker shows every time.
      try {
        await google.signOut();
      } catch (_) {}

      final account = await google.signIn();
      if (account == null) return null;

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        return AuthResult.failure(
            'Could not get a Google ID token. Check the Web client ID.');
      }

      final response = await ApiClient.instance.dio
          .post('/api/auth/google', data: {'id_token': idToken});
      final data = response.data;
      await TokenStore.instance.saveToken(data['token'] as String);
      await TokenStore.instance
          .saveUserId((data['user'] as Map<String, dynamic>)['id'] as String);
      await PropertyStore.instance.load();
      return AuthResult.success();
    } on DioException catch (e) {
      final d = e.response?.data;
      if (d is Map && d['error'] != null) {
        return AuthResult.failure(d['error'].toString());
      }
      return AuthResult.failure(
          e.message ?? 'Something went wrong. Please try again.');
    } on PlatformException catch (e) {
      final m = '${e.code} ${e.message}';
      if (m.contains('network_error') || m.contains('ApiException: 7')) {
        return AuthResult.failure('No internet connection.');
      }
      if (m.contains('ApiException: 10') || m.contains('12500')) {
        return AuthResult.failure(
            'Google sign-in is not set up for this build. Add the SHA-1 in '
            'Firebase and use the new google-services.json.');
      }
      return AuthResult.failure('Google sign-in failed (${e.code}).');
    } catch (_) {
      return AuthResult.failure('Google sign-in failed. Please try again.');
    }
  }
}