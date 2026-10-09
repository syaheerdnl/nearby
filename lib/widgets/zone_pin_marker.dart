import 'package:flutter/material.dart';

import '../core/place_category.dart';

/// Map pin: a coloured disc with the category icon, an optional red count
/// badge (active reminders) and a label to the right. The marker is
/// anchored on the disc centre.
class ZonePinMarker extends StatelessWidget {
  const ZonePinMarker({
    super.key,
    required this.category,
    this.label,
    this.size = 26,
    this.count = 0,
    this.selected = false,
    this.onTap,
  });

  final PlaceCategory category;
  final String? label;
  final double size;

  /// Active reminders waiting here. 0 hides the badge.
  final int count;

  /// Picked on the map: bigger disc with a soft ring.
  final bool selected;

  /// Only the disc is tappable, so map taps next to a pin still reach the map.
  final VoidCallback? onTap;

  /// Marker box: the disc sits in the middle, the label hangs to the right.
  static const double width = 180;
  static const double height = 30;

  @override
  Widget build(BuildContext context) {
    final d = selected ? size + 6 : size;
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: category.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          if (selected)
            BoxShadow(
                color: category.color.withValues(alpha: 0.35), spreadRadius: 5),
          const BoxShadow(
              color: Color(0x59000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(category.icon, color: Colors.white, size: d * 0.55),
    );

    final disc = Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        if (count > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFC62F2F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1),
              ),
            ),
          ),
      ],
    );
    final tappable =
        onTap == null ? disc : GestureDetector(onTap: onTap, child: disc);

    if (label == null) return Center(child: tappable);
    // Disc centred in the box; label hangs off to the right.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        tappable,
        Positioned(
          left: width / 2 + d / 2 + 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: width / 2 - 22),
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: const Color(0xFF2B2A26),
                shadows: const [
                  Shadow(color: Colors.white, blurRadius: 3),
                  Shadow(color: Colors.white, blurRadius: 3),
                  Shadow(color: Colors.white, blurRadius: 3),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
