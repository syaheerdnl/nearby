import 'package:flutter/material.dart';

import '../core/constants.dart';

/// Small map credit line (Geoapify free plan + OpenStreetMap require it).
///
/// Replaces flutter_map's SimpleAttributionWidget, whose single Row
/// overflowed on narrow screens once the Geoapify credit was added.
/// Put it last in FlutterMap.children so it draws on top.
class MapCredit extends StatelessWidget {
  const MapCredit({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              AppConstants.mapAttribution,
              maxLines: 2,
              softWrap: true,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 9.5, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}
