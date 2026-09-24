import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small on-device store for user preferences (notification toggles).
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  final _storage = const FlutterSecureStorage();

  static const notifMessages = 'pref_notif_messages';
  static const notifVisits = 'pref_notif_visits';
  static const notifAgreements = 'pref_notif_agreements';
  static const notifOffers = 'pref_notif_offers';

  Future<bool> getBool(String key, {bool defaultValue = true}) async {
    final value = await _storage.read(key: key);
    if (value == null) return defaultValue;
    return value == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      _storage.write(key: key, value: value.toString());
}