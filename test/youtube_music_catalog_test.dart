import 'dart:convert';

import 'package:cloudio_mobile/services/youtube_music_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> result(
  String id,
  String title, {
  String artist = 'Musisi',
  String type = 'MUSIC_VIDEO_TYPE_ATV',
  String pageType = 'MUSIC_PAGE_TYPE_ARTIST',
  String length = '3:20',
}) =>
    {
      'musicResponsiveListItemRenderer': {
        'playlistItemData': {'videoId': id},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {
                    'text': title,
                    'navigationEndpoint': {
                      'watchEndpoint': {
                        'videoId': id,
                        'watchEndpointMusicSupportedConfigs': {
                          'watchEndpointMusicConfig': {'musicVideoType': type},
                        },
                      },
                    },
                  },
                ],
              },
            },
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {
                    'text': artist,
                    'navigationEndpoint': {
                      'browseEndpoint': {
                        'browseEndpointContextSupportedConfigs': {
                          'browseEndpointContextMusicConfig': {
                            'pageType': pageType,
                          },
                        },
                      },
                    },
                  },
                  {'text': ' • '},
                  {'text': length},
                ],
              },
            },
          },
        ],
      },
    };

void main() {
  test('requests songs and rejects mixed spoken results before the limit',
      () async {
    final catalog = YoutubeMusicCatalog(client: MockClient((request) async {
      expect(request.url.host, 'music.youtube.com');
      expect(request.url.path, '/youtubei/v1/search');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['query'], 'Musisi');
      expect(body['params'], 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D');
      return http.Response(
          jsonEncode({
            'contents': [
              result('podcast', 'Podcast Musisi'),
              result('episode', 'Cerita Malam',
                  type: 'MUSIC_VIDEO_TYPE_PODCAST'),
              result('podcast-page', 'Cerita Malam',
                  pageType: 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE'),
              result('news', 'Kabar Hari Ini', artist: 'CNN Indonesia'),
              result('wawancanda', 'WAWANCANDA DEDDY CORBUZIER - GAJI 700RB',
                  artist: 'Abdel Achrian', length: '1:29:47'),
              result('raditya',
                  'RADITYA DIKA - JADI BAPAK, STANDUP, SAMPAI NGOMONGIN SAHAM',
                  artist: 'Abdel Achrian', length: '55:21'),
              result(
                  'unlabeled-talk', 'Raditya Dika Bahagia Ajak Jarwo Bercanda',
                  artist: 'Jarwo Kwat', length: '23:21'),
              result('song', 'Lagu Pertama'),
              result('song', 'Lagu Pertama'),
              result('video', 'Lagu Kedua', type: 'MUSIC_VIDEO_TYPE_OMV'),
              result('upload', 'Lagu Ketiga', type: 'MUSIC_VIDEO_TYPE_UGC'),
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(catalog.close);

    final tracks = await catalog.searchSongs(' Musisi ', limit: 3);

    expect(tracks.map((track) => track.id),
        ['ytm:song', 'ytm:video', 'ytm:upload']);
    expect(tracks.first.artist, 'Musisi');
    expect(tracks.first.duration, const Duration(minutes: 3, seconds: 20));
  });

  test(
      'playlist discovery ignores song and artist results; browse excludes recommendations and unavailable items',
      () async {
    final catalog = YoutubeMusicCatalog(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith('/search')) {
        expect(body['params'], 'EgeKAQQoAEAB');
        Map<String, dynamic> playlist(String id) => {
              'musicResponsiveListItemRenderer': {
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': id}
                },
                'flexColumns': [
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': 'TikTok picks'}
                        ]
                      }
                    }
                  }
                ],
              }
            };
        return http.Response(
            jsonEncode({
              'contents': [
                playlist('VLcurator'),
                playlist('VLcurator'),
                playlist('UCartist'),
                result('song', 'Song')
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      expect(body['browseId'], 'VLcurator');
      final available = result('available', 'Lagu');
      final renderer =
          available['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
      final columns = renderer['flexColumns'] as List;
      final metadata = columns[1]['musicResponsiveListItemFlexColumnRenderer']
          ['text']['runs'] as List;
      metadata.removeLast();
      renderer['fixedColumns'] = [
        {
          'musicResponsiveListItemFixedColumnRenderer': {
            'text': {
              'runs': [
                {'text': '3.25'}
              ]
            }
          }
        }
      ];
      final unavailable = result('private', 'Private');
      unavailable['musicResponsiveListItemRenderer']['isPlayable'] = false;
      return http.Response(
          jsonEncode({
            'contents': [
              {
                'musicPlaylistShelfRenderer': {
                  'contents': [
                    available,
                    unavailable,
                    result('talk', 'Podcast episode')
                  ]
                }
              }
            ],
            'recommendations': [result('unrelated', 'Other')],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(catalog.close);
    final playlists = await catalog.searchPlaylists('TikTok');
    expect(playlists.map((p) => p.browseId), ['VLcurator']);
    final songs = await catalog.playlistTracks(playlists.single.browseId);
    expect(songs.map((t) => t.id), ['ytm:available']);
    expect(songs.single.duration, const Duration(minutes: 3, seconds: 25));
  });

  test('songs shelf still accepts long recorded DJ sets', () async {
    final catalog = YoutubeMusicCatalog(client: MockClient((request) async {
      return http.Response(
        jsonEncode({
          'contents': [
            result('dj', 'HIPDUT BREAKBEAT LIVE SET MIX',
                artist: 'motomovth', length: '36:19'),
          ]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));
    addTearDown(catalog.close);
    final tracks = await catalog.searchSongs('hipdut');
    expect(tracks.map((track) => track.id), ['ytm:dj']);
  });
}
