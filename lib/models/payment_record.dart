/// How the owner paid: scanned the QR, or a bank transfer to the account.
enum PaymentMethod {
  qr,
  bank;

  static PaymentMethod? fromName(String? v) {
    for (final m in values) {
      if (m.name == v) return m;
    }
    return null;
  }
}

/// The owner paid the buyer back for a receipt (`payment_records` table).
/// Created only when the payment is made, so it is always settled, and it is
/// final: the database has no update or delete policy for it.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.receiptId,
    required this.payerId,
    required this.payeeId,
    required this.settledAt,
    this.method,
  });

  final String id;
  final String receiptId;
  final String payerId;
  final String payeeId;
  final PaymentMethod? method;
  final DateTime settledAt;

  factory PaymentRecord.fromRow(Map<String, dynamic> r) => PaymentRecord(
    id: r['id'] as String,
    receiptId: r['receipt_id'] as String,
    payerId: r['payer_id'] as String,
    payeeId: r['payee_id'] as String,
    method: PaymentMethod.fromName(r['method'] as String?),
    settledAt: DateTime.parse(r['settled_at'] as String).toLocal(),
  );
}
