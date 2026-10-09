import 'package:flutter/material.dart';

/// What kind of place a zone is. Matches `zones.category` in the database.
/// Drives the colour and icon used on the pin, circle and list tile.
enum PlaceCategory {
  home('Home', Icons.home_outlined, Color(0xFF3467B2)),
  shop('Shop', Icons.shopping_cart_outlined, Color(0xFFD66E26)),
  masjid('Masjid', Icons.mosque_outlined, Color(0xFF1F805A)),
  work('Work', Icons.work_outline, Color(0xFF8A4FA6)),
  school('School', Icons.school_outlined, Color(0xFFA8862A)),
  other('Other', Icons.place_outlined, Color(0xFF6D6B63));

  const PlaceCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static PlaceCategory fromName(String? value) => PlaceCategory.values.firstWhere(
        (c) => c.name == value,
        orElse: () => PlaceCategory.other,
      );
}
