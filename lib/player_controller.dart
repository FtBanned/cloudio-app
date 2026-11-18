import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

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

/// Əlavə oluna bilən səs faylı uzantıları (seçici hamısını göstərir, burada süzülür).
const kAudioExts = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'];

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

class PlayerController extends ChangeNotifier {
  PlayerController._() {
    player.playerStateStream.listen((_) => notifyListeners());
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    unawaited(_restore()); // əvvəl saxlanmış kitabxananı yüklə
  }

  static final PlayerController instance = PlayerController._();

  final AudioPlayer player = AudioPlayer();
  final List<Song> songs = []; // kitaplık (tüm şarkılar)
  final List<Playlist> playlists = [];
  final Random _rng = Random();

  /// Şu an çalan listenin kopyası: next/previous bunun üstünde döner.
  List<Song> _queue = [];
  int? currentIndex; // _queue içindeki yer
  bool shuffleOn = false;
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
      }
    } catch (e, st) {
      debugPrint('Kitabxana bərpa olunmadı: $e');
      debugPrint('$st');
    }
    loading = false;
    restored = true;
    notifyListeners();
    unawaited(refreshCovers()); // üzlüyü olmayanlar üçün axtarışa davam
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
      audio: withAudio ? s.bytes : null,
    );
  }

  void _savePlaylists() {
    unawaited(CloudioStore.instance.savePlaylists([
      for (final p in playlists)
        SavedPlaylist(p.name, [for (final s in p.songs) s.id]),
    ]));
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

        // "Sanatçı - Şarkı" biçimindeki dosya adı (etiket yoksa yedek)
        var nameArtist = '';
        var nameTitle = fileTitle;
        final dash = fileTitle.indexOf(' - ');
        if (dash > 0) {
          nameArtist = fileTitle.substring(0, dash).trim();
          nameTitle = fileTitle.substring(dash + 3).trim();
        }

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
        );
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

  Future<void> _playIndex(int index) async {
    currentIndex = index;
    final s = _queue[index];
    notifyListeners();

    try {
      // Önceki şarkıyı kesinlikle durdur
      await player.stop();

      if (kIsWeb) {
        final data = s.bytes ?? await _loadAudioFor(s);
        if (data == null) {
          debugPrint('Səs faylı bazada tapılmadı: ${s.title}');
          return;
        }
        final oldUrl = _currentBlobUrl;
        final url = createAudioUrl(data, _mime(s.ext));
        _currentBlobUrl = url;
        await player.setUrl(url);
        if (oldUrl != null) revokeAudioUrl(oldUrl);
      } else {
        final path = s.path;
        if (path == null) {
          debugPrint('Fayl tapılmadı: ${s.title}');
          return;
        }
        await player.setFilePath(path);
      }
      player.play();
    } catch (e, st) {
      // Hata olursa Hata Ayıklama Konsolu'nda görünür
      debugPrint('Şarkı çalınamadı (${s.title}): $e');
      debugPrint('$st');
    }
  }

  void togglePlay() {
    if (player.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  Future<void> seek(Duration position) => player.seek(position);

  void toggleShuffle() {
    shuffleOn = !shuffleOn;
    if (shuffleOn) _buildShuffle(first: currentIndex); // çalan mahnı sıranın əvvəlində qalır
    notifyListeners();
  }

  void cycleRepeat() {
    repeatKind = RepeatKind.values[(repeatKind.index + 1) % 3];
    notifyListeners();
  }

  // ---- qarışıq çalma: hər mahnı bir dəfə çalınır (təsadüfi sıra + geri qayıtmaq üçün tarix) ----
  List<int> _order = []; // _queue indekslərinin təsadüfi sırası
  int _pos = 0; // _order içində hazırkı yer

  /// [first] verilərsə həmin mahnı sıranın əvvəlində olur.
  void _buildShuffle({int? first}) {
    final idx = List<int>.generate(_queue.length, (i) => i)..shuffle(_rng);
    if (first != null && first >= 0 && first < idx.length) {
      idx.remove(first);
      idx.insert(0, first);
    }
    _order = idx;
    _pos = 0;
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
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
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
    shuffleOn = true;
    _queue = List.of(list);
    queueName = _nameFor(context);
    _buildShuffle();
    await _playIndex(_order[0]);
  }

  // ---- yuxu taymeri ----
  Timer? _sleepTimer;
  Timer? _fadeTimer;
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
      unawaited(player.setVolume(1.0));
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
        await player.pause();
        await player.setVolume(1.0);
      } else {
        await player.setVolume(1.0 - step / steps);
      }
    });
  }

  Future<void> _onCompleted() async {
    if (sleepAtSongEnd) {
      sleepAtSongEnd = false;
      await player.pause();
      await player.seek(Duration.zero);
      notifyListeners();
      return;
    }
    if (repeatKind == RepeatKind.one) {
      await player.seek(Duration.zero);
      player.play();
      return;
    }
    final isLast = (_shuffleActive && _order.length == _queue.length)
        ? _pos >= _order.length - 1
        : currentIndex == _queue.length - 1;
    if (isLast && repeatKind == RepeatKind.off) {
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