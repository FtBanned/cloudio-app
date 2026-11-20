import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart' show AudioService, AudioServiceConfig;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import 'app_theme.dart';
import 'audio_handler.dart';
import 'cover_tint.dart' show CoverPalette, coverPalette;
import 'cover_lookup.dart'
    show CoverCandidate, fetchCoverImage, kOnlineCovers, searchCandidates;
import 'lyrics.dart';
import 'player_controller.dart';
import 'queue_page.dart';
import 'settings_page.dart';

part 'ui/cover_background.dart';
part 'ui/library_sort.dart';
part 'ui/app_shell.dart';
part 'ui/common_widgets.dart';
part 'ui/now_playing_page.dart';
part 'ui/home_page.dart';
part 'ui/search_page.dart';
part 'ui/library_page.dart';
part 'ui/collection_page.dart';
part 'ui/song_menus.dart';
part 'ui/lyrics_ui.dart';
part 'ui/edit_song_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kilid ekranı və arxa planda çalma (yalnız telefonda; web-də söndürülüb).
  // Xəta olsa tətbiq yenə də açılır, sadəcə kilid ekranı idarəsi olmur.
  if (!kIsWeb) {
    try {
      // iOS: ses oturumu "playback" olmalı, yoksa uygulama arka plana geçince müzik susar
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await AudioService.init(
        builder: () => CloudioAudioHandler(PlayerController.instance),
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.cloudio.app.audio',
          androidNotificationChannelName: 'Cloudio',
        ),
      );
    } catch (e, st) {
      debugPrint('[Cloudio] AudioService başlamadı: $e');
      debugPrint('$st');
    }
  }
  runApp(const CloudioApp());
}

// Rənglər seçilmiş temadan (app_theme.dart) oxunur: vurğu, fon, kart, yazı.
Color get kGreen => AppTheme.instance.accent;
Color get kBg => AppTheme.instance.bg;
Color get kCard => AppTheme.instance.card;
Color get kText => AppTheme.instance.fg();
Color get kText70 => AppTheme.instance.fg(179);
Color get kText60 => AppTheme.instance.fg(153);
Color get kText54 => AppTheme.instance.fg(138);
Color get kText38 => AppTheme.instance.fg(98);
Color get kText30 => AppTheme.instance.fg(77);
Color get kText24 => AppTheme.instance.fg(61);
Color get kText12 => AppTheme.instance.fg(31);
Color get kText10 => AppTheme.instance.fg(26);

String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Şarkı listesinin toplam süresi: "3 sa 24 dk", "47 dk", "35 sn". Süre bilinmiyorsa ''.
String formatTotal(Iterable<Song> list) {
  var ms = 0;
  for (final s in list) {
    ms += s.duration?.inMilliseconds ?? 0;
  }
  if (ms <= 0) return '';
  final d = Duration(milliseconds: ms);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '$h sa $m dk';
  if (d.inMinutes > 0) return '${d.inMinutes} dk';
  return '${d.inSeconds} sn';
}

/// "12 şarkı • 47 dk"
String countAndTotal(List<Song> list) {
  final t = formatTotal(list);
  return t.isEmpty ? '${list.length} şarkı' : '${list.length} şarkı • $t';
}

/// Kapağın ortalama rengini arka plan için koyulaştırır (Spotify gibi).
Color shadeTint(Color? c, Color fallback) {
  if (c == null) return fallback;
  final h = HSLColor.fromColor(c);
  return h
      .withLightness((h.lightness * 0.55).clamp(0.10, 0.30).toDouble())
      .withSaturation(h.saturation.clamp(0.0, 0.75).toDouble())
      .toColor();
}
