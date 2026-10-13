import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'zone_pin_marker.dart';

/// Pin for a place a friend shared with me: white disc with an indigo ring
/// and a "group" icon, so it reads differently from my own coloured pins.
/// Same box size and anchor as [ZonePinMarker].
class SharedPinMarker extends StatelessWidget {
  const SharedPinMarker({
    super.key,
    required this.label,
    this.openCount = 0,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final int openCount;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static const double width = ZonePinMarker.width;
  static const double height = ZonePinMarker.height;

  @override
  Widget build(BuildContext context) {
    // Fixed accent, not scheme.primary: in dark mode primary turns pale
    // lavender and washes out on the light map tiles.
    const indigo = AppTheme.indigo;
    const d = 26.0;
    final disc = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: indigo, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: const Icon(Icons.groups, size: 14, color: indigo),
        ),
        if (openCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: indigo,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text('$openCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
    // Disc centred in the box (the marker anchor); label to the right.
    return Row(
      children: [
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(width: d + 8, height: height, child: Center(child: disc)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: indigo,
                shadows: [
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
