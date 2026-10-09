/// One place returned by the search service.
class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;
}
