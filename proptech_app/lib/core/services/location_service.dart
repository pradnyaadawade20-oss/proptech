import 'dart:async';
import 'package:geolocator/geolocator.dart';

enum LocationFailure { serviceDisabled, denied, deniedForever, timeout, unknown }

class LocationResult {
  final double? lat;
  final double? lng;
  final LocationFailure? failure;

  const LocationResult._({this.lat, this.lng, this.failure});
  const LocationResult.ok(double lat, double lng) : this._(lat: lat, lng: lng);
  const LocationResult.failed(LocationFailure f) : this._(failure: f);

  bool get ok => failure == null && lat != null && lng != null;
}

/// One place that handles GPS: service check -> permission -> position.
/// Used by the "use my current location" icon in the search bar.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  Future<LocationResult> getCurrent() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(LocationFailure.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failed(LocationFailure.denied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(LocationFailure.deniedForever);
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        return LocationResult.ok(pos.latitude, pos.longitude);
      } on TimeoutException {
        // GPS fix slow (indoors) -> fall back to the last known position.
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return LocationResult.ok(last.latitude, last.longitude);
        return const LocationResult.failed(LocationFailure.timeout);
      }
    } catch (_) {
      return const LocationResult.failed(LocationFailure.unknown);
    }
  }

  /// Opens the right system screen so the user can fix the problem.
  Future<void> openSettingsFor(LocationFailure f) async {
    if (f == LocationFailure.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else if (f == LocationFailure.deniedForever) {
      await Geolocator.openAppSettings();
    }
  }
}