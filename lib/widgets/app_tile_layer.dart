import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/constants.dart';

/// The base map used on every screen. Sends [AppConstants.httpHeaders] so
/// tile requests carry the Referer the Geoapify key is restricted to.
class AppTileLayer extends StatelessWidget {
  const AppTileLayer({super.key});

  // One shared provider: a new one per build would drop cached tiles.
  static final _provider = NetworkTileProvider(
    headers: AppConstants.httpHeaders,
  );

  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: AppConstants.tileUrl,
    userAgentPackageName: AppConstants.userAgentPackageName,
    tileProvider: _provider,
  );
}
