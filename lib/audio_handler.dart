import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import 'local_files_stub.dart' if (dart.library.io) 'local_files_io.dart';
import 'player_controller.dart';

/// Kilid ekranı / Control Center / qulaqlıq düymələri ilə PlayerController arasında körpü.
/// Çalma məntiqi (növbə, qarışdır, təkrar) hamısı PlayerController-də qalır:
/// kilid ekranından gələn əmrlər sadəcə ora ötürülür.
class CloudioAudioHandler extends BaseAudioHandler {
  CloudioAudioHandler(this._c) {
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

  void _broadcast() {
    final p = _c.player;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (p.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
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

  void _onController() {
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