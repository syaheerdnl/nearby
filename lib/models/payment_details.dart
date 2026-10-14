/// Where friends can pay me back (`payment_details` table). Entered by hand in
/// Profile; only friends can read it. Nearby only shows it, it never pays.
class PaymentDetails {
  const PaymentDetails({
    required this.userId,
    this.bankName,
    this.accountName,
    this.accountNumber,
    this.qrPath,
  });

  final String userId;
  final String? bankName;
  final String? accountName;
  final String? accountNumber;

  /// Path of the DuitNow / bank QR image in the private `payment-qr` bucket.
  final String? qrPath;

  bool get hasBank =>
      (accountNumber ?? '').isNotEmpty && (bankName ?? '').isNotEmpty;
  bool get hasQr => (qrPath ?? '').isNotEmpty;
  bool get isEmpty => !hasBank && !hasQr;

  factory PaymentDetails.fromRow(Map<String, dynamic> r) => PaymentDetails(
    userId: r['user_id'] as String,
    bankName: _blankToNull(r['bank_name']),
    accountName: _blankToNull(r['account_name']),
    accountNumber: _blankToNull(r['account_number']),
    qrPath: _blankToNull(r['qr_path']),
  );

  static String? _blankToNull(Object? v) {
    final s = (v as String?)?.trim();
    return s == null || s.isEmpty ? null : s;
  }
}

/// Account numbers: digits, spaces and dashes, 4 to 30 long (matches the
/// database check). Returns the trimmed value, or null if it isn't valid.
String? cleanAccountNumber(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  return RegExp(r'^[0-9 -]{4,30}$').hasMatch(s) ? s : null;
}
