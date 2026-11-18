import 'dart:convert';

import 'package:http/http.dart' as http;

/// Şarkı sözlerinin bir satırı. [time] null ise söz senkronsuzdur.
class LyricLine {
  final Duration? time;
  final String text;
  const LyricLine(this.time, this.text);
}

class Lyrics {
  final List<LyricLine> lines;
  final bool synced; // true: satırların zamanı var (LRC / SYLT)
  final String source; // 'Dosya', '.lrc', 'LRCLIB'
  const Lyrics(this.lines, {required this.synced, required this.source});

  static final _ts = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _meta = RegExp(r'^\s*\[([a-zA-Z#]+):(.*)\]\s*$');
  static final _wordTs = RegExp(r'<\d+:\d+(?:[.:]\d+)?>'); // "enhanced LRC" kelime zamanları

  /// LRC ya da düz metni çözer. İçinde [dd:ss.xx] varsa senkron, yoksa düz söz olur.
  static Lyrics? parse(String raw, {String source = 'Dosya'}) {
    final text = raw
        .replaceAll('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    var offsetMs = 0;
    final timed = <({int ms, int order, String text})>[];
    final plain = <String>[];

    for (final line in text.split('\n')) {
      final matches = _ts.allMatches(line).toList();
      if (matches.isEmpty) {
        final meta = _meta.firstMatch(line);
        if (meta != null) {
          // [ar:..] [ti:..] gibi künye satırları; sadece offset işimize yarar
          if (meta.group(1)!.toLowerCase() == 'offset') {
            offsetMs = int.tryParse(meta.group(2)!.trim()) ?? 0;
          }
          continue;
        }
        plain.add(line.trim());
        continue;
      }
      final body =
          line.substring(matches.last.end).replaceAll(_wordTs, '').trim();
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final frac = m.group(3);
        var ms = min * 60000 + sec * 1000;
        if (frac != null) {
          // 1 hane = onda bir, 2 hane = yüzde bir, 3 hane = milisaniye
          ms += int.parse(frac) * (frac.length == 1 ? 100 : frac.length == 2 ? 10 : 1);
        }
        timed.add((ms: ms, order: timed.length, text: body));
      }
    }

    if (timed.isNotEmpty) {
      // LRC'de pozitif offset sözlerin daha erken görünmesi demektir
      timed.sort((a, b) {
        final c = a.ms.compareTo(b.ms);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
      return Lyrics(
        [
          for (final t in timed)
            LyricLine(
                Duration(milliseconds: (t.ms - offsetMs).clamp(0, 1 << 31).toInt()),
                t.text),
        ],
        synced: true,
        source: source,
      );
    }

    // düz söz: baştaki/sondaki boşlukları ve 2'den fazla boş satırı temizle
    final out = <LyricLine>[];
    var blanks = 0;
    for (final p in plain) {
      if (p.isEmpty) {
        blanks++;
        if (out.isNotEmpty && blanks <= 1) out.add(const LyricLine(null, ''));
      } else {
        blanks = 0;
        out.add(LyricLine(null, p));
      }
    }
    while (out.isNotEmpty && out.last.text.isEmpty) {
      out.removeLast();
    }
    if (out.isEmpty) return null;
    return Lyrics(out, synced: false, source: source);
  }

  /// [pos] anında okunması gereken satırın indeksi (henüz başlamadıysa -1).
  int indexAt(Duration pos) {
    if (!synced || lines.isEmpty) return -1;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time! <= pos) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

// ------------------------------------------------------------ çevrimiçi arama

/// Mod'daki (TvMusicOnline) temizleme mantığı: "(Official Video)", "[Lyrics]", "klip" vb. atılır.
String cleanForSearch(String s) => s
    .replaceAll('_', ' ')
    .replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ')
    .replaceAll(
        RegExp(r'(?:https?://)?(?:www\.)?[\w-]+\.(?:com|net|org|az|ru|tr|info|biz|me|tv|fm|co|io|ws|ir)\b',
            caseSensitive: false),
        ' ')
    .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[\.\-–)]\s+'), '')
    .replaceAll(
        RegExp(r'\b(official|video|music|lyrics?|lyric|audio|hd|hq|4k|klip|sözleri|şarkı sözleri|mp3|indir|download|yukle)\b',
            caseSensitive: false),
        ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// LRCLIB'den söz arar (anahtarsız, ücretsiz). Sadece ad/sanatçı/albüm metni gönderilir.
/// Bulunamazsa null; ağ hatasında istisna fırlatır (üst katman "tekrar dene" gösterir).
Future<Lyrics?> fetchLyricsOnline({
  required String title,
  String artist = '',
  String album = '',
  Duration? duration,
}) async {
  final cleanTitle = cleanForSearch(title);
  final cleanArtist = cleanForSearch(artist);

  // Sırayla daha gevşek sorgular dene
  final queries = <Map<String, String>>[
    if (artist.isNotEmpty) {'track_name': title, 'artist_name': artist},
    if (artist.isNotEmpty && (cleanTitle != title || cleanArtist != artist))
      {'track_name': cleanTitle, 'artist_name': cleanArtist},
    {'q': artist.isEmpty ? cleanTitle : '$cleanArtist $cleanTitle'},
  ];

  var anySuccess = false;
  Object? lastError;
  for (final q in queries) {
    try {
      final res = await http
          .get(Uri.https('lrclib.net', '/api/search', q))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        continue;
      }
      anySuccess = true;
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is! List) continue;
      final best = _pickBest(list, duration);
      if (best != null) return best;
    } catch (e) {
      lastError = e;
    }
  }
  if (!anySuccess && lastError != null) throw Exception(lastError);
  return null;
}

Lyrics? _pickBest(List list, Duration? duration) {
  Lyrics? bestLyrics;
  var bestScore = double.infinity;
  for (final item in list) {
    if (item is! Map) continue;
    if (item['instrumental'] == true) continue;
    final synced = (item['syncedLyrics'] as String?)?.trim() ?? '';
    final plain = (item['plainLyrics'] as String?)?.trim() ?? '';
    if (synced.isEmpty && plain.isEmpty) continue;

    // Süre farkı küçük olan ve senkron sözü olan kazanır
    var score = synced.isNotEmpty ? 0.0 : 100.0;
    final d = item['duration'];
    if (duration != null && d is num && d > 0) {
      final diff = (d - duration.inMilliseconds / 1000).abs().toDouble();
      if (diff > 8) continue; // büyük ihtimalle başka bir kayıt/versiyon
      score += diff;
    }
    if (score < bestScore) {
      final parsed = Lyrics.parse(synced.isNotEmpty ? synced : plain, source: 'LRCLIB');
      if (parsed != null) {
        bestScore = score;
        bestLyrics = parsed;
      }
    }
  }
  return bestLyrics;
}