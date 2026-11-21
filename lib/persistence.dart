import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sembast/utils/sembast_import_export.dart';

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
  final int? durationMs; // null: hələ yoxlanmayıb, -1: yoxlanıb amma bilinmir
  final int playCount;
  final int lastPlayedMs; // 0: heç çalınmayıb
  final double? gainDb; // ReplayGain (dB), yoxdursa null
  final bool gainTried; // etiket bir dəfə yoxlanıb
  final String genre;
  final int year; // 0: yoxdur
  final int trackNo; // 0: yoxdur
  final int discNo; // 0: yoxdur
  final bool tagsTried; // janr/il/trek etiketi bir dəfə oxunub

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
    this.durationMs,
    this.playCount = 0,
    this.lastPlayedMs = 0,
    this.gainDb,
    this.gainTried = false,
    this.genre = '',
    this.year = 0,
    this.trackNo = 0,
    this.discNo = 0,
    this.tagsTried = false,
  });
}

/// Bir dinləmə hadisəsi (30 san dinlənəndə yazılır). Şəxsi statistika bunun üstündən qurulur.
/// Mahnı sonradan silinsə də statistika qalsın deyə ad/sənətçi/janr burada da saxlanır.
class PlayEvent {
  final int ts; // epoch ms
  final String songId;
  final String title;
  final String artist;
  final String genre;
  final int durMs; // 0: bilinmir
  const PlayEvent({
    required this.ts,
    required this.songId,
    required this.title,
    required this.artist,
    this.genre = '',
    this.durMs = 0,
  });
}

class SavedPlaylist {
  final String name;
  final List<String> ids;
  SavedPlaylist(this.name, this.ids);
}

/// Son çalma növbəsi (tətbiq bağlanıb açılanda bərpa üçün).
class SavedQueue {
  final List<String> ids; // növbədəki mahnıların sırası
  final List<int> order; // qarışıq sıra (ids indeksləri), boş ola bilər
  final int? cur; // ids içində hazırkı mahnı
  final int pos; // order içində hazırkı yer
  final bool shuffle;
  final bool smart; // true: Ağıllı mix (shuffle ilə birlikdə)
  final int repeat; // RepeatKind.index
  final String name;
  SavedQueue({
    required this.ids,
    required this.order,
    required this.cur,
    required this.pos,
    required this.shuffle,
    this.smart = false,
    required this.repeat,
    required this.name,
  });
}

class SavedPosition {
  final String id;
  final int ms;
  SavedPosition(this.id, this.ms);
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
  // Sözler ayrıca küçük bir kayıtta da tutulur: büyük şarkı kaydı (kapak dahil) yarım
  // yazılsa ya da yazılamasa bile internetten bulunan/seçilen söz kaybolmasın.
  final _lyrics = stringMapStoreFactory.store('lyrics');
  final _plays = intMapStoreFactory.store('plays'); // dinləmə tarixçəsi (statistika)

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

  // ---- yedək / bərpa ----

