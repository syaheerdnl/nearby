import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/trip_planner_screen.dart';
import '../zones/zone_map_screen.dart';
import 'shell_nav.dart';

/// Signed-in app: Home, Map, Trips, Profile in a bottom bar. Tabs stay alive
/// (IndexedStack) so the map keeps its position when you switch away.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ShellNav(),
      child: const _ShellBody(),
    );
  }
}

class _ShellBody extends StatelessWidget {
  const _ShellBody();

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<ShellNav>();
    return Scaffold(
      // The map tab handles the keyboard itself (search bar over the map).
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: nav.tab,
        children: const [
          HomeScreen(),
          ZoneMapScreen(),
          TripPlannerScreen(embedded: true),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: nav.tab,
        onDestinationSelected: nav.goTo,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route),
              label: 'Trips'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
