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

  /// true: "yakın sonuç" son çaresiyle bulundu; elle seçimdeki gibi ad, sanatçı ve albüm de
  /// bulunan sonuca göre doldurulur.
  final bool forceInfo;
  const CoverHit(this.bytes, this.title, this.artist, this.album, this.source,
      {this.swapped = false, this.score = 0, this.forceInfo = false});
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
  // Sərt yoxlama heç nə tapmadı: əl ilə axtarışdakı kimi yumşaq ehtiyat axtarış.
  // (Heç bir mənbəyə çatılmayıbsa internet yoxdur, boşuna gözləmirik.)
  if (reached > 0) {
    try {
      final fb = await _fallbackCover(title: title, artist: artist);
      if (fb != null) return fb;
    } catch (e) {
      debugPrint('[Kapak] ehtiyat axtarış xətası: $e');
    }
    // Yumşaq ehtiyat da tapmadı: "İnternette ara"da çıkan ən güclü yaxın nəticəni götür.
    try {
      final be = await _bestEffortCover(title: title, artist: artist);
      if (be != null) return be;
    } catch (e) {
      debugPrint('[Kapak] yakın sonuç xətası: $e');
    }
  }
  if (reached == 0 && lastError != null) throw Exception(lastError);
  return null;
}

/// Ehtiyat axtarış. Fayl adı təmizlənmədən, həm "ad sənətçi", həm "sənətçi ad" sırası ilə
/// Deezer və iTunes-da axtarır; sözlərin sırasına və ad/sənətçi yerinə baxmır (əl ilə
/// axtarışdakı kimi), yalnız daha yumşaq eşiklə yoxlayır. Ad ilə sənətçi dəyişik
/// yazılıbsa (Mahnı - Sənətçi) [CoverHit.swapped] true olur və tətbiq onları düzəldir.
Future<CoverHit?> _fallbackCover({
  required String title,
  required String artist,
}) async {
  final rawT = tidyName(title);
  final rawA = artist.isEmpty ? '' : tidyName(artist);
  final tTok = _tokens(rawT);
  final aTok = _tokens(rawA);
  if (tTok.isEmpty && aTok.isEmpty) return null;

  final seen = <String>{};
  final queries = <String>[
    for (final q in [
      rawA.isEmpty ? rawT : '$rawT $rawA',
      if (rawA.isNotEmpty) '$rawA $rawT',
      cleanForSearch(rawA.isEmpty ? rawT : '$rawT $rawA'),
    ])
      if (q.trim().isNotEmpty && seen.add(_norm(q))) q.trim(),
  ];

  // (mənbə adı, sorğu, funksiya): iTunes yavaşdır, ona görə az sorğu
  final calls = <(String, String, Future<List<_Cand>> Function())>[
    for (final q in queries.take(3)) ('Deezer', q, () => _deezer(q, limit: 15)),
    for (final q in queries.take(2)) ('iTunes-tr', q, () => _itunes(q, 'tr', limit: 12)),
    if (queries.isNotEmpty) ('iTunes-us', queries.first, () => _itunes(queries.first, 'us', limit: 8)),
  ];

  for (final (name, q, fetch) in calls) {
    try {
      final cands = await fetch();
      final scored = <(double, bool, _Cand)>[];
      for (final c in cands) {
        final m = _looseMatch(c, tTok, aTok);
        if (m != null) scored.add((m.$1, m.$2, c));
      }
      scored.sort((x, y) => y.$1.compareTo(x.$1));
      debugPrint(
          '[Kapak] ehtiyat "$q" · $name: ${cands.length} sonuç, ${scored.length} uygun');
      for (final (score, swapped, c) in scored.take(5)) {
        for (final url in c.arts) {
          final img = await _getImage(url);
          if (img != null) {
            debugPrint(
                '[Kapak] ehtiyat "$q" · $name: BULUNDU (${score.toStringAsFixed(2)}, '
                '${c.artist} - ${c.title})');
            return CoverHit(img, c.title, c.artist, c.album, 'ehtiyat-$name',
                swapped: swapped, score: score);
          }
        }
      }
    } catch (e) {
      debugPrint('[Kapak] ehtiyat "$q" · $name HATA: $e');
    }
  }
  return null;
}

/// Son çare: "Şarkı bilgilerini düzenle > İnternette ara" ekranındaki aramanın aynısını
/// ("sanatçı ad") yapar, sonuçlardan girişe EN YAKIN olanı seçer ve uygular.
/// Çok zayıf eşleşmeler (ortak sözcük yok) yine de reddedilir; yanlış seçilirse kullanıcı
/// düzenleme ekranından elle düzeltir.
Future<CoverHit?> _bestEffortCover({
  required String title,
  required String artist,
}) async {
  final rawT = tidyName(title);
  final rawA = artist.isEmpty ? '' : tidyName(artist);
  final q = cleanForSearch('$rawA $rawT'.trim());
  final qTok = _tokens('$rawA $rawT');
  if (q.isEmpty || qTok.isEmpty) return null;

  final all = <_Cand>[];
  final seen = <String>{};
  for (final fetch in <Future<List<_Cand>> Function()>[
    () => _deezer(q, limit: 15),
    () => _itunes(q, 'tr', limit: 12),
    () => _itunes(q, 'us', limit: 8),
  ]) {
    try {
      for (final c in await fetch()) {
        if (c.arts.isEmpty) continue;
        if (seen.add(_norm('${c.artist} ${c.title} ${c.album}'))) all.add(c);
      }
    } catch (e) {
      debugPrint('[Kapak] yakın sonuç "$q" HATA: $e');
    }
  }

  // Eşit puanda sıradaki (kaynağın kendi alaka sırası) öne geçsin
  final scored = <(double, _Cand)>[];
  for (var i = 0; i < all.length; i++) {
    final sc = _bestEffortScore(all[i], qTok);
    if (sc > 0) scored.add((sc - i * 0.002, all[i]));
  }
  scored.sort((x, y) => y.$1.compareTo(x.$1));
  debugPrint('[Kapak] yakın sonuç "$q": ${all.length} sonuç, ${scored.length} uygun');
  for (final (score, c) in scored.take(5)) {
    for (final url in c.arts) {
      final img = await _getImage(url);
      if (img != null) {
        debugPrint(
            '[Kapak] yakın sonuç "$q": SEÇİLDİ (${score.toStringAsFixed(2)}, ${c.artist} - ${c.title})');
        return CoverHit(img, c.title, c.artist, c.album, 'yakin-sonuc',
            score: score, forceInfo: true);
      }
    }
  }
  return null;
}

/// 0 = uygun değil. Girişteki sözcüklerin adayda (başlık+sanatçı+albüm) bulunması ve
/// adayın başlığının girişte bulunması gerekir (sıra ve ad/sanatçı yeri fark etmez).
double _bestEffortScore(_Cand c, List<String> qTok) {
  final ct = _tokens(c.title);
  if (ct.isEmpty || qTok.isEmpty) return 0;
  final all = [...ct, ..._tokens(c.artist), ..._tokens(c.album)];
  final qIn = _coverage(qTok, all); // giriş adayda var mı
  final cIn = _coverage(ct, qTok); // adayın başlığı girişte var mı
  if (cIn < 0.5 || qIn < 0.5) return 0;
  return 0.6 * qIn + 0.4 * cIn;
}

/// Yumşaq uyğunluq: adayın başlığı girişdə (ad+sənətçi sözləri birlikdə) olmalı, giriş
/// də adayın (sənətçi+başlıq) mətninin əksəriyyətində olmalıdır. Sıra və ad/sənətçi yeri
/// fərq etmir. (bal, ad/sənətçi dəyişikdir) və ya uyğun deyilsə null.
(double, bool)? _looseMatch(_Cand c, List<String> tTok, List<String> aTok) {
  final ct = _tokens(c.title);
  final ca = _tokens(c.artist);
  if (ct.isEmpty) return null;
  final input = [...tTok, ...aTok];
  if (input.isEmpty) return null;

  final titleIn = _coverage(ct, input); // adayın başlığı girişdə varmı
  final inputIn = _coverage(input, [...ca, ...ct]); // giriş adayda varmı
  if (titleIn < 0.8) return null;
  if (aTok.isEmpty) {
    if (inputIn < 0.85) return null; // sənətçi bilinmir: daha ehtiyatlı ol
  } else {
    if (inputIn < 0.6) return null;
    if (ca.isNotEmpty && _coverage(ca, input) < 0.5) return null; // sənətçi uyğun deyil
  }
  final score = 0.5 * titleIn + 0.5 * inputIn;
  if (score < 0.7) return null;
  // adayın başlığı "sənətçi" sahəsinə daha çox oxşayırsa, ad ilə sənətçi yer dəyişib
  final swapped = aTok.isNotEmpty && _coverage(ct, aTok) > _coverage(ct, tTok);
  return (score, swapped);
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

// ------------------------------------------------------------ tür / yıl / albüm sırası

/// İnternetten bulunan tür, yıl ve albümdeki sıra bilgisi (bulunamayan alan boş/0 kalır).
class MetaHit {
  final String genre;
  final int year;
  final int trackNo;
  final int discNo;
  final String source;
  const MetaHit(
      {this.genre = '',
      this.year = 0,
      this.trackNo = 0,
      this.discNo = 0,
      this.source = ''});
}

class _MetaCand {
  final _Cand base; // ad/sanatçı/albüm: eşleştirme puanı için
  String genre;
  int year;
  int trackNo;
  int discNo;
  final Future<void> Function(_MetaCand)? _detail; // ek istekle tamamlanacak kaynaklar
  _MetaCand(this.base,
      {this.genre = '',
      this.year = 0,
      this.trackNo = 0,
      this.discNo = 0,
      Future<void> Function(_MetaCand)? detail})
      : _detail = detail;

  Future<void> resolve() async {
    final d = _detail;
    if (d != null) await d(this);
  }
}

int _asInt(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

/// "2019-05-17T12:00:00Z" / "2019-05-17" / "2019" -> 2019 (mantıksız yıl 0 olur).
int _yearOf(Object? v) {
  final m = RegExp(r'^\s*(\d{4})').firstMatch('${v ?? ''}');
  if (m == null) return 0;
  final y = int.parse(m.group(1)!);
  return (y >= 1900 && y <= DateTime.now().year + 1) ? y : 0;
}

/// Şarkının türünü, çıkış yılını ve albümdeki sırasını arar (hepsi anahtarsız):
/// önce Deezer (hızlı), eksik kalan alanlar için iTunes (tr, us, az). Eşleştirme kapak
/// aramasıyla aynı bulanık puanlamayı kullanır; yanlış şarkının bilgisi yazılmasın diye
/// eşik yüksektir. Sadece [needGenre]/[needYear]/[needTrack] istenen alanlar doldurulur.
/// Hiçbir kaynağa ulaşılamazsa istisna fırlatır; hiçbir şey bulunamazsa null döner.
Future<MetaHit?> findMeta({
  required String title,
  String artist = '',
  bool needGenre = true,
  bool needYear = true,
  bool needTrack = true,
}) async {
  final qTitle = cleanForSearch(title);
  final qArtist = cleanForSearch(artist);
  if (qTitle.isEmpty) return null;
  final noFeat = _stripFeat(qTitle);

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

  var genre = '';
  var year = 0;
  var trackNo = 0;
  var discNo = 0;
  var src = '';
  bool done() =>
      (!needGenre || genre.isNotEmpty) &&
      (!needYear || year > 0) &&
      (!needTrack || trackNo > 0);

  final sources = <(String, Future<List<_MetaCand>> Function(String))>[
    ('Deezer', (q) => _deezerMeta(q)),
    for (final cc in const ['tr', 'us', 'az']) ('iTunes-$cc', (q) => _itunesMeta(q, cc)),
  ];

  var reached = 0;
  Object? lastError;
  for (final (name, search) in sources) {
    if (done()) break;
    for (final q in queries) {
      if (done()) break;
      try {
        final cands = await search(q);
        reached++;
        _MetaCand? best;
        var bestScore = 0.0;
        for (final c in cands) {
          var sc = _score(c.base, qTitle, qArtist);
          if (qArtist.isNotEmpty) {
            final b = _score(c.base, qArtist, qTitle); // "Şarkı - Sanatçı" sırası
            if (b > sc) sc = b;
          }
          if (sc >= minScore && sc > bestScore) {
            best = c;
            bestScore = sc;
          }
        }
        if (best == null) continue;
        await best.resolve();
        var got = false;
        if (needGenre && genre.isEmpty && best.genre.isNotEmpty) {
          genre = best.genre;
          got = true;
        }
        if (needYear && year == 0 && best.year > 0) {
          year = best.year;
          got = true;
        }
        if (needTrack && trackNo == 0 && best.trackNo > 0) {
          trackNo = best.trackNo;
          discNo = best.discNo;
          got = true;
        }
        debugPrint('[Bilgi] "$q" · $name: ${got ? 'BULUNDU' : 'eşleşti ama alan yok'}');
        if (got) {
          src = src.isEmpty ? name : '$src+$name';
          break; // bu kaynaktan alındı; eksik kalan varsa sıradaki kaynağa geç
        }
      } catch (e) {
        lastError = e;
        debugPrint('[Bilgi] "$q" · $name HATA: $e');
      }
    }
  }
  // Sərt yoxlama hamısını tapmadısa: "yakın sonuç" son çaresi (eksik alanları doldurur)
  if (!done() && reached > 0) {
    try {
      final rawT = tidyName(title);
      final rawA = artist.isEmpty ? '' : tidyName(artist);
      final q = cleanForSearch('$rawA $rawT'.trim());
      final qTok = _tokens('$rawA $rawT');
      if (q.isNotEmpty && qTok.isNotEmpty) {
        final all = <_MetaCand>[];
        for (final search in <Future<List<_MetaCand>> Function()>[
          () => _deezerMeta(q),
          () => _itunesMeta(q, 'tr'),
          () => _itunesMeta(q, 'us'),
        ]) {
          try {
            all.addAll(await search());
          } catch (e) {
            debugPrint('[Bilgi] yakın sonuç "$q" HATA: $e');
          }
        }
        final scored = <(double, _MetaCand)>[];
        for (var i = 0; i < all.length; i++) {
          final sc = _bestEffortScore(all[i].base, qTok);
          if (sc > 0) scored.add((sc - i * 0.002, all[i]));
        }
        scored.sort((x, y) => y.$1.compareTo(x.$1));
        for (final (_, m) in scored.take(2)) {
          if (done()) break;
          await m.resolve();
          var got = false;
          if (needGenre && genre.isEmpty && m.genre.isNotEmpty) {
            genre = m.genre;
            got = true;
          }
          if (needYear && year == 0 && m.year > 0) {
            year = m.year;
            got = true;
          }
          if (needTrack && trackNo == 0 && m.trackNo > 0) {
            trackNo = m.trackNo;
            discNo = m.discNo;
            got = true;
          }
          debugPrint('[Bilgi] yakın sonuç "$q": ${got ? 'BULUNDU' : 'alan yok'}');
          if (got) src = src.isEmpty ? 'yakin-sonuc' : '$src+yakin-sonuc';
        }
      }
    } catch (e) {
      debugPrint('[Bilgi] yakın sonuç xətası: $e');
    }
  }
  if (reached == 0 && lastError != null) throw Exception(lastError);
  if (genre.isEmpty && year == 0 && trackNo == 0) return null;
  return MetaHit(
      genre: genre, year: year, trackNo: trackNo, discNo: discNo, source: src);
}

Future<List<_MetaCand>> _itunesMeta(String term, String country) async {
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
  final out = <_MetaCand>[];
  for (final r in (data['results'] as List? ?? const [])) {
    if (r is! Map) continue;
    out.add(_MetaCand(
      _Cand('${r['trackName'] ?? ''}', '${r['artistName'] ?? ''}',
          '${r['collectionName'] ?? ''}', const []),
      genre: '${r['primaryGenreName'] ?? ''}'.trim(),
      year: _yearOf(r['releaseDate']),
      trackNo: _asInt(r['trackNumber']),
      discNo: _asInt(r['discNumber']),
    ));
  }
  return out;
}

Future<List<_MetaCand>> _deezerMeta(String term) async {
  final data = await _getJson(
    Uri.https('api.deezer.com', '/search', {'limit': '8', 'q': term}),
    300,
  );
  if (data is Map && data['error'] != null) {
    throw Exception('Deezer: ${data['error']}');
  }
  final out = <_MetaCand>[];
  for (final r in (data['data'] as List? ?? const [])) {
    if (r is! Map) continue;
    final album = r['album'] is Map ? r['album'] as Map : const {};
    final artist = r['artist'] is Map ? r['artist'] as Map : const {};
    final trackId = r['id'];
    final albumId = album['id'];
    out.add(_MetaCand(
      _Cand('${r['title'] ?? ''}', '${artist['name'] ?? ''}',
          '${album['title'] ?? ''}', const []),
      // Arama sonucunda tür/yıl/sıra yok: sadece en iyi eşleşme için ek istek atılır
      detail: (m) async {
        try {
          final t = await _getJson(Uri.https('api.deezer.com', '/track/$trackId'), 300);
          if (t is Map && t['error'] == null) {
            m.trackNo = _asInt(t['track_position']);
            m.discNo = _asInt(t['disk_number']);
            m.year = _yearOf(t['release_date']);
          }
        } catch (_) {}
        try {
          if (albumId != null) {
            final a = await _getJson(Uri.https('api.deezer.com', '/album/$albumId'), 300);
            if (a is Map && a['error'] == null) {
              final g = a['genres'] is Map ? (a['genres'] as Map)['data'] : null;
              if (g is List) {
                for (final x in g) {
                  if (x is Map && _asInt(x['id']) > 0) {
                    final n = '${x['name'] ?? ''}'.trim();
                    if (n.isNotEmpty) {
                      m.genre = n;
                      break;
                    }
                  }
                }
              }
              if (m.year == 0) m.year = _yearOf(a['release_date']);
            }
          }
        } catch (_) {}
      },
    ));
  }
  return out;
}

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