import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/trigger_log_entry.dart';
import '../../models/zone.dart';
import '../../models/zone_reminder.dart';
import '../../providers/zone_provider.dart';
import '../../services/geofence_service.dart';
import '../../widgets/reminder_tile.dart';
import 'zone_create_screen.dart';

class ZoneDetailScreen extends StatefulWidget {
  const ZoneDetailScreen({super.key, required this.zoneId});

  final String zoneId;

  @override
  State<ZoneDetailScreen> createState() => _ZoneDetailScreenState();
}

class _ZoneDetailScreenState extends State<ZoneDetailScreen> {
  final _quickAdd = TextEditingController();
  final _quickFocus = FocusNode();
  late Future<List<TriggerLogEntry>> _log;

  @override
  void initState() {
    super.initState();
    _log = context.read<ZoneProvider>().triggerLog(widget.zoneId);
  }

  @override
  void dispose() {
    _quickAdd.dispose();
    _quickFocus.dispose();
    super.dispose();
  }

  void _reloadLog() {
    if (!mounted) return;
    setState(() {
      _log = context.read<ZoneProvider>().triggerLog(widget.zoneId);
    });
  }

  Future<void> _addQuick() async {
    final text = _quickAdd.text.trim();
    if (text.isEmpty) return;
    _quickAdd.clear();
    HapticFeedback.selectionClick();
    await context.read<ZoneProvider>().addReminder(widget.zoneId, text, null);
    _quickFocus.requestFocus(); // keep typing the next one
  }

