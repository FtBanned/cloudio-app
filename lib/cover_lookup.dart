import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

import 'lyrics.dart' show cleanForSearch;

/// Kapağı olmayan şarkı için sırayla (hepsi anahtarsız): Deezer → iTunes (tr, us, az) →
/// MusicBrainz + Cover Art Archive. Her kaynakta birkaç farklı sorgu denenir
/// ("sanatçı ad", sadece "ad", "feat." kısmı atılmış ad) ve adaylar bulanık eşleştirmeyle
/// puanlanır (Türkçe/Azerice harfler, yazım hatası, sıra değişikliği tolere edilir).
/// Siteler arası limitlere uyulur (iTunes ≈ 20 sorgu/dk, MusicBrainz 1/sn).
///
/// Gizlilik: aramaya sadece şarkı adı ve sanatçı metni gider.
/// Web'de tarayıcı (CORS) bu siteleri engelliyor; bu yüzden sadece telefonda/masaüstünde açık.
const kOnlineCovers = !kIsWeb;

class CoverHit {
  final Uint8List bytes;
  final String title;
  final String artist;
  final String album;
  final String source;
  final double score;

  /// true: dosya adı "Şarkı - Sanatçı" sırasıyla yazılmıştı (ad ve sanatçı yer değiştirmiş).
  final bool swapped;
  const CoverHit(this.bytes, this.title, this.artist, this.album, this.source,
      {this.swapped = false, this.score = 0});
}

class _Cand {
  final String title;
  final String artist;
  final String album;
  final List<String> arts; // kapak adresleri (ilk işleyen alınır)
  final String thumb; // küçük önizleme (elle arama listesi için)
  const _Cand(this.title, this.artist, this.album, this.arts, [this.thumb = '']);
}

/// Elle aramada listelenen sonuç.
class CoverCandidate {
  final String title;
  final String artist;
  final String album;
  final String thumbUrl;
  final String artUrl;
  const CoverCandidate(
      this.title, this.artist, this.album, this.thumbUrl, this.artUrl);
}

// ------------------------------------------------------------ dosya adı çözümleme

/// Görünen ada zarar vermeden dosya adındaki çöpü temizler:
/// alt çizgiler, baştaki parça numarası ("01. "), site adları.
String tidyName(String s) => s
    .replaceAll('_', ' ')
    .replaceAll(
        RegExp(r'[\(\[]?\s*(?:https?://)?(?:www\.)?[\w-]+\.(?:com|net|org|az|ru|tr|info|biz|me|tv|fm|co|io|ws|ir)\s*[\)\]]?',
            caseSensitive: false),
        ' ')
    .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[\.\-–)]\s+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// "Sanatçı - Şarkı" (-, –, —, | ayırıcılı). Ayırıcı yoksa sanatçı boş döner.
({String artist, String title}) parseFileName(String fileTitle) {
  final t = tidyName(fileTitle);
  final m = RegExp(r'\s[-–—|]\s').firstMatch(t);
  if (m == null) return (artist: '', title: t);
  final a = t.substring(0, m.start).trim();
  final b = t.substring(m.end).trim();
  if (a.isEmpty || b.isEmpty) return (artist: '', title: t);
  return (artist: a, title: b);
}

