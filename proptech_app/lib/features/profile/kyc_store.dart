import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Result of a completed KYC check: the masked Aadhaar number and when it
/// was verified. Kept minimal — the full Aadhaar number is never stored,
/// only the last 4 digits, mirroring how real KYC providers only ever
/// surface a masked number back to the app after verification.
class KycStatus {
  final String maskedAadhaar; // e.g. "XXXX XXXX 4321"
  final DateTime verifiedAt;
  const KycStatus({required this.maskedAadhaar, required this.verifiedAt});

  Map<String, dynamic> toJson() => {
        'maskedAadhaar': maskedAadhaar,
        'verifiedAt': verifiedAt.toIso8601String(),
      };

  factory KycStatus.fromJson(Map<String, dynamic> json) => KycStatus(
        maskedAadhaar: json['maskedAadhaar'] as String,
        verifiedAt: DateTime.parse(json['verifiedAt'] as String),
      );
}

/// Tracks whether the current user has completed Aadhaar-based KYC,
/// persisted locally so the "Verified" state survives an app restart.
///
/// Singleton so both the Profile screen and the KYC flow itself share the
/// same state.
class KycStore {
  KycStore._();
  static final KycStore instance = KycStore._();

  static const _storageKey = 'kyc_status';
  final _storage = const FlutterSecureStorage();

  /// Null while not yet KYC-verified. Screens can listen directly via
  /// ValueListenableBuilder.
  final ValueNotifier<KycStatus?> status = ValueNotifier<KycStatus?>(null);

  bool _loaded = false;
  Future<void>? _loadFuture;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        status.value = KycStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      status.value = null;
    } finally {
      _loaded = true;
    }
  }

  /// Marks KYC as complete for the given Aadhaar number, storing only a
  /// masked version, and persists it.
  Future<void> markVerified(String fullAadhaar) async {
    final digits = fullAadhaar.replaceAll(RegExp(r'\D'), '');
    final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    final result = KycStatus(maskedAadhaar: 'XXXX XXXX $last4', verifiedAt: DateTime.now());
    status.value = result;
    await _storage.write(key: _storageKey, value: jsonEncode(result.toJson()));
  }

  /// Clears KYC status (e.g. on logout).
  Future<void> clear() async {
    status.value = null;
    await _storage.delete(key: _storageKey);
  }
}