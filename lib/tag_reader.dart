import 'dart:convert';
import 'dart:typed_data';

/// Bir şarkı dosyasının içindeki etiket bilgisi.
class TagInfo {
  final String title;
  final String artist;
  final String album;
  final Uint8List? cover;

  /// Gömülü şarkı sözü ham metni: LRC (zamanlı) ya da düz metin. Yoksa ''.
  final String lyrics;

  /// Janr (ID3v1 nömrəsi mətnə çevrilir), buraxılış ili, trek və disk nömrəsi. Yoxdursa '' / 0.
  final String genre;
  final int year;
  final int track;
  final int disc;

  const TagInfo({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.cover,
    this.lyrics = '',
    this.genre = '',
    this.year = 0,
    this.track = 0,
    this.disc = 0,
  });

  static const empty = TagInfo();
}

/// Dosya baytlarından etiketleri okur. Hata olursa boş sonuç döner, asla patlamaz.
TagInfo readTags(Uint8List data, String ext) {
  try {
    switch (ext.toLowerCase()) {
      case 'mp3':
        return _readMp3(data);
      case 'flac':
        return _readFlac(data);
      case 'm4a':
      case 'mp4':
      case 'm4b':
        return _readMp4(data);
    }
  } catch (_) {
    // bozuk etiket: dosya adı yedeği kullanılacak
  }
  return TagInfo.empty;
}

// ---------------------------------------------------------------- yardımcılar

/// ID3v1 standart janr siyahısı (indeks = janr nömrəsi).
const _kGenres = [
  'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge', 'Hip-Hop',
  'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B', 'Rap', 'Reggae', 'Rock',
  'Techno', 'Industrial', 'Alternative', 'Ska', 'Death Metal', 'Pranks', 'Soundtrack',
  'Euro-Techno', 'Ambient', 'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion', 'Trance',
  'Classical', 'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
  'Alt. Rock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative', 'Instrumental Pop',
  'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave', 'Techno-Industrial', 'Electronic',
  'Pop-Folk', 'Eurodance', 'Dream', 'Southern Rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40',
  'Christian Rap', 'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
  'Psychedelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal', 'Acid Punk',
  'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll', 'Hard Rock',
];

/// "(13)", "(13)Pop", "13" və ya "Pop" -> "Pop". Tanınmayan nömrə -> ''.
String _id3Genre(String raw) {
  var s = raw.trim();
  final m = RegExp(r'^\((\d{1,3})\)\s*(.*)$').firstMatch(s);
  if (m != null) {
    final rest = m.group(2)!.trim();
    if (rest.isNotEmpty) return rest;
    s = m.group(1)!;
  }
  final n = int.tryParse(s);
  if (n != null) return n >= 0 && n < _kGenres.length ? _kGenres[n] : '';
  return s;
}

/// "2019", "2019-05-03", "2019-05-03T10:00" -> 2019. Tapılmazsa 0.
int _yearOf(String s) {
  final m = RegExp(r'(?:1[5-9]|20)\d{2}').firstMatch(s);
  return m == null ? 0 : int.parse(m.group(0)!);
}

/// "3", "3/12", "03" -> 3. Tapılmazsa 0.
int _leadInt(String s) {
  final m = RegExp(r'^\s*(\d+)').firstMatch(s);
  return m == null ? 0 : int.parse(m.group(1)!);
}

int _be32(Uint8List b, int o) =>
    b[o] * 16777216 + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3];

int _le32(Uint8List b, int o) =>
    b[o] + (b[o + 1] << 8) + (b[o + 2] << 16) + b[o + 3] * 16777216;

int _syncsafe(Uint8List b, int o) =>
    ((b[o] & 0x7F) << 21) |
    ((b[o + 1] & 0x7F) << 14) |
    ((b[o + 2] & 0x7F) << 7) |
    (b[o + 3] & 0x7F);

