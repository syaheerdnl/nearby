import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/zone_provider.dart';
import '../../services/geofence_service.dart';
import '../onboarding/battery_optimization_screen.dart';

/// Account and the settings that decide whether reminders actually fire.
/// (Was the avatar menu on the map.)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android settings: show the new permission state.
    if (state == AppLifecycleState.resumed) {
      context.read<ZoneProvider>().checkPermission();
    }
  }

  Future<void> _signOut() async {
    final zones = context.read<ZoneProvider>();
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Reminders stop on this phone until you sign in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await zones.reset();
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<ZoneProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = auth.displayName ?? 'Signed in';

    final (permText, permOk) = switch (provider.permission) {
      GeofencePermission.granted => ('Allowed all the time', true),
      GeofencePermission.foregroundOnly =>
        ('Only while using the app: reminders won\'t fire', false),
      GeofencePermission.denied => ('Not allowed', false),
    };

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Text('Profile',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                child: Text(name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    if (auth.email != null)
                      Text(auth.email!,
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('Reminders',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          _Row(
            icon: Icons.location_on_outlined,
            title: 'Location',
            subtitle: permText,
            warn: !permOk,
            onTap: () async {
              final before = provider.permission;
              final p = await provider.requestGeofencePermission();
              // Android only lets the app ask so many times. If asking
              // changed nothing, send the user to Settings instead.
              if (p != GeofencePermission.granted && p == before) {
                await openAppSettings();
              }
            },
          ),
          _Row(
            icon: Icons.battery_saver_outlined,
            title: 'Battery settings',
            subtitle: 'Keep Nearby running in the background',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BatteryOptimizationScreen())),
          ),
          _Row(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Open app settings',
            onTap: openAppSettings,
          ),
          const SizedBox(height: 22),
          _Row(
            icon: Icons.logout,
            title: 'Sign out',
            danger: true,
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.warn = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool warn;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: danger ? scheme.error : null)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12,
                                color: warn
                                    ? scheme.error
                                    : scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (!danger)
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
