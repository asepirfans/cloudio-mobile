import 'package:flutter/foundation.dart';

import 'track.dart';

@immutable
class Playlist {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<Track> tracks;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.tracks = const [],
  });

  Playlist copyWith({String? name, List<Track>? tracks}) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'tracks': tracks.map((track) => track.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? const [];
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      tracks: rawTracks
          .map((item) => Track.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}
