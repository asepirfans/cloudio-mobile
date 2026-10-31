import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Recent songs played on this device. Cloudio has no user accounts yet.
class ListeningHistoryController extends ChangeNotifier {
  static final ListeningHistoryController instance =
      ListeningHistoryController._internal();

  ListeningHistoryController._internal() {
    _ready = _load();
  }

  static const _storageKey = 'cloudio.listening_history.v1';
  static const _maxItems = 200;
  final List<Track> _items = [];
  late final Future<void> _ready;
  Future<void> _write = Future<void>.value();
  bool _isLoaded = false;

  List<Track> get items => List.unmodifiable(_items);
  bool get isLoaded => _isLoaded;
  Future<void> ensureLoaded() => _ready;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_storageKey);
      if (saved == null) return;
      final decoded = jsonDecode(saved) as List<dynamic>;
      _items
        ..clear()
        ..addAll(decoded.map((value) => Track.fromJson(
              Map<String, dynamic>.from(value as Map),
            )));
    } catch (error) {
      debugPrint('Failed to load listening history: $error');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> record(Track track) async {
    await _ready;
    _items.removeWhere((item) => item.id == track.id);
    _items.insert(0, track);
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String trackId) async {
    await _ready;
    _items.removeWhere((item) => item.id == trackId);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    await _ready;
    _items.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() {
    final snapshot = jsonEncode(_items.map((track) => track.toJson()).toList());
    _write = _write.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_storageKey, snapshot);
      } catch (error) {
        debugPrint('Failed to save listening history: $error');
      }
    });
    return _write;
  }
}
