import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/shared_list.dart';

/// Quick look at a place a friend shared with me (long-press on its map pin).
/// Built from the local [SharedPlace] cache only, so it works offline; the
/// items are the unclaimed ones as of the last refresh.
class SharedPlaceSheet extends StatelessWidget {
  const SharedPlaceSheet({
    super.key,
    required this.place,
    required this.onDirections,
    required this.onOpen,
  });

  final SharedPlace place;
  final VoidCallback onDirections;
  final VoidCallback onOpen;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = place.openItems;
    final hidden = items.length - _shown;
    final meta = [
      if (place.ownerName.isNotEmpty) 'from ${place.ownerName}',
      '${place.radiusMeters} m zone',
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.indigo, width: 2.5),
                  ),
                  child: const Icon(Icons.groups,
                      size: 20, color: AppTheme.indigo),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(meta,
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(place.listTitle,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              items.isEmpty
                  ? 'Nothing left to claim'
                  : '${items.length} not claimed yet',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            for (final line in items.take(_shown))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('•  $line',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('+ $hidden more',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: scheme.primary)),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42)),
                    onPressed: onDirections,
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: const Text('Directions'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(42)),
                    onPressed: onOpen,
                    child: const Text('Open list'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
