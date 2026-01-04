// lib/providers/lyrics_provider.dart
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

enum LyricsSource { kugou, someRandomApi }

class LyricsModel {
  final int timestamp;
  final String text;
  final String timeFormatted;

  LyricsModel({
    required this.timestamp,
    required this.text,
    required this.timeFormatted,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'text': text,
    'time': timeFormatted,
  };
}

class PlainLyricsLine {
  final String text;

  PlainLyricsLine({required this.text});

  Map<String, dynamic> toJson() => {'text': text};
}

class LyricsParser {
  static List<LyricsModel> parseLrc(String lrcContent) {
    final lines = <LyricsModel>[];
    final lrcLines = lrcContent.split('\n');

    for (final line in lrcLines) {
      final match = RegExp(
        r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)',
      ).firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = int.parse(match.group(3)!.padRight(3, '0'));
        final text = match.group(4)!.trim();

        final timestamp =
            (minutes * 60 * 1000) + (seconds * 1000) + milliseconds;
        final timeFormatted =
            '${match.group(1)}:${match.group(2)}.${match.group(3)}';

        if (text.isNotEmpty) {
          lines.add(
            LyricsModel(
              timestamp: timestamp,
              text: text,
              timeFormatted: timeFormatted,
            ),
          );
        }
      }
    }

    return lines;
  }

  static String toLrcString(List<LyricsModel> lines) {
    return lines
        .map((line) => '[${line.timeFormatted}]${line.text}')
        .join('\n');
  }
}

class LyricsProvider {
  static const int pageSize = 8;
  static const int durationTolerance = 8;

  final http.Client client = http.Client();
  LyricsSource selectedSource = LyricsSource.kugou;

  final List<String> _userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.3 Safari/605.1.15',
    'Mozilla/5.0 (Linux; Android 12; Pixel 6 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 11; SM-A515F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.6312.120 Mobile Safari/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile Safari/604.1',
    'Mozilla/5.0 (iPad; CPU OS 15_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari/604.1',
  ];

  Map<String, String> get randomHeaders => {
    'User-Agent': _userAgents[Random().nextInt(_userAgents.length)],
  };

  Future<Map<String, dynamic>> fetchLyrics(
    String title,
    String artist, {
    int duration = -1,
  }) async {
    if (title.trim().isEmpty || artist.trim().isEmpty) {
      return {'success': false, 'error': 'Title or artist cannot be empty'};
    }

    print(
      'LYRICS_PROVIDER: fetchLyrics called with selectedSource: $selectedSource',
    );

    try {
      Map<String, dynamic> result;

      switch (selectedSource) {
        case LyricsSource.kugou:
          print('LYRICS_PROVIDER: Using Kugou source (Word by word)');
          result = await _fetchFromKugou(title, artist, duration: duration);
          break;
        case LyricsSource.someRandomApi:
          print('LYRICS_PROVIDER: Using SomeRandomApi source (Line by line)');
          result = await _fetchFromSomeRandomApi(title, artist);
          break;
      }

      print(
        'LYRICS_PROVIDER: Result from $selectedSource: ${result['success']}',
      );
      return result;
    } catch (e) {
      print('LYRICS_PROVIDER ERROR: $e');
      return {'success': false, 'error': 'Failed to fetch lyrics: $e'};
    }
  }

  Future<Map<String, dynamic>> _fetchFromSomeRandomApi(
    String title,
    String artist,
  ) async {
    try {
      final fullTitle = '$title $artist';
      final uri = Uri.https('some-random-api.com', '/lyrics', {
        'title': fullTitle,
      });

      print('LYRICS_PROVIDER: Fetching from SomeRandomApi for: $fullTitle');

      final response = await client.get(uri, headers: randomHeaders);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['lyrics'] != null &&
            data['lyrics'].toString().trim().isNotEmpty) {
          final lyrics = data['lyrics'] as String;
          final lines = lyrics
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .map((line) => PlainLyricsLine(text: line.trim()))
              .toList();

          if (lines.isNotEmpty) {
            print(
              "LYRICS_PROVIDER: SUCCESS - Used SomeRandomApi, found ${lines.length} lines",
            );
            return {
              'success': true,
              'plain': true,
              'lines': lines.map((e) => e.toJson()).toList(),
              'source': 'SomeRandomAPI',
              'total_lines': lines.length,
              'type': 'line_by_line',
            };
          }
        }
      } else {
        print(
          'LYRICS_PROVIDER: SomeRandomApi returned status ${response.statusCode}',
        );
      }
    } catch (e) {
      print('LYRICS_PROVIDER: SomeRandomApi error: $e');
    }

    return {
      'success': false,
      'error': 'No lyrics found using SomeRandomAPI for $title by $artist',
    };
  }

  Future<Map<String, dynamic>> _fetchFromKugou(
    String title,
    String artist, {
    int duration = -1,
  }) async {
    try {
      final keyword = '$title - $artist';
      print('LYRICS_PROVIDER: Fetching from Kugou for: $keyword');

      final searchResponse = await client.get(
        Uri.https('mobileservice.kugou.com', '/api/v3/search/song', {
          'version': '9108',
          'plat': '0',
          'pagesize': '$pageSize',
          'showtype': '0',
          'keyword': keyword,
        }),
        headers: randomHeaders,
      );

      if (searchResponse.statusCode != 200) {
        print(
          'LYRICS_PROVIDER: Kugou search failed with status ${searchResponse.statusCode}',
        );
        return {
          'success': false,
          'error': 'Kugou search API returned ${searchResponse.statusCode}',
        };
      }

      final searchData = json.decode(searchResponse.body);
      final songs = searchData['data']?['info'];

      if (songs == null || songs.isEmpty) {
        print('LYRICS_PROVIDER: No songs found on Kugou for: $keyword');
        return {
          'success': false,
          'error': 'No songs found on Kugou for $title by $artist',
        };
      }

      for (final song in songs) {
        if (duration == -1 ||
            (song['duration'] != null &&
                (song['duration'] - duration).abs() <= durationTolerance)) {
          final hash = song['hash'];
          if (hash == null) continue;

          try {
            final lyricsSearchResponse = await client.get(
              Uri.https('lyrics.kugou.com', '/search', {
                'ver': '1',
                'man': 'yes',
                'client': 'pc',
                'hash': hash,
              }),
              headers: randomHeaders,
            );

            if (lyricsSearchResponse.statusCode != 200) continue;

            final lyricsData = json.decode(lyricsSearchResponse.body);
            final candidates = lyricsData['candidates'];

            if (candidates != null && candidates.isNotEmpty) {
              final candidate = candidates[0];

              final downloadResponse = await client.get(
                Uri.https('lyrics.kugou.com', '/download', {
                  'fmt': 'lrc',
                  'charset': 'utf8',
                  'client': 'pc',
                  'ver': '1',
                  'id': candidate['id'].toString(),
                  'accesskey': candidate['accesskey'],
                }),
                headers: randomHeaders,
              );

              if (downloadResponse.statusCode == 200) {
                final downloadData = json.decode(downloadResponse.body);
                final content = downloadData['content'];

                if (content != null) {
                  try {
                    final decodedContent = utf8.decode(base64.decode(content));
                    final lines = LyricsParser.parseLrc(decodedContent);

                    if (lines.isNotEmpty) {
                      print(
                        "LYRICS_PROVIDER: SUCCESS - Used Kugou, found ${lines.length} lines",
                      );
                      return {
                        'success': true,
                        'plain': false,
                        'lrc': LyricsParser.toLrcString(lines),
                        'lines': lines.map((e) => e.toJson()).toList(),
                        'source': 'KuGou',
                        'total_lines': lines.length,
                        'type': 'word_by_word',
                      };
                    }
                  } catch (e) {
                    print('LYRICS_PROVIDER: Failed to decode Kugou lyrics: $e');
                    continue;
                  }
                }
              }
            }
          } catch (e) {
            print(
              'LYRICS_PROVIDER: Error processing Kugou song hash $hash: $e',
            );
            continue;
          }
        }
      }
    } catch (e) {
      print('LYRICS_PROVIDER: Kugou error: $e');
    }

    return {
      'success': false,
      'error': 'No lyrics found using KuGou for $title by $artist',
    };
  }

  void dispose() {
    client.close();
  }
}
