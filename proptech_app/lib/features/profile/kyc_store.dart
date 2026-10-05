import 'package:flutter/foundation.dart';
import 'kyc_service.dart';

/// In-memory cache of the current user's KYC status, shared by the Profile
/// screen and the KYC flow. The server is the source of truth: this is only
/// a cache for the UI (nothing is persisted on the device, so a stale or
/// edited local value can never make someone look "verified").
class KycStore {
  KycStore._();
  static final KycStore instance = KycStore._();

  /// Null until the first successful [refresh]. Listen with ValueListenableBuilder.
  final ValueNotifier<KycStatus?> status = ValueNotifier<KycStatus?>(null);

  /// Re-fetches from the server. Network errors keep the last known value.
  Future<void> refresh() async {
    try {
      status.value = await KycService.instance.getStatus();
    } catch (_) {}
  }

  void update(KycStatus s) => status.value = s;

  /// Call on logout so the next account on this phone doesn't see old state.
  void clear() => status.value = null;
}