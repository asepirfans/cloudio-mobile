import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';

class PlaylistController extends ChangeNotifier {
  static final PlaylistController instance = PlaylistController._internal();
  PlaylistController._internal() {
    _ready = _load();
  }

  static const _storageKey = 'cloudio.playlists.v1';
  final List<Playlist> _playlists = [];
  late final Future<void> _ready;
  bool _isLoaded = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isLoaded => _isLoaded;

  Future<void> ensureLoaded() => _ready;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_storageKey);
      if (saved != null) {
        final values = jsonDecode(saved) as List<dynamic>;
        _playlists
          ..clear()
          ..addAll(
            values.map(
              (value) => Playlist.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            ),
          );
      }
    } catch (error) {
      debugPrint('Failed to load local playlists: $error');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<Playlist> createPlaylist(String name) async {
    await _ready;
    final cleanName = name.trim();
    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: cleanName.isEmpty ? 'Playlist baru' : cleanName,
      createdAt: DateTime.now(),
    );
    _playlists.insert(0, playlist);
    notifyListeners();
    await _save();
    return playlist;
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _ready;
    _playlists.removeWhere((playlist) => playlist.id == playlistId);
    notifyListeners();
    await _save();
  }

  Future<bool> addTrack(String playlistId, Track track) async {
    await _ready;
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index < 0) return false;

    final playlist = _playlists[index];
    if (playlist.tracks.any((item) => item.id == track.id)) return false;
    _playlists[index] = playlist.copyWith(tracks: [...playlist.tracks, track]);
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    await _ready;
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index < 0) return;
    final playlist = _playlists[index];
    _playlists[index] = playlist.copyWith(
      tracks: playlist.tracks.where((track) => track.id != trackId).toList(),
    );
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(_playlists.map((playlist) => playlist.toJson()).toList()),
    );
  }
}
