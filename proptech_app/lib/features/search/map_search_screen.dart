import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../properties/property.dart';

/// Shows all (or a pre-filtered list of) properties as pins on a real
/// street map of India. Uses OpenStreetMap tiles via flutter_map — free,
/// no API key required — with animated camera movement and a "my location"
/// button so it behaves like Google Maps.
class MapSearchScreen extends StatefulWidget {
  final List<Property>? properties;
  const MapSearchScreen({super.key, this.properties});

  @override
  State<MapSearchScreen> createState() => _MapSearchScreenState();
}

class _MapSearchScreenState extends State<MapSearchScreen>
    with TickerProviderStateMixin {
  late final AnimatedMapController _mapController;
  final TextEditingController _searchController = TextEditingController();
  final Dio _dio = Dio();
  Property? _selectedProperty;

  List<Property> _propertyMatches = [];
  List<_GeoResult> _placeMatches = [];
  bool _isSearchingPlace = false;
  bool _isLocatingMe = false;
  LatLng? _myLocation;
  Timer? _debounce;
  double _rotation = 0;

  // Geographic center of India, framing the whole country on load.
  static const LatLng _indiaCenter = LatLng(22.9734, 78.6569);

  static const Map<String, LatLng> _cityLabels = {
    'Mumbai': LatLng(19.0760, 72.8777),
    'Pune': LatLng(18.5204, 73.8567),
    'Delhi': LatLng(28.6139, 77.2090),
    'Bengaluru': LatLng(12.9716, 77.5946),
    'Hyderabad': LatLng(17.3850, 78.4867),
    'Chennai': LatLng(13.0827, 80.2707),
    'Kolkata': LatLng(22.5726, 88.3639),
    'Ahmedabad': LatLng(23.0225, 72.5714),
    'Jaipur': LatLng(26.9124, 75.7873),
    'Nagpur': LatLng(21.1458, 79.0882),
  };

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<Property> get _properties => widget.properties ?? dummyProperties;

  // --- Search ---

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _propertyMatches = [];
        _placeMatches = [];
      });
      return;
    }

    final q = query.toLowerCase();
    setState(() {
      _propertyMatches = _properties
          .where((p) => p.location.toLowerCase().contains(q) || p.title.toLowerCase().contains(q))
          .take(5)
          .toList();
    });

    _debounce = Timer(const Duration(milliseconds: 500), () => _searchPlaces(query));
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 3) {
      setState(() => _placeMatches = []);
      return;
    }
    setState(() => _isSearchingPlace = true);
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {'q': query, 'format': 'json', 'countrycodes': 'in', 'limit': 5},
        options: Options(headers: {'User-Agent': 'proptech_app'}),
      );
      final results = (response.data as List)
          .map((e) => _GeoResult(
                name: e['display_name'] as String,
                lat: double.parse(e['lat'] as String),
                lng: double.parse(e['lon'] as String),
              ))
          .toList();
      if (mounted) setState(() => _placeMatches = results);
    } catch (_) {
      if (mounted) setState(() => _placeMatches = []);
    } finally {
      if (mounted) setState(() => _isSearchingPlace = false);
    }
  }

  void _jumpToPlace(_GeoResult place) {
    _mapController.animateTo(
      dest: LatLng(place.lat, place.lng),
      zoom: 13,
      curve: Curves.easeInOutCubic,
      duration: const Duration(milliseconds: 900),
    );
    setState(() {
      _placeMatches = [];
      _propertyMatches = [];
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _jumpToProperty(Property p) {
    final pos = p.mapPosition;
    _mapController.animateTo(
      dest: LatLng(pos.lat, pos.lng),
      zoom: 14,
      curve: Curves.easeInOutCubic,
      duration: const Duration(milliseconds: 900),
    );
    setState(() {
      _selectedProperty = p;
      _propertyMatches = [];
      _placeMatches = [];
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  // --- Current location ---

  Future<void> _goToMyLocation() async {
    setState(() => _isLocatingMe = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Please enable location services');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack('Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack('Location permission permanently denied. Enable it from app settings.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final target = LatLng(position.latitude, position.longitude);
      setState(() => _myLocation = target);
      _mapController.animateTo(
        dest: target,
        zoom: 15,
        curve: Curves.easeInOutCubic,
        duration: const Duration(milliseconds: 900),
      );
    } catch (_) {
      _showSnack('Could not fetch your location');
    } finally {
      if (mounted) setState(() => _isLocatingMe = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Formatting & markers ---

  String _formatPrice(Property p) {
    final v = p.price;
    String formatted;
    if (v >= 10000000) {
      formatted = '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    } else if (v >= 100000) {
      formatted = '₹${(v / 100000).toStringAsFixed(1)}L';
    } else {
      formatted = '₹${v.toStringAsFixed(0)}';
    }
    return '$formatted${p.priceUnit}';
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[
      for (final entry in _cityLabels.entries)
        Marker(point: entry.value, width: 90, height: 40, child: _cityLabel(entry.key)),
    ];

    for (final p in _properties) {
      final pos = p.mapPosition;
      final isSelected = _selectedProperty?.id == p.id;
      markers.add(
        Marker(
          point: LatLng(pos.lat, pos.lng),
          width: isSelected ? 46 : 38,
          height: isSelected ? 46 : 38,
          child: GestureDetector(
            onTap: () => setState(() => _selectedProperty = p),
            child: AnimatedScale(
              scale: isSelected ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.location_on,
                color: isSelected ? Colors.orange : AppColors.primary,
                size: isSelected ? 46 : 38,
                shadows: const [Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
              ),
            ),
          ),
        ),
      );
    }

    if (_myLocation != null) {
      markers.add(
        Marker(
          point: _myLocation!,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _cityLabel(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Map Search'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController.mapController,
            options: MapOptions(
              initialCenter: _indiaCenter,
              initialZoom: 4.4,
              minZoom: 4,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all, // pinch-zoom, drag, double-tap zoom, rotate — like Google Maps
              ),
              onTap: (_, __) => setState(() => _selectedProperty = null),
              onPositionChanged: (position, hasGesture) {
                final newRotation = position.rotation ?? _rotation;
                if (hasGesture || newRotation != _rotation) {
                  setState(() => _rotation = newRotation);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.proptech.app',
                maxZoom: 19,
              ),
              MarkerLayer(markers: _buildMarkers()),
              if (_myLocation != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _myLocation!,
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withValues(alpha: 0.25),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                  TextSourceAttribution('CARTO'),
                ],
              ),
            ],
          ),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: AppColors.textHint),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: const InputDecoration(
                            hintText: 'Search locality, city, or property...',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_isSearchingPlace)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                    ],
                  ),
                ),
                if (_propertyMatches.isNotEmpty || _placeMatches.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.xs),
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      children: [
                        if (_propertyMatches.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                            child: Text('Properties', style: AppTextStyles.caption),
                          ),
                          for (final p in _propertyMatches)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.home_work_outlined, color: AppColors.primary, size: 20),
                              title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(p.location, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => _jumpToProperty(p),
                            ),
                        ],
                        if (_placeMatches.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                            child: Text('Places', style: AppTextStyles.caption),
                          ),
                          for (final place in _placeMatches)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined, color: AppColors.textSecondary, size: 20),
                              title: Text(place.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () => _jumpToPlace(place),
                            ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_rotation != 0)
            Positioned(
              top: 90,
              right: AppSpacing.md,
              child: _mapButton(
                icon: Transform.rotate(
                  angle: -_rotation * 3.1415926535 / 180,
                  child: const Icon(Icons.navigation, size: 20, color: AppColors.primary),
                ),
                onTap: () => _mapController.animatedRotateReset(curve: Curves.easeOut).then((_) {
                  if (mounted) setState(() => _rotation = 0);
                }),
              ),
            ),
          Positioned(
            right: AppSpacing.md,
            bottom: _selectedProperty != null ? 150 : AppSpacing.md,
            child: Column(
              children: [
                _mapButton(
                  icon: _isLocatingMe
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 20, color: AppColors.primary),
                  onTap: _isLocatingMe ? null : _goToMyLocation,
                ),
                const SizedBox(height: AppSpacing.sm),
                _mapButton(
                  icon: const Icon(Icons.add, size: 20, color: AppColors.textPrimary),
                  onTap: () => _mapController.animatedZoomIn(curve: Curves.easeOut),
                ),
                const SizedBox(height: AppSpacing.xs),
                _mapButton(
                  icon: const Icon(Icons.remove, size: 20, color: AppColors.textPrimary),
                  onTap: () => _mapController.animatedZoomOut(curve: Curves.easeOut),
                ),
              ],
            ),
          ),
          if (_selectedProperty != null)
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: _buildPropertyCard(_selectedProperty!),
            ),
        ],
      ),
    );
  }

  Widget _mapButton({required Widget icon, required VoidCallback? onTap}) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(width: 20, height: 20, child: Center(child: icon)),
        ),
      ),
    );
  }

  Widget _buildPropertyCard(Property p) {
    return GestureDetector(
      onTap: () => context.push('/property/${p.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: CachedNetworkImage(imageUrl: p.imageUrl, width: 80, height: 80, fit: BoxFit.cover),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.title, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(p.location, style: AppTextStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(_formatPrice(p), style: AppTextStyles.price.copyWith(fontSize: 15)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _GeoResult {
  final String name;
  final double lat;
  final double lng;
  _GeoResult({required this.name, required this.lat, required this.lng});
}