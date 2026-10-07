import 'package:flutter/foundation.dart';

/// Holds the ids of the listings the user picked to compare (max 3).
class CompareStore extends ChangeNotifier {
  CompareStore._();
  static final CompareStore instance = CompareStore._();

  static const int maxItems = 3;
  final List<String> _ids = [];

  List<String> get ids => List.unmodifiable(_ids);
  int get count => _ids.length;
  bool contains(String id) => _ids.contains(id);

  /// Adds or removes [id]. Returns false only when the list is full and [id] was not added.
  bool toggle(String id) {
    if (_ids.remove(id)) {
      notifyListeners();
      return true;
    }
    if (_ids.length >= maxItems) return false;
    _ids.add(id);
    notifyListeners();
    return true;
  }

  void remove(String id) {
    if (_ids.remove(id)) notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}