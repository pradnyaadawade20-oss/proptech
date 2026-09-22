import 'package:flutter/material.dart';
import '../properties/property.dart';

/// Holds all advanced-search filter selections. A single object is easy
/// to pass around, reset, and later serialize into API query params.
class PropertyFilters {
  RangeValues priceRange;
  RangeValues areaRange;
  String? possessionStatus; // null = any
  int? maxAgeYears; // null = any
  RangeValues floorRange;
  String? facing; // null = any

  static const RangeValues defaultPriceRange = RangeValues(0, 50000000);
  static const RangeValues defaultAreaRange = RangeValues(0, 5000);
  static const RangeValues defaultFloorRange = RangeValues(0, 50);

  PropertyFilters({
    RangeValues? priceRange,
    RangeValues? areaRange,
    this.possessionStatus,
    this.maxAgeYears,
    RangeValues? floorRange,
    this.facing,
  })  : priceRange = priceRange ?? defaultPriceRange,
        areaRange = areaRange ?? defaultAreaRange,
        floorRange = floorRange ?? defaultFloorRange;

  bool get isActive =>
      priceRange.start > defaultPriceRange.start ||
      priceRange.end < defaultPriceRange.end ||
      areaRange.start > defaultAreaRange.start ||
      areaRange.end < defaultAreaRange.end ||
      possessionStatus != null ||
      maxAgeYears != null ||
      floorRange.start > defaultFloorRange.start ||
      floorRange.end < defaultFloorRange.end ||
      facing != null;

  int get activeCount {
    int count = 0;
    if (priceRange.start > defaultPriceRange.start || priceRange.end < defaultPriceRange.end) count++;
    if (areaRange.start > defaultAreaRange.start || areaRange.end < defaultAreaRange.end) count++;
    if (possessionStatus != null) count++;
    if (maxAgeYears != null) count++;
    if (floorRange.start > defaultFloorRange.start || floorRange.end < defaultFloorRange.end) count++;
    if (facing != null) count++;
    return count;
  }

  PropertyFilters copy() => PropertyFilters(
        priceRange: priceRange,
        areaRange: areaRange,
        possessionStatus: possessionStatus,
        maxAgeYears: maxAgeYears,
        floorRange: floorRange,
        facing: facing,
      );

  void reset() {
    priceRange = defaultPriceRange;
    areaRange = defaultAreaRange;
    possessionStatus = null;
    maxAgeYears = null;
    floorRange = defaultFloorRange;
    facing = null;
  }

  List<Property> apply(List<Property> input) {
    return input.where((p) {
      if (p.price < priceRange.start || p.price > priceRange.end) return false;
      if (p.area < areaRange.start || p.area > areaRange.end) return false;
      if (possessionStatus != null && p.possessionStatus != possessionStatus) return false;
      if (maxAgeYears != null && p.ageOfPropertyYears > maxAgeYears!) return false;
      if (p.floorNumber < floorRange.start || p.floorNumber > floorRange.end) return false;
      if (facing != null && p.facing != facing) return false;
      return true;
    }).toList();
  }
}