/// A receipt the buyer added for a list item they bought (`receipts` table).
/// One per item. Money is kept in sen (whole cents) so RM 12.10 stays exact.
class Receipt {
  const Receipt({
    required this.id,
    required this.listItemId,
    required this.uploadedBy,
    required this.imageUrl,
    required this.amountSen,
    required this.createdAt,
  });

  final String id;
  final String listItemId;
  final String uploadedBy;

  /// Path in the private `receipts` bucket (column name from the schema).
  /// Turned into a short-lived signed URL before showing it.
  final String imageUrl;
  final int amountSen;
  final DateTime createdAt;

  factory Receipt.fromRow(Map<String, dynamic> r) => Receipt(
    id: r['id'] as String,
    listItemId: r['list_item_id'] as String,
    uploadedBy: r['uploaded_by'] as String,
    imageUrl: r['image_url'] as String,
    amountSen: senFromNumeric(r['amount']),
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
  );
}

/// Postgres numeric(10,2) arrives as a number or a string, depending on size.
int senFromNumeric(Object? v) {
  if (v is num) return (v * 100).round();
  if (v is String) return parseAmountSen(v) ?? 0;
  return 0;
}

/// "12.5" -> 1250, "RM 12.50" -> 1250, "1,234.5" -> 123450.
/// Null for anything that isn't a positive amount under RM 100,000 with at
/// most 2 decimals (what the database accepts).
int? parseAmountSen(String raw) {
  final s = raw
      .trim()
      .replaceFirst(RegExp(r'^rm\s*', caseSensitive: false), '')
      .replaceAll(',', '');
  final m = RegExp(r'^(\d{1,5})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final sen = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  return sen > 0 && sen < 10000000 ? sen : null;
}

/// 1250 -> "RM 12.50", 123450 -> "RM 1,234.50".
String formatSen(int sen) {
  final whole = (sen ~/ 100).toString();
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return 'RM $grouped.${(sen % 100).toString().padLeft(2, '0')}';
}

/// For the database: 1250 -> "12.50" (sent as text, so no float rounding).
String senToNumeric(int sen) =>
    '${sen ~/ 100}.${(sen % 100).toString().padLeft(2, '0')}';