  Future<void> _editReminder(ZoneReminder existing) async {
    final result = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReminderSheet(existing: existing),
    );
    if (result == null || !mounted) return;
    final (title, body) = result;
    await context.read<ZoneProvider>().updateReminder(existing.copyWith(
          title: title,
          body: body,
          clearBody: body == null,
        ));
  }

  Future<void> _deleteReminder(ZoneReminder r) async {
    final zones = context.read<ZoneProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await zones.deleteReminder(r);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed "${r.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => zones.restoreReminder(r),
        ),
      ));
  }

  Future<void> _delete(Zone zone) async {
    final zones = context.read<ZoneProvider>();
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${zone.name}"?'),
        content: const Text('Its reminders and history go too.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await zones.deleteZone(zone.id);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ZoneProvider>();
    final zone = provider.zoneById(widget.zoneId);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (zone == null) {
      // Opened from a notification on cold start: zones not read yet.
      if (provider.zones.isEmpty && (provider.loading || provider.syncing)) {
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This place no longer exists.')),
      );
    }

    final reminders = provider.remindersFor(zone.id);
    final activeCount = reminders.where((r) => r.active).length;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Edit place',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ZoneCreateScreen(existing: zone))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(zone);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete place')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.refresh();
          _reloadLog();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: zone.category.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(zone.category.icon,
                          color: zone.category.color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(zone.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700, height: 1.2)),
                          const SizedBox(height: 2),
                          Text(zone.category.label,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: zone.category.color)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _InfoRow(
                icon: Icons.login,
                label: 'Trigger',
                value: zone.triggerType.segment),
            _InfoRow(
                icon: Icons.radar,
                label: 'Radius',
                value: '${zone.radiusMeters} m'),
            const SizedBox(height: 8),
            FutureBuilder<List<TriggerLogEntry>>(
              future: _log,
              builder: (context, snap) => _StatusStrip(
                registered: provider.isRegistered(zone.id),
                permission: provider.permission,
                hasActive: activeCount > 0,
                lastFired: (snap.data?.isNotEmpty ?? false)
                    ? snap.data!.first.firedAt
                    : null,
                onAllow: provider.requestGeofencePermission,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('To remember',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (reminders.isNotEmpty)
                    Text('$activeCount of ${reminders.length} on',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const Divider(),
            // Quick add: type and press enter, stays focused for the next one.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _quickAdd,
                focusNode: _quickFocus,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addQuick(),
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Icon(Icons.add, color: scheme.primary),
                  hintText: 'Add',
                  hintStyle: TextStyle(
                      color: scheme.primary, fontWeight: FontWeight.w500),
                  suffixIcon: IconButton(
                    tooltip: 'Add',
                    icon: const Icon(Icons.keyboard_return),
                    onPressed: _addQuick,
                  ),
                ),
              ),
            ),
            for (final r in reminders) ...[
              const Divider(),
              ReminderTile(
                reminder: r,
                onTap: () => _editReminder(r),
                onToggle: (v) {
                  HapticFeedback.selectionClick();
                  provider.updateReminder(r.copyWith(active: v));
                },
                onDelete: () => _deleteReminder(r),
              ),
            ],
            const Divider(),
            if (reminders.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Nothing yet. Without a reminder this place stays quiet '
                  'when you get there.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            _History(log: _log, onReload: _reloadLog),
          ],
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.registered,
    required this.permission,
    required this.hasActive,
    required this.lastFired,
    required this.onAllow,
  });

  final bool registered;
  final GeofencePermission permission;
  final bool hasActive;
  final DateTime? lastFired;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;
    Widget? action;

    if (permission != GeofencePermission.granted) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
      icon = Icons.location_off_outlined;
      text = 'Paused. Location needs "Allow all the time".';
      action = TextButton(onPressed: onAllow, child: const Text('Allow'));
    } else if (!registered) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
      icon = Icons.sync_problem;
      text = 'Not set up on this phone yet. Pull down to retry.';
    } else if (!hasActive) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.notifications_off_outlined;
      text = 'Quiet. Add something below and it will remind you.';
    } else {
      bg = dark ? const Color(0xFF1F2A1C) : AppTheme.okBg;
      fg = dark ? const Color(0xFFB8D8A8) : AppTheme.okFg;
      icon = Icons.notifications_outlined;
      text = lastFired == null
          ? 'Working on this phone. Hasn\'t gone off yet.'
          : 'Working on this phone. Last went off ${_when(lastFired!)}.';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.fromLTRB(12, 10, action == null ? 12 : 4, 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 17, color: fg),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: fg))),
          if (action != null) action,
        ],
      ),
    );
  }

  static String _when(DateTime t) {
    final l = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(l.year, l.month, l.day);
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final time = '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'am' : 'pm'}';
    if (day == today) return 'today, $time';
    if (day == today.subtract(const Duration(days: 1))) return 'yesterday, $time';
    return '${l.day}/${l.month}, $time';
  }
}

class _History extends StatelessWidget {
  const _History({required this.log, required this.onReload});

  final Future<List<TriggerLogEntry>> log;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('History',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('When this place went off',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        onExpansionChanged: (open) {
          if (open) onReload();
        },
        children: [
          FutureBuilder<List<TriggerLogEntry>>(
            future: log,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                );
              }
              final entries = snap.data ?? const [];
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                      'Nothing yet. Walk in or out to test it, ideally with '
                      'the app closed.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                );
              }
              return Column(
                children: [
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(_StatusStrip._when(e.firedAt),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                          Expanded(
                            child: Text(
                              '${_eventLabel(e)} · ${e.notified ? 'reminded' : 'nothing on'}',
                              style: TextStyle(
                                  fontSize: 13, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _eventLabel(TriggerLogEntry e) => switch (e.event.name) {
        'enter' => 'Arrived',
        'exit' => 'Left',
        _ => 'Stayed',
      };
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({this.existing});

  final ZoneReminder? existing;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.existing?.body ?? '');

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final body = _body.text.trim();
    Navigator.pop<(String, String?)>(
        context, (_title.text.trim(), body.isEmpty ? null : body));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit reminder',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'What to remember', counterText: ''),
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Write something' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _body,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)', hintText: '2 botol, 5 kg'),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}


class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