Uint8List _deunsync(Uint8List input) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < input.length; i++) {
    out.addByte(input[i]);
    if (input[i] == 0xFF && i + 1 < input.length && input[i + 1] == 0) {
      i++;
    }
  }
  return out.toBytes();
}

String _clean(String s) => s.replaceAll(RegExp(r'[\u0000-\u001F]'), ' ').trim();

String _utf16(Uint8List b, bool? bigEndian) {
  var i = 0;
  var be = bigEndian ?? false;
  if (bigEndian == null && b.length >= 2) {
    if (b[0] == 0xFF && b[1] == 0xFE) {
      be = false;
      i = 2;
    } else if (b[0] == 0xFE && b[1] == 0xFF) {
      be = true;
      i = 2;
    }
  }
  final units = <int>[];
  for (; i + 1 < b.length; i += 2) {
    units.add(be ? (b[i] << 8) | b[i + 1] : (b[i + 1] << 8) | b[i]);
  }
  return String.fromCharCodes(units);
}

/// Kodlama baytına göre ham metin (satır sonlarını korur, bölmez).
String _decodeRaw(int enc, Uint8List data) {
  String s;
  switch (enc) {
    case 1:
      s = _utf16(data, null);
      break;
    case 2:
      s = _utf16(data, true);
      break;
    case 3:
      s = utf8.decode(data, allowMalformed: true);
      break;
    default:
      s = latin1.decode(data, allowInvalid: true);
  }
  return s.replaceAll('\uFEFF', '').replaceAll('\u0000', '');
}

/// [p] konumundan itibaren kodlamaya uygun sonlandırıcıyı (\0 ya da \0\0) atlar.
int _skipTerminated(Uint8List b, int p, int enc) {
  final wide = enc == 1 || enc == 2;
  while (p < b.length) {
    if (wide) {
      if (p + 1 < b.length && b[p] == 0 && b[p + 1] == 0) return p + 2;
      p += 2;
    } else {
      if (b[p] == 0) return p + 1;
      p++;
    }
  }
  return b.length;
}

/// USLT / USL: kodlama(1) dil(3) açıklama(\0) metin
String _parseUslt(Uint8List b) {
  if (b.length < 5) return '';
  final enc = b[0];
  final p = _skipTerminated(b, 4, enc);
  if (p >= b.length) return '';
  return _decodeRaw(enc, Uint8List.sublistView(b, p)).trim();
}

/// SYLT / SLT: zaman damgası ms ise LRC metnine çevirir, değilse ''.
/// kodlama(1) dil(3) zamanBiçimi(1) içerikTürü(1) açıklama(\0) { metin(\0) zaman(4) }*
String _syltToLrc(Uint8List b) {
  if (b.length < 8) return '';
  final enc = b[0];
  final format = b[4]; // 1 = MPEG kare, 2 = milisaniye
  if (format != 2) return '';
  var p = _skipTerminated(b, 6, enc);
  final sb = StringBuffer();
  while (p < b.length) {
    final start = p;
    p = _skipTerminated(b, p, enc);
    final end = (enc == 1 || enc == 2) ? p - 2 : p - 1;
    if (p + 4 > b.length || end < start) break;
    final text = _decodeRaw(enc, Uint8List.sublistView(b, start, end))
        .replaceAll('\n', ' ')
        .trim();
    final ms = _be32(b, p);
    p += 4;
    final mm = (ms ~/ 60000).toString().padLeft(2, '0');
    final ss = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    sb.writeln('[$mm:$ss.$cs]$text');
  }
  return sb.toString();
}

/// ID3 metin freymi: ilk bayt kodlama, sonrası metin. Çoklu değerler ", " ile birleşir.
String _decodeText(Uint8List body) {
  if (body.length < 2) return '';
  final enc = body[0];
  final data = Uint8List.sublistView(body, 1);
  String s;
  switch (enc) {
    case 1:
      s = _utf16(data, null);
      break;
    case 2:
      s = _utf16(data, true);
      break;
    case 3:
      s = utf8.decode(data, allowMalformed: true);
      break;
    default:
      s = latin1.decode(data, allowInvalid: true);
  }
  return s
      .split('\u0000')
      .map((p) => p.replaceAll('\uFEFF', '').trim())
      .where((p) => p.isNotEmpty)
      .join(', ');
}

