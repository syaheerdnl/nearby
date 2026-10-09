import 'package:flutter/material.dart';

import '../core/place_category.dart';

/// Square colour tile with the category icon (list rows, headers).
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category, this.size = 36});

  final PlaceCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(category.icon, color: Colors.white, size: size * 0.55),
    );
  }
}
