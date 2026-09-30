import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'property.dart';
import 'property_service.dart';

/// Runs the full "Verify Now" flow for [property]:
/// 1. Opens the device camera (gallery is not accepted — a real-time photo
///    is what proves the property actually exists where it's listed).
/// 2. Reads the phone's current GPS location at that same moment.
/// 3. Uploads both to the backend, which marks the property verified.
///
/// Shows its own loading/result SnackBars via [context], and updates the
/// shared dummyProperties list on success so the "Verified" badge appears
/// immediately everywhere without needing a manual refresh.
Future<void> runVerifyNowFlow(BuildContext context, Property property) async {
  final messenger = ScaffoldMessenger.of(context);

  // 1. Camera photo — ImageSource.camera, not .gallery, so this can never
  // be a screenshot or a downloaded/WhatsApp image (those carry no GPS data).
  final picker = ImagePicker();
  final XFile? photo;
  try {
    photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open camera: $e')));
    return;
  }
  if (photo == null) return; // user cancelled

  messenger.showSnackBar(
    const SnackBar(content: Text('Getting your location...'), duration: Duration(seconds: 30)),
  );

  // 2. GPS location, captured right after the photo so it reflects where
  // the phone is right now (i.e. at the property).
  double lat, lng;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are turned off. Turn on GPS and try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to verify a property.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    lat = position.latitude;
    lng = position.longitude;
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Could not get location: $e')));
    return;
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    const SnackBar(content: Text('Verifying property...'), duration: Duration(seconds: 30)),
  );

  // 3. Upload photo + coordinates.
  try {
    final photoUrl = await PropertyService.instance.verifyProperty(property.id, photo, lat: lat, lng: lng);
    final idx = dummyProperties.indexWhere((p) => p.id == property.id);
    if (idx != -1) {
      dummyProperties[idx] = dummyProperties[idx].copyWith(isVerified: true);
      notifyPropertiesChanged();
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('✅ Property verified!')));
    // photoUrl isn't shown anywhere yet, but is returned for screens that
    // want to display the verification photo itself later.
    debugPrint('Verification photo: $photoUrl');
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Could not verify: $e')));
  }
}