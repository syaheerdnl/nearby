import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Nearby's mark: an indigo tile with a pin. Same shape as the app icon.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.indigo,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.near_me, color: Colors.white, size: size * 0.52),
    );
  }
}
