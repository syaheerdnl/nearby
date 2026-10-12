import 'package:flutter/foundation.dart';

import '../../core/place_category.dart';

/// Which bottom tab is showing, plus one-shot requests between tabs
/// (Home's category tiles open the Map tab with a filter on).
class ShellNav extends ChangeNotifier {
  static const home = 0, map = 1, trips = 2, profile = 3;

  int _tab = home;
  int get tab => _tab;

  PlaceCategory? _pendingFilter;
  bool _hasPendingFilter = false;

  void goTo(int tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Open the Map tab showing only [category] (null = all places).
  void openMap({PlaceCategory? category}) {
    _pendingFilter = category;
    _hasPendingFilter = true;
    _tab = map;
    notifyListeners();
  }

  /// The map calls this once to pick up a filter request.
  ({PlaceCategory? category})? takeFilterRequest() {
    if (!_hasPendingFilter) return null;
    _hasPendingFilter = false;
    return (category: _pendingFilter);
  }
}
