import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/zone.dart';
import '../models/zone_reminder.dart';
import 'category_badge.dart';

/// Card shown when a pin is tapped: what's waiting there, tick things off,
/// get directions or open the full page.
class PlacePreviewCard extends StatelessWidget {
  const PlacePreviewCard({
    super.key,
    required this.zone,
    required this.reminders,
    required this.distanceMeters,
    required this.onToggleDone,
    required this.onDirections,
    required this.onOpen,
    required this.onClose,
  });

  final Zone zone;
  final List<ZoneReminder> reminders;
  final double? distanceMeters;

  /// Ticking marks a reminder done (turns it off); unticking brings it back.
  final void Function(ZoneReminder reminder, bool done) onToggleDone;
  final VoidCallback onDirections;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Still-to-do first, done ones after.
    final sorted = [
      ...reminders.where((r) => r.active),
      ...reminders.where((r) => !r.active),
    ];
    final visible = sorted.take(_shown).toList();
    final hidden = sorted.length - visible.length;
    final meta = [
      zone.category.label,
      zone.triggerType.short.toLowerCase(),
      if (distanceMeters != null) '${_km(distanceMeters!)} away',
    ].join(' · ');

    return Material(
      color: scheme.surface,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 4, 10),
              child: Row(
                children: [
                  CategoryBadge(category: zone.category),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(zone.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Text('Nothing to remember here yet.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          for (final r in visible) ...[
            const Divider(),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onToggleDone(r, r.active);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 14, 0),
                child: Row(
                  children: [
                    Checkbox(
                      value: !r.active,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        onToggleDone(r, v ?? false);
                      },
                    ),
                    Expanded(
                      child: Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: r.active
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          decoration:
                              r.active ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (r.body != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(r.body!,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: GestureDetector(
                onTap: onOpen,
                child: Text('+$hidden more',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: scheme.primary)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
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
                    child: const Text('Open'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _km(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
}

