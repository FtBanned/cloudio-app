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

  const TagInfo({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.cover,
    this.lyrics = '',
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
    }
  }

  return TagInfo(
    title: _clean(title),
    artist: _clean(artist),
    album: _clean(album),
    cover: cover,
    lyrics: sylt.isNotEmpty ? sylt : uslt, // zamanlı söz varsa o tercih edilir
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
  );
}