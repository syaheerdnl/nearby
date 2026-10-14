import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/list_item.dart';
import '../../models/payment_details.dart';
import '../../models/payment_record.dart';
import '../../models/receipt.dart';
import '../../services/settlement_repository.dart';

/// A receipt and how to pay it back. The list owner pays in their own bank
/// app, then marks it paid here (final). Everyone else sees it read-only.
/// Pops `true` after a payment is recorded.
class PaymentConfirmScreen extends StatefulWidget {
  const PaymentConfirmScreen({
    super.key,
    required this.item,
    required this.receipt,
    required this.buyerName,
    required this.canPay,
    this.payment,
  });

  final ListItem item;
  final Receipt receipt;
  final String buyerName;

  /// I own the list, the buyer is someone else, and it isn't paid yet.
  final bool canPay;
  final PaymentRecord? payment;

  @override
  State<PaymentConfirmScreen> createState() => _PaymentConfirmScreenState();
}

class _PaymentConfirmScreenState extends State<PaymentConfirmScreen> {
  final _repo = SettlementRepository();

  String? _photoUrl;
  PaymentDetails? _details;
  String? _qrUrl;
  bool _loading = true;
  String? _loadError;
  PaymentMethod? _method;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final photo = await _repo.receiptPhotoUrl(widget.receipt);
      PaymentDetails? details;
      String? qr;
      if (widget.canPay) {
        details = await _repo.paymentDetails(widget.receipt.uploadedBy);
        if (details != null && details.hasQr) {
          qr = await _repo.qrUrl(details.qrPath!);
        }
      }
      if (!mounted) return;
      setState(() {
        _photoUrl = photo;
        _details = details;
        _qrUrl = qr;
        _method = details == null
            ? null
            : details.hasQr
            ? PaymentMethod.qr
            : details.hasBank
            ? PaymentMethod.bank
            : null;
      });
    } catch (e) {
      debugPrint('Load payment screen failed: $e');
      if (mounted) {
        setState(
          () => _loadError =
              "Couldn't load the receipt. Check your connection and try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markPaid() async {
    final amount = formatSen(widget.receipt.amountSen);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark $amount as paid?'),
        content: Text(
          'Only do this after the money has gone to ${widget.buyerName}. '
          "It can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark as paid'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _paying = true);
    try {
      await _repo.markPaid(widget.receipt, method: _method);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Mark paid failed: $e');
      if (mounted) {
        setState(() => _paying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save the payment. Check your connection."),
          ),
        );
      }
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what copied')));
  }

  void _openPhoto(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.network(url, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = widget.receipt;
    final paid = widget.payment;
    final title = widget.canPay ? 'Pay ${widget.buyerName}' : 'Receipt';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                children: [
                  Text(
                    widget.item.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _photoUrl == null
                            ? null
                            : () => _openPhoto(_photoUrl!),
                        child: Container(
                          width: 112,
                          height: 150,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: _photoUrl == null
                              ? const Icon(Icons.receipt_long_outlined)
                              : Image.network(
                                  _photoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatSen(r.amountSen),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Bought by ${widget.buyerName}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                            Text(
                              _date(r.createdAt),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the photo to zoom',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (paid != null)
                    _Banner(
                      icon: Icons.check_circle,
                      color: const Color(0xFF1F7A55),
                      text:
                          'Paid on ${_date(paid.settledAt)}'
                          '${paid.method == PaymentMethod.qr
                              ? ' by QR'
                              : paid.method == PaymentMethod.bank
                              ? ' by bank transfer'
                              : ''}.',
                    )
                  else if (!widget.canPay)
                    _Banner(
                      icon: Icons.schedule,
                      color: scheme.onSurfaceVariant,
                      text: 'Not paid yet.',
                    )
                  else ...[
                    Text(
                      'Pay to',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._payTo(scheme),
                    const SizedBox(height: 20),
                    Text(
                      'Pay in your bank app first, then mark it here.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _paying ? null : _markPaid,
                      child: _paying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text('Mark as paid'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _payTo(ColorScheme scheme) {
    final d = _details;
    if (d == null || d.isEmpty) {
      return [
        _Banner(
          icon: Icons.info_outline,
          color: scheme.onSurfaceVariant,
          text:
              "${widget.buyerName} hasn't added payment details yet. "
              'Ask them how they want to be paid.',
        ),
      ];
    }
    return [
      if (d.hasBank)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        d.bankName,
                        d.accountName,
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.accountNumber!,
                      style: const TextStyle(fontSize: 17, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _copy(
                  d.accountNumber!.replaceAll(RegExp(r'[ -]'), ''),
                  'Account number',
                ),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
      if (d.hasQr && _qrUrl != null) ...[
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: () => _openPhoto(_qrUrl!),
            child: Container(
              width: 220,
              height: 220,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Image.network(
                _qrUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Scan with your bank app',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
      if (d.hasBank && d.hasQr) ...[
        const SizedBox(height: 14),
        SegmentedButton<PaymentMethod>(
          segments: const [
            ButtonSegment(value: PaymentMethod.qr, label: Text('Paid by QR')),
            ButtonSegment(
              value: PaymentMethod.bank,
              label: Text('Bank transfer'),
            ),
          ],
          selected: {?_method},
          emptySelectionAllowed: true,
          onSelectionChanged: (s) =>
              setState(() => _method = s.isEmpty ? null : s.first),
        ),
      ],
    ];
  }

  static String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $h:$m';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
