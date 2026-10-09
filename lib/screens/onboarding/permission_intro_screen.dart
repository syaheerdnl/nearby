import 'package:flutter/material.dart';

import '../../core/place_category.dart';
import '../../widgets/app_mark.dart';

/// First launch explainer. Deliberately asks for nothing: location is only
/// requested when the user saves their first zone (CLAUDE.md section 6).
class PermissionIntroScreen extends StatelessWidget {
  const PermissionIntroScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 48),
          child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const AppMark(),
              const SizedBox(height: 24),
              Text('Remember things where they matter',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              _Point(
                color: PlaceCategory.shop.color,
                icon: Icons.add_location_alt_outlined,
                text: 'Save the places you go: rumah, the kedai, the masjid. '
                    'Add what you need to remember at each one.',
              ),
              _Point(
                color: PlaceCategory.home.color,
                icon: Icons.notifications_active_outlined,
                text: 'Nearby reminds you when you arrive, leave, or stay a while.',
              ),
              _Point(
                color: PlaceCategory.masjid.color,
                icon: Icons.lock_outline,
                text: 'Your phone does the location check itself. Your '
                    'location is not tracked or sent anywhere.',
              ),
              _Point(
                color: PlaceCategory.school.color,
                icon: Icons.battery_alert_outlined,
                text: 'To work with the app closed, Nearby needs location '
                    '"all the time". We will ask when you save your first place.',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
          ),
          ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, required this.color});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
