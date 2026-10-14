import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/payment_details.dart';
import '../../services/settlement_repository.dart';

/// Where friends can pay me back: bank account and/or a DuitNow QR image.
/// Only accepted friends can read it (RLS). Nearby never makes payments.
class PaymentDetailsScreen extends StatefulWidget {
  const PaymentDetailsScreen({super.key});

  @override
  State<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends State<PaymentDetailsScreen> {
  final _repo = SettlementRepository();
  final _bank = TextEditingController();
  final _name = TextEditingController();
  final _number = TextEditingController();

  PaymentDetails? _current;
  String? _qrUrl;
  Uint8List? _newQr;
  String _qrExt = 'jpg';
  bool _removeQr = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bank.dispose();
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final d = await _repo.paymentDetails(_repo.me);
      final qr = d != null && d.hasQr ? await _repo.qrUrl(d.qrPath!) : null;
      if (!mounted) return;
      setState(() {
        _current = d;
        _qrUrl = qr;
        _bank.text = d?.bankName ?? '';
        _name.text = d?.accountName ?? '';
        _number.text = d?.accountNumber ?? '';
      });
    } catch (e) {
      debugPrint('Load payment details failed: $e');
      if (mounted) {
        // Don't show an empty form: saving it would wipe the real details.
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickQr() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 90,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final dot = x.name.lastIndexOf('.');
      final ext = dot < 0 ? 'jpg' : x.name.substring(dot + 1).toLowerCase();
      if (!mounted) return;
      setState(() {
        _newQr = bytes;
        _qrExt = const {'png', 'webp'}.contains(ext) ? ext : 'jpg';
        _removeQr = false;
      });
    } catch (e) {
      debugPrint('Pick QR failed: $e');
      if (mounted) setState(() => _error = "Couldn't open your photos.");
    }
  }

  Future<void> _save() async {
    String? clean(TextEditingController c) {
      final s = c.text.trim();
      return s.isEmpty ? null : s;
    }

    final rawNumber = _number.text.trim();
    final number = rawNumber.isEmpty ? null : cleanAccountNumber(rawNumber);
    if (rawNumber.isNotEmpty && number == null) {
      setState(
        () => _error =
            'Account number: digits only (spaces and '
            'dashes are fine), 4 to 30 long.',
      );
      return;
    }
    if (number != null && clean(_bank) == null) {
      setState(() => _error = 'Add the bank name too.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.saveMyPaymentDetails(
        bankName: clean(_bank),
        accountName: clean(_name),
        accountNumber: number,
        qr: _newQr,
        qrExt: _qrExt,
        removeQr: _removeQr,
        currentQrPath: _current?.qrPath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Save payment details failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = settlementErrorMessage(e, 'save your details');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showQr = !_removeQr && (_newQr != null || _qrUrl != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Payment details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Couldn't load your details. Check your connection "
                      'and try again.',
                      textAlign: TextAlign.center,
                    ),
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
                    'Friends see this when they pay you back for something '
                    'you bought. Only friends can see it, and Nearby never '
                    'takes payments.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _bank,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Bank',
                      hintText: 'Maybank',
                    ),
                  ),
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Name on the account',
                    ),
                  ),
                  TextField(
                    controller: _number,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Account number',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'DuitNow or bank QR',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (showQr)
                    Center(
                      child: Container(
                        width: 200,
                        height: 200,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: _newQr != null
                            ? Image.memory(_newQr!, fit: BoxFit.contain)
                            : Image.network(
                                _qrUrl!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _pickQr,
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(showQr ? 'Change QR' : 'Add QR image'),
                        ),
                      ),
                      if (showQr) ...[
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _newQr = null;
                                  _removeQr = true;
                                }),
                          child: const Text('Remove'),
                        ),
                      ],
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
