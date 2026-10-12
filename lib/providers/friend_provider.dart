import 'package:flutter/foundation.dart';

import '../models/friend.dart';
import '../services/friend_repository.dart';

class FriendProvider extends ChangeNotifier {
  FriendProvider({FriendRepository? repository})
      : _repo = repository ?? FriendRepository();

  final FriendRepository _repo;

  List<Friend> _all = const [];
  bool _loading = false;
  String? _error;

  bool get loading => _loading;
  String? get error => _error;
  List<Friend> get friends =>
      _all.where((f) => f.state == FriendState.accepted).toList();
  List<Friend> get incoming =>
      _all.where((f) => f.state == FriendState.incoming).toList();
  List<Friend> get outgoing =>
      _all.where((f) => f.state == FriendState.outgoing).toList();

  /// Status of [userId] relative to me, or null if no row.
  FriendState? stateOf(String userId) {
    for (final f in _all) {
      if (f.userId == userId) return f.state;
    }
    return null;
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _all = await _repo.list();
    } catch (e) {
      _error = 'Could not load friends. Check your connection.';
      debugPrint('Load friends failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<ProfileHit>> search(String q) => _repo.search(q);

  /// Returns an error message, or null on success.
  Future<String?> _run(Future<void> Function() action) async {
    try {
      await action();
      await load();
      return null;
    } on FriendException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Friend action failed: $e');
      return 'Something went wrong. Try again.';
    }
  }

  Future<String?> sendRequest(String userId) =>
      _run(() => _repo.sendRequest(userId));
  Future<String?> accept(Friend f) => _run(() => _repo.accept(f.rowId));
  Future<String?> remove(Friend f) => _run(() => _repo.remove(f.rowId));

  void reset() {
    _all = const [];
    _error = null;
    notifyListeners();
  }
}