String _stripFeat(String s) => s
    .replaceAll(RegExp(r'\b(?:feat|ft|featuring)\b\.?.*$', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// ------------------------------------------------------------ arama

/// Bulunamazsa null. Hiçbir kaynağa ulaşılamadıysa (ağ/CORS) istisna fırlatır,
/// böylece üst katman "bulunamadı" diye kalıcı işaretlemez.
/// [minScore]: bilinmeyen sanatçıda yanlış adlandırmamak için daha yüksek tutulur.
Future<CoverHit?> findCover({
  required String title,
  String artist = '',
  String album = '',
}) async {
  final qTitle = cleanForSearch(title);
  final qArtist = cleanForSearch(artist);
  if (qTitle.isEmpty) return null;
  final noFeat = _stripFeat(qTitle);

  // Sırayla denenecek sorgular (tekrarlar atılır)
  final seen = <String>{};
  final queries = <String>[
    for (final q in [
      qArtist.isEmpty ? qTitle : '$qArtist $qTitle',
      if (qArtist.isNotEmpty) qTitle,
      if (noFeat.isNotEmpty && noFeat != qTitle)
        (qArtist.isEmpty ? noFeat : '$qArtist $noFeat'),
    ])
      if (seen.add(_norm(q))) q,
  ];
  final minScore = qArtist.isEmpty ? 0.85 : 0.72;

  final sources = <(String, Future<List<_Cand>> Function(String))>[
    ('Deezer', (q) => _deezer(q)),
    for (final cc in const ['tr', 'us', 'az']) ('iTunes-$cc', (q) => _itunes(q, cc)),
    ('MusicBrainz', (q) => _musicBrainz(q)),
  ];

  var reached = 0;
  Object? lastError;
  for (final (name, search) in sources) {
    // MusicBrainz yavaş (1 sn/sorgu): sadece ilk sorguyla
    final qs = name == 'MusicBrainz' ? queries.take(1) : queries;
    for (final q in qs) {
      try {
        final cands = await search(q);
        reached++;
        final scored = <(double, bool, _Cand)>[];
        for (final c in cands) {
          final a = _score(c, qTitle, qArtist);
          var best = a;
          var swapped = false;
          if (qArtist.isNotEmpty) {
            final b = _score(c, qArtist, qTitle); // "Şarkı - Sanatçı" sırası
            if (b > a) {
              best = b;
              swapped = true;
            }
          }
          if (best >= minScore) scored.add((best, swapped, c));
        }
        scored.sort((x, y) => y.$1.compareTo(x.$1));
        debugPrint(
            '[Kapak] "$q" · $name: ${cands.length} sonuç, ${scored.length} uygun');
        for (final (score, swapped, c) in scored.take(3)) {
          for (final url in c.arts) {
            final img = await _getImage(url);
            if (img != null) {
              debugPrint('[Kapak] "$q" · $name: BULUNDU (${score.toStringAsFixed(2)})');
              return CoverHit(img, c.title, c.artist, c.album, name,
                  swapped: swapped, score: score);
            }
          }
        }
      } catch (e) {
        lastError = e;
        debugPrint('[Kapak] "$q" · $name HATA: $e');
      }
    }
  }
  if (reached == 0 && lastError != null) throw Exception(lastError);
  return null;
}

/// Elle arama: serbest metinle Deezer + iTunes sonuçlarını listeler (eşleştirme yok,
/// kullanıcı kendisi seçer). Hiçbir kaynağa ulaşılamazsa istisna fırlatır.
Future<List<CoverCandidate>> searchCandidates(String query) async {
  final q = cleanForSearch(query);
  if (q.isEmpty) return const [];
  final out = <CoverCandidate>[];
  final seen = <String>{};
  var reached = 0;
  Object? lastError;

  void add(List<_Cand> cands) {
    for (final c in cands) {
      if (c.arts.isEmpty) continue;
      if (!seen.add(_norm('${c.artist} ${c.title} ${c.album}'))) continue;
      out.add(CoverCandidate(
          c.title, c.artist, c.album, c.thumb.isEmpty ? c.arts.first : c.thumb, c.arts.first));
    }
  }

  for (final fetch in <Future<List<_Cand>> Function()>[
    () => _deezer(q, limit: 15),
    () => _itunes(q, 'tr', limit: 12),
    () => _itunes(q, 'us', limit: 8),
  ]) {
    try {
      add(await fetch());
      reached++;
    } catch (e) {
      lastError = e;
    }
  }
  if (reached == 0 && lastError != null) throw Exception(lastError);
  return out;
}

/// Seçilen sonucun büyük kapağını indirir (okunamazsa null).
Future<Uint8List?> fetchCoverImage(String url) => _getImage(url);

// ------------------------------------------------------------ eşleştirme

const _tr = {
  'ç': 'c', 'ğ': 'g', 'ı': 'i', 'İ': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
  'ə': 'e', 'Ə': 'e', 'â': 'a', 'î': 'i', 'û': 'u', 'é': 'e', 'è': 'e',
  'á': 'a', 'à': 'a', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'Ç': 'c', 'Ğ': 'g',
  'Ö': 'o', 'Ş': 's', 'Ü': 'u',
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

const _stop = {'feat', 'ft', 'featuring', 'the', 'and', 've', 'ile', 'vs', 'x', 'a'};

List<String> _tokens(String s) =>
    [for (final t in _norm(s).split(' ')) if (t.isNotEmpty && !_stop.contains(t)) t];

int _lev(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Aynı sözcük ya da 1 harf hatası (uzun sözcüklerde).
bool _tokEq(String a, String b) {
  if (a == b) return true;
  if (a.length >= 5 && b.length >= 5 && (a.length - b.length).abs() <= 1) {
    return _lev(a, b) <= 1;
  }
  return false;
}

/// [a] sözcüklerinin ne kadarı [b] içinde var (0..1).
double _coverage(List<String> a, List<String> b) {
  if (a.isEmpty) return 0;
  final used = <int>{};
  var hit = 0;
  for (final t in a) {
    for (var j = 0; j < b.length; j++) {
      if (!used.contains(j) && _tokEq(t, b[j])) {
        used.add(j);
        hit++;
        break;
      }
    }
  }
  return hit / a.length;
}

double _dice(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final c = (_coverage(a, b) * a.length + _coverage(b, a) * b.length) / 2;
  return 2 * c / (a.length + b.length);
}

/// 0..1 puan. Sanatçı biliniyorsa başlık+sanatçı birlikte, bilinmiyorsa
/// sorgunun tamamı adayın "sanatçı + başlık" metniyle karşılaştırılır.
double _score(_Cand c, String qTitle, String qArtist) {
  final qt = _tokens(qTitle);
  final ct = _tokens(c.title);
  if (qt.isEmpty || ct.isEmpty) return 0;
  final ca = _tokens(c.artist);

  if (qArtist.isEmpty) {
    // sorgudaki sözcüklerin ne kadarı aday (sanatçı+başlık) içinde, aday başlığının ne
    // kadarı sorguda var: ikisi de yüksek olmalı
    final qIn = _coverage(qt, [...ca, ...ct]);
    final cIn = _coverage(ct, qt);
    return min(qIn, cIn);
  }

  final qa = _tokens(qArtist);
  final title = max(_dice(qt, ct), _coverage(ct, qt) * (ct.length >= 2 || ct.first.length >= 4 ? 1 : 0.0));
  if (title < 0.7) return 0;
  final artist = max(_coverage(qa, ca), _coverage(ca, qa));
  if (artist < 0.4) return 0;
  return 0.65 * title + 0.35 * artist;
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

Future<List<_Cand>> _itunes(String term, String country, {int limit = 10}) async {
  final data = await _getJson(
    Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': 'song',
      'limit': '$limit',
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
      art,
    ));
  }
  return out;
}

Future<List<_Cand>> _deezer(String term, {int limit = 10}) async {
  final data = await _getJson(
    Uri.https('api.deezer.com', '/search', {'limit': '$limit', 'q': term}),
    300,
  );
  if (data is Map && data['error'] != null) {
    throw Exception('Deezer: ${data['error']}');
  }
  final out = <_Cand>[];
  for (final r in (data['data'] as List? ?? const [])) {
    if (r is! Map) continue;
    final album = r['album'] is Map ? r['album'] as Map : const {};
    final artist = r['artist'] is Map ? r['artist'] as Map : const {};
    final art = '${album['cover_xl'] ?? album['cover_big'] ?? ''}';
    if (art.isEmpty) continue;
    out.add(_Cand('${r['title'] ?? ''}', '${artist['name'] ?? ''}',
        '${album['title'] ?? ''}', [art],
        '${album['cover_medium'] ?? album['cover'] ?? ''}'));
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