import 'dart:async' show StreamController, StreamSubscription, Timer, unawaited;
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:just_audio/just_audio.dart';

import 'app_theme.dart' show AppTheme;
import 'audio_route_io.dart' if (dart.library.js_interop) 'audio_route_web.dart';
import 'audio_url_stub.dart' if (dart.library.js_interop) 'audio_url_web.dart';
import 'cover_lookup.dart';
import 'cover_tint.dart';
import 'local_files_stub.dart' if (dart.library.io) 'local_files_io.dart';
import 'lyrics.dart';
import 'persistence.dart';
import 'tag_reader.dart';

/// false yapılırsa söz araması asla internete çıkmaz (sadece dosyadaki/.lrc sözler).
/// İnternete sadece şarkı adı, sanatçı ve albüm metni gider (lrclib.net).
/// Web'de CORS yüzünden her aramada istisna fırlıyor; sadece telefonda açık.
const kOnlineLyrics = !kIsWeb;

const kUnknownArtist = 'Bilinmeyen sanatçı';

/// Kapak/isim arama algoritmasının sürümü: artırılınca "bulunamadı" olanlar yeniden aranır.
const kCoverSearchVersion = 2;

/// Əlavə oluna bilən səs faylı uzantıları (seçici hamısını göstərir, burada süzülür).
const kAudioExts = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'];

/// off: qarışıq söndürülüb, normal: tam təsadüfi, smart: ağıllı mix (zövqünə görə çəkili).
enum ShuffleMode { off, normal, smart }

enum LyricsStatus { idle, loading, found, notFound, error }

/// Kapak durumu: idle = henüz aranmadı / ağ hatası, found = bulundu, none = kaynaklarda yok.
enum CoverStatus { idle, found, none }

class Song {
  final String id; // saxlama üçün sabit kimlik: "fayl adı|ölçü"
  int seq; // kitabxanaya əlavə olunma sırası
  String title; // internetten düzeltilebilir (etiketsiz dosyalarda)
  String artist;
  String album;
  Uint8List? cover; // gömülü ya da internetten bulunan kapak (jpeg/png baytları)
  Color? tint; // kapağın ortalama rengi
  CoverStatus coverStatus;
  final String? path; // telefon/masaüstünde fayl yolu (hər açılışda yenidən tapılır)
  final String? file; // telefonda tətbiq qovluğundakı fayl adı (bazada saxlanır)
  Uint8List? bytes; // web'de dosya içeriği (bazadan lazım olanda yüklənir, sonra boşaldılır)
  final String ext;
  bool liked = false; // beğenilenler (yeşil tik)
  Lyrics? lyrics;
  LyricsStatus lyricsStatus;
  Duration? duration; // etiketten hesaplanır ya da ilk çalınınca öğrenilir
  bool durationTried = false; // süre bir kez yoxlandı (tapılmasa da)
  int playCount = 0; // 30 sn dinlenen çalma sayısı
  int lastPlayedMs = 0; // son çalma anı (epoch ms), 0 = hiç çalınmadı
  double? gainDb; // ReplayGain etiketi (dB), yoksa null
  bool gainTried = false; // etiket bir kez arandı
  String genre = ''; // etiketten ya da elle
  int year = 0; // 0 = bilinmiyor
  int trackNo = 0; // albümdeki sıra, 0 = bilinmiyor
  int discNo = 0; // 0 = bilinmiyor
  bool tagsTried = false; // janr/yıl/sıra etiketi bir kez okundu

  Song({
    required this.id,
    this.seq = 0,
    required this.title,
    this.artist = kUnknownArtist,
    this.album = '',
    this.cover,
    this.tint,
    this.path,
    this.file,
    this.bytes,
    required this.ext,
    this.lyrics,
    this.duration,
  })  : lyricsStatus =
            lyrics != null ? LyricsStatus.found : LyricsStatus.idle,
        coverStatus = cover != null ? CoverStatus.found : CoverStatus.idle;
}

class Playlist {
  String name;
  final List<Song> songs = [];
  Playlist(this.name);
}

enum RepeatKind { off, all, one }

class PlayerController extends ChangeNotifier with WidgetsBindingObserver {
  PlayerController._() {
    WidgetsBinding.instance.addObserver(this);
    _bind(player);
    unawaited(_route.start()); // qulaqlıq çıxanda dayan, taxılanda davam et
    unawaited(_restore()); // əvvəl saxlanmış kitabxananı yüklə
  }

  // ---- qulaqlıq çıxanda avto-pauza, taxılanda avto-davam ----
  late final AudioRouteWatcher _route =
      AudioRouteWatcher(onRemoved: _onRouteRemoved, onAdded: _onRouteAdded);
  bool _autoPausedByRoute = false; // qulaqlıq çıxdığı üçün dayanıb
  bool _userPaused = false; // istifadəçi / sleep timer / siyahı sonu dayandırıb
  bool _wasPlaying = false;
  DateTime? _stoppedAt; // çalma ən son nə vaxt dayandı

  /// Aktiv pleyerin vəziyyəti dəyişəndə çağırılır: çalma nə vaxt dayandığını izləyir.
  void _trackPlaying(bool playing) {
    if (playing) {
      _wasPlaying = true;
      _userPaused = false;
      _autoPausedByRoute = false;
    } else if (_wasPlaying) {
      _wasPlaying = false;
      _stoppedAt = DateTime.now();
    }
  }

  void _onRouteRemoved() {
    // iOS qulaqlıq çıxanda pleyeri özü dayandıra bilir, ona görə "az əvvəl dayandı" da sayılır
    final st = _stoppedAt;
    final justStopped = st != null &&
        DateTime.now().difference(st) < const Duration(seconds: 2) &&
        !_userPaused &&
        player.processingState != ProcessingState.completed;
    if (!player.playing && !justStopped) return;
    _autoPausedByRoute = true;
    if (player.playing) {
      _cancelFade();
      unawaited(player.pause());
    }
  }

  Future<void> _onRouteAdded() async {
    if (!_autoPausedByRoute) return;
    _autoPausedByRoute = false;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_userPaused || player.playing || current == null) return;
    play();
  }

  static final PlayerController instance = PlayerController._();

  /// Aktiv pleyer. Crossfade zamanı ikinci pleyerlə yer dəyişir, ona görə final deyil.
  AudioPlayer player = AudioPlayer();
  AudioPlayer? _spare; // crossfade üçün ikinci pleyer (lazım olanda yaradılır)
  final List<Song> songs = []; // kitaplık (tüm şarkılar)
  final List<Playlist> playlists = [];
  final Random _rng = Random();

  /// Şu an çalan listenin kopyası: next/previous bunun üstünde döner.
  List<Song> _queue = [];
  int? currentIndex; // _queue içindeki yer
  ShuffleMode shuffleMode = ShuffleMode.off;
  bool get shuffleOn => shuffleMode != ShuffleMode.off;
  bool get smartShuffle => shuffleMode == ShuffleMode.smart;
  bool loading = false;
  RepeatKind repeatKind = RepeatKind.off;
  String? _currentBlobUrl;

  // ---- saxlama (səhifə yenilənəndə mahnılar, siyahılar, bəyənmələr itməsin) ----
  int _seq = 0;
  Song? _lazySong; // səsi hazırda bazadan yaddaşa yüklənmiş mahnı
  bool restored = false; // saxlanmış kitabxananın yüklənməsi bitdi

  Future<void> _restore() async {
    loading = true;
    notifyListeners();
    try {
      await initLocalFiles();
      await CloudioStore.instance.open();
      final st = await CloudioStore.instance.loadSettings();
      if (st != null) {
        crossfadeSecs = kIsWeb ? 0 : st.crossfade;
        normalizeOn = st.normalize;
        _coverVersion = st.coverVersion;
        speed = st.speed;
        dynamicBg = st.dynamicBg;
        unawaited(player.setSpeed(speed));
      }
      final th = await CloudioStore.instance.loadTheme();
      if (th != null) AppTheme.instance.restore(th.mode, th.accent);
      final pr = await CloudioStore.instance.loadProfile();
      if (pr != null) {
        profileName = pr.name;
        profileColor = pr.color;
        profileSince = DateTime.fromMillisecondsSinceEpoch(
            pr.sinceMs > 0 ? pr.sinceMs : DateTime.now().millisecondsSinceEpoch);
      } else {
        profileSince = DateTime.now(); // ilk açılış: hesab indi yaradılır
        _saveProfile();
      }
      playLog
        ..clear()
        ..addAll(await CloudioStore.instance.loadPlays());
      final lib = await CloudioStore.instance.loadAll();
      if (lib != null) {
        final byId = <String, Song>{};
        for (final r in lib.songs) {
          final cover = r.cover;
          final tint = cover == null ? null : await coverTint(cover);
          final s = Song(
            id: r.id,
            seq: r.seq,
            title: r.title,
            artist: r.artist,
            album: r.album,
            cover: cover,
            tint: tint,
            ext: r.ext,
            lyrics: r.lyrics,
            file: r.file,
            path: audioPathFor(r.file),
          );
          s.liked = r.liked;
          s.playCount = r.playCount;
          s.lastPlayedMs = r.lastPlayedMs;
          s.gainDb = r.gainDb;
          s.gainTried = r.gainTried;
          s.genre = r.genre;
          s.year = r.year;
          s.trackNo = r.trackNo;
          s.discNo = r.discNo;
          s.tagsTried = r.tagsTried;
          final dm = r.durationMs;
          if (dm != null) {
            s.durationTried = true;
            if (dm > 0) s.duration = Duration(milliseconds: dm);
          }
          if (cover == null && r.coverStatus == CoverStatus.none.index) {
            s.coverStatus = CoverStatus.none;
          }
          if (r.lyrics == null && r.lyricsNotFound) {
            s.lyricsStatus = LyricsStatus.notFound;
          }
          songs.add(s);
          byId[s.id] = s;
        }
        for (final p in lib.playlists) {
          final pl = Playlist(p.name);
          for (final id in p.ids) {
            final s = byId[id];
            if (s != null) pl.songs.add(s);
          }
          playlists.add(pl);
        }
        _seq = songs.fold<int>(0, (m, s) => max(m, s.seq));
        // Əl ilə saxlanmış kitaplıq sırası (yeni əlavə olunanlar sona düşür)
        final savedOrder = await CloudioStore.instance.loadLibraryOrder();
        if (savedOrder != null && savedOrder.isNotEmpty) {
          final seen = <Song>{};
          final ordered = <Song>[];
          for (final id in savedOrder) {
            final s = byId[id];
            if (s != null && seen.add(s)) ordered.add(s);
          }
          for (final s in songs) {
            if (seen.add(s)) ordered.add(s);
          }
          songs
            ..clear()
            ..addAll(ordered);
        }
        // Arama algoritması yenilendi: eskiden "bulunamadı" işaretlenenler yeniden denensin
        if (_coverVersion < kCoverSearchVersion) {
          for (final s in songs) {
            if (s.cover == null && s.coverStatus == CoverStatus.none) {
              s.coverStatus = CoverStatus.idle;
              unawaited(_saveSong(s));
            }
          }
          _coverVersion = kCoverSearchVersion;
          _saveSettings();
        }
        await _restorePlayback(byId);
      }
    } catch (e, st) {
      debugPrint('Kitabxana bərpa olunmadı: $e');
      debugPrint('$st');
    }
    loading = false;
    restored = true;
    notifyListeners();
    unawaited(_backfillDurations()); // süresi bilinməyən köhnə mahnılar üçün (bir dəfə)
    if (normalizeOn) unawaited(_backfillGains());
    unawaited(_backfillTags()); // köhnə mahnılar üçün janr/il/trek bir dəfə oxunur
    unawaited(refreshCovers()); // üzlüyü olmayanlar üçün axtarışa davam
  }

  // ---- aktiv pleyerin axınları sabit axınlara yönləndirilir ----
  final _stateCtl = StreamController<void>.broadcast();
  final _durCtl = StreamController<Duration?>.broadcast();
  final _posCtl = StreamController<Duration>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Oynatma vəziyyəti dəyişəndə (kilid ekranı üçün).
  Stream<void> get stateTick => _stateCtl.stream;
  Stream<Duration?> get durationTick => _durCtl.stream;

  /// Hazırkı mövqe ilə başlayır, sonra aktiv pleyerin mövqeyini ötürür.
  Stream<Duration> get positionStream async* {
    yield player.position;
    yield* _posCtl.stream;
  }

  void _bind(AudioPlayer p) {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs
      ..clear()
      ..addAll([
        p.playerStateStream.listen((_) {
          if (!_fading) _trackPlaying(p.playing);
          // pauza: mövqeyi dərhal saxla (mahnı yüklənərkən köhnə mövqe yazılmasın)
          if (!_fading &&
              !p.playing &&
              p.processingState == ProcessingState.ready) {
            _crossTimer?.cancel();
            _crossTimer = null;
            _savePositionNow();
          }
          notifyListeners();
          _stateCtl.add(null);
        }),
        p.playbackEventStream.listen((_) => _stateCtl.add(null),
            onError: (Object e) => debugPrint('Pleyer xətası: $e')),
        p.processingStateStream.listen((state) {
          if (state == ProcessingState.completed) _onCompleted();
        }),
        p.positionStream.listen((pos) {
          _onPosition(pos);
          _posCtl.add(pos);
        }),
        p.durationStream.listen(_durCtl.add),
      ]);
  }

  Future<bool> _saveSong(Song s, {bool withAudio = false}) {
    return CloudioStore.instance.saveSong(
      id: s.id,
      seq: s.seq,
      title: s.title,
      artist: s.artist,
      album: s.album,
      ext: s.ext,
      liked: s.liked,
      coverStatus: s.coverStatus.index,
      cover: s.cover,
      lyrics: s.lyrics,
      lyricsNotFound: s.lyricsStatus == LyricsStatus.notFound,
      file: s.file,
      durationMs: s.duration != null
          ? s.duration!.inMilliseconds
          : (s.durationTried ? -1 : null),
      playCount: s.playCount,
      lastPlayedMs: s.lastPlayedMs,
      gainDb: s.gainDb,
      gainTried: s.gainTried,
      genre: s.genre,
      year: s.year,
      trackNo: s.trackNo,
      discNo: s.discNo,
      tagsTried: s.tagsTried,
      audio: withAudio ? s.bytes : null,
    );
  }

  void _savePlaylists() {
    unawaited(CloudioStore.instance.savePlaylists([
      for (final p in playlists)
        SavedPlaylist(p.name, [for (final s in p.songs) s.id]),
    ]));
  }

  // ---- son çalma vəziyyəti (mahnı, növbə sırası, mövqe) ----
  int _lastPosSave = 0;

  void _saveQueueState() {
    unawaited(CloudioStore.instance.saveQueue(SavedQueue(
      ids: [for (final s in _queue) s.id],
      order: List.of(_order),
      cur: currentIndex,
      pos: _pos,
      shuffle: shuffleOn,
      smart: smartShuffle,
      repeat: repeatKind.index,
      name: queueName,
    )));
  }

  /// Hazırkı mahnının çalma mövqeyini saxlayır. Yeni mahnı hələ yüklənməyibsə
  /// (_markSong null) heç nə yazmır ki, səhv mövqe yazılmasın.
  void _savePositionNow([Duration? pos]) {
    final s = _markSong;
    if (s == null || !identical(s, current)) return;
    _lastPosSave = DateTime.now().millisecondsSinceEpoch;
    unawaited(CloudioStore.instance
        .savePosition(s.id, (pos ?? player.position).inMilliseconds));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _savePositionNow();
  }

  /// Tətbiq açılanda son mahnını, növbəni və mövqeyi pauzada hazırlayır.
  Future<void> _restorePlayback(Map<String, Song> byId) async {
    try {
      final q = await CloudioStore.instance.loadQueue();
      if (q == null) return;
      final c = q.cur;
      if (c == null || c < 0 || c >= q.ids.length) return;
      final curSong = byId[q.ids[c]];
      if (curSong == null) return;
      if (!kIsWeb && curSong.path == null) return; // fayl yoxdur

      final queue = <Song>[
        for (final id in q.ids)
          if (byId[id] != null) byId[id]!,
      ];
      final newCur = queue.indexOf(curSong);
      if (newCur < 0) return;

      _queue = queue;
      queueName = q.name.isEmpty ? 'Tüm Şarkılar' : q.name;
      shuffleMode = !q.shuffle
          ? ShuffleMode.off
          : (q.smart ? ShuffleMode.smart : ShuffleMode.normal);
      repeatKind = RepeatKind.values[q.repeat.clamp(0, 2)];
      if (shuffleOn) {
        final okOrder = queue.length == q.ids.length &&
            q.order.length == queue.length &&
            q.order.toSet().length == queue.length &&
            q.order.every((i) => i >= 0 && i < queue.length) &&
            q.pos >= 0 &&
            q.pos < q.order.length &&
            q.order[q.pos] == newCur;
        if (okOrder) {
          _order = List.of(q.order);
          _pos = q.pos;
        } else {
          _buildShuffle(first: newCur);
        }
      }

      final p = await CloudioStore.instance.loadPosition();
      var start = Duration.zero;
      if (p != null && p.id == curSong.id && p.ms > 0) {
        start = Duration(milliseconds: p.ms);
        final d = curSong.duration;
        if (d != null && start >= d - const Duration(seconds: 1)) {
          start = Duration.zero;
        }
      }
      await _playIndex(newCur, autoPlay: false, startAt: start);
    } catch (e, st) {
      debugPrint('Son çalma vəziyyəti bərpa olunmadı: $e');
      debugPrint('$st');
    }
  }

  // ---- dinləmə statistikası (Son çaldıkların / En çok dinlediklerin) ----
  Song? _markSong; // yüklənib çalmağa başlayan mahnı
  bool _markedRecent = false;
  bool _markedCount = false;

  /// Son çalınanlar (yenidən köhnəyə), en çok 20.
  List<Song> get recentSongs {
    final l = songs.where((s) => s.lastPlayedMs > 0).toList()
      ..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    return l.length > 20 ? l.sublist(0, 20) : l;
  }

  /// En çok dinlenenler (çalma sayısına göre), en çok 10.
  List<Song> get topSongs {
    final l = songs.where((s) => s.playCount > 0).toList()
      ..sort((a, b) {
        final c = b.playCount.compareTo(a.playCount);
        return c != 0 ? c : b.lastPlayedMs.compareTo(a.lastPlayedMs);
      });
    return l.length > 10 ? l.sublist(0, 10) : l;
  }

  void _onPosition(Duration pos) {
    final s = _markSong;
    if (s == null || !player.playing) return;
    if (player.processingState != ProcessingState.ready) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastPosSave >= 3000) _savePositionNow(pos);
    _crossfadeTick(pos);
    if (!_markedRecent && pos >= const Duration(seconds: 5)) {
      _markedRecent = true;
      s.lastPlayedMs = DateTime.now().millisecondsSinceEpoch;
      unawaited(_saveSong(s));
      notifyListeners();
    }
    if (!_markedCount) {
      var need = const Duration(seconds: 30);
      final dur = s.duration ?? player.duration;
      if (dur != null && dur < const Duration(seconds: 60)) need = dur ~/ 2;
      if (pos >= need) {
        _markedCount = true;
        s.playCount++;
        s.lastPlayedMs = DateTime.now().millisecondsSinceEpoch;
        _logPlay(s);
        unawaited(_saveSong(s));
        notifyListeners();
      }
    }
  }

  // ---- süre: köhnə mahnılar üçün arxa planda bir dəfə hesablanır ----
  bool _backfillRunning = false;

  Future<void> _backfillDurations() async {
    if (_backfillRunning) return;
    _backfillRunning = true;
    try {
      final todo = songs.where((s) => !s.durationTried).toList();
      for (final s in todo) {
        if (!songs.contains(s)) continue;
        Uint8List? data;
        try {
          data = kIsWeb
              ? await CloudioStore.instance.loadAudio(s.id)
              : await readAudioBytes(s.path);
        } catch (_) {}
        if (data != null) s.duration ??= readDuration(data, s.ext);
        s.durationTried = true;
        await _saveSong(s);
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 20)); // UI donmasın
      }
    } finally {
      _backfillRunning = false;
    }
  }

  // ---- ses seviyəsi tarazlama (ReplayGain etiketi → səs yüksəkliyi) ----
  bool normalizeOn = false;
  double _baseVolume = 1.0; // hazırkı mahnının tarazlama səsi (0..1)
  bool _gainRunning = false;

  int get gainTaggedCount => songs.where((s) => s.gainDb != null).length;

  /// iOS səsi yalnız azalda bilir (maks. 1.0). Hədəf: etiket dB + 6 (müasir mahnılar üçün
  /// ~ -12 LUFS); +6 dB-dən çox artırma tələb edən sakit mahnılar olduğu kimi qalır.
  double _gainFor(Song s) {
    final g = s.gainDb;
    if (!normalizeOn || g == null) return 1.0;
    final db = min(0.0, g + 6.0);
    return pow(10, db / 20).toDouble().clamp(0.05, 1.0);
  }

  void _applyBaseVolume() {
    final cur = current;
    _baseVolume = cur == null ? 1.0 : _gainFor(cur);
    if (!_fading && _fadeTimerSleep == null) {
      unawaited(player.setVolume(_baseVolume));
    }
  }

  Future<void> setNormalize(bool on) async {
    normalizeOn = on;
    _applyBaseVolume();
    _saveSettings();
    notifyListeners();
    if (on) unawaited(_backfillGains());
  }

  /// Etiketi hələ yoxlanmamış (köhnə) mahnılar üçün fayldan oxuyur (bir dəfə).
  Future<void> _backfillGains() async {
    if (_gainRunning) return;
    _gainRunning = true;
    try {
      for (final s in songs.where((s) => !s.gainTried).toList()) {
        if (!songs.contains(s)) continue;
        Uint8List? data;
        try {
          data = kIsWeb
              ? await CloudioStore.instance.loadAudio(s.id)
              : await readAudioBytes(s.path);
        } catch (_) {}
        if (data != null) s.gainDb = readReplayGain(data, s.ext);
        s.gainTried = true;
        await _saveSong(s);
        if (identical(s, current)) _applyBaseVolume();
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      _gainRunning = false;
    }
  }

  bool _tagsRunning = false;

  /// Bu yeniləmədən əvvəl əlavə olunmuş mahnılar üçün fayldan janr, il, trek və disk nömrəsini
  /// bir dəfə oxuyur (istifadəçinin əl ilə yazdığı ad/sənətçi/albom dəyişmir).
  Future<void> _backfillTags() async {
    if (_tagsRunning) return;
    _tagsRunning = true;
    try {
      var n = 0;
      for (final s in songs.where((s) => !s.tagsTried).toList()) {
        if (!songs.contains(s)) continue;
        Uint8List? data;
        try {
          data = kIsWeb
              ? await CloudioStore.instance.loadAudio(s.id)
              : await readAudioBytes(s.path);
        } catch (_) {}
        if (data != null) {
          final t = readTags(data, s.ext);
          s.genre = t.genre;
          s.year = t.year;
          s.trackNo = t.track;
          s.discNo = t.disc;
          if (!s.gainTried) {
            s.gainDb = readReplayGain(data, s.ext); // eyni oxumada pulsuz
            s.gainTried = true;
          }
          s.tagsTried = true;
          await _saveSong(s);
        } else if (s.path == null && !kIsWeb) {
          s.tagsTried = true; // fayl yoxdur: təkrar yoxlamağa dəyməz
        }
        if (++n % 10 == 0) notifyListeners();
        await Future.delayed(const Duration(milliseconds: 20));
      }
      if (n > 0) notifyListeners();
    } finally {
      _tagsRunning = false;
    }
  }

  int _coverVersion = 0;

  void _saveSettings() => unawaited(CloudioStore.instance.saveSettings(
      crossfade: crossfadeSecs,
      normalize: normalizeOn,
      coverVersion: _coverVersion,
      speed: speed,
      dynamicBg: dynamicBg));

  // ---- crossfade / boşluksuz keçid ----
  // İkinci pleyer sıradakı mahnını əvvəlcədən yükləyir; sonda iki pleyerin səsi
  // bərabər-güc əyrisi ilə dəyişir və rollar yer dəyişir.
  double crossfadeSecs = 0; // 0 = kapalı, 0.25 = boşluksuz, 3..12 saniyə
  bool get crossfadeSupported => !kIsWeb;

  bool _fading = false;
  Timer? _fadeRamp; // səs əyrisi taymeri
  Timer? _crossTimer; // keçidin başlama anını dəqiq tutur
  AudioPlayer? _fadeOld; // səsi azalan köhnə pleyer
  Song? _preSong; // ikinci pleyerdə hazır gözləyən mahnı
  bool _preloading = false;

  // ---- yerli profil ("Admin" hesabı: bu cihazda, giriş tələb etmir) ----
  String profileName = 'Admin';
  int profileColor = 0; // settings_page.dart-dakı kProfileColors indeksi
  DateTime profileSince = DateTime.now();

  void _saveProfile() => unawaited(CloudioStore.instance.saveProfile(
      name: profileName,
      color: profileColor,
      sinceMs: profileSince.millisecondsSinceEpoch));

  void setProfile({required String name, required int color}) {
    final n = name.trim();
    profileName = n.isEmpty ? 'Admin' : n;
    profileColor = color;
    _saveProfile();
    notifyListeners();
  }

  /// Bütün mahnıların cəmi dinləmə sayı.
  int get totalPlays => songs.fold(0, (a, s) => a + s.playCount);

  /// Təxmini dinləmə vaxtı: hər mahnının müddəti x dinləmə sayı.
  Duration get listenedTime {
    var ms = 0;
    for (final s in songs) {
      ms += (s.duration?.inMilliseconds ?? 0) * s.playCount;
    }
    return Duration(milliseconds: ms);
  }

  /// Ən çox dinlənən sənətçi (yoxdursa null) və onun dinləmə sayı.
  (String, int)? get topArtist {
    final m = <String, int>{};
    for (final s in songs) {
      if (s.playCount > 0 && s.artist.trim().isNotEmpty && s.artist != kUnknownArtist) {
        m[s.artist] = (m[s.artist] ?? 0) + s.playCount;
      }
    }
    if (m.isEmpty) return null;
    final e = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (e.key, e.value);
  }

  // ---- Şəxsi statistika ----
  /// Hər 30 san dinləmə üçün bir yazı (köhnədən yeniyə). Köhnə versiyadan gələn
  /// dinləmələrin tarixi yoxdur: onlar yalnız "Hamısı" görünüşündəki cəmlərdə sayılır.
  final List<PlayEvent> playLog = [];

  void _logPlay(Song s) {
    final e = PlayEvent(
      ts: s.lastPlayedMs,
      songId: s.id,
      title: s.title,
      artist: s.artist,
      genre: s.genre,
      durMs: s.duration?.inMilliseconds ?? 0,
    );
    playLog.add(e);
    unawaited(CloudioStore.instance.addPlay(e));
  }

  /// [from] ilə [to] arasındakı (to daxil deyil) dinləmələr.
  List<PlayEvent> playsBetween(DateTime from, [DateTime? to]) {
    final a = from.millisecondsSinceEpoch;
    final b = to?.millisecondsSinceEpoch ?? 9007199254740991; // 2^53-1 (web-də də təhlükəsiz)
    return [
      for (final e in playLog)
        if (e.ts >= a && e.ts < b) e,
    ];
  }

  /// Tarixçəsi olmayan, köhnə versiyadan qalmış dinləmələrin sayı.
  int get untrackedPlays {
    final d = totalPlays - playLog.length;
    return d > 0 ? d : 0;
  }

  // ---- görünüş ----
  bool dynamicBg = true; // Now Playing fonu kapağın rənglərindən qurulsun

  void setDynamicBg(bool v) {
    dynamicBg = v;
    _saveSettings();
    notifyListeners();
  }

  // ---- çalma sürəti ----
  static const speedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  double speed = 1.0;

  /// Çalma sürəti (0.5x–2x). Hər iki pleyerə tətbiq olunur ki, crossfade zamanı da eyni qalsın.
  void setSpeed(double v) {
    speed = v.clamp(0.5, 2.0).toDouble();
    unawaited(player.setSpeed(speed));
    final sp = _spare;
    if (sp != null) unawaited(sp.setSpeed(speed));
    _crossTimer?.cancel(); // keçid vaxtı sürətə görə yenidən hesablansın
    _crossTimer = null;
    _saveSettings();
    notifyListeners();
  }

  void setCrossfade(double secs) {
    crossfadeSecs = kIsWeb ? 0 : secs;
    _crossTimer?.cancel();
    _crossTimer = null;
    _saveSettings();
    notifyListeners();
  }

  /// Avtomatik keçiddə sıradakı mahnının indeksi (yoxdursa null).
  /// Qarışıq sıranın sonu / hamısını təkrarla halı adi keçidə buraxılır.
  int? _peekNextIndex() {
    final cur = currentIndex;
    if (cur == null || _queue.length < 2) return null;
    if (_shuffleActive) {
      if (_order.length != _queue.length) return null;
      return _pos + 1 < _order.length ? _order[_pos + 1] : null;
    }
    if (cur + 1 < _queue.length) return cur + 1;
    return repeatKind == RepeatKind.all ? 0 : null;
  }

  bool get _crossfadeAllowed =>
      crossfadeSecs > 0 &&
      crossfadeSupported &&
      repeatKind != RepeatKind.one &&
      !sleepAtSongEnd &&
      !_fading;

  void _crossfadeTick(Duration pos) {
    if (!_crossfadeAllowed || _crossTimer != null) return;
    final dur = player.duration;
    if (dur == null) return;
    final fadeMs = (crossfadeSecs * 1000).round();
    if (dur.inMilliseconds < fadeMs * 2 + 2000) return; // çox qısa mahnı
    final rem = (dur - pos).inMilliseconds;
    final idx = _peekNextIndex();
    if (idx == null) return;
    final next = _queue[idx];
    if (rem <= fadeMs + 10000 && !identical(_preSong, next)) {
      unawaited(_preload(next));
    }
    // rem mahnı vaxtıdır; sürət 1x deyilsə real gözləmə müddəti rem / speed olur
    if (rem <= fadeMs * speed + 1000 && identical(_preSong, next)) {
      final waitMs = max(0, (rem / speed).round() - fadeMs);
      _crossTimer = Timer(Duration(milliseconds: waitMs), () {
        _crossTimer = null;
        unawaited(_doCrossfade(fadeMs));
      });
    }
  }

  Future<void> _preload(Song s) async {
    final path = s.path;
    if (_preloading || path == null) return;
    _preloading = true;
    try {
      final sp = _spare ??= AudioPlayer();
      await sp.setVolume(0);
      await sp.setSpeed(speed);
      await sp.setFilePath(path);
      _preSong = s;
    } catch (e) {
      _preSong = null;
      debugPrint('Sıradakı mahnı hazırlanmadı (${s.title}): $e');
    }
    _preloading = false;
  }

  Future<void> _doCrossfade(int fadeMs) async {
    if (!_crossfadeAllowed || !player.playing) return;
    final idx = _peekNextIndex();
    final sp = _spare;
    if (idx == null || sp == null) return;
    final next = _queue[idx];
    if (!identical(_preSong, next)) return;

    final old = player;
    final gOld = _baseVolume;
    final gNew = _gainFor(next);
    _fading = true;
    _fadeOld = old;
    _playToken++; // gözləyən əl ilə keçidlər ləğv olsun

    // rollar yer dəyişir: yeni mahnı artıq aktivdir (UI, söz, mövqe ona keçir)
    player = sp;
    _spare = old;
    _preSong = null;
    _bind(player);
    if (_shuffleActive) _pos++;
    currentIndex = idx;
    _baseVolume = gNew;
    _markSong = next;
    _markedRecent = false;
    _markedCount = false;
    _saveQueueState();
    _savePositionNow(Duration.zero);
    notifyListeners();

    unawaited(sp.play());
    final sw = Stopwatch()..start();
    _fadeRamp = Timer.periodic(const Duration(milliseconds: 60), (t) {
      final x = (sw.elapsedMilliseconds / fadeMs).clamp(0.0, 1.0).toDouble();
      unawaited(sp.setVolume(gNew * sin(x * pi / 2)));
      unawaited(old.setVolume(gOld * cos(x * pi / 2)));
      if (x >= 1) {
        t.cancel();
        _fadeRamp = null;
        _fading = false;
        _fadeOld = null;
        unawaited(old.pause());
        unawaited(sp.setVolume(_baseVolume));
      }
    });
  }

  /// Keçidi (və ya gözləyən taymeri) dayandırır: köhnə pleyer susur, yeni pleyer tam səsə qayıdır.
  void _cancelFade() {
    _crossTimer?.cancel();
    _crossTimer = null;
    if (!_fading) return;
    _fadeRamp?.cancel();
    _fadeRamp = null;
    _fading = false;
    final old = _fadeOld;
    _fadeOld = null;
    if (old != null) unawaited(old.pause());
    unawaited(player.setVolume(_baseVolume));
  }

  Song? get current {
    final i = currentIndex;
    return (i == null || i < 0 || i >= _queue.length) ? null : _queue[i];
  }

  bool get isPlaying => player.playing;
  List<Song> get likedSongs => songs.where((s) => s.liked).toList();

  // ---- kapakları internetten bulma (modun "Listeyi yenilə" mantığı) ----
  bool coversRunning = false;
  int coversDone = 0;
  int coversTotal = 0;
  String? coversNote; // son çalıştırmanın sonucu / uyarısı
  bool _coversCancel = false;

  void cancelCovers() => _coversCancel = true;

  /// Kapağı olmayan şarkılar için tek tek (limitlere uyarak) arama yapar.
  /// [retryNone]: daha önce "bulunamadı" işaretlenenleri de tekrar dener (manuel yenile).
  Future<void> refreshCovers({bool retryNone = false}) async {
    if (!kOnlineCovers || coversRunning) return;
    final todo = songs
        .where((s) =>
            s.cover == null &&
            (s.coverStatus == CoverStatus.idle ||
                (retryNone && s.coverStatus == CoverStatus.none)))
        .toList();
    if (todo.isEmpty) {
      coversNote = retryNone ? 'Kapağı eksik şarkı yok' : null;
      notifyListeners();
      return;
    }

    coversRunning = true;
    coversDone = 0;
    coversTotal = todo.length;
    coversNote = null;
    _coversCancel = false;
    notifyListeners();

    var found = 0;
    var errors = 0; // art arda ağ hatası: bağlantı yok demektir, boşuna beklemeyelim
    for (final s in todo) {
      if (_coversCancel) break;
      if (!songs.contains(s)) {
        coversDone++;
        continue;
      }
      try {
        final hit = await findCover(
          title: s.title,
          artist: s.artist == kUnknownArtist ? '' : s.artist,
          album: s.album,
        );
        errors = 0;
        if (hit == null) {
          s.coverStatus = CoverStatus.none;
          unawaited(_saveSong(s));
        } else {
          s.cover = hit.bytes;
          s.tint = await coverTint(hit.bytes);
          s.coverStatus = CoverStatus.found;
          if (s.album.isEmpty) s.album = hit.album;
          if (hit.swapped && hit.title.isNotEmpty && hit.artist.isNotEmpty) {
            s.title = hit.title; // ad ilə sənətçi yer dəyişmişdi: düzəlt
            s.artist = hit.artist;
          } else if (s.artist == kUnknownArtist && hit.artist.isNotEmpty) {
            s.artist = hit.artist; // etiketsiz dosya: doğru sanatçıyı/adı al
            if (hit.title.isNotEmpty) s.title = hit.title;
          }
          found++;
          unawaited(_saveSong(s));
        }
      } catch (e) {
        debugPrint('Kapak aranamadı (${s.title}): $e');
        errors++; // durum idle kalır: sonra tekrar denenebilir
        if (errors >= 3) {
          coversNote = 'Bağlantı kurulamadı, kapak araması durduruldu ($e)';
          break;
        }
      }
      coversDone++;
      notifyListeners(); // kapak geldikçe liste kendiliğinden güncellenir
    }

    coversRunning = false;
    if (coversNote == null) {
      coversNote = _coversCancel
          ? 'Kapak araması durduruldu'
          : '$found/${todo.length} şarkının kapağı bulundu';
    }
    _coversCancel = false;
    notifyListeners();
  }

  // ---- şarkı bilgisini elle düzenleme ----

  /// Başlık, sanatçı, albüm ve (istenirse) kapağı günceller.
  /// [coverChanged] true ise [cover] yeni kapaktır (null = kapağı kaldır).
  Future<void> updateSongInfo(
    Song s, {
    required String title,
    required String artist,
    required String album,
    String? genre,
    int? year,
    int? trackNo,
    Uint8List? cover,
    bool coverChanged = false,
  }) async {
    final t = title.trim();
    if (t.isNotEmpty) s.title = t;
    final a = artist.trim();
    s.artist = a.isEmpty ? kUnknownArtist : a;
    s.album = album.trim();
    if (genre != null) s.genre = genre.trim();
    if (year != null) s.year = year;
    if (trackNo != null) s.trackNo = trackNo;
    if (coverChanged) {
      s.cover = cover;
      s.tint = cover == null ? null : await coverTint(cover);
      // kaldırılan kapak otomatik aramayla geri gelmesin
      s.coverStatus = cover == null ? CoverStatus.none : CoverStatus.found;
    }
    unawaited(_saveSong(s));
    notifyListeners();
  }

  /// Galeri / dosyadan kapak seçtirir. null: vazgeçildi. Okunamayan resim için istisna fırlatır.
  Future<Uint8List?> pickCoverImage() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    final out = await normalizeCover(bytes);
    if (out == null) throw const FormatException('Resim okunamadı');
    return out;
  }

  /// Girilen bilgilerle internette kapak arar (kaydetmez, sadece önizleme için döner).
  Future<Uint8List?> searchCoverOnline(
      {required String title, required String artist, required String album}) async {
    final hit = await findCover(
      title: title.trim(),
      artist: artist.trim() == kUnknownArtist ? '' : artist.trim(),
      album: album.trim(),
    );
    return hit?.bytes;
  }

  // ---- şarkı sözleri ----

  /// .lrc / .txt dosyası seçtirip şarkıya bağlar. true: eklendi, false: okunamadı, null: vazgeçildi.
  Future<bool?> importLyricsFile(Song s) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );
    if (files.isEmpty) return null;
    try {
      final bytes = await files.first.readAsBytes();
      final raw = utf8.decode(bytes, allowMalformed: true);
      final l = Lyrics.parse(raw, source: '.lrc');
      if (l == null) return false;
      s.lyrics = l;
      s.lyricsStatus = LyricsStatus.found;
      unawaited(_saveSong(s));
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Söz dosyası okunamadı: $e');
      return false;
    }
  }

  /// Gömülü söz yoksa internetten arar; sonuç şarkıda saklanır (bir kez aranır).
  Future<void> loadLyricsOnline(Song s, {bool force = false}) async {
    if (!kOnlineLyrics || (s.lyrics != null && !force)) return;
    if (s.lyricsStatus == LyricsStatus.loading) return;
    if (!force &&
        (s.lyricsStatus == LyricsStatus.found ||
            s.lyricsStatus == LyricsStatus.notFound)) {
      return;
    }
    s.lyricsStatus = LyricsStatus.loading;
    notifyListeners();
    try {
      final l = await fetchLyricsOnline(
        title: s.title,
        artist: s.artist == kUnknownArtist ? '' : s.artist,
        album: s.album,
        duration: current == s ? player.duration : null,
      );
      if (l != null) {
        s.lyrics = l;
        s.lyricsStatus = LyricsStatus.found;
      } else {
        // zorla aramada eski söz korunur
        s.lyricsStatus =
            s.lyrics != null ? LyricsStatus.found : LyricsStatus.notFound;
      }
    } catch (e) {
      debugPrint('Söz aranamadı (${s.title}): $e');
      s.lyricsStatus = LyricsStatus.error; // ağ hatası: tekrar denenebilir
    }
    if (s.lyricsStatus != LyricsStatus.error) unawaited(_saveSong(s));
    notifyListeners();
  }

  /// İnternetdə əl ilə seçilmiş sözü mahnıya bağlayır (varsa əvvəlkinin yerinə keçir).
  void setLyrics(Song s, Lyrics l) {
    s.lyrics = l;
    s.lyricsStatus = LyricsStatus.found;
    unawaited(_saveSong(s));
    notifyListeners();
  }

  void clearLyrics(Song s) {
    s.lyrics = null;
    s.lyricsStatus = LyricsStatus.notFound; // kullanıcı kaldırdı: kendiliğinden tekrar aranmasın
    unawaited(_saveSong(s));
    notifyListeners();
  }

  // ---- beğeni / çalma listesi ----
  void toggleLike(Song s) {
    s.liked = !s.liked;
    unawaited(_saveSong(s));
    notifyListeners();
  }

  Playlist createPlaylist(String name) {
    final n = name.trim();
    final p = Playlist(n.isEmpty ? 'Çalma listem #${playlists.length + 1}' : n);
    playlists.add(p);
    _savePlaylists();
    notifyListeners();
    return p;
  }

  void renamePlaylist(Playlist p, String name) {
    final n = name.trim();
    if (n.isNotEmpty) p.name = n;
    _savePlaylists();
    notifyListeners();
  }

  void deletePlaylist(Playlist p) {
    playlists.remove(p);
    _savePlaylists();
    notifyListeners();
  }

  void addToPlaylist(Playlist p, Iterable<Song> add) {
    for (final s in add) {
      if (!p.songs.contains(s)) p.songs.add(s);
    }
    _savePlaylists();
    notifyListeners();
  }

  /// Çalma siyahısında mahnının yerini dəyişir. [newIndex] artıq düzəldilmiş
  /// indeksdir (Flutter-in onReorderItem-i belə verir), əlavə -1 lazım deyil.
  /// Hazırda çalan növbəyə (queue) toxunmur.
  void reorderPlaylist(Playlist p, int oldIndex, int newIndex) {
    final n = p.songs.length;
    if (oldIndex < 0 || oldIndex >= n || n < 2) return;
    final target = newIndex.clamp(0, n - 1);
    if (target == oldIndex) return;
    final s = p.songs.removeAt(oldIndex);
    p.songs.insert(target, s);
    _savePlaylists();
    notifyListeners();
  }

  /// Kitaplıqda (Tüm Şarkılar) mahnının yerini dəyişir. [newIndex] artıq düzəldilmiş
  /// indeksdir. Hazırda çalan növbəyə toxunmur.
  void reorderLibrary(int oldIndex, int newIndex) {
    final n = songs.length;
    if (oldIndex < 0 || oldIndex >= n || n < 2) return;
    final target = newIndex.clamp(0, n - 1);
    if (target == oldIndex) return;
    final s = songs.removeAt(oldIndex);
    songs.insert(target, s);
    unawaited(CloudioStore.instance
        .saveLibraryOrder([for (final x in songs) x.id]));
    notifyListeners();
  }

  void removeFromPlaylist(Playlist p, Song s) {
    p.songs.remove(s);
    _savePlaylists();
    notifyListeners();
  }

  /// Şarkıyı kitaplıktan, listelerden ve çalma sırasından çıkarır.
  Future<void> removeSong(Song s) async {
    final cur = current;
    for (final p in playlists) {
      p.songs.remove(s);
    }
    songs.remove(s);
    _queue.remove(s);
    unawaited(CloudioStore.instance.deleteSong(s.id));
    unawaited(deleteAudioFile(s.file));
    _savePlaylists();
    if (cur == s) {
      currentIndex = null;
      await player.stop();
    } else {
      currentIndex = cur == null ? null : _queue.indexOf(cur);
    }
    if (shuffleOn) _buildShuffle(first: currentIndex);
    _saveQueueState();
    notifyListeners();
  }

  Future<void> addSongs() async {
    // iPhone Safari-də FileType.audio mahnıları solğun göstərirdi, ona görə hamısını
    // göstərib uzantını özümüz yoxlayırıq (aşağıda).
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;

    loading = true;
    notifyListeners();

    for (final f in files) {
      try {
        final lowerName = f.name.toLowerCase();
        if (!kAudioExts.any((e) => lowerName.endsWith('.$e'))) continue; // audio deyil
        final bytes = await f.readAsBytes();
        final id = '${f.name}|${bytes.length}';
        if (songs.any((x) => x.id == id)) continue; // eyni fayl ikinci dəfə əlavə olunmur
        final dot = f.name.lastIndexOf('.');
        final ext = dot > 0 ? f.name.substring(dot + 1).toLowerCase() : '';
        final fileTitle = dot > 0 ? f.name.substring(0, dot) : f.name;

        // "Sanatçı - Şarkı" biçimindeki dosya adı (etiket yoksa yedek); çöp temizlenir
        final parsed = parseFileName(fileTitle);
        final nameArtist = parsed.artist;
        final nameTitle = parsed.title.isEmpty ? fileTitle : parsed.title;

        final seq = ++_seq;
        // Telefonda: müvəqqəti faylı tətbiqin qovluğuna köçür ki, tətbiq bağlanıb açılanda qalsın
        String? localFile;
        String? localPath = kIsWeb ? null : f.path;
        if (!kIsWeb && f.path != null) {
          localFile = await importAudioFile(
              sourcePath: f.path!, fileName: '$seq.$ext');
          if (localFile != null) localPath = audioPathFor(localFile);
        }

        final tags = readTags(bytes, ext);
        final cover = tags.cover;
        final tint = cover == null ? null : await coverTint(cover);
        final dur = readDuration(bytes, ext);
        final gain = readReplayGain(bytes, ext);

        final song = Song(
          id: id,
          seq: seq,
          title: tags.title.isNotEmpty ? tags.title : nameTitle,
          artist: tags.artist.isNotEmpty
              ? tags.artist
              : (nameArtist.isNotEmpty ? nameArtist : kUnknownArtist),
          album: tags.album,
          lyrics: tags.lyrics.isEmpty
              ? null
              : Lyrics.parse(tags.lyrics, source: 'Dosya'),
          cover: cover,
          tint: tint,
          ext: ext,
          path: localPath,
          file: localFile,
          bytes: kIsWeb ? bytes : null,
          duration: dur,
        )
          ..durationTried = true
          ..gainDb = gain
          ..gainTried = true
          ..genre = tags.genre
          ..year = tags.year
          ..trackNo = tags.track
          ..discNo = tags.disc
          ..tagsTried = true;
        songs.add(song);
        final saved = await _saveSong(song, withAudio: true);
        // Baza yazdısa səs faylını yaddaşda saxlamırıq: çalanda bazadan oxunacaq
        if (saved && kIsWeb) song.bytes = null;
        notifyListeners(); // liste şarkı şarkı dolsun
      } catch (e) {
        debugPrint('Dosya okunamadı (${f.name}): $e');
      }
    }

    loading = false;
    notifyListeners();
    unawaited(refreshCovers()); // etiketi olmayan şarkıların kapağını arka planda ara
  }

  /// [context] verilirse sıra o liste olur (çalma listesi, beğenilenler...).
  Future<void> playSong(Song s, {List<Song>? context}) async {
    _queue = List.of(context ?? songs);
    queueName = _nameFor(context);
    var i = _queue.indexOf(s);
    if (i < 0) {
      _queue = [s];
      i = 0;
    }
    if (shuffleOn) _buildShuffle(first: i);
    await _playIndex(i);
  }

  /// Səs faylını bazadan oxuyur; əvvəl oxunmuş mahnının yaddaşını boşaldır.
  Future<Uint8List?> _loadAudioFor(Song s) async {
    final data = await CloudioStore.instance.loadAudio(s.id);
    if (data == null) return null;
    final prev = _lazySong;
    if (prev != null && prev != s) prev.bytes = null;
    _lazySong = s;
    s.bytes = data;
    return data;
  }

  int _playToken = 0; // art arda gelen sonraki/önceki isteklerinde eskisini iptal eder

  Future<void> _playIndex(int index,
      {bool autoPlay = true, Duration? startAt}) async {
    currentIndex = index;
    final s = _queue[index];
    _saveQueueState();
    notifyListeners();

    _cancelFade();
    Duration? loadedDur;
    final token = ++_playToken;
    _markSong = null; // yeni mahnı yüklənənə qədər sayma
    try {
      // iOS: player.stop() ses oturumunu kapatıyor; arka planda/kilit ekranında
      // oturum bir daha açılamıyor ve sonraki şarkı çalmıyordu. Bu yüzden
      // mobilde stop() ÇAĞIRMIYORUZ: setFilePath eski kaynağı kendisi değiştirir.
      if (kIsWeb) await player.stop();

      if (kIsWeb) {
        final data = s.bytes ?? await _loadAudioFor(s);
        if (data == null) {
          debugPrint('Səs faylı bazada tapılmadı: ${s.title}');
          return;
        }
        final oldUrl = _currentBlobUrl;
        final url = createAudioUrl(data, _mime(s.ext));
        _currentBlobUrl = url;
        loadedDur = await player.setUrl(url, initialPosition: startAt);
        if (oldUrl != null) revokeAudioUrl(oldUrl);
      } else {
        final path = s.path;
        if (path == null) {
          debugPrint('Fayl tapılmadı: ${s.title}');
          return;
        }
        loadedDur = await player.setFilePath(path, initialPosition: startAt);
      }
      if (token != _playToken) return; // bu arada başka şarkıya geçildi
      // Süre etiketten bulunamadıysa, yüklenen dosyadan öğren ve sakla
      if (s.duration == null && loadedDur != null && loadedDur > Duration.zero) {
        s.duration = loadedDur;
        s.durationTried = true;
        unawaited(_saveSong(s));
        notifyListeners();
      }
      _markSong = s;
      _baseVolume = _gainFor(s);
      await player.setVolume(_baseVolume);
      final resumed = startAt ?? Duration.zero;
      _markedRecent = resumed >= const Duration(seconds: 5); // davam: təkrar sayılmasın
      _markedCount = resumed >= const Duration(seconds: 30);
      _savePositionNow(resumed);
      if (autoPlay) unawaited(player.play());
    } catch (e, st) {
      // Hata olursa Hata Ayıklama Konsolu'nda görünür
      debugPrint('Şarkı çalınamadı (${s.title}): $e');
      debugPrint('$st');
    }
  }

  void togglePlay() {
    if (player.playing) {
      unawaited(pause());
    } else {
      play();
    }
  }

  void play() => unawaited(player.play());

  Future<void> pause() async {
    _userPaused = true;
    _autoPausedByRoute = false;
    _cancelFade();
    await player.pause();
  }

  Future<void> seek(Duration position) async {
    _cancelFade();
    await player.seek(position);
    _savePositionNow(position);
  }

  void toggleShuffle() =>
      setShuffleMode(shuffleOn ? ShuffleMode.off : ShuffleMode.normal);

  /// Qarışıq rejimini seçir (Spotify kimi: Qarışıq / Ağıllı mix / söndür).
  void setShuffleMode(ShuffleMode m) {
    shuffleMode = m;
    if (shuffleOn) _buildShuffle(first: currentIndex); // çalan mahnı sıranın əvvəlində qalır
    _saveQueueState();
    notifyListeners();
  }

  void cycleRepeat() {
    repeatKind = RepeatKind.values[(repeatKind.index + 1) % 3];
    _saveQueueState();
    notifyListeners();
  }

  // ---- qarışıq çalma: hər mahnı bir dəfə çalınır (təsadüfi sıra + geri qayıtmaq üçün tarix) ----
  List<int> _order = []; // _queue indekslərinin təsadüfi sırası
  int _pos = 0; // _order içində hazırkı yer

  /// [first] verilərsə həmin mahnı sıranın əvvəlində olur.
  void _buildShuffle({int? first}) {
    final idx = smartShuffle
        ? _smartOrder()
        : (List<int>.generate(_queue.length, (i) => i)..shuffle(_rng));
    if (first != null && first >= 0 && first < idx.length) {
      idx.remove(first);
      idx.insert(0, first);
    }
    if (smartShuffle) _spreadArtists(idx);
    _order = idx;
    _pos = 0;
  }

  // ---- Ağıllı mix: hər mahnıya çəki verilir, çəkili təsadüfi sıra qurulur ----
  /// Çəki nə qədər böyükdürsə, mahnı sıranın əvvəlinə o qədər çox düşür.
  /// - çox dinlədiklərin və bəyəndiklərin irəli çəkilir;
  /// - çoxdandır (30+ gün) çalınmayan sevimlilər "yenidən kəşf" üçün irəli çəkilir;
  /// - heç çalınmamışlara kiçik bonus verilir;
  /// - bu gün çalınanlar geri atılır ki, təkrar eşitməyəsən.
  double _smartWeight(Song s, int nowMs) {
    var w = 1.0 + log(1 + s.playCount) * 0.9;
    if (s.liked) w *= 1.5;
    if (s.lastPlayedMs > 0) {
      final days = (nowMs - s.lastPlayedMs) / 86400000;
      if (days < 1) {
        w *= 0.35;
      } else if (days > 30 && s.playCount >= 2) {
        w *= 1.8;
      }
    } else {
      w *= 1.2;
    }
    return w;
  }

  /// Çəkili təsadüfi sıra (Efraimidis–Spirakis): açar = u^(1/w), böyükdən kiçiyə.
  List<int> _smartOrder() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final keys = <int, double>{};
    for (var i = 0; i < _queue.length; i++) {
      final w = _smartWeight(_queue[i], now);
      final u = max(_rng.nextDouble(), 1e-9);
      keys[i] = pow(u, 1 / w).toDouble();
    }
    final idx = List<int>.generate(_queue.length, (i) => i)
      ..sort((a, b) => keys[b]!.compareTo(keys[a]!));
    return idx;
  }

  /// Eyni sənətçinin mahnıları ardıcıl gəlməsin (yaxın olan fərqli sənətçi ilə yer dəyişir).
  void _spreadArtists(List<int> idx) {
    bool known(String a) => a.trim().isNotEmpty && a != kUnknownArtist;
    for (var i = 1; i < idx.length; i++) {
      final a = _queue[idx[i]].artist;
      if (!known(a) || a != _queue[idx[i - 1]].artist) continue;
      final end = min(idx.length, i + 8);
      for (var j = i + 1; j < end; j++) {
        if (_queue[idx[j]].artist != a) {
          final t = idx[i];
          idx[i] = idx[j];
          idx[j] = t;
          break;
        }
      }
    }
  }

  bool get _shuffleActive => shuffleOn && _queue.length > 1;

  // ---- Sıra (queue) ekranı ----
  String queueName = 'Tüm Şarkılar'; // "Çalan: ..." yazısı

  /// Sıradan asılı olmayaraq: eyni mahnılar varsa eyni siyahı sayılır
  /// (sıralanmış siyahıdan çalanda da ad düzgün çıxsın deyə).
  bool _sameList(List<Song> a, List<Song> b) {
    if (a.length != b.length) return false;
    final set = Set<Song>.identity()..addAll(b);
    return a.every(set.contains);
  }

  /// Hansı siyahıdan çalındığını siyahının məzmunundan tapır.
  String _nameFor(List<Song>? ctx) {
    if (ctx == null || _sameList(ctx, songs)) return 'Tüm Şarkılar';
    if (_sameList(ctx, likedSongs)) return 'Beğenilen Şarkılar';
    for (final p in playlists) {
      if (_sameList(ctx, p.songs)) return p.name;
    }
    if (_sameList(ctx, recentSongs)) return 'Son çaldıkların';
    if (_sameList(ctx, topSongs)) return 'En çok dinlediklerin';
    // Albom / sənətçi səhifəsindən çalınıbsa onun adı
    if (ctx.isNotEmpty) {
      final al = ctx.first.album.trim();
      if (al.isNotEmpty && ctx.every((s) => s.album.trim() == al)) return al;
      final ar = ctx.first.artist.trim();
      if (ar.isNotEmpty && ctx.every((s) => s.artist.trim() == ar)) return ar;
    }
    return 'Arama sonuçları';
  }

  bool get _orderValid => _shuffleActive && _order.length == _queue.length;

  /// Çalan mahnıdan sonra gələcək mahnılar (qarışıq açıqdırsa qarışıq sıra ilə).
  List<Song> get upNext {
    final cur = currentIndex;
    if (cur == null || _queue.isEmpty) return const [];
    if (_orderValid) {
      return [for (var k = _pos + 1; k < _order.length; k++) _queue[_order[k]]];
    }
    if (cur + 1 >= _queue.length) return const [];
    return _queue.sublist(cur + 1);
  }

  /// Sıradakı [i]-ci mahnıya keç.
  Future<void> playUpNext(int i) async {
    final cur = currentIndex;
    if (cur == null) return;
    if (_orderValid) {
      final k = _pos + 1 + i;
      if (k >= _order.length) return;
      _pos = k;
      await _playIndex(_order[k]);
    } else {
      final k = cur + 1 + i;
      if (k >= _queue.length) return;
      await _playIndex(k);
    }
  }

  /// Sıradakı mahnının yerini dəyişir (i = sıradakılar içində indeks).
  void reorderUpNext(int oldI, int newI) {
    final cur = currentIndex;
    if (cur == null) return;
    if (_orderValid) {
      final base = _pos + 1;
      if (base + oldI >= _order.length || base + newI >= _order.length) return;
      final v = _order.removeAt(base + oldI);
      _order.insert(base + newI, v);
    } else {
      final base = cur + 1;
      if (base + oldI >= _queue.length || base + newI >= _queue.length) return;
      final v = _queue.removeAt(base + oldI);
      _queue.insert(base + newI, v);
    }
    _saveQueueState();
    notifyListeners();
  }

  /// Mahnını yalnız sıradan çıxarır (kitabxanadan silmir).
  void removeFromUpNext(int i) {
    final cur = currentIndex;
    if (cur == null) return;
    if (_orderValid) {
      final k = _pos + 1 + i;
      if (k >= _order.length) return;
      final qi = _order.removeAt(k);
      _queue.removeAt(qi);
      for (var j = 0; j < _order.length; j++) {
        if (_order[j] > qi) _order[j]--;
      }
      if (cur > qi) currentIndex = cur - 1;
    } else {
      final k = cur + 1 + i;
      if (k >= _queue.length) return;
      _queue.removeAt(k);
    }
    _saveQueueState();
    notifyListeners();
  }

  /// "İleri" mümkündürmü: sıranın / qarışıq sıranın sonunda və təkrar "hamısı" deyilsə
  /// sonrakı mahnı yoxdur (düymə söndürülür, kilid ekranından da gizlənir).
  bool get hasNext {
    if (_queue.isEmpty) return false;
    if (repeatKind == RepeatKind.all) return true;
    final cur = currentIndex;
    if (cur == null) return true;
    if (_shuffleActive) {
      if (_order.length != _queue.length) return true;
      return _pos + 1 < _order.length;
    }
    return cur + 1 < _queue.length;
  }

  Future<void> next() async {
    if (_queue.isEmpty || !hasNext) return;
    if (_shuffleActive) {
      if (_order.length != _queue.length) _buildShuffle(first: currentIndex);
      if (_pos + 1 < _order.length) {
        _pos++;
      } else {
        // hamısı çalındı: yenidən qarışdır (cari mahnı yenə birinci olmasın)
        final last = currentIndex;
        _buildShuffle();
        if (_order.length > 1 && _order.first == last) {
          final t = _order[0];
          _order[0] = _order[_order.length - 1];
          _order[_order.length - 1] = t;
        }
      }
      await _playIndex(_order[_pos]);
    } else {
      await _playIndex(((currentIndex ?? -1) + 1) % _queue.length);
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    // Mahnı 3 saniyədən çox çalıbsa başa sar
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    if (_shuffleActive) {
      if (_pos > 0 && _order.length == _queue.length) {
        _pos--;
        await _playIndex(_order[_pos]);
      } else {
        await player.seek(Duration.zero); // qarışıq sıranın əvvəli: geriyə yer yoxdur
      }
      return;
    }
    final cur = currentIndex ?? 0;
    if (cur <= 0) {
      // ilk mahnıdır: əvvəlki yoxdur, sona keçmir, sadəcə başa sarır
      await player.seek(Duration.zero);
      return;
    }
    await _playIndex(cur - 1);
  }

  /// [context] listesini karışık çalmaya başlar (verilmezse tüm şarkılar).
  Future<void> shuffle({List<Song>? context}) async {
    final list = context ?? songs;
    if (list.isEmpty) return;
    if (!shuffleOn) shuffleMode = ShuffleMode.normal; // Ağıllı mix seçilibsə qalır
    _queue = List.of(list);
    queueName = _nameFor(context);
    _buildShuffle();
    await _playIndex(_order[0]);
  }

  // ---- yuxu taymeri ----
  Timer? _sleepTimer;
  Timer? _fadeTimer;
  Timer? get _fadeTimerSleep => _fadeTimer;
  DateTime? sleepEndsAt; // dəqiqələrlə taymer bitəcək an (yoxdursa null)
  bool sleepAtSongEnd = false; // "mahnı bitəndə dayan"

  bool get sleepActive => sleepEndsAt != null || sleepAtSongEnd;

  void _clearSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepEndsAt = null;
    sleepAtSongEnd = false;
    // səssizləşmə yarımçıq qalıbsa səsi bərpa et
    if (_fadeTimer != null) {
      _fadeTimer!.cancel();
      _fadeTimer = null;
      unawaited(player.setVolume(_baseVolume));
    }
  }

  void setSleepTimer(Duration d) {
    _clearSleep();
    sleepEndsAt = DateTime.now().add(d);
    _sleepTimer = Timer(d, _sleepFire);
    notifyListeners();
  }

  void sleepAfterCurrentSong() {
    _clearSleep();
    sleepAtSongEnd = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _clearSleep();
    notifyListeners();
  }

  /// Vaxt bitdi: səs ~3 saniyəyə azalır, sonra mahnı dayanır, səs 100%-ə qaytarılır.
  void _sleepFire() {
    _sleepTimer = null;
    sleepEndsAt = null;
    notifyListeners();
    if (!player.playing) return;
    const steps = 20; // 20 x 150 ms = 3 saniyə
    var step = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 150), (t) async {
      step++;
      if (step >= steps) {
        t.cancel();
        _fadeTimer = null;
        await pause();
        await player.setVolume(_baseVolume);
      } else {
        await player.setVolume(_baseVolume * (1.0 - step / steps));
      }
    });
  }

  Future<void> _onCompleted() async {
    if (sleepAtSongEnd) {
      sleepAtSongEnd = false;
      _userPaused = true;
      await player.pause();
      await player.seek(Duration.zero);
      notifyListeners();
      return;
    }
    if (repeatKind == RepeatKind.one) {
      _markedRecent = false; // tək mahnı təkrarı: hər dövr ayrıca sayılsın
      _markedCount = false;
      await player.seek(Duration.zero);
      player.play();
      return;
    }
    final isLast = (_shuffleActive && _order.length == _queue.length)
        ? _pos >= _order.length - 1
        : currentIndex == _queue.length - 1;
    if (isLast && repeatKind == RepeatKind.off) {
      _userPaused = true;
      await player.pause();
      await player.seek(Duration.zero);
      return;
    }
    await next();
  }

  String _mime(String ext) {
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'audio/mpeg';
    }
  }
}