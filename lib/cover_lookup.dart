import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

import 'lyrics.dart' show cleanForSearch;

/// Modun TvMusicOnline mantığının Dart karşılığı.
/// Kapağı olmayan şarkı için sırayla (hepsi anahtarsız): iTunes (us, az, tr mağazaları) →
/// Deezer (web'de CORS yüzünden atlanır) → MusicBrainz + Cover Art Archive.
/// Siteler arası limitlere uyulur (iTunes ≈ 20 sorgu/dk, MusicBrainz 1/sn).
///
/// Gizlilik: aramaya sadece şarkı adı ve sanatçı metni gider.
/// Web'de tarayıcı (CORS) bu siteleri engelliyor; her denemede istisna fırlayıp
/// hata ayıklayıcıyı durduruyordu. Bu yüzden sadece telefonda/masaüstünde açık.
const kOnlineCovers = !kIsWeb;

class CoverHit {
  final Uint8List bytes;
  final String title;
  final String artist;
  final String album;
  final String source;
  /// true: fayl adı "Mahnı - Sənətçi" sırası ilə yazılmışdı (ad və sənətçi yer dəyişib).
  final bool swapped;
  const CoverHit(this.bytes, this.title, this.artist, this.album, this.source,
      {this.swapped = false});
}

class _Cand {
  final String title;
  final String artist;
  final String album;
  final List<String> arts; // kapak adresleri (ilk işleyen alınır)
  const _Cand(this.title, this.artist, this.album, this.arts);
}

/// Bulunamazsa null. Hiçbir kaynağa ulaşılamadıysa (ağ/CORS) istisna fırlatır,
/// böylece üst katman "bulunamadı" diye kalıcı işaretlemez.
Future<CoverHit?> findCover({
  required String title,
  String artist = '',
  String album = '',
}) async {
  final qTitle = cleanForSearch(title);
  final qArtist = cleanForSearch(artist);
  if (qTitle.isEmpty) return null;
  final term = qArtist.isEmpty ? qTitle : '$qArtist $qTitle';

  final sources = <(String, Future<List<_Cand>> Function())>[
    for (final cc in const ['us', 'az', 'tr'])
      ('iTunes-$cc', () => _itunes(term, cc)),
    if (!kIsWeb) ('Deezer', () => _deezer(term)),
    ('MusicBrainz', () => _musicBrainz(term)),
  ];

  var reached = 0;
  Object? lastError;
  for (final (name, search) in sources) {
    try {
      final cands = await search();
      reached++;
      var tried = 0;
      var matched = 0;
      for (final c in cands) {
        var swapped = false;
        if (!_matches(c, qTitle, qArtist)) {
          // Fayl adı "Mahnı - Sənətçi" ola bilər: ad və sənətçini tərsinə də yoxla
          if (qArtist.isNotEmpty && _matches(c, qArtist, qTitle)) {
            swapped = true;
          } else {
            continue;
          }
        }
        matched++;
        if (++tried > 3) break; // en fazla 3 uygun adayı dene
        for (final url in c.arts) {
          final img = await _getImage(url);
          if (img != null) {
            debugPrint('[Kapak] "$term" · $name: TAPILDI');
            return CoverHit(img, c.title, c.artist, c.album, name,
                swapped: swapped);
          }
        }
      }
      debugPrint(
          '[Kapak] "$term" · $name: ${cands.length} nəticə, $matched uyğun, tapılmadı');
    } catch (e) {
      lastError = e;
      debugPrint('[Kapak] "$term" · $name XƏTA: $e');
    }
  }
  if (reached == 0 && lastError != null) throw Exception(lastError);
  return null;
}

// ------------------------------------------------------------ eşleştirme

const _tr = {
  'ç': 'c', 'ğ': 'g', 'ı': 'i', 'İ': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
  'ə': 'e', 'Ə': 'e', 'â': 'a', 'î': 'i', 'û': 'u', 'é': 'e', 'è': 'e',
  'á': 'a', 'à': 'a', 'ó': 'o', 'ú': 'u', 'ñ': 'n',
};

