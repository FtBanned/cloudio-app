import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:just_audio/just_audio.dart' show ProcessingState;

import 'local_files_stub.dart' if (dart.library.io) 'local_files_io.dart';
import 'player_controller.dart';

/// Kilid ekranı / Control Center / qulaqlıq düymələri ilə PlayerController arasında körpü.
/// Çalma məntiqi (növbə, qarışdır, təkrar) hamısı PlayerController-də qalır:
/// kilid ekranından gələn əmrlər sadəcə ora ötürülür.
class CloudioAudioHandler extends BaseAudioHandler with WidgetsBindingObserver {
  CloudioAudioHandler(this._c) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_listenInterruptions());
    // Controller-in sabit axınları: crossfade zamanı aktiv pleyer dəyişsə də qırılmır
    _c.stateTick.listen((_) => _broadcast());
    _c.durationTick.listen((_) {
      final s = _c.current;
      if (s != null) unawaited(_publishItem(s));
    });
    _c.addListener(_onController);
    _broadcast();
  }

  final PlayerController _c;

  // ---- kilid ekranındakı düymələr ----
  @override
  Future<void> play() async {
    _c.play();
  }

  @override
  Future<void> pause() => _c.pause();

  @override
  Future<void> stop() => _c.pause();

  @override
  Future<void> seek(Duration position) => _c.seek(position);

  @override
  Future<void> skipToNext() => _c.next();

  @override
  Future<void> skipToPrevious() => _c.previous();

  // ---- vəziyyəti sistemə bildir ----
  AudioProcessingState _map(ProcessingState s) => switch (s) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };

  // ---- kontroller kaybolursa kendini toparla ----
  // iOS, bir süre sonra (kesinti, başka uygulamanın sesi, ses oturumu değişimi) Now Playing
  // bilgisini silebilir. Eklenti aynı MediaItem tekrar gelmezse bilgiyi yeniden yazmıyor;
  // bu yüzden şu anlarda mahnı bilgisi ve durum zorla yeniden yayınlanır:
  //  - uygulama ön plana dönünce, - çalma yeniden başlayınca, - ses kesintisi bitince.
  bool _wasPlaying = false;

  void _reassert() {
    final s = _c.current;
    if (s != null) unawaited(_publishItem(s));
    _broadcast();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reassert();
  }

  Future<void> _listenInterruptions() async {
    try {
      final session = await AudioSession.instance;
      session.interruptionEventStream.listen((e) {
        if (!e.begin) _reassert();
      });
    } catch (_) {}
  }

  void _broadcast() {
    final p = _c.player;
    if (p.playing && !_wasPlaying) {
      _wasPlaying = true;
      final s = _c.current;
      if (s != null) unawaited(_publishItem(s)); // çalma başladı: Now Playing'i yenile
    } else if (!p.playing) {
      _wasPlaying = false;
    }
    // Sıranın sonunda "ileri" düyməsi kilid ekranında göstərilmir
    final controls = [
      MediaControl.skipToPrevious,
      if (p.playing) MediaControl.pause else MediaControl.play,
      if (_c.hasNext) MediaControl.skipToNext,
    ];
    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices:
          List<int>.generate(controls.length, (i) => i),
      processingState: _map(p.processingState),
      playing: p.playing,
      updatePosition: p.position,
      bufferedPosition: p.bufferedPosition,
      speed: p.speed,
    ));
  }

  // ---- mahnı məlumatı (ad, sənətçi, albom, kapak) ----
  Song? _song;
  int _coverLen = -1;
  String _title = '';
  String _artist = '';
  String _album = '';

  bool _hadNext = true;

  void _onController() {
    final hn = _c.hasNext;
    if (hn != _hadNext) {
      _hadNext = hn;
      _broadcast(); // "ileri" düyməsi göstərilməli / gizlədilməli
    }
    final s = _c.current;
    if (s == null) {
      if (_song != null) {
        _song = null;
        mediaItem.add(null);
      }
      return;
    }
    final coverLen = s.cover?.length ?? 0;
    if (identical(s, _song) &&
        coverLen == _coverLen &&
        s.title == _title &&
        s.artist == _artist &&
        s.album == _album) {
      return; // dəyişiklik yoxdur
    }
    _song = s;
    _coverLen = coverLen;
    _title = s.title;
    _artist = s.artist;
    _album = s.album;
    unawaited(_publishItem(s));
  }

  Future<void> _publishItem(Song s) async {
    Uri? art;
    final cover = s.cover;
    if (cover != null) {
      art = await writeCoverFile('${s.seq}_${cover.length}', cover);
    }
    if (!identical(_c.current, s)) return; // bu arada başqa mahnıya keçilib
    mediaItem.add(MediaItem(
      id: s.id,
      title: s.title,
      artist: s.artist == kUnknownArtist ? null : s.artist,
      album: s.album.isEmpty ? null : s.album,
      duration: _c.player.duration,
      artUri: art,
    ));
  }
}