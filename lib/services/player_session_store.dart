import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Metadata only: expiring stream URLs are resolved again when playback resumes.
class PlayerSession {
  const PlayerSession({
    required this.queue,
    required this.currentIndex,
    required this.position,
    this.repeatMode = 0,
    this.isShuffle = false,
    this.shuffledIndices = const [],
    this.manualQueueIds = const [],
  });

  final List<Track> queue;
  final int currentIndex;
  final Duration position;
  final int repeatMode;
  final bool isShuffle;
  final List<int> shuffledIndices;
  final List<String> manualQueueIds;

  Track get currentTrack => queue[currentIndex];

  Map<String, dynamic> toJson() => {
        'queue': queue.map((track) => track.toJson()).toList(),
        'currentIndex': currentIndex,
        'positionMs': position.inMilliseconds,
        'repeatMode': repeatMode,
        'isShuffle': isShuffle,
        'shuffledIndices': shuffledIndices,
        'manualQueueIds': manualQueueIds,
      };

  factory PlayerSession.fromJson(Map<String, dynamic> json) {
    final queue = (json['queue'] as List)
        .map((value) => Track.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
    final index = json['currentIndex'] as int;
    if (index < 0 || index >= queue.length) {
      throw const FormatException('Invalid saved player index');
    }
    var position = Duration(milliseconds: json['positionMs'] as int);
    if (position.isNegative) position = Duration.zero;
    final duration = queue[index].duration;
    if (duration != null && duration > Duration.zero && position > duration) {
      position = duration;
    }
    final repeat = json['repeatMode'] as int? ?? 0;
    final shuffled = List<int>.from(json['shuffledIndices'] as List? ?? []);
    final validShuffle = shuffled.length == queue.length &&
        shuffled.toSet().length == queue.length &&
        shuffled.every((value) => value >= 0 && value < queue.length);
    return PlayerSession(
      queue: queue,
      currentIndex: index,
      position: position,
      repeatMode: repeat >= 0 && repeat <= 2 ? repeat : 0,
      isShuffle: json['isShuffle'] == true && validShuffle,
      shuffledIndices: validShuffle ? shuffled : const [],
      manualQueueIds: List<String>.from(json['manualQueueIds'] as List? ?? [])
          .where((id) =>
              id != queue[index].id && queue.any((track) => track.id == id))
          .toList(),
    );
  }
}

class PlayerSessionStore {
  static const storageKey = 'cloudio.player_session.v1';
  Future<void> _write = Future<void>.value();

  Future<PlayerSession?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(storageKey);
      if (saved == null) return null;
      return PlayerSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(saved) as Map),
      );
    } catch (error) {
      debugPrint('Could not restore player session: $error');
      return null;
    }
  }

  Future<void> save(PlayerSession session) {
    final snapshot = jsonEncode(session.toJson());
    // Serialize writes so an older progress checkpoint cannot win a race
    // with a new track selection or seek.
    _write = _write.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(storageKey, snapshot);
      } catch (error) {
        debugPrint('Could not save player session: $error');
      }
    });
    return _write;
  }
}
