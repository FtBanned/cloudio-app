import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sembast/sembast.dart';

import 'cloudio_db_stub.dart'
    if (dart.library.js_interop) 'cloudio_db_web.dart'
    if (dart.library.io) 'cloudio_db_io.dart';
import 'lyrics.dart';

/// Diskdən oxunmuş bir mahnı (Song obyekti player_controller.dart-da qurulur).
class SavedSong {
  final String id;
  final int seq;
  final String title;
  final String artist;
  final String album;
  final String ext;
  final bool liked;
  final int coverStatus; // CoverStatus.index
  final Uint8List? cover;
  final Lyrics? lyrics;
  final bool lyricsNotFound;
  final String? file; // telefonda: tətbiq qovluğundakı səs faylının adı

  SavedSong({
    required this.id,
    required this.seq,
    required this.title,
    required this.artist,
    required this.album,
    required this.ext,
    required this.liked,
    required this.coverStatus,
    required this.cover,
    required this.lyrics,
    required this.lyricsNotFound,
    this.file,
  });
}

class SavedPlaylist {
  final String name;
  final List<String> ids;
  SavedPlaylist(this.name, this.ids);
}

class SavedLibrary {
  final List<SavedSong> songs;
  final List<SavedPlaylist> playlists;
  SavedLibrary(this.songs, this.playlists);
}

/// Kitabxananı (mahnılar, siyahılar, bəyənmələr, sözlər, üzlüklər) saxlayır.
/// Bütün xətalar tutulur və konsola "[Cloudio DB]" ilə yazılır: tətbiq heç vaxt çökmür.
class CloudioStore {
  CloudioStore._();
  static final CloudioStore instance = CloudioStore._();

  Database? _db;
  bool get enabled => _db != null;

  final _songs = stringMapStoreFactory.store('songs'); // yüngül məlumat + üzlük
  final _audio = stringMapStoreFactory.store('audio'); // səs faylının özü (base64)
  final _meta = stringMapStoreFactory.store('meta'); // çalma siyahıları

  Future<void> open() async {
    try {
      _db = await openCloudioDb();
      debugPrint('[Cloudio DB] ${_db == null ? 'bu platformda söndürülüb' : 'açıldı'}');
    } catch (e, st) {
      debugPrint('[Cloudio DB] açıla bilmədi: $e');
      debugPrint('$st');
      _db = null;
    }
  }

  // ---- söz <-> JSON ----
  static Map<String, Object?> _lyricsToMap(Lyrics l) => <String, Object?>{
        's': l.synced,
        'src': l.source,
        'l': [
          for (final line in l.lines)
            <Object?>[line.time?.inMilliseconds ?? -1, line.text],
        ],
      };

  static Lyrics? _lyricsFromMap(Object? raw) {
    try {
      if (raw is! Map) return null;
      final lines = <LyricLine>[];
      for (final e in (raw['l'] as List)) {
        final row = e as List;
        final ms = row[0] as int;
        lines.add(LyricLine(
          ms < 0 ? null : Duration(milliseconds: ms),
          row[1] as String,
        ));
      }
      return Lyrics(
        lines,
        synced: raw['s'] as bool? ?? false,
        source: raw['src'] as String? ?? 'Dosya',
      );
    } catch (e) {
      debugPrint('[Cloudio DB] söz oxunmadı: $e');
      return null;
    }
  }

  /// Bütün kitabxananı oxuyur. Baza yoxdursa null.
  Future<SavedLibrary?> loadAll() async {
    final db = _db;
    if (db == null) return null;
    try {
      final songSnaps = await _songs.find(db);
      final result = <SavedSong>[];
      for (final snap in songSnaps) {
        try {
          final m = snap.value;
          final id = snap.key;
          final coverB64 = m['cover'] as String?;
          result.add(SavedSong(
            id: id,
            seq: m['seq'] as int? ?? 0,
            title: m['title'] as String? ?? '',
            artist: m['artist'] as String? ?? '',
            album: m['album'] as String? ?? '',
            ext: m['ext'] as String? ?? '',
            liked: m['liked'] as bool? ?? false,
            coverStatus: m['coverStatus'] as int? ?? 0,
            cover: coverB64 == null ? null : base64Decode(coverB64),
            lyrics: _lyricsFromMap(m['lyrics']),
            lyricsNotFound: m['lyricsNotFound'] as bool? ?? false,
            file: m['file'] as String?,
          ));
        } catch (e) {
          debugPrint('[Cloudio DB] bir mahnı oxunmadı (${snap.key}): $e');
        }
      }
      result.sort((a, b) => a.seq.compareTo(b.seq));

      final plRec = await _meta.record('playlists').get(db);
      final playlists = <SavedPlaylist>[];
      if (plRec != null) {
        for (final p in (plRec['list'] as List? ?? const [])) {
          final pm = p as Map;
          playlists.add(SavedPlaylist(
            pm['name'] as String? ?? '',
            [for (final id in (pm['ids'] as List? ?? const [])) id as String],
          ));
        }
      }
      debugPrint(
          '[Cloudio DB] yükləndi: ${result.length} mahnı, ${playlists.length} siyahı');
      return SavedLibrary(result, playlists);
    } catch (e, st) {
      debugPrint('[Cloudio DB] oxuma xətası: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// Səs faylını yalnız çalınanda oxuyur (açılışda bütün faylları yaddaşa yükləmirik).
  Future<Uint8List?> loadAudio(String id) async {
    final db = _db;
    if (db == null) return null;
    try {
      final rec = await _audio.record(id).get(db);
      final b64 = rec == null ? null : rec['b'] as String?;
      return b64 == null ? null : base64Decode(b64);
    } catch (e) {
      debugPrint('[Cloudio DB] səs oxunmadı ($id): $e');
      return null;
    }
  }

  /// Bir mahnının məlumatını yazır. [audio] verilərsə səs faylı da yazılır
  /// (yalnız mahnı ilk əlavə olunanda lazımdır). Uğurlu olarsa true qaytarır.
  Future<bool> saveSong({
    required String id,
    required int seq,
    required String title,
    required String artist,
    required String album,
    required String ext,
    required bool liked,
    required int coverStatus,
    Uint8List? cover,
    Lyrics? lyrics,
    required bool lyricsNotFound,
    String? file,
    Uint8List? audio,
  }) async {
    final db = _db;
    if (db == null) return false;
    try {
      final meta = <String, Object?>{
        'seq': seq,
        'title': title,
        'artist': artist,
        'album': album,
        'ext': ext,
        'liked': liked,
        'coverStatus': coverStatus,
        'cover': cover == null ? null : base64Encode(cover),
        'lyrics': lyrics == null ? null : _lyricsToMap(lyrics),
        'lyricsNotFound': lyricsNotFound,
        'file': file,
      };
      await db.transaction((txn) async {
        await _songs.record(id).put(txn, meta);
        if (audio != null) {
          await _audio.record(id).put(txn, <String, Object?>{'b': base64Encode(audio)});
        }
      });
      return true;
    } catch (e, st) {
      debugPrint('[Cloudio DB] yazıla bilmədi ($title): $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<void> deleteSong(String id) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await _songs.record(id).delete(txn);
        await _audio.record(id).delete(txn);
      });
    } catch (e) {
      debugPrint('[Cloudio DB] silinə bilmədi ($id): $e');
    }
  }

  Future<void> savePlaylists(List<SavedPlaylist> lists) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('playlists').put(db, <String, Object?>{
        'list': [
          for (final p in lists) <String, Object?>{'name': p.name, 'ids': p.ids},
        ],
      });
    } catch (e) {
      debugPrint('[Cloudio DB] siyahılar yazıla bilmədi: $e');
    }
  }
}