import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/models/list_item.dart';
import 'package:nearby/models/payment_details.dart';
import 'package:nearby/models/payment_record.dart';
import 'package:nearby/models/receipt.dart';
import 'package:nearby/services/settlement_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('parseAmountSen', () {
    test('reads normal amounts as whole sen', () {
      expect(parseAmountSen('12.50'), 1250);
      expect(parseAmountSen('12.5'), 1250);
      expect(parseAmountSen('12'), 1200);
      expect(parseAmountSen('0.05'), 5);
      expect(parseAmountSen(' RM 7.90 '), 790);
      expect(parseAmountSen('rm3'), 300);
      expect(parseAmountSen('1,234.56'), 123456);
    });

    test('keeps cents exact (no float rounding)', () {
      expect(parseAmountSen('0.10'), 10);
      expect(parseAmountSen('12.10'), 1210);
      expect(parseAmountSen('99999.99'), 9999999);
    });

    test('rejects what the database would reject', () {
      expect(parseAmountSen(''), isNull);
      expect(parseAmountSen('abc'), isNull);
      expect(parseAmountSen('0'), isNull);
      expect(parseAmountSen('0.00'), isNull);
      expect(parseAmountSen('-5'), isNull);
      expect(parseAmountSen('12.345'), isNull);
      expect(parseAmountSen('100000'), isNull);
      expect(parseAmountSen('1.2.3'), isNull);
    });
  });

  group('money formatting', () {
    test('formatSen shows ringgit with 2 decimals and grouping', () {
      expect(formatSen(1250), 'RM 12.50');
      expect(formatSen(5), 'RM 0.05');
      expect(formatSen(123456), 'RM 1,234.56');
      expect(formatSen(9999999), 'RM 99,999.99');
    });

    test('senToNumeric round-trips with parseAmountSen', () {
      for (final sen in [5, 10, 99, 100, 1210, 123456, 9999999]) {
        expect(parseAmountSen(senToNumeric(sen)), sen);
      }
    });

    test('senFromNumeric accepts number or text from Postgres', () {
      expect(senFromNumeric(12.5), 1250);
      expect(senFromNumeric(12.1), 1210);
      expect(senFromNumeric('12.10'), 1210);
      expect(senFromNumeric(null), 0);
    });
  });

  group('rows', () {
    test('Receipt.fromRow', () {
      final r = Receipt.fromRow({
        'id': 'r1',
        'list_item_id': 'i1',
        'uploaded_by': 'u2',
        'image_url': 'l1/i1/a.jpg',
        'amount': '12.50',
        'created_at': '2026-10-14T02:00:00Z',
      });
      expect(r.amountSen, 1250);
      expect(r.imageUrl, 'l1/i1/a.jpg');
      expect(r.uploadedBy, 'u2');
    });

    test('PaymentRecord.fromRow, method optional', () {
      final p = PaymentRecord.fromRow({
        'id': 'p1',
        'receipt_id': 'r1',
        'payer_id': 'u1',
        'payee_id': 'u2',
        'method': 'qr',
        'settled_at': '2026-10-14T02:05:00Z',
      });
      expect(p.method, PaymentMethod.qr);
      expect(
        PaymentRecord.fromRow({
          'id': 'p2',
          'receipt_id': 'r2',
          'payer_id': 'u1',
          'payee_id': 'u2',
          'method': null,
          'settled_at': '2026-10-14T02:05:00Z',
        }).method,
        isNull,
      );
    });

    test('PaymentDetails: blanks are empty, bank needs name and number', () {
      final d = PaymentDetails.fromRow({
        'user_id': 'u2',
        'bank_name': ' ',
        'account_name': null,
        'account_number': '1234 5678',
        'qr_path': '',
      });
      expect(d.bankName, isNull);
      expect(d.hasBank, isFalse);
      expect(d.hasQr, isFalse);
      expect(d.isEmpty, isTrue);
      final full = PaymentDetails.fromRow({
        'user_id': 'u2',
        'bank_name': 'Maybank',
        'account_number': '1234 5678',
        'qr_path': 'u2/qr.jpg',
      });
      expect(full.hasBank, isTrue);
      expect(full.hasQr, isTrue);
    });

    test('cleanAccountNumber matches the database check', () {
      expect(cleanAccountNumber(' 1234  5678 '), '1234 5678');
      expect(cleanAccountNumber('5641-2233-0098'), '5641-2233-0098');
      expect(cleanAccountNumber('123'), isNull);
      expect(cleanAccountNumber('12a4'), isNull);
    });
  });

  group('settled items are final', () {
    ListItem item(ItemStatus status) => ListItem(
          id: 'i1',
          listId: 'l1',
          name: 'Telur',
          quantity: 1,
          status: status,
          createdBy: 'owner',
          claimedBy: 'friend',
        );

    test('no action changes a settled item', () {
      for (final action in ItemAction.values) {
        expect(ListItem.transition(item(ItemStatus.settled), action, 'friend'),
            isNull,
            reason: action.name);
        expect(ListItem.transition(item(ItemStatus.settled), action, 'owner'),
            isNull,
            reason: action.name);
      }
    });

    test('a bought item can still be reopened before it is paid', () {
      expect(ListItem.transition(item(ItemStatus.bought), ItemAction.reopen, 'owner'),
          {'status': 'open', 'claimed_by': null});
    });
  });

  group('settlementErrorMessage', () {
    test('only blames the connection for network errors', () {
      expect(settlementErrorMessage(const SocketException('x'), 'save it'),
          contains('Check your connection'));
    });

    test('a refusal from the server says so', () {
      final rls = StorageException(
          'new row violates row-level security policy',
          statusCode: '403');
      expect(settlementErrorMessage(rls, 'save the receipt'),
          contains("not allowed"));
      expect(settlementErrorMessage(rls, 'save the receipt'),
          isNot(contains('connection')));
      expect(
          settlementErrorMessage(
              const PostgrestException(message: 'denied', code: '42501'),
              'save it'),
          contains('not allowed'));
    });

    test('own validation messages pass through, others are generic', () {
      expect(
          settlementErrorMessage(
              const SettlementException('Add a photo of the receipt.'), 'x'),
          'Add a photo of the receipt.');
      expect(settlementErrorMessage(Exception('boom'), 'save it'),
          "Couldn't save it. Please try again.");
    });
  });
}