String _latin1Z(Uint8List b, int off, int len) {
  var end = off;
  while (end < off + len && b[end] != 0) {
    end++;
  }
  return latin1.decode(b.sublist(off, end), allowInvalid: true).trim();
}

bool _looksLikeImage(Uint8List b) {
  if (b.length < 16) return false;
  final jpeg = b[0] == 0xFF && b[1] == 0xD8;
  final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
  return jpeg || png;
}

// ------------------------------------------------------------------------ MP3

({int type, Uint8List data})? _parseApic(Uint8List b, bool v22) {
  if (b.length < 5) return null;
  final enc = b[0];
  var p = 1;
  if (v22) {
    p += 3; // 3 harfli format (JPG/PNG)
  } else {
    while (p < b.length && b[p] != 0) {
      p++; // mime tipi
    }
    p++;
  }
  if (p >= b.length) return null;
  final type = b[p++];
  final wide = enc == 1 || enc == 2;
  while (p < b.length) {
    if (wide) {
      if (p + 1 < b.length && b[p] == 0 && b[p + 1] == 0) {
        p += 2;
        break;
      }
      p += 2;
    } else {
      if (b[p] == 0) {
        p++;
        break;
      }
      p++;
    }
  }
  if (p >= b.length) return null;
  return (type: type, data: Uint8List.sublistView(b, p));
}

TagInfo _readMp3(Uint8List d) {
  var title = '', artist = '', album = '';
  var genre = '';
  var year = 0, track = 0, disc = 0;
  var uslt = '', sylt = '';
  Uint8List? cover;
  var coverRank = -1;

  if (d.length >= 10 && d[0] == 0x49 && d[1] == 0x44 && d[2] == 0x33) {
    final ver = d[3];
    final flags = d[5];
    final size = _syncsafe(d, 6);
    if (size > 0 && 10 + size <= d.length) {
      var tag = d.sublist(10, 10 + size);
      if ((flags & 0x80) != 0 && ver < 4) {
        tag = _deunsync(tag);
      }
      var pos = 0;
      if ((flags & 0x40) != 0 && ver >= 3 && tag.length >= 4) {
        pos = ver == 3 ? 4 + _be32(tag, 0) : _syncsafe(tag, 0);
      }
      final idLen = ver == 2 ? 3 : 4;
      final hdrLen = ver == 2 ? 6 : 10;

      while (pos + hdrLen <= tag.length) {
        if (tag[pos] == 0) break; // doldurma (padding)
        final id = String.fromCharCodes(tag.sublist(pos, pos + idLen));
        int fsize;
        var fflags = 0;
        if (ver == 2) {
          fsize = (tag[pos + 3] << 16) | (tag[pos + 4] << 8) | tag[pos + 5];
        } else if (ver == 3) {
          fsize = _be32(tag, pos + 4);
          fflags = (tag[pos + 8] << 8) | tag[pos + 9];
        } else {
          fsize = _syncsafe(tag, pos + 4);
          fflags = (tag[pos + 8] << 8) | tag[pos + 9];
        }
        final bodyStart = pos + hdrLen;
        if (fsize < 0 || bodyStart + fsize > tag.length) break;
        var body = tag.sublist(bodyStart, bodyStart + fsize);
        pos = bodyStart + fsize;

        if (ver == 4) {
          if ((fflags & 0x000C) != 0) continue; // sıkıştırılmış/şifreli
          if ((fflags & 0x0001) != 0 && body.length >= 4) {
            body = body.sublist(4);
          }
          if ((fflags & 0x0002) != 0) {
            body = _deunsync(body);
          }
        } else if (ver == 3 && (fflags & 0x00C0) != 0) {
          continue;
        }

        switch (id) {
          case 'TIT2':
          case 'TT2':
            if (title.isEmpty) title = _decodeText(body);
            break;
          case 'TPE1':
          case 'TP1':
            if (artist.isEmpty) artist = _decodeText(body);
            break;
          case 'TALB':
          case 'TAL':
            if (album.isEmpty) album = _decodeText(body);
            break;
          case 'TCON':
          case 'TCO':
            if (genre.isEmpty) genre = _id3Genre(_decodeText(body));
            break;
          case 'TYER':
          case 'TYE':
          case 'TDRC':
          case 'TDRL':
          case 'TDOR':
            if (year == 0) year = _yearOf(_decodeText(body));
            break;
          case 'TRCK':
          case 'TRK':
            if (track == 0) track = _leadInt(_decodeText(body));
            break;
          case 'TPOS':
          case 'TPA':
            if (disc == 0) disc = _leadInt(_decodeText(body));
            break;
          case 'USLT':
          case 'USL':
            if (uslt.isEmpty) uslt = _parseUslt(body);
            break;
          case 'SYLT':
          case 'SLT':
            if (sylt.isEmpty) sylt = _syltToLrc(body);
            break;
          case 'APIC':
          case 'PIC':
            final pic = _parseApic(body, ver == 2);
            if (pic != null && _looksLikeImage(pic.data)) {
              final rank = pic.type == 3 ? 2 : (pic.type == 0 ? 1 : 0);
              if (rank > coverRank) {
                coverRank = rank;
                cover = pic.data;
              }
            }
            break;
        }
      }
    }
  }

  // ID3v1 yedeği (dosyanın sonunda 128 bayt)
  if (d.length >= 128) {
    final o = d.length - 128;
    if (d[o] == 0x54 && d[o + 1] == 0x41 && d[o + 2] == 0x47) {
      if (title.isEmpty) title = _latin1Z(d, o + 3, 30);
      if (artist.isEmpty) artist = _latin1Z(d, o + 33, 30);
      if (album.isEmpty) album = _latin1Z(d, o + 63, 30);
      if (year == 0) year = _yearOf(_latin1Z(d, o + 93, 4));
      // ID3v1.1: 29-cu baytda 0 varsa 30-cu bayt trek nömrəsidir
      if (track == 0 && d[o + 125] == 0 && d[o + 126] != 0) track = d[o + 126];
      if (genre.isEmpty && d[o + 127] < _kGenres.length) genre = _kGenres[d[o + 127]];
    }
  }

  return TagInfo(
    title: _clean(title),
    artist: _clean(artist),
    album: _clean(album),
    cover: cover,
    lyrics: sylt.isNotEmpty ? sylt : uslt, // zamanlı söz varsa o tercih edilir
    genre: _clean(genre),
    year: year,
    track: track,
    disc: disc,
  );
}

// ----------------------------------------------------------------------- FLAC