/// Küçük harf, Türkçe/Azerice harfler ASCII'ye, harf-rakam dışı her şey atılır.
String _norm(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_tr[ch] ?? ch);
  }
  return b
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _matches(_Cand c, String qTitle, String qArtist) {
  final qt = _norm(qTitle);
  final ct = _norm(c.title);
  if (qt.isEmpty || ct.isEmpty) return false;

  final qa = _norm(qArtist);
  if (qa.isEmpty) {
    // Sanatçı bilinmiyorsa yanlış eşleşmemek için başlık birebir aynı olmalı
    return ct == qt;
  }
  final titleOk = ct == qt ||
      (ct.length >= 4 && qt.contains(ct)) ||
      (qt.length >= 4 && ct.contains(qt) && qt.length / ct.length >= 0.7);
  if (!titleOk) return false;

  final ca = _norm(c.artist);
  if (ca.contains(qa) || qa.contains(ca)) return true;
  // "A, B feat. C" gibi durumlar: sanatçı sözcüklerinden biri tutsun
  for (final tok in qa.split(' ')) {
    if (tok.length >= 3 && ca.contains(tok)) return true;
  }
  return false;
}

// ------------------------------------------------------------ ağ yardımcıları

final Map<String, DateTime> _last = {};

Future<void> _throttle(String host, int gapMs) async {
  final last = _last[host];
  if (last != null) {
    final wait = gapMs - DateTime.now().difference(last).inMilliseconds;
    if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
  }
  _last[host] = DateTime.now();
}

Future<dynamic> _getJson(Uri uri, int gapMs) async {
  await _throttle(uri.host, gapMs);
  final res = await http
      .get(uri, headers: kIsWeb ? {} : {'User-Agent': 'Cloudio/1.0 (local music player)'})
      .timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  return jsonDecode(utf8.decode(res.bodyBytes));
}

bool _looksLikeImage(Uint8List b) {
  if (b.length < 1000) return false;
  final jpeg = b[0] == 0xFF && b[1] == 0xD8;
  final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
  return jpeg || png;
}

Future<Uint8List?> _getImage(String url) async {
  try {
    final uri = Uri.parse(url);
    await _throttle('img:${uri.host}', 400);
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      debugPrint('[Kapak] şəkil HTTP ${res.statusCode}: $url');
      return null;
    }
    if (!_looksLikeImage(res.bodyBytes)) {
      debugPrint('[Kapak] şəkil formatı yanlış: $url');
      return null;
    }
    return res.bodyBytes;
  } catch (e) {
    debugPrint('[Kapak] şəkil alınmadı ($url): $e');
    return null;
  }
}

// ------------------------------------------------------------ kaynaklar

Future<List<_Cand>> _itunes(String term, String country) async {
  final data = await _getJson(
    Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': 'song',
      'limit': '10',
      'country': country,
    }),
    3200,
  );
  final out = <_Cand>[];
  for (final r in (data['results'] as List? ?? const [])) {
    if (r is! Map) continue;
    final art = (r['artworkUrl100'] as String?) ?? '';
    if (art.isEmpty) continue;
    out.add(_Cand(
      '${r['trackName'] ?? ''}',
      '${r['artistName'] ?? ''}',
      '${r['collectionName'] ?? ''}',
      [art.replaceAll('100x100bb', '600x600bb')],
    ));
  }
  return out;
}

Future<List<_Cand>> _deezer(String term) async {
  final data = await _getJson(
    Uri.https('api.deezer.com', '/search', {'limit': '10', 'q': term}),
    1500,
  );
  final out = <_Cand>[];
  for (final r in (data['data'] as List? ?? const [])) {
    if (r is! Map) continue;
    final album = r['album'] is Map ? r['album'] as Map : const {};
    final artist = r['artist'] is Map ? r['artist'] as Map : const {};
    final art = '${album['cover_xl'] ?? album['cover_big'] ?? ''}';
    if (art.isEmpty) continue;
    out.add(_Cand('${r['title'] ?? ''}', '${artist['name'] ?? ''}',
        '${album['title'] ?? ''}', [art]));
  }
  return out;
}

Future<List<_Cand>> _musicBrainz(String term) async {
  final data = await _getJson(
    Uri.https('musicbrainz.org', '/ws/2/recording',
        {'fmt': 'json', 'limit': '6', 'query': term}),
    1100,
  );
  final out = <_Cand>[];
  for (final r in (data['recordings'] as List? ?? const [])) {
    if (r is! Map) continue;
    final names = <String>[];
    for (final ac in (r['artist-credit'] as List? ?? const [])) {
      if (ac is Map) {
        final n = ac['name'] ?? (ac['artist'] is Map ? (ac['artist'] as Map)['name'] : null);
        if (n != null) names.add('$n');
      }
    }
    final releases = (r['releases'] as List? ?? const []).whereType<Map>().toList();
    if (releases.isEmpty) continue;
    out.add(_Cand(
      '${r['title'] ?? ''}',
      names.join(', '),
      '${releases.first['title'] ?? ''}',
      [
        for (final rel in releases.take(3))
          'https://coverartarchive.org/release/${rel['id']}/front-500',
      ],
    ));
  }
  return out;
}