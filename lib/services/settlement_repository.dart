import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase_client.dart';
import '../models/list_item.dart';
import '../models/payment_details.dart';
import '../models/payment_record.dart';
import '../models/receipt.dart';

/// Receipts, payments and payment details (Phase 3). Server only, like shared
/// lists. RLS decides who may see or write what; photos live in private
/// buckets and are shown through short-lived signed URLs.
class SettlementRepository {
  static const _receiptsBucket = 'receipts';
  static const _qrBucket = 'payment-qr';
  static const _uuid = Uuid();

  String get me {
    final id = supabase.auth.currentUser?.id;
    if (id == null) throw const SettlementException('Not signed in.');
    return id;
  }

  // ---------- receipts and payments ----------

  /// Receipts for these items, keyed by item id.
  Future<Map<String, Receipt>> receiptsFor(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await supabase
        .from('receipts')
        .select()
        .inFilter('list_item_id', ids);
    final out = <String, Receipt>{};
    for (final r in rows.map(Receipt.fromRow)) {
      out[r.listItemId] = r;
    }
    return out;
  }

  /// Payments for these receipts, keyed by receipt id. RLS only returns the
  /// ones where I am the payer or the payee.
  Future<Map<String, PaymentRecord>> paymentsFor(
    Iterable<String> receiptIds,
  ) async {
    final ids = receiptIds.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await supabase
        .from('payment_records')
        .select()
        .inFilter('receipt_id', ids);
    final out = <String, PaymentRecord>{};
    for (final p in rows.map(PaymentRecord.fromRow)) {
      out[p.receiptId] = p;
    }
    return out;
  }

  /// Adds the receipt for an item I bought, or replaces the photo/amount of
  /// my unpaid one. [photo] is null when only the amount changes.
  Future<void> saveReceipt({
    required ListItem item,
    required int amountSen,
    Uint8List? photo,
    String photoExt = 'jpg',
    Receipt? existing,
  }) async {
    if (existing == null && photo == null) {
      throw const SettlementException('Add a photo of the receipt.');
    }
    String? path;
    if (photo != null) {
      path = '${item.listId}/${item.id}/${_uuid.v4()}.$photoExt';
      await supabase.storage
          .from(_receiptsBucket)
          .uploadBinary(
            path,
            photo,
            fileOptions: FileOptions(contentType: _mime(photoExt)),
          );
    }
    final amount = senToNumeric(amountSen);
    if (existing == null) {
      await supabase.from('receipts').insert({
        'list_item_id': item.id,
        'uploaded_by': me,
        'image_url': path,
        'amount': amount,
      });
    } else {
      await supabase
          .from('receipts')
          .update({'amount': amount, 'image_url': ?path})
          .eq('id', existing.id);
    }
    // Realtime only watches list_items. Writing the same status again still
    // sends an UPDATE event, so the owner's open list shows the receipt live.
    await supabase
        .from('list_items')
        .update({'status': ItemStatus.bought.name}).eq('id', item.id);
  }

  /// Records that I (the list owner) paid the buyer. The database settles the
  /// item in the same transaction, and the record can't be changed after.
  Future<void> markPaid(Receipt receipt, {PaymentMethod? method}) =>
      supabase.from('payment_records').insert({
        'receipt_id': receipt.id,
        'payer_id': me,
        'payee_id': receipt.uploadedBy,
        'method': method?.name,
      });

  /// A link to show a receipt photo, valid for 10 minutes.
  Future<String> receiptPhotoUrl(Receipt r) =>
      supabase.storage.from(_receiptsBucket).createSignedUrl(r.imageUrl, 600);

  // ---------- payment details ----------

  /// My own details, or a friend's (RLS hides non-friends: null then).
  Future<PaymentDetails?> paymentDetails(String userId) async {
    final row = await supabase
        .from('payment_details')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : PaymentDetails.fromRow(row);
  }

  Future<void> saveMyPaymentDetails({
    required String? bankName,
    required String? accountName,
    required String? accountNumber,
    Uint8List? qr,
    String qrExt = 'jpg',
    bool removeQr = false,
    String? currentQrPath,
  }) async {
    String? qrPath = removeQr ? null : currentQrPath;
    if (qr != null) {
      qrPath = '$me/qr-${_uuid.v4()}.$qrExt';
      await supabase.storage
          .from(_qrBucket)
          .uploadBinary(
            qrPath,
            qr,
            fileOptions: FileOptions(contentType: _mime(qrExt)),
          );
    }
    await supabase.from('payment_details').upsert({
      'user_id': me,
      'bank_name': bankName,
      'account_name': accountName,
      'account_number': accountNumber,
      'qr_path': qrPath,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    // Old QR files are no longer referenced: remove them (best effort).
    if (currentQrPath != null && currentQrPath != qrPath) {
      try {
        await supabase.storage.from(_qrBucket).remove([currentQrPath]);
      } catch (_) {}
    }
  }

  Future<String> qrUrl(String path) =>
      supabase.storage.from(_qrBucket).createSignedUrl(path, 600);

  static String _mime(String ext) => switch (ext.toLowerCase()) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

class SettlementException implements Exception {
  const SettlementException(this.message);
  final String message;
  @override
  String toString() => message;
}
