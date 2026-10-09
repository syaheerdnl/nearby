import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/place_result.dart';
import '../services/place_search_service.dart';

/// Search box with live results (Photon). Debounced so typing doesn't
/// flood the shared server.
class PlaceSearchBar extends StatefulWidget {
  const PlaceSearchBar({
    super.key,
    required this.onSelected,
    this.biasPoint,
    this.hintText = 'Search a place',
    this.trailing,
  });

  /// Shown at the right end of the pill when the box is empty (e.g. avatar).
  final Widget? trailing;

  final ValueChanged<PlaceResult> onSelected;

  /// Called on each search; results near this point rank higher.
  final LatLng? Function()? biasPoint;
  final String hintText;

  @override
  State<PlaceSearchBar> createState() => _PlaceSearchBarState();
}

class _PlaceSearchBarState extends State<PlaceSearchBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _service = PlaceSearchService();
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() {}); // show/hide the clear button
    if (text.trim().length < 3) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(text));
  }

  Future<void> _search(String text) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final near = widget.biasPoint?.call();
      final results = await _service.search(text,
          nearLat: near?.latitude, nearLng: near?.longitude);
      if (!mounted || id != _requestId) return; // a newer search won
      setState(() {
        _results = results;
        _error = results.isEmpty ? 'No places found. You can still tap the map.' : null;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = const [];
        _error = 'Search is unavailable right now. Tap the map instead.';
      });
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  void _clear() {
    _debounce?.cancel();
    _requestId++;
    _controller.clear();
    setState(() {
      _results = const [];
      _error = null;
      _loading = false;
    });
  }

  void _pick(PlaceResult place) {
    _focus.unfocus();
    _clear();
    widget.onSelected(place);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 2,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(24),
          color: theme.colorScheme.surface,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (t) {
              _debounce?.cancel();
              if (t.trim().length >= 3) _search(t);
            },
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_controller.text.isEmpty
                      ? (widget.trailing == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.all(6),
                              child: widget.trailing,
                            ))
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        )),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (_results.isNotEmpty || _error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 2,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          return ListTile(
                            leading: Icon(Icons.place_outlined,
                                color: theme.colorScheme.onSurfaceVariant),
                            title: Text(r.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: r.subtitle.isEmpty
                                ? null
                                : Text(r.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            onTap: () => _pick(r),
                          );
                        },
                      ),
              ),
            ),
          ),
        if (_results.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text('Search by Photon · OpenStreetMap',
                  style: theme.textTheme.labelSmall),
            ),
          ),
      ],
    );
  }
}