TagInfo _readFlac(Uint8List d) {
  if (d.length < 4 ||
      d[0] != 0x66 ||
      d[1] != 0x4C ||
      d[2] != 0x61 ||
      d[3] != 0x43) {
    return TagInfo.empty;
  }
  var title = '', artist = '', album = '';
  var genre = '';
  var year = 0, track = 0, disc = 0;
  var lyrics = '', syncedLyrics = '';
  Uint8List? cover;
  var coverRank = -1;

  var p = 4;
  var last = false;
  while (!last && p + 4 <= d.length) {
    final hdr = d[p];
    last = (hdr & 0x80) != 0;
    final type = hdr & 0x7F;
    final len = (d[p + 1] << 16) | (d[p + 2] << 8) | d[p + 3];
    p += 4;
    if (p + len > d.length) break;
    final b = Uint8List.sublistView(d, p, p + len);

    try {
      if (type == 4) {
        // VORBIS_COMMENT (little-endian)
        var q = 0;
        final vend = _le32(b, q);
        q += 4 + vend;
        final count = _le32(b, q);
        q += 4;
        for (var i = 0; i < count && q + 4 <= b.length; i++) {
          final cl = _le32(b, q);
          q += 4;
          if (cl < 0 || q + cl > b.length) break;
          final c = utf8.decode(b.sublist(q, q + cl), allowMalformed: true);
          q += cl;
          final eq = c.indexOf('=');
          if (eq > 0) {
            final k = c.substring(0, eq).toUpperCase();
            final v = c.substring(eq + 1).trim();
            if (k == 'TITLE' && title.isEmpty) title = v;
            if (k == 'ARTIST' && artist.isEmpty) artist = v;
            if (k == 'ALBUM' && album.isEmpty) album = v;
            if (k == 'GENRE' && genre.isEmpty) genre = _id3Genre(v);
            if ((k == 'DATE' || k == 'YEAR') && year == 0) year = _yearOf(v);
            if (k == 'TRACKNUMBER' && track == 0) track = _leadInt(v);
            if (k == 'DISCNUMBER' && disc == 0) disc = _leadInt(v);
            if ((k == 'LYRICS' || k == 'UNSYNCEDLYRICS') && lyrics.isEmpty) {
              lyrics = v;
            }
            if (k == 'SYNCEDLYRICS' && syncedLyrics.isEmpty) syncedLyrics = v;
          }
        }
      } else if (type == 6) {
        // PICTURE (big-endian)
        final picType = _be32(b, 0);
        var q = 4;
        final mimeLen = _be32(b, q);
        q += 4 + mimeLen;
        final descLen = _be32(b, q);
        q += 4 + descLen + 16; // en, boy, derinlik, renk sayısı
        final dataLen = _be32(b, q);
        q += 4;
        if (dataLen > 0 && q + dataLen <= b.length) {
          final img = b.sublist(q, q + dataLen);
          final rank = picType == 3 ? 2 : (picType == 0 ? 1 : 0);
          if (rank > coverRank && _looksLikeImage(img)) {
            coverRank = rank;
            cover = img;
          }
        }
      }
    } catch (_) {
      // bu blok bozuk: sonrakine geç
    }
    p += len;
  }

  return TagInfo(
    title: _clean(title),
    artist: _clean(artist),
    album: _clean(album),
    cover: cover,
    lyrics: syncedLyrics.isNotEmpty ? syncedLyrics : lyrics,
    genre: _clean(genre),
    year: year,
    track: track,
    disc: disc,
  );
}

// ------------------------------------------------------------- M4A / MP4 (iPhone)

({int start, int end})? _findAtom(Uint8List d, int from, int to, String type) {
  var p = from;
  while (p + 8 <= to) {
    var size = _be32(d, p);
    final name = String.fromCharCodes(d.sublist(p + 4, p + 8));
    var header = 8;
    if (size == 1) {
      if (p + 16 > to) return null;
      size = _be32(d, p + 12); // 64 bit boyutun alt kısmı
      header = 16;
    } else if (size == 0) {
      size = to - p;
    }
    if (size < header || p + size > to) return null;
    if (name == type) return (start: p + header, end: p + size);
    p += size;
  }
  return null;
}

