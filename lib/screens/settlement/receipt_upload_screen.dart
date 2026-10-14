import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/list_item.dart';
import '../../models/receipt.dart';
import '../../services/settlement_repository.dart';

/// The buyer adds (or fixes, until it's paid) the receipt for an item they
/// bought: a photo and the amount. Pops `true` when saved.
class ReceiptUploadScreen extends StatefulWidget {
  const ReceiptUploadScreen({super.key, required this.item, this.existing});

  final ListItem item;
  final Receipt? existing;

  @override
  State<ReceiptUploadScreen> createState() => _ReceiptUploadScreenState();
}

class _ReceiptUploadScreenState extends State<ReceiptUploadScreen> {
  final _repo = SettlementRepository();
  final _amount = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _photo;
  String _ext = 'jpg';
  String? _existingUrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _amount.text = senToNumeric(e.amountSen);
      _repo
          .receiptPhotoUrl(e)
          .then((u) {
            if (mounted) setState(() => _existingUrl = u);
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      // Shrunk on the phone: a receipt stays readable and uploads fast.
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final dot = x.name.lastIndexOf('.');
      final ext = dot < 0 ? 'jpg' : x.name.substring(dot + 1).toLowerCase();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _ext = const {'png', 'webp'}.contains(ext) ? ext : 'jpg';
        _error = null;
      });
    } catch (e) {
      debugPrint('Pick receipt failed: $e');
      if (mounted) {
        setState(
          () => _error = source == ImageSource.camera
              ? "Couldn't open the camera."
              : "Couldn't open your photos.",
        );
      }
    }
  }

  Future<void> _save() async {
    final sen = parseAmountSen(_amount.text);
    if (sen == null) {
      setState(() => _error = 'Enter the amount, for example 12.50');
      return;
    }
    if (_photo == null && widget.existing == null) {
      setState(() => _error = 'Add a photo of the receipt.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.saveReceipt(
        item: widget.item,
        amountSen: sen,
        photo: _photo,
        photoExt: _ext,
        existing: widget.existing,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Save receipt failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = settlementErrorMessage(e, 'save the receipt');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit receipt' : 'Add receipt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            Text(
              widget.item.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'The owner sees this and pays you back.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: _photo != null
                    ? Image.memory(_photo!, fit: BoxFit.contain)
                    : _existingUrl != null
                    ? Image.network(
                        _existingUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const _NoPhoto(),
                      )
                    : const _NoPhoto(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('From photos'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: 'RM ',
                hintText: '12.50',
              ),
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

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 44,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            'No photo yet',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
