import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shown once, right after the first zone is saved.
///
/// OEM note: Vivo/iQOO, Xiaomi and Oppo/Realme kill background work far more
/// aggressively than stock Android. Without these settings, geofence events
/// can arrive very late or not at all once the app is swiped away. Menu
/// names differ between OS versions, so the steps are guidance, not exact.
class BatteryOptimizationScreen extends StatefulWidget {
  const BatteryOptimizationScreen({super.key});

  @override
  State<BatteryOptimizationScreen> createState() =>
      _BatteryOptimizationScreenState();
}

enum _Oem { vivo, xiaomi, oppo, samsung, other }

class _BatteryOptimizationScreenState extends State<BatteryOptimizationScreen>
    with WidgetsBindingObserver {
  _Oem _oem = _Oem.other;
  String _brand = '';
  bool _exempt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user comes back from system settings.
    if (state == AppLifecycleState.resumed) _checkExempt();
  }

  Future<void> _detect() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final m = '${info.manufacturer} ${info.brand}'.toLowerCase();
      _brand = info.brand;
      _oem = m.contains('vivo') || m.contains('iqoo')
          ? _Oem.vivo
          : m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')
              ? _Oem.xiaomi
              : m.contains('oppo') || m.contains('realme') || m.contains('oneplus')
                  ? _Oem.oppo
                  : m.contains('samsung')
                      ? _Oem.samsung
                      : _Oem.other;
    }
    await _checkExempt();
  }

  Future<void> _checkExempt() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (mounted) setState(() => _exempt = status.isGranted);
  }

  Future<void> _requestExempt() async {
    await Permission.ignoreBatteryOptimizations.request();
    await _checkExempt();
  }

  List<String> get _steps => switch (_oem) {
        _Oem.vivo => const [
            'Settings > Battery > Background power consumption management > Nearby > Allow.',
            'Settings > Apps > Nearby > turn on Autostart (or "Allow background activity").',
            'Open recent apps, pull down on Nearby\'s card (or long-press) and tap the lock icon so it is not cleared.',
          ],
        _Oem.xiaomi => const [
            'Settings > Apps > Manage apps > Nearby > Autostart: on.',
            'Same page > Battery saver > No restrictions.',
            'Lock Nearby in recent apps (long-press its card > lock).',
          ],
        _Oem.oppo => const [
            'Settings > Battery > App battery management > Nearby > Allow background activity.',
            'Settings > Apps > Nearby > allow Auto launch.',
            'Lock Nearby in recent apps.',
          ],
        _Oem.samsung => const [
            'Settings > Apps > Nearby > Battery > Unrestricted.',
            'Settings > Battery > Background usage limits: make sure Nearby is not in "Sleeping apps".',
          ],
        _Oem.other => const [
            'Settings > Apps > Nearby > Battery > Unrestricted (or "Don\'t optimise").',
          ],
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _steps;
    return Scaffold(
      appBar: AppBar(title: const Text('Keep Nearby awake')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _oem == _Oem.other
                ? 'Some phones stop apps in the background to save battery. '
                    'That can delay or block your reminders.'
                : '${_brand.isEmpty ? 'This phone' : _brand} phones stop apps '
                    'in the background quite aggressively. Without these '
                    'settings, reminders can arrive late or not at all once '
                    'you swipe Nearby away.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: Icon(
                _exempt ? Icons.check_circle : Icons.battery_alert_outlined,
                color: _exempt ? theme.colorScheme.primary : null,
              ),
              title: const Text('Battery optimisation'),
              subtitle: Text(_exempt
                  ? 'Nearby is exempt.'
                  : 'Tap to let Nearby run without battery limits.'),
              onTap: _exempt ? null : _requestExempt,
            ),
          ),
          const SizedBox(height: 24),
          Text('Also on this phone', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 12, child: Text('${i + 1}')),
                  const SizedBox(width: 12),
                  Expanded(child: Text(steps[i])),
                ],
              ),
            ),
          Text('Menu names can differ a little between OS versions.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open Nearby\'s app settings'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