TagInfo _readMp4(Uint8List d) {
  final moov = _findAtom(d, 0, d.length, 'moov');
  if (moov == null) return TagInfo.empty;
  final udta = _findAtom(d, moov.start, moov.end, 'udta');
  if (udta == null) return TagInfo.empty;
  final meta = _findAtom(d, udta.start, udta.end, 'meta');
  if (meta == null || meta.start + 4 > meta.end) return TagInfo.empty;
  final ilst = _findAtom(d, meta.start + 4, meta.end, 'ilst'); // meta: 4 bayt sürüm/bayrak
  if (ilst == null) return TagInfo.empty;

  var title = '', artist = '', album = '', albumArtist = '', lyrics = '';
  var genre = '';
  var year = 0, track = 0, disc = 0;
  Uint8List? cover;

  var p = ilst.start;
  while (p + 8 <= ilst.end) {
    final size = _be32(d, p);
    if (size < 8 || p + size > ilst.end) break;
    final name = String.fromCharCodes(d.sublist(p + 4, p + 8));
    final data = _findAtom(d, p + 8, p + size, 'data');
    if (data != null && data.start + 8 <= data.end) {
      // data atomu: 4 bayt tip + 4 bayt dil + içerik
      final payload = Uint8List.sublistView(d, data.start + 8, data.end);
      switch (name) {
        case '\u00A9nam':
          title = utf8.decode(payload, allowMalformed: true);
          break;
        case '\u00A9ART':
          artist = utf8.decode(payload, allowMalformed: true);
          break;
        case '\u00A9alb':
          album = utf8.decode(payload, allowMalformed: true);
          break;
        case '\u00A9lyr':
          lyrics = utf8.decode(payload, allowMalformed: true).trim();
          break;
        case 'aART':
          albumArtist = utf8.decode(payload, allowMalformed: true);
          break;
        case '\u00A9gen':
          genre = utf8.decode(payload, allowMalformed: true);
          break;
        case 'gnre':
          // ikili janr: 2 bayt, ID3v1 indeksi + 1
          if (genre.isEmpty && payload.length >= 2) {
            final gi = ((payload[0] << 8) | payload[1]) - 1;
            if (gi >= 0 && gi < _kGenres.length) genre = _kGenres[gi];
          }
          break;
        case '\u00A9day':
          year = _yearOf(utf8.decode(payload, allowMalformed: true));
          break;
        case 'trkn':
          // 2 bayt boş, 2 bayt trek, 2 bayt cəmi
          if (payload.length >= 4) track = (payload[2] << 8) | payload[3];
          break;
        case 'disk':
          if (payload.length >= 4) disc = (payload[2] << 8) | payload[3];
          break;
        case 'covr':
          if (_looksLikeImage(payload)) cover = payload;
          break;
      }
    }
    p += size;
  }

  return TagInfo(
    title: _clean(title),
    artist: _clean(artist.isNotEmpty ? artist : albumArtist),
    album: _clean(album),
    cover: cover,
    lyrics: lyrics,
    genre: _clean(genre),
    year: year,
    track: track,
    disc: disc,
  );
}


// ---------------------------------------------------------------- süre

/// Dosya baytlarından şarkı süresini hesaplar (etiket/başlıktan; çalmaya gerek yok).
/// MP3: Xing/Info/VBRI başlığı, yoksa sabit bitrate; FLAC: STREAMINFO; M4A: mvhd.
/// Bulunamazsa null (OGG/Opus/WAV vb.: şarkı ilk çalınınca öğrenilir).
Duration? readDuration(Uint8List data, String ext) {
  try {
    Duration? d;
    switch (ext.toLowerCase()) {
      case 'mp3':
        d = _mp3Duration(data);
        break;
      case 'flac':
        d = _flacDuration(data);
        break;
      case 'm4a':
      case 'mp4':
      case 'm4b':
        d = _mp4Duration(data);
        break;
    }
    if (d != null && d.inMilliseconds > 0) return d;
  } catch (_) {
    // bozuk dosya: süre bilinmiyor
  }
  return null;
}

const _mp3Br1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
const _mp3Br2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
const _mp3Sr = {
  3: [44100, 48000, 32000], // MPEG1
  2: [22050, 24000, 16000], // MPEG2
  0: [11025, 12000, 8000], // MPEG2.5
};

class _Mp3Frame {
  final bool mpeg1;
  final bool mono;
  final bool crc; // CRC korumalı mı
  final int bitrate; // kbps
  final int sampleRate;
  final int frameLen;
  const _Mp3Frame(
      this.mpeg1, this.mono, this.crc, this.bitrate, this.sampleRate, this.frameLen);
  int get samples => mpeg1 ? 1152 : 576;
}