  /// Bütün bazanı (mahnılar, üzlüklər, sözlər, siyahılar, bəyənmələr, statistika,
  /// ayarlar, tema, profil, növbə) JSON-a çevrilə bilən Map kimi verir.
  Future<Map<String, Object?>?> exportAll() async {
    final db = _db;
    if (db == null) return null;
    try {
      return await exportDatabase(db);
    } catch (e, st) {
      debugPrint('[Cloudio DB] ixrac olunmadı: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// Bazanı yedəkdən gələn məzmunla tamamilə əvəz edir. Uğursuz olarsa köhnə baza
  /// geri açılır və false qaytarılır.
  Future<bool> replaceAll(Map<String, Object?> content) async {
    final old = _db;
    if (old == null) return false;
    try {
      await old.close();
      _db = null;
      final fresh = await importCloudioDb(content);
      if (fresh == null) throw StateError('baza idxal olunmadı');
      _db = fresh;
      return true;
    } catch (e, st) {
      debugPrint('[Cloudio DB] bərpa olunmadı: $e');
      debugPrint('$st');
      try {
        _db = await openCloudioDb();
      } catch (e2) {
        debugPrint('[Cloudio DB] köhnə baza açıla bilmədi: $e2');
      }
      return false;
    }
  }

  // ---- söz <-> JSON ----
  static Map<String, Object?> _lyricsToMap(Lyrics l) => <String, Object?>{
    's': l.synced,
    'src': l.source,
    'l': [
      for (final line in l.lines) <Object?>[line.time?.inMilliseconds ?? -1, line.text],
    ],
  };

  static Lyrics? _lyricsFromMap(Object? raw) {
    try {
      if (raw is! Map) return null;
      final lines = <LyricLine>[];
      for (final e in (raw['l'] as List)) {
        final row = e as List;
        final ms = row[0] as int;
        lines.add(LyricLine(ms < 0 ? null : Duration(milliseconds: ms), row[1] as String));
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
      final lyricById = <String, Map<String, Object?>>{};
      try {
        for (final r in await _lyrics.find(db)) {
          lyricById[r.key] = r.value;
        }
      } catch (e) {
        debugPrint('[Cloudio DB] söz deposu okunamadı: $e');
      }
      final result = <SavedSong>[];
      for (final snap in songSnaps) {
        try {
          final m = snap.value;
          final id = snap.key;
          final coverB64 = m['cover'] as String?;
          // Söz deposunda kayıt varsa o geçerli (daha güvenilir ve daha yeni)
          final extra = lyricById[id];
          final Lyrics? lyr;
          final bool lyrNotFound;
          if (extra != null) {
            lyr = extra['l'] == null
                ? null
                : (_lyricsFromMap(extra['l']) ?? _lyricsFromMap(m['lyrics']));
            lyrNotFound = extra['nf'] as bool? ?? false;
          } else {
            lyr = _lyricsFromMap(m['lyrics']);
            lyrNotFound = m['lyricsNotFound'] as bool? ?? false;
          }
          result.add(
            SavedSong(
              id: id,
              seq: m['seq'] as int? ?? 0,
              title: m['title'] as String? ?? '',
              artist: m['artist'] as String? ?? '',
              album: m['album'] as String? ?? '',
              ext: m['ext'] as String? ?? '',
              liked: m['liked'] as bool? ?? false,
              coverStatus: m['coverStatus'] as int? ?? 0,
              cover: coverB64 == null ? null : base64Decode(coverB64),
              lyrics: lyr,
              lyricsNotFound: lyrNotFound,
              file: m['file'] as String?,
              durationMs: m['dur'] as int?,
              playCount: m['plays'] as int? ?? 0,
              lastPlayedMs: m['last'] as int? ?? 0,
              gainDb: (m['gain'] as num?)?.toDouble(),
              gainTried: m['gt'] as bool? ?? false,
              genre: m['genre'] as String? ?? '',
              year: m['year'] as int? ?? 0,
              trackNo: m['trk'] as int? ?? 0,
              discNo: m['disc'] as int? ?? 0,
              tagsTried: m['tt'] as bool? ?? false,
            ),
          );
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
          playlists.add(
            SavedPlaylist(pm['name'] as String? ?? '', [
              for (final id in (pm['ids'] as List? ?? const [])) id as String,
            ]),
          );
        }
      }
      debugPrint('[Cloudio DB] yükləndi: ${result.length} mahnı, ${playlists.length} siyahı');
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
    int? durationMs,
    int playCount = 0,
    int lastPlayedMs = 0,
    double? gainDb,
    bool gainTried = false,
    String genre = '',
    int year = 0,
    int trackNo = 0,
    int discNo = 0,
    bool tagsTried = false,
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
        'dur': durationMs,
        'plays': playCount,
        'last': lastPlayedMs,
        'gain': gainDb,
        'gt': gainTried,
        'genre': genre,
        'year': year,
        'trk': trackNo,
        'disc': discNo,
        'tt': tagsTried,
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

  /// Bir şarkının sözünü (ya da "bulunamadı" işaretini) küçük ayrı kayıtta saklar.
  /// Yazılamazsa kısa bir beklemeyle bir kez daha dener. Başarılıysa true döner.
  Future<bool> saveLyrics(String id, Lyrics? lyrics, {required bool notFound}) async {
    final db = _db;
    if (db == null) return false;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _lyrics.record(id).put(db, <String, Object?>{
          'l': lyrics == null ? null : _lyricsToMap(lyrics),
          'nf': notFound,
        });
        return true;
      } catch (e) {
        debugPrint('[Cloudio DB] söz yazılamadı ($id): $e');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return false;
  }

  Future<void> deleteSong(String id) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await _songs.record(id).delete(txn);
        await _audio.record(id).delete(txn);
        await _lyrics.record(id).delete(txn);
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

  // ---- kitaplıqda əl ilə sıralama (sürüklə-burax) ----
  Future<void> saveLibraryOrder(List<String> ids) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('libOrder').put(db, <String, Object?>{'ids': ids});
    } catch (e) {
      debugPrint('[Cloudio DB] kitaplıq sırası yazıla bilmədi: $e');
    }
  }

  Future<List<String>?> loadLibraryOrder() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('libOrder').get(db);
      if (m == null) return null;
      return [for (final id in (m['ids'] as List? ?? const [])) id as String];
    } catch (e) {
      debugPrint('[Cloudio DB] kitaplıq sırası oxunmadı: $e');
      return null;
    }
  }

  // ---- son çalma vəziyyəti ----
  Future<void> saveQueue(SavedQueue q) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('queue').put(db, <String, Object?>{
        'ids': q.ids,
        'order': q.order,
        'cur': q.cur,
        'pos': q.pos,
        'shuffle': q.shuffle,
        'smart': q.smart,
        'repeat': q.repeat,
        'name': q.name,
      });
    } catch (e) {
      debugPrint('[Cloudio DB] növbə yazıla bilmədi: $e');
    }
  }

  Future<SavedQueue?> loadQueue() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('queue').get(db);
      if (m == null) return null;
      return SavedQueue(
        ids: [for (final e in (m['ids'] as List? ?? const [])) e as String],
        order: [for (final e in (m['order'] as List? ?? const [])) e as int],
        cur: m['cur'] as int?,
        pos: m['pos'] as int? ?? 0,
        shuffle: m['shuffle'] as bool? ?? false,
        smart: m['smart'] as bool? ?? false,
        repeat: m['repeat'] as int? ?? 0,
        name: m['name'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('[Cloudio DB] növbə oxunmadı: $e');
      return null;
    }
  }

  Future<void> savePosition(String id, int ms) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('position').put(db, <String, Object?>{'id': id, 'ms': ms});
    } catch (e) {
      debugPrint('[Cloudio DB] mövqe yazıla bilmədi: $e');
    }
  }

  Future<SavedPosition?> loadPosition() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('position').get(db);
      if (m == null) return null;
      final id = m['id'] as String?;
      if (id == null) return null;
      return SavedPosition(id, m['ms'] as int? ?? 0);
    } catch (e) {
      debugPrint('[Cloudio DB] mövqe oxunmadı: $e');
      return null;
    }
  }

  // ---- çalma ayarları (crossfade, ses seviyəsi tarazlama) ----
  Future<void> saveSettings({
    required double crossfade,
    required bool normalize,
    int coverVersion = 0,
    double speed = 1.0,
    bool dynamicBg = true,
  }) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('settings').put(db, <String, Object?>{
        'crossfade': crossfade,
        'normalize': normalize,
        'coverV': coverVersion,
        'speed': speed,
        'dynBg': dynamicBg,
      });
    } catch (e) {
      debugPrint('[Cloudio DB] ayarlar yazıla bilmədi: $e');
    }
  }

  Future<({double crossfade, bool normalize, int coverVersion, double speed, bool dynamicBg})?>
  loadSettings() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('settings').get(db);
      if (m == null) return null;
      return (
        crossfade: (m['crossfade'] as num?)?.toDouble() ?? 0.0,
        normalize: m['normalize'] as bool? ?? false,
        coverVersion: m['coverV'] as int? ?? 0,
        speed: (m['speed'] as num?)?.toDouble() ?? 1.0,
        dynamicBg: m['dynBg'] as bool? ?? true,
      );
    } catch (e) {
      debugPrint('[Cloudio DB] ayarlar oxunmadı: $e');
      return null;
    }
  }

  // ---- səs gücləndirici ayarları ----
  Future<void> saveBooster(Map<String, Object?> data) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('booster').put(db, data);
    } catch (e) {
      debugPrint('[Cloudio DB] gücləndirici yazıla bilmədi: $e');
    }
  }

  Future<Map<String, Object?>?> loadBooster() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('booster').get(db);
      return m == null ? null : Map<String, Object?>.of(m);
    } catch (e) {
      debugPrint('[Cloudio DB] gücləndirici oxunmadı: $e');
      return null;
    }
  }

  // ---- qarşılama ekranı ("artıq göstərilib" bayrağı) ----
  Future<void> saveOnboardingSeen() async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('onboarding').put(db, <String, Object?>{'seen': true});
    } catch (e) {
      debugPrint('[Cloudio DB] qarşılama bayrağı yazıla bilmədi: $e');
    }
  }

  Future<bool> loadOnboardingSeen() async {
    final db = _db;
    if (db == null) return true;
    try {
      final m = await _meta.record('onboarding').get(db);
      return m != null && m['seen'] == true;
    } catch (e) {
      debugPrint('[Cloudio DB] qarşılama bayrağı oxunmadı: $e');
      return true; // xəta olarsa narahat etmə
    }
  }

  // ---- yedək xatırlatması (son yedək vaxtı, təxirə salma, həftə sayı) ----
  Future<void> saveBackupInfo(Map<String, Object?> data) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('backupinfo').put(db, data);
    } catch (e) {
      debugPrint('[Cloudio DB] yedək məlumatı yazıla bilmədi: $e');
    }
  }

  Future<Map<String, Object?>?> loadBackupInfo() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('backupinfo').get(db);
      return m == null ? null : Map<String, Object?>.of(m);
    } catch (e) {
      debugPrint('[Cloudio DB] yedək məlumatı oxunmadı: $e');
      return null;
    }
  }

  // ---- dinləmə tarixçəsi (Şəxsi statistika) ----
  Future<void> addPlay(PlayEvent e) async {
    final db = _db;
    if (db == null) return;
    try {
      await _plays.add(db, <String, Object?>{
        'ts': e.ts,
        'id': e.songId,
        't': e.title,
        'a': e.artist,
        'g': e.genre,
        'd': e.durMs,
      });
    } catch (err) {
      debugPrint('[Cloudio DB] dinləmə yazıla bilmədi: $err');
    }
  }

  /// Təkrar mahnı birləşdirilərkən: [fromId]-yə aid bütün dinləmə qeydlərini [toId]-yə köçürür.
  Future<void> reassignPlays(
    String fromId,
    String toId, {
    required String title,
    required String artist,
  }) async {
    final db = _db;
    if (db == null) return;
    try {
      await _plays.update(db, <String, Object?>{
        'id': toId,
        't': title,
        'a': artist,
      }, finder: Finder(filter: Filter.equals('id', fromId)));
    } catch (e) {
      debugPrint('[Cloudio DB] dinləmə qeydləri köçürülmədi: $e');
    }
  }

  Future<List<PlayEvent>> loadPlays() async {
    final db = _db;
    if (db == null) return const [];
    try {
      final snaps = await _plays.find(db);
      final out = <PlayEvent>[];
      for (final snap in snaps) {
        try {
          final m = snap.value;
          out.add(
            PlayEvent(
              ts: m['ts'] as int? ?? 0,
              songId: m['id'] as String? ?? '',
              title: m['t'] as String? ?? '',
              artist: m['a'] as String? ?? '',
              genre: m['g'] as String? ?? '',
              durMs: m['d'] as int? ?? 0,
            ),
          );
        } catch (_) {}
      }
      out.sort((a, b) => a.ts.compareTo(b.ts));
      return out;
    } catch (e) {
      debugPrint('[Cloudio DB] dinləmə tarixçəsi oxunmadı: $e');
      return const [];
    }
  }

  // ---- tema (rejim + vurğu rəngi) ----
  Future<void> saveTheme(int mode, int accent) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('theme').put(db, <String, Object?>{'mode': mode, 'accent': accent});
    } catch (e) {
      debugPrint('[Cloudio DB] tema yazıla bilmədi: $e');
    }
  }

  Future<({int mode, int accent})?> loadTheme() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('theme').get(db);
      if (m == null) return null;
      return (mode: m['mode'] as int? ?? 0, accent: m['accent'] as int? ?? 0);
    } catch (e) {
      debugPrint('[Cloudio DB] tema oxunmadı: $e');
      return null;
    }
  }

  // ---- yerli profil (ad, rəng, yaradılma tarixi) ----
  Future<void> saveProfile({required String name, required int color, required int sinceMs}) async {
    final db = _db;
    if (db == null) return;
    try {
      await _meta.record('profile').put(db, <String, Object?>{
        'name': name,
        'color': color,
        'since': sinceMs,
      });
    } catch (e) {
      debugPrint('[Cloudio DB] profil yazıla bilmədi: $e');
    }
  }

  Future<({String name, int color, int sinceMs})?> loadProfile() async {
    final db = _db;
    if (db == null) return null;
    try {
      final m = await _meta.record('profile').get(db);
      if (m == null) return null;
      return (
        name: m['name'] as String? ?? 'Admin',
        color: m['color'] as int? ?? 0,
        sinceMs: m['since'] as int? ?? 0,
      );
    } catch (e) {
      debugPrint('[Cloudio DB] profil oxunmadı: $e');
      return null;
    }
  }
}