/// [i] konumunda geçerli bir MPEG Layer III kare başlığı varsa onu döndürür.
_Mp3Frame? _mp3Frame(Uint8List d, int i) {
  if (i + 4 > d.length) return null;
  if (d[i] != 0xFF || (d[i + 1] & 0xE0) != 0xE0) return null;
  final ver = (d[i + 1] >> 3) & 3;
  final layer = (d[i + 1] >> 1) & 3;
  if (ver == 1 || layer != 1) return null; // yalnızca Layer III
  final brIdx = d[i + 2] >> 4;
  final srIdx = (d[i + 2] >> 2) & 3;
  if (brIdx == 0 || brIdx == 15 || srIdx == 3) return null;
  final mpeg1 = ver == 3;
  final br = (mpeg1 ? _mp3Br1 : _mp3Br2)[brIdx];
  final sr = _mp3Sr[ver]![srIdx];
  final pad = (d[i + 2] >> 1) & 1;
  final spf = mpeg1 ? 1152 : 576;
  final len = ((spf ~/ 8) * br * 1000) ~/ sr + pad;
  final mono = ((d[i + 3] >> 6) & 3) == 3;
  final crc = (d[i + 1] & 1) == 0;
  return _Mp3Frame(mpeg1, mono, crc, br, sr, len);
}

bool _tagAt(Uint8List d, int o, String t) {
  if (o < 0 || o + t.length > d.length) return false;
  for (var k = 0; k < t.length; k++) {
    if (d[o + k] != t.codeUnitAt(k)) return false;
  }
  return true;
}

Duration? _mp3Duration(Uint8List d) {
  var p = 0;
  if (d.length > 10 && _tagAt(d, 0, 'ID3')) {
    p = 10 + _syncsafe(d, 6) + ((d[5] & 0x10) != 0 ? 10 : 0);
  }
  final limit = (p + 65536 < d.length - 4) ? p + 65536 : d.length - 4;
  for (var i = p; i < limit; i++) {
    final f = _mp3Frame(d, i);
    if (f == null) continue;
    // yanlış senkronu elemek için bir sonraki kare de geçerli olmalı
    final next = i + f.frameLen;
    if (next + 4 <= d.length && _mp3Frame(d, next) == null) continue;

    // Xing / Info (VBR) başlığı
    final side = f.mpeg1 ? (f.mono ? 17 : 32) : (f.mono ? 9 : 17);
    final x = i + 4 + side + (f.crc ? 2 : 0);
    if ((_tagAt(d, x, 'Xing') || _tagAt(d, x, 'Info')) && x + 12 <= d.length) {
      final flags = _be32(d, x + 4);
      if ((flags & 1) != 0) {
        final frames = _be32(d, x + 8);
        if (frames > 0) {
          return Duration(
              milliseconds: (frames * f.samples * 1000 / f.sampleRate).round());
        }
      }
    }
    // VBRI (Fraunhofer) başlığı
    final v = i + 4 + 32;
    if (_tagAt(d, v, 'VBRI') && v + 18 <= d.length) {
      final frames = _be32(d, v + 14);
      if (frames > 0) {
        return Duration(
            milliseconds: (frames * f.samples * 1000 / f.sampleRate).round());
      }
    }
    // Sabit bitrate: ses baytları / bitrate
    var end = d.length;
    if (end >= 128 && _tagAt(d, end - 128, 'TAG')) end -= 128;
    final bytes = end - i;
    if (bytes <= 0) return null;
    return Duration(milliseconds: (bytes * 8 / f.bitrate).round());
  }
  return null;
}

Duration? _flacDuration(Uint8List d) {
  if (d.length < 26 || !_tagAt(d, 0, 'fLaC')) return null;
  if ((d[4] & 0x7F) != 0) return null; // ilk blok STREAMINFO olmalı
  final sr = (d[18] << 12) | (d[19] << 4) | (d[20] >> 4);
  final total = (d[21] & 0x0F) * 4294967296 + _be32(d, 22);
  if (sr <= 0 || total <= 0) return null;
  return Duration(milliseconds: (total * 1000 / sr).round());
}

Duration? _mp4Duration(Uint8List d) {
  final moov = _findAtom(d, 0, d.length, 'moov');
  if (moov == null) return null;
  final mvhd = _findAtom(d, moov.start, moov.end, 'mvhd');
  if (mvhd == null) return null;
  final s = mvhd.start;
  final ver = d[s];
  int timescale, dur;
  if (ver == 1) {
    if (s + 32 > mvhd.end) return null;
    timescale = _be32(d, s + 20);
    dur = _be32(d, s + 24) * 4294967296 + _be32(d, s + 28);
  } else {
    if (s + 20 > mvhd.end) return null;
    timescale = _be32(d, s + 12);
    dur = _be32(d, s + 16);
  }
  if (timescale <= 0 || dur <= 0) return null;
  return Duration(milliseconds: (dur * 1000 / timescale).round());
}


// ---------------------------------------------------------------- ReplayGain

int _lc(int b) => (b >= 65 && b <= 90) ? b + 32 : b;

/// [key] (kiçik hərflə) açarını [from, to) aralığında axtarır; UTF-16 kimi
/// hərflər arasında tək sıfır baytına icazə verir. Tapılsa açarın bitdiyi yeri qaytarır.
int _findKeyEnd(Uint8List d, List<int> key, int from, int to) {
  final n = key.length;
  if (to > d.length) to = d.length;
  for (var i = from; i < to; i++) {
    if (_lc(d[i]) != key[0]) continue;
    var j = 1, p = i + 1, z = 0;
    while (j < n && p < to) {
      final b = d[p];
      if (b == 0) {
        if (++z > 1) break;
        p++;
        continue;
      }
      z = 0;
      if (_lc(b) != key[j]) break;
      j++;
      p++;
    }
    if (j == n) return p;
  }
  return -1;
}

double? _gainAfter(Uint8List d, int at) {
  final sb = StringBuffer();
  for (var i = at; i < d.length && sb.length < 40 && i < at + 120; i++) {
    if (d[i] != 0) sb.writeCharCode(d[i]);
  }
  final m = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(sb.toString());
  if (m == null) return null;
  final v = double.tryParse(m.group(0)!.replaceAll(',', '.'));
  if (v == null || v.abs() > 40) return null;
  return v;
}

final _kTrackGain = 'replaygain_track_gain'.codeUnits;
final _kAlbumGain = 'replaygain_album_gain'.codeUnits;

/// Fayldakı ReplayGain etiketini (dB) oxuyur: ID3 TXXX, Vorbis/FLAC şərhi, MP4 "----" atomu.
/// Yoxdursa null. Heç vaxt xəta atmır.
double? readReplayGain(Uint8List d, String ext) {
  try {
    final e = ext.toLowerCase();
    final ranges = <(int, int)>[];
    if (e == 'mp3' || e == 'aac') {
      if (d.length > 10 && d[0] == 0x49 && d[1] == 0x44 && d[2] == 0x33) {
        ranges.add((0, 10 + _syncsafe(d, 6)));
      } else {
        ranges.add((0, 65536));
      }
      ranges.add((d.length > 65536 ? d.length - 65536 : 0, d.length)); // APE / ID3v1
    } else if (e == 'flac' || e == 'ogg' || e == 'opus') {
      ranges.add((0, 4 * 1024 * 1024));
    } else {
      ranges.add((0, d.length)); // m4a: moov faylın sonunda ola bilər
    }
    for (final key in [_kTrackGain, _kAlbumGain]) {
      for (final r in ranges) {
        final end = _findKeyEnd(d, key, r.$1, r.$2);
        if (end < 0) continue;
        final v = _gainAfter(d, end);
        if (v != null) return v;
      }
    }
  } catch (_) {}
  return null;
}
