import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart' show AudioService, AudioServiceConfig;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import 'audio_handler.dart';
import 'cover_lookup.dart'
    show CoverCandidate, fetchCoverImage, kOnlineCovers, searchCandidates;
import 'lyrics.dart';
import 'player_controller.dart';
import 'queue_page.dart';

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

const kGreen = Color(0xFF1DB954);
const kBg = Color(0xFF121212);
const kCard = Color(0xFF2A2A2A);

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

// ================= Sıralama =================
enum SongSort { standard, newest, title, artist }

String songSortLabel(SongSort s) => switch (s) {
      SongSort.standard => 'Varsayılan',
      SongSort.newest => 'Son eklenen',
      SongSort.title => 'Ada göre',
      SongSort.artist => 'Sanatçıya göre',
    };

int _cmpText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// [src] siyahısının sıralanmış KOPYASINI qaytarır (orijinal dəyişmir).
List<Song> sortedSongs(List<Song> src, SongSort sort) {
  final l = List<Song>.of(src);
  switch (sort) {
    case SongSort.standard:
      break; // olduğu kimi
    case SongSort.newest:
      l.sort((a, b) => b.seq.compareTo(a.seq));
    case SongSort.title:
      l.sort((a, b) => _cmpText(a.title, b.title));
    case SongSort.artist:
      l.sort((a, b) {
        final r = _cmpText(a.artist, b.artist);
        return r != 0 ? r : _cmpText(a.title, b.title);
      });
  }
  return l;
}

/// Aşağıdan açılan "Sırala" menyusu. Seçilən variantın indeksini qaytarır (ləğv: null).
Future<int?> showSortSheet(BuildContext context,
    {required List<String> options, required int selected}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Sırala',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          for (var i = 0; i < options.length; i++)
            ListTile(
              title: Text(options[i],
                  style: TextStyle(
                      color: i == selected ? kGreen : null,
                      fontWeight:
                          i == selected ? FontWeight.bold : FontWeight.normal)),
              trailing:
                  i == selected ? const Icon(Icons.check, color: kGreen) : null,
              onTap: () => Navigator.pop(ctx, i),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// "⇅ Varsayılan" şəklində kiçik sıralama çubuğu.
class SortBar extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const SortBar({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert, size: 20),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CloudioApp extends StatelessWidget {
  const CloudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloudio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kGreen),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

// ================= Ana iskelet =================
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _createOpen = false; // "Oluştur" penceresi açık mı
  double _barH = 80; // pencere açılırken ölçülen alt çubuk yüksekliği
  final _barKey = GlobalKey(); // alt çubuğun (mini oynatıcı + menü) yüksekliğini ölçmek için

  final _pages = const [HomePage(), SearchPage(), LibraryPage()];

  void _onTap(int i) {
    if (i == 3) {
      if (_createOpen) {
        setState(() => _createOpen = false);
      } else {
        final h = _barKey.currentContext?.size?.height ?? 80;
        setState(() {
          _barH = h;
          _createOpen = true;
        });
      }
      return;
    }
    setState(() {
      _createOpen = false;
      _index = i;
    });
  }

  Future<void> _createPlaylist() async {
    setState(() => _createOpen = false);
    final name = await askText(context,
        title: 'Çalma listesine ad ver',
        initial:
            'Çalma listem #${PlayerController.instance.playlists.length + 1}');
    if (name == null || !mounted) return;
    final pl = PlayerController.instance.createPlaylist(name);
    openPlaylist(context, pl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // siyahı alttakı şəffaf çubuğun arxasına qədər uzansın
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            _pages[_index],
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _createOpen
                    ? _CreateOverlay(
                        key: const ValueKey('create-open'),
                        bottomOffset: _barH,
                        onClose: () => setState(() => _createOpen = false),
                        onCreatePlaylist: _createPlaylist,
                      )
                    : const SizedBox.shrink(key: ValueKey('create-closed')),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [kBg.withAlpha(120), kBg.withAlpha(235)],
              ),
            ),
            child: Column(
              key: _barKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 72,
                    child: Row(
                      children: [
                        _NavItem(
                          label: 'Ana Sayfa',
                          selected: !_createOpen && _index == 0,
                          icon: const Icon(Icons.home_outlined),
                          selectedIcon: const Icon(Icons.home),
                          onTap: () => _onTap(0),
                        ),
                        _NavItem(
                          label: 'Arama',
                          selected: !_createOpen && _index == 1,
                          icon: const Icon(Icons.search),
                          onTap: () => _onTap(1),
                        ),
                        _NavItem(
                          label: 'Kitaplığın',
                          selected: !_createOpen && _index == 2,
                          icon: const _LibraryIcon(filled: false),
                          selectedIcon: const _LibraryIcon(filled: true),
                          onTap: () => _onTap(2),
                        ),
                        _NavItem(
                          label: 'Oluştur',
                          selected: false,
                          hideLabel: _createOpen,
                          icon: _CreateButton(open: _createOpen),
                          onTap: () => _onTap(3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alt menüdeki tek bir düğme (simge + yazı). Seçiliyken beyaz, değilken gri.
class _NavItem extends StatelessWidget {
  final String label;
  final bool selected;
  final bool hideLabel;
  final Widget icon;
  final Widget? selectedIcon;
  final VoidCallback onTap;
  const _NavItem({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.selectedIcon,
    this.hideLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFFB3B3B3);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(size: 28, color: color),
                  child: selected ? (selectedIcon ?? icon) : icon,
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: hideLabel ? 0 : 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+" simgesi: açılınca dönerek "×" olur ve içi beyaz yuvarlağa dönüşür.
class _CreateButton extends StatelessWidget {
  final bool open;
  const _CreateButton({required this.open});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: open ? Colors.white : Colors.transparent,
      ),
      child: AnimatedRotation(
        turns: open ? 0.125 : 0, // 45°: "+" → "×"
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 300),
          tween: ColorTween(
            end: open ? Colors.black : const Color(0xFFB3B3B3),
          ),
          builder: (_, c, __) => Icon(Icons.add, size: 30, color: c),
        ),
      ),
    );
  }
}

/// Alt menünün üstünde açılan buzlu cam pencere (şimdilik sadece "Çalma Listesi").
class _CreateOverlay extends StatelessWidget {
  final double bottomOffset;
  final VoidCallback onClose;
  final VoidCallback onCreatePlaylist;
  const _CreateOverlay({
    super.key,
    required this.bottomOffset,
    required this.onClose,
    required this.onCreatePlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: ColoredBox(color: Colors.black.withAlpha(40)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomOffset + 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Panel rengi (0-255 arası alpha: büyüdükçe daha opak)
                    color: const Color(0xFF3A3A3A).withAlpha(150),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      leading: const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white12,
                        child: Icon(Icons.music_note),
                      ),
                      title: const Text('Çalma Listesi',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle:
                          const Text('Şarkı içeren bir çalma listesi oluştur'),
                      onTap: onCreatePlaylist,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spotify'ın "Kitaplığın" simgesi: iki ince çubuk + hafif eğik bir dikdörtgen.
class _LibraryIcon extends StatelessWidget {
  final bool filled;
  const _LibraryIcon({required this.filled});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 28;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LibraryIconPainter(theme.color ?? Colors.white, filled),
      ),
    );
  }
}

class _LibraryIconPainter extends CustomPainter {
  final Color color;
  final bool filled;
  _LibraryIconPainter(this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k, k);
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..isAntiAlias = true;
    RRect bar(double x, double y, double w, double h) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(1));
    // inset: çizgi modunda kenar dışarı taşmasın
    final i = filled ? 0.0 : 0.85;
    canvas.drawRRect(bar(3 + i, 4 + i, 2.4 - 2 * i + (filled ? 0 : 0.5), 16 - 2 * i), paint);
    canvas.drawRRect(bar(8 + i, 4 + i, 2.4 - 2 * i + (filled ? 0 : 0.5), 16 - 2 * i), paint);
    canvas.save();
    canvas.translate(17, 12);
    canvas.rotate(-0.2);
    canvas.drawRRect(
      bar(-3 + i, -8 + i, 6 - 2 * i, 16 - 2 * i),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LibraryIconPainter old) =>
      old.color != color || old.filled != filled;
}

// ================= Ortak küçük parçalar =================
class Cover extends StatelessWidget {
  final double size;
  final Uint8List? bytes;
  const Cover({super.key, this.size = 48, this.bytes});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.grey.shade800,
      child: Icon(Icons.music_note, size: size * 0.5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null
            ? placeholder
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song>? queue; // tıklanınca çalacak liste (null = tüm şarkılar)
  final Playlist? playlist; // bir çalma listesinin içindeysek
  const SongTile({super.key, required this.song, this.queue, this.playlist});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListTile(
      selected: c.current == song,
      selectedColor: kGreen,
      leading: Cover(size: 48, bytes: song.cover),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.duration != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(formatDuration(song.duration!),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          if (song.liked)
            const Icon(Icons.check_circle, color: kGreen, size: 20),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () => showSongMenu(context, song, playlist: playlist),
          ),
        ],
      ),
      onTap: () => c.playSong(song, context: queue),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      radius: 18,
      backgroundColor: Colors.deepOrange,
      child: Icon(Icons.person, size: 20, color: Colors.white),
    );
  }
}

class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const FilterPill(this.label,
      {super.key, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kGreen : kCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ================= Mini oynatıcı =================
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  void _openFull(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const NowPlayingPage(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final song = c.current;
        if (song == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => _openFull(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            decoration: BoxDecoration(
              color: shadeTint(song.tint, const Color(0xFF1B3A28))
                  .withAlpha(215),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Cover(size: 44, bytes: song.cover),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(c.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 30),
                      onPressed: c.togglePlay,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                StreamBuilder<Duration>(
                  stream: c.positionStream,
                  builder: (context, snap) {
                    final dur = c.player.duration?.inMilliseconds ?? 0;
                    final pos = snap.data?.inMilliseconds ?? 0;
                    final v =
                        dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0).toDouble();
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 2,
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ================= Tam ekran oynatıcı =================
class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final song = c.current;
        if (song == null) return const Scaffold();

        final top = shadeTint(song.tint, const Color(0xFF3A2E5C));

        return Scaffold(
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, kBg],
                stops: const [0.0, 0.7],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  // İlk ekran oynatıcı; altta söz kartının üst kısmı görünür kalır (Spotify gibi)
                  final firstH =
                      box.maxHeight - 72 < 520 ? 520.0 : box.maxHeight - 72;
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(
                          height: firstH,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'Çalıyor',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_horiz),
                          onPressed: () => showSongMenu(context, song),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: song.cover == null
                              ? Container(
                                  color: Colors.grey.shade800,
                                  child:
                                      const Icon(Icons.music_note, size: 96),
                                )
                              : Image.memory(
                                  song.cover!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 900,
                                  gaplessPlayback: true,
                                ),
                        ),
                      ),
                    ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (song.lyrics != null && song.lyrics!.synced)
                      _CoverLyricLine(
                        key: ValueKey(song.lyrics),
                        lyrics: song.lyrics!,
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                song.album.isEmpty
                                    ? song.artist
                                    : '${song.artist} • ${song.album}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          iconSize: 30,
                          tooltip: song.liked ? 'Beğenmekten vazgeç' : 'Beğen',
                          icon: Icon(
                            song.liked
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: song.liked ? kGreen : Colors.white70,
                          ),
                          onPressed: () => c.toggleLike(song),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const SeekBar(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.shuffle,
                              color: c.shuffleOn ? kGreen : Colors.white),
                          onPressed: c.toggleShuffle,
                        ),
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: c.previous,
                        ),
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            iconSize: 40,
                            color: Colors.black,
                            icon: Icon(
                                c.isPlaying ? Icons.pause : Icons.play_arrow),
                            onPressed: c.togglePlay,
                          ),
                        ),
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_next),
                          onPressed: c.hasNext ? c.next : null,
                        ),
                        IconButton(
                          icon: Icon(
                            c.repeatKind == RepeatKind.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                            color: c.repeatKind == RepeatKind.off
                                ? Colors.white
                                : kGreen,
                          ),
                          onPressed: c.cycleRepeat,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const _SleepTimerButton(),
                        IconButton(
                          tooltip: 'Çalma ayarları',
                          icon: const Icon(Icons.tune),
                          onPressed: () => showPlaybackSettingsSheet(context),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Sıra',
                          icon: const Icon(Icons.queue_music),
                          onPressed: () => openQueue(context),
                        ),
                      ],
                    ),
                  ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: LyricsCard(song: song),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tam ekran pleyerdə yuxu taymeri düyməsi: aktivdirsə yaşıl olur və qalan vaxtı göstərir.
class _SleepTimerButton extends StatelessWidget {
  const _SleepTimerButton();

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (!c.sleepActive) {
          return IconButton(
            tooltip: 'Uyku zamanlayıcısı',
            icon: const Icon(Icons.bedtime_outlined),
            onPressed: () => showSleepSheet(context),
          );
        }
        Widget btn(String text) => TextButton.icon(
              onPressed: () => showSleepSheet(context),
              icon: const Icon(Icons.bedtime, color: kGreen),
              label: Text(text,
                  style: const TextStyle(
                      color: kGreen, fontWeight: FontWeight.bold)),
            );
        final ends = c.sleepEndsAt;
        if (ends == null) return btn('Şarkı bitince');
        // Qalan vaxt hər saniyə yenilənir
        return StreamBuilder<int>(
          stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
          builder: (context, _) =>
              btn(formatDuration(ends.difference(DateTime.now()))),
        );
      },
    );
  }
}

/// Yuxu taymeri variantları.
void showSleepSheet(BuildContext context) {
  final c = PlayerController.instance;
  const options = <(String, int)>[
    ('5 dakika', 5),
    ('10 dakika', 10),
    ('15 dakika', 15),
    ('30 dakika', 30),
    ('45 dakika', 45),
    ('1 saat', 60),
  ];
  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Uyku zamanlayıcısı',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.$1),
                onTap: () {
                  Navigator.pop(ctx);
                  c.setSleepTimer(Duration(minutes: o.$2));
                },
              ),
            ListTile(
              title: const Text('Şarkı bitince'),
              onTap: () {
                Navigator.pop(ctx);
                c.sleepAfterCurrentSong();
              },
            ),
            if (c.sleepActive)
              ListTile(
                leading: const Icon(Icons.close, color: kGreen),
                title: const Text('Zamanlayıcıyı kapat',
                    style: TextStyle(color: kGreen)),
                onTap: () {
                  Navigator.pop(ctx);
                  c.cancelSleepTimer();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Tam ekran oynatıcıda cover-in altındakı cari söz sətri: mahnı getdikcə yuxarı sürüşərək dəyişir.
class _CoverLyricLine extends StatefulWidget {
  final Lyrics lyrics;
  const _CoverLyricLine({super.key, required this.lyrics});

  @override
  State<_CoverLyricLine> createState() => _CoverLyricLineState();
}

class _CoverLyricLineState extends State<_CoverLyricLine> {
  final c = PlayerController.instance;
  StreamSubscription<Duration>? _sub;
  int _idx = -1;

  static const _lookahead = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _idx = widget.lyrics.indexAt(c.player.position + _lookahead);
    _sub = c.positionStream.listen(_onPos);
  }

  void _onPos(Duration pos) {
    final i = widget.lyrics.indexAt(pos + _lookahead);
    if (i == _idx || !mounted) return;
    setState(() => _idx = i);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    var text = '';
    if (_idx >= 0 && _idx < lines.length) {
      text = lines[_idx].text.trim();
      if (text.isEmpty) text = '♪';
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openLyricsPage(context),
      child: SizedBox(
        height: 30,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.5),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Align(
            key: ValueKey<int>(_idx),
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SeekBar extends StatelessWidget {
  const SeekBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return StreamBuilder<Duration>(
      stream: c.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = c.player.duration ?? Duration.zero;
        final maxMs = dur.inMilliseconds;
        final posMs = pos.inMilliseconds.clamp(0, maxMs <= 0 ? 0 : maxMs);

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: posMs.toDouble(),
                min: 0,
                max: maxMs <= 0 ? 1 : maxMs.toDouble(),
                onChanged: (v) => c.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(pos),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white60)),
                  Text('-${formatDuration(dur - pos)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ================= Ana Sayfa =================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // false = "Tümü" (ilk 6 şarkı), true = "Müzik" (bütün şarkılar)
  bool _musicOnly = false;

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final songs = c.songs;
        final recent = _musicOnly ? const <Song>[] : c.recentSongs;
        final top = _musicOnly ? const <Song>[] : c.topSongs;
        final count = _musicOnly
            ? songs.length
            : (songs.length < 6 ? songs.length : 6);

        // Başlıq hissəsi; mahnılar ListView.builder ilə tənbəl (lazy) qurulur
        final header = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const ProfileAvatar(),
                const SizedBox(width: 12),
                FilterPill(
                  'Tümü',
                  selected: !_musicOnly,
                  onTap: () => setState(() => _musicOnly = false),
                ),
                const SizedBox(width: 8),
                FilterPill(
                  'Müzik',
                  selected: _musicOnly,
                  onTap: () => setState(() => _musicOnly = true),
                ),
              ],
            ),
          ),
          if (recent.isNotEmpty)
            _SongShelf(title: 'Son çaldıkların', songs: recent),
          if (top.isNotEmpty)
            _SongShelf(title: 'En çok dinlediklerin', songs: top, showCount: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(_musicOnly ? 'Tüm şarkılar' : 'Dinlemeye başla',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          if (songs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Henüz şarkı yok.\nKitaplığın sekmesinden şarkı ekle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            ),
        ];

        return ListView.builder(
          padding: EdgeInsets.only(
              bottom: 16 + MediaQuery.of(context).padding.bottom),
          itemCount: header.length + count,
          itemBuilder: (context, i) {
            if (i < header.length) return header[i];
            final s = songs[i - header.length];
            return SongTile(key: ValueKey(s.id), song: s);
          },
        );
      },
    );
  }
}

/// Ana sayfadaki yatay şarkı rafı (kapak kartları).
class _SongShelf extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final bool showCount; // true: sanatçı yerine "N kez" yaz
  const _SongShelf(
      {required this.title, required this.songs, this.showCount = false});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 212,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: songs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final s = songs[i];
              final playing = c.current == s;
              return GestureDetector(
                onTap: () => c.playSong(s, context: songs),
                child: SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Cover(size: 140, bytes: s.cover),
                      const SizedBox(height: 8),
                      Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: playing ? kGreen : Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                          showCount
                              ? '${s.playCount} kez çalındı'
                              : s.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white60)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ================= Arama =================
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        final matches = <int>[
          for (var i = 0; i < c.songs.length; i++)
            if (q.isNotEmpty &&
                (c.songs[i].title.toLowerCase().contains(q) ||
                    c.songs[i].artist.toLowerCase().contains(q) ||
                    c.songs[i].album.toLowerCase().contains(q)))
              i,
        ];

        final matchSongs = [for (final i in matches) c.songs[i]];

        // Başlıq və axtarış xanası sabit qalır, nəticələr aşağıda sürüşür
        // (xana siyahının içində olsaydı, aşağı sürüşəndə yazılan mətn itərdi).
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              const Row(
                children: [
                  ProfileAvatar(),
                  SizedBox(width: 12),
                  Text('Ara',
                      style:
                          TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.black),
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  hintText: 'Ne dinlemek istiyorsun?',
                  hintStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search, color: Colors.black),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: q.isEmpty
                    ? SingleChildScrollView(
                        child: GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 2.0,
                          children: const [
                            CategoryTile('Müzik', Color(0xFFE91E8C)),
                            CategoryTile('Podcast\'ler', Color(0xFF00695C)),
                            CategoryTile('Sesli kitaplar', Color(0xFF283593)),
                            CategoryTile('Canlı Etkinlikler', Color(0xFF8E24AA)),
                          ],
                        ),
                      )
                    : matchSongs.isEmpty
                        ? const Center(
                            child: Text('Sonuç bulunamadı',
                                style: TextStyle(color: Colors.white60)),
                          )
                        : ListView.builder(
                            itemCount: matchSongs.length,
                            itemBuilder: (context, i) => SongTile(
                              key: ValueKey(matchSongs[i].id),
                              song: matchSongs[i],
                              queue: matchSongs,
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CategoryTile extends StatelessWidget {
  final String label;
  final Color color;
  const CategoryTile(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.topLeft,
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ================= Kitaplığın =================
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  // Çalma listelərinin sıralanması: 0 = yaradılma sırası, 1 = son yaradılan, 2 = ada görə
  static const _sortLabels = ['Oluşturma sırası', 'Son oluşturulan', 'Ada göre'];
  int _sort = 0;

  List<Playlist> _sortedPlaylists(List<Playlist> src) {
    final l = List<Playlist>.of(src);
    if (_sort == 1) {
      return l.reversed.toList();
    } else if (_sort == 2) {
      l.sort((a, b) => _cmpText(a.name, b.name));
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final liked = c.likedSongs;
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Kitaplığın',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  if (kOnlineCovers)
                    IconButton(
                      icon: Icon(c.coversRunning ? Icons.close : Icons.refresh,
                          size: 26),
                      tooltip: c.coversRunning
                          ? 'Kapak aramasını durdur'
                          : 'Listeyi yenile (eksik kapakları bul)',
                      onPressed: c.coversRunning
                          ? c.cancelCovers
                          : () => c.refreshCovers(retryNone: true),
                    ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 28),
                    tooltip: 'Şarkı ekle',
                    onPressed: c.loading ? null : c.addSongs,
                  ),
                ],
              ),
            ),
            if (c.loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (c.coversRunning)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      minHeight: 2,
                      value: c.coversTotal == 0
                          ? null
                          : c.coversDone / c.coversTotal,
                    ),
                    const SizedBox(height: 4),
                    Text('Kapaklar aranıyor… ${c.coversDone}/${c.coversTotal}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white60)),
                  ],
                ),
              )
            else if (c.coversNote != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(c.coversNote!,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white60)),
              ),
            _CollectionRow(
              leading: const _IconSquare(
                  Icons.favorite, [Color(0xFF4A2BD8), Color(0xFF9DB6E8)]),
              title: 'Beğenilen Şarkılar',
              subtitle: 'Çalma listesi • ${countAndTotal(liked)}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CollectionPage.liked(),
              )),
            ),
            _CollectionRow(
              leading: const _IconSquare(
                  Icons.library_music, [Color(0xFF1B6B3A), kGreen]),
              title: 'Tüm Şarkılar',
              subtitle: 'Kitaplık • ${countAndTotal(c.songs)}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CollectionPage.all(),
              )),
            ),
            if (c.songs.isNotEmpty)
              _CollectionRow(
                leading: const _IconSquare(
                    Icons.person, [Color(0xFF8E24AA), Color(0xFFE91E8C)]),
                title: 'Sanatçılar',
                subtitle:
                    'Kitaplık • ${groupSongs(c.songs, byAlbum: false).length} sanatçı',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const GroupListPage(byAlbum: false),
                )),
              ),
            if (c.songs.any((s) => s.album.trim().isNotEmpty))
              _CollectionRow(
                leading: const _IconSquare(
                    Icons.album, [Color(0xFF00695C), Color(0xFF26A69A)]),
                title: 'Albümler',
                subtitle:
                    'Kitaplık • ${groupSongs(c.songs, byAlbum: true).length} albüm',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const GroupListPage(byAlbum: true),
                )),
              ),
            if (c.playlists.length > 1)
              SortBar(
                label: _sortLabels[_sort],
                onTap: () async {
                  final i = await showSortSheet(context,
                      options: _sortLabels, selected: _sort);
                  if (i != null && mounted) setState(() => _sort = i);
                },
              ),
            for (final p in _sortedPlaylists(c.playlists))
              _CollectionRow(
                leading: MosaicCover(songs: p.songs, size: 56),
                title: p.name,
                subtitle: 'Çalma listesi • ${countAndTotal(p.songs)}',
                onTap: () => openPlaylist(context, p),
              ),
            if (c.songs.isEmpty && !c.loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Henüz şarkı yok.\nSağ üstteki + ile şarkı ekle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CollectionRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _CollectionRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white60, fontSize: 13)),
      onTap: onTap,
    );
  }
}

class _IconSquare extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final double size;
  const _IconSquare(this.icon, this.colors, {this.size = 56});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Icon(icon, size: size * 0.45, color: Colors.white),
      ),
    );
  }
}

/// Liste kapağı: kapaklı 4+ şarkı varsa 2x2 mozaik, yoksa ilk kapak.
class MosaicCover extends StatelessWidget {
  final List<Song> songs;
  final double size;
  const MosaicCover({super.key, required this.songs, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final covers = [
      for (final s in songs)
        if (s.cover != null) s.cover!,
    ];
    if (covers.length < 4) {
      return Cover(size: size, bytes: covers.isEmpty ? null : covers.first);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(children: [
              _tile(covers[0], half),
              _tile(covers[1], half),
            ]),
            Row(children: [
              _tile(covers[2], half),
              _tile(covers[3], half),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _tile(Uint8List b, double s) => SizedBox(
        width: s,
        height: s,
        child: Image.memory(b,
            fit: BoxFit.cover,
            cacheWidth: (s * 3).round(),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade800)),
      );
}

// ================= Liste sayfası =================
void openPlaylist(BuildContext context, Playlist p) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CollectionPage.playlist(p),
  ));
}

enum _CollectionKind { all, liked, playlist, artist, album }

// ---- Sənətçi / albom qrupları ----
class SongGroup {
  final String name;
  final List<Song> songs = [];
  SongGroup(this.name);

  /// Qrupun ilk tapılan üzlüyü (varsa)
  Uint8List? get cover {
    for (final s in songs) {
      if (s.cover != null) return s.cover;
    }
    return null;
  }
}

String _groupName(Song s, bool byAlbum) =>
    (byAlbum ? s.album : s.artist).trim();

/// Mahnıları sənətçiyə (və ya albomə) görə qruplaşdırır; adlar böyük/kiçik hərfə həssas deyil.
/// Albomu boş olan mahnılar albom siyahısına düşmür.
List<SongGroup> groupSongs(List<Song> src, {required bool byAlbum}) {
  final map = <String, SongGroup>{};
  for (final s in src) {
    final name = _groupName(s, byAlbum);
    if (name.isEmpty) continue;
    map.putIfAbsent(name.toLowerCase(), () => SongGroup(name)).songs.add(s);
  }
  final l = map.values.toList()..sort((a, b) => _cmpText(a.name, b.name));
  return l;
}

class CollectionPage extends StatefulWidget {
  final _CollectionKind kind;
  final Playlist? playlistRef;
  final String? groupName; // sənətçi / albom adı

  const CollectionPage.all({super.key})
      : kind = _CollectionKind.all,
        playlistRef = null,
        groupName = null;
  const CollectionPage.liked({super.key})
      : kind = _CollectionKind.liked,
        playlistRef = null,
        groupName = null;
  const CollectionPage.playlist(Playlist p, {super.key})
      : kind = _CollectionKind.playlist,
        playlistRef = p,
        groupName = null;
  const CollectionPage.artist(String name, {super.key})
      : kind = _CollectionKind.artist,
        playlistRef = null,
        groupName = name;
  const CollectionPage.album(String name, {super.key})
      : kind = _CollectionKind.album,
        playlistRef = null,
        groupName = name;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  SongSort _sort = SongSort.standard;
  bool _editing = false; // çalma siyahısında "Düzenle" rejimi (sürüklə-burax)

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final playlistRef = widget.playlistRef;
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final pl = playlistRef;
        // Silinmiş bir liste açık kaldıysa sayfayı kapat
        if (pl != null && !c.playlists.contains(pl)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const Scaffold();
        }

        // Sənətçi/albom: mahnılar silinib qrup boşalıbsa səhifəni bağla
        final gName = widget.groupName;
        List<Song> groupSongsNow = const [];
        if (gName != null) {
          final byAlbum = kind == _CollectionKind.album;
          final key = gName.trim().toLowerCase();
          groupSongsNow = [
            for (final s in c.songs)
              if (_groupName(s, byAlbum).toLowerCase() == key) s,
          ];
          if (groupSongsNow.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).maybePop();
            });
            return const Scaffold();
          }
        }

        final List<Song> base; // sıralanmamış orijinal siyahı
        final String title;
        switch (kind) {
          case _CollectionKind.artist:
          case _CollectionKind.album:
            base = groupSongsNow;
            title = gName!;
          case _CollectionKind.all:
            base = c.songs;
            title = 'Tüm Şarkılar';
          case _CollectionKind.liked:
            base = c.likedSongs;
            title = 'Beğenilen Şarkılar';
          case _CollectionKind.playlist:
            base = pl!.songs;
            title = pl.name;
        }
        // Ekranda göstərilən və çalınan siyahı (seçilmiş sıralama ilə)
        final list = sortedSongs(base, _sort);

        Color? tint;
        for (final s in base) {
          if (s.tint != null) {
            tint = s.tint;
            break;
          }
        }
        final top = shadeTint(tint, const Color(0xFF3A2E5C));
        final playingHere = c.isPlaying && c.current != null && list.contains(c.current);

        // Siyahının başlıq hissəsi; mahnılar ListView.builder ilə tənbəl (lazy) qurulur
        final header = <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Center(
                    child: switch (kind) {
                      _CollectionKind.liked => const _IconSquare(
                          Icons.favorite,
                          [Color(0xFF4A2BD8), Color(0xFF9DB6E8)],
                          size: 200),
                      _ => MosaicCover(songs: base, size: 200),
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(countAndTotal(list),
                        style: const TextStyle(color: Colors.white60)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        if (kind == _CollectionKind.all ||
                            kind == _CollectionKind.playlist)
                          _ActionPill(
                            icon: Icons.add,
                            label: 'Ekle',
                            onTap: () {
                              if (kind == _CollectionKind.all) {
                                if (!c.loading) c.addSongs();
                              } else {
                                showAddSongsSheet(context, pl!);
                              }
                            },
                          ),
                        if (kind == _CollectionKind.playlist) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.more_horiz),
                            onPressed: () => showPlaylistMenu(context, pl!),
                          ),
                        ],
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.shuffle,
                              size: 28,
                              color: c.shuffleOn ? kGreen : Colors.white),
                          onPressed: c.toggleShuffle,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: kGreen,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            iconSize: 32,
                            color: Colors.black,
                            icon: Icon(
                                playingHere ? Icons.pause : Icons.play_arrow),
                            onPressed: list.isEmpty
                                ? null
                                : () {
                                    if (playingHere) {
                                      c.togglePlay();
                                    } else if (c.shuffleOn) {
                                      c.shuffle(context: list);
                                    } else {
                                      c.playSong(list.first, context: list);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (base.length > 1 ||
                      (kind == _CollectionKind.playlist &&
                          (base.isNotEmpty || _editing)))
                    Row(
                      children: [
                        Expanded(
                          child: (_editing || base.length < 2)
                              ? const SizedBox.shrink()
                              : SortBar(
                                  label: songSortLabel(_sort),
                                  onTap: () async {
                                    final i = await showSortSheet(context,
                                        options: [
                                          for (final s in SongSort.values)
                                            songSortLabel(s)
                                        ],
                                        selected: _sort.index);
                                    if (i != null && mounted) {
                                      setState(() => _sort = SongSort.values[i]);
                                    }
                                  },
                                ),
                        ),
                        if (kind == _CollectionKind.playlist ||
                            kind == _CollectionKind.all)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TextButton(
                              onPressed: () => setState(() {
                                _editing = !_editing;
                                // Düzenləmə həqiqi sıra üzərində aparılır
                                if (_editing) _sort = SongSort.standard;
                              }),
                              child: Text(
                                _editing ? 'Bitti' : 'Düzenle',
                                style: TextStyle(
                                  color: _editing ? kGreen : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          switch (kind) {
                            _CollectionKind.liked =>
                              'Henüz beğendiğin şarkı yok.\nŞarkının yanındaki ⊕ ile beğen.',
                            _CollectionKind.all =>
                              'Henüz şarkı yok.\n"Ekle" ile dosya seç.',
                            _CollectionKind.playlist =>
                              'Bu liste boş.\n"Ekle" ile kitaplığından şarkı seç.',
                            _CollectionKind.artist ||
                            _CollectionKind.album =>
                              'Bu bölümde şarkı yok.',
                          },
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                    ),
        ];

        // Düzenle rejimində sürüklənən siyahı: çalma listəsi ya da bütün kitaplıq
        final editSongs = pl?.songs ?? c.songs;

        return Scaffold(
          bottomNavigationBar: const MiniPlayer(),
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, kBg],
                stops: const [0.0, 0.45],
              ),
            ),
            child: SafeArea(
              child: (_editing &&
                      (pl != null || kind == _CollectionKind.all))
                  ? CustomScrollView(
                      slivers: [
                        SliverList(delegate: SliverChildListDelegate(header)),
                        SliverReorderableList(
                          itemCount: editSongs.length,
                          onReorderItem: (oldI, newI) => pl != null
                              ? c.reorderPlaylist(pl, oldI, newI)
                              : c.reorderLibrary(oldI, newI),
                          proxyDecorator: (child, index, animation) => Material(
                            color: kCard,
                            elevation: 6,
                            borderRadius: BorderRadius.circular(8),
                            child: child,
                          ),
                          itemBuilder: (context, i) {
                            final s = editSongs[i];
                            return _EditSongRow(
                              key: ValueKey(s.id),
                              song: s,
                              index: i,
                              onRemove: pl == null
                                  ? null
                                  : () => c.removeFromPlaylist(pl, s),
                            );
                          },
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: header.length + list.length,
                      itemBuilder: (context, i) {
                        if (i < header.length) return header[i];
                        final s = list[i - header.length];
                        return SongTile(
                            key: ValueKey(s.id),
                            song: s,
                            queue: list,
                            playlist: pl);
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// "Düzenle" rejimində bir sətir: sağda çıxar (−) düyməsi və sürükləmə tutacağı (≡).
class _EditSongRow extends StatelessWidget {
  final Song song;
  final int index;
  final VoidCallback? onRemove; // null: kitaplıqda çıxarma düyməsi yok
  const _EditSongRow({
    super.key,
    required this.song,
    required this.index,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Cover(size: 48, bytes: song.cover),
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRemove != null)
              IconButton(
                tooltip: 'Bu listeden çıkar',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: onRemove,
              ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bütün sənətçilərin (byAlbum: false) və ya albomların (byAlbum: true) siyahısı.
class GroupListPage extends StatelessWidget {
  final bool byAlbum;
  const GroupListPage({super.key, required this.byAlbum});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final groups = groupSongs(c.songs, byAlbum: byAlbum);
        return Scaffold(
          bottomNavigationBar: const MiniPlayer(),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text(byAlbum ? 'Albümler' : 'Sanatçılar',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
                Expanded(
                  child: groups.isEmpty
                      ? const Center(
                          child: Text('Henüz kayıt yok',
                              style: TextStyle(color: Colors.white60)),
                        )
                      : ListView.builder(
                          itemCount: groups.length,
                          itemBuilder: (context, i) {
                            final g = groups[i];
                            final art = g.cover;
                            return ListTile(
                              key: ValueKey(g.name.toLowerCase()),
                              leading: byAlbum
                                  ? Cover(size: 56, bytes: art)
                                  : ClipOval(
                                      child: SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: art == null
                                            ? Container(
                                                color: Colors.grey.shade800,
                                                child: const Icon(Icons.person),
                                              )
                                            : Image.memory(art,
                                                fit: BoxFit.cover,
                                                cacheWidth: 168,
                                                gaplessPlayback: true),
                                      ),
                                    ),
                              title: Text(g.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  byAlbum
                                      ? '${g.songs.first.artist} • ${countAndTotal(g.songs)}'
                                      : countAndTotal(g.songs),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 13)),
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(
                                builder: (_) => byAlbum
                                    ? CollectionPage.album(g.name)
                                    : CollectionPage.artist(g.name),
                              )),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionPill(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ================= Menüler ve diyaloglar =================
Future<String?> askText(BuildContext context,
    {required String title, String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kCard,
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Tamam', style: TextStyle(color: kGreen)),
        ),
      ],
    ),
  );
}

ShapeBorder get _sheetShape => const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    );

/// Şarkı "⋯" menüsü.
void showSongMenu(BuildContext context, Song song, {Playlist? playlist}) {
  final c = PlayerController.instance;
  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Cover(size: 48, bytes: song.cover),
            title: Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(song.artist,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              song.liked ? Icons.check_circle : Icons.add_circle_outline,
              color: song.liked ? kGreen : null,
            ),
            title: Text(song.liked
                ? 'Beğenilenlerden kaldır'
                : 'Beğenilenlere ekle'),
            onTap: () {
              Navigator.pop(ctx);
              c.toggleLike(song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Şarkı bilgilerini düzenle'),
            onTap: () {
              Navigator.pop(ctx);
              openEditSong(context, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Çalma listesine ekle'),
            onTap: () {
              Navigator.pop(ctx);
              showPickPlaylistSheet(context, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: Text(song.lyrics == null
                ? 'Şarkı sözü ekle (.lrc / .txt)'
                : 'Şarkı sözünü değiştir (.lrc / .txt)'),
            onTap: () {
              Navigator.pop(ctx);
              pickLyricsFor(context, song);
            },
          ),
          if (kOnlineLyrics)
            ListTile(
              leading: const Icon(Icons.manage_search),
              title: const Text('Şarkı sözünü internette ara'),
              onTap: () {
                Navigator.pop(ctx);
                showLyricsSearch(context, song);
              },
            ),
          if (playlist != null)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Bu listeden çıkar'),
              onTap: () {
                Navigator.pop(ctx);
                c.removeFromPlaylist(playlist, song);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Kitaplıktan sil'),
            onTap: () {
              Navigator.pop(ctx);
              c.removeSong(song);
            },
          ),
        ],
      ),
    ),
  );
}

/// Şarkıyı hangi listeye ekleyeceğini seçtirir (yeni liste de açılabilir).
void showPickPlaylistSheet(BuildContext context, Song song) {
  final c = PlayerController.instance;
  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Çalma listesine ekle',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.white12,
                child: Icon(Icons.add),
              ),
              title: const Text('Yeni çalma listesi'),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await askText(context,
                    title: 'Çalma listesine ad ver',
                    initial: 'Çalma listem #${c.playlists.length + 1}');
                if (name == null) return;
                final p = c.createPlaylist(name);
                c.addToPlaylist(p, [song]);
              },
            ),
            for (final p in c.playlists)
              ListTile(
                leading: MosaicCover(songs: p.songs, size: 44),
                title: Text(p.name),
                subtitle: Text(p.songs.contains(song)
                    ? 'Zaten listede'
                    : '${p.songs.length} şarkı'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.addToPlaylist(p, [song]);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('"${p.name}" listesine eklendi')),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Kitaplıktan birden fazla şarkı seçip listeye ekler.
void showAddSongsSheet(BuildContext context, Playlist p) {
  final c = PlayerController.instance;
  final candidates = [
    for (final s in c.songs)
      if (!p.songs.contains(s)) s,
  ];
  final picked = <Song>{};

  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Şarkı ekle',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (candidates.isNotEmpty)
                      TextButton(
                        onPressed: () => setSt(() {
                          if (picked.length == candidates.length) {
                            picked.clear();
                          } else {
                            picked.addAll(candidates);
                          }
                        }),
                        child: Text(
                          picked.length == candidates.length
                              ? 'Seçimi kaldır'
                              : 'Tümünü seç',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    TextButton(
                      onPressed: picked.isEmpty
                          ? null
                          : () {
                              c.addToPlaylist(p, picked);
                              Navigator.pop(ctx);
                            },
                      child: Text('Ekle (${picked.length})',
                          style: TextStyle(
                              color: picked.isEmpty ? Colors.white30 : kGreen,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Eklenecek şarkı kalmadı.\nÖnce Kitaplığından şarkı yükle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in candidates)
                        CheckboxListTile(
                          activeColor: kGreen,
                          checkColor: Colors.black,
                          secondary: Cover(size: 44, bytes: s.cover),
                          title: Text(s.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.artist,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          value: picked.contains(s),
                          onChanged: (v) => setSt(() {
                            if (v == true) {
                              picked.add(s);
                            } else {
                              picked.remove(s);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Çalma listesi "⋯" menüsü: yeniden adlandır / sil.
void showPlaylistMenu(BuildContext context, Playlist p) {
  final c = PlayerController.instance;
  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Ad ve ayrıntıları düzenle'),
            onTap: () async {
              Navigator.pop(ctx);
              final name =
                  await askText(context, title: 'Yeni ad', initial: p.name);
              if (name != null) c.renamePlaylist(p, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Çalma listesini sil'),
            onTap: () {
              Navigator.pop(ctx);
              c.deletePlaylist(p);
            },
          ),
        ],
      ),
    ),
  );
}


// ================= Şarkı sözleri =================
Color lyricsBg(Color? tint) {
  if (tint == null) return const Color(0xFF6C63B8);
  final h = HSLColor.fromColor(tint);
  return h
      .withLightness(0.34)
      .withSaturation(h.saturation.clamp(0.25, 0.7).toDouble())
      .toColor();
}

/// Serbest metinlə internette söz axtarır, siyahıdan seçilən sözü mahnıya bağlayır.
Future<void> showLyricsSearch(BuildContext context, Song song) async {
  final initial = cleanForSearch(song.artist == kUnknownArtist
      ? song.title
      : '${song.artist} ${song.title}');
  final picked = await showModalBottomSheet<LyricsCandidate>(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    isScrollControlled: true,
    builder: (_) => _LyricsSearchSheet(initial: initial),
  );
  if (picked == null || !context.mounted) return;
  PlayerController.instance.setLyrics(song, picked.lyrics);
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Şarkı sözü eklendi')));
}

class _LyricsSearchSheet extends StatefulWidget {
  final String initial;
  const _LyricsSearchSheet({required this.initial});

  @override
  State<_LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends State<_LyricsSearchSheet> {
  late final TextEditingController _q;
  List<LyricsCandidate> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: widget.initial);
    if (widget.initial.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await searchLyricsCandidates(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Arama yapılamadı, bağlantını kontrol et';
        _loading = false;
      });
    }
  }

  /// Sözün ilk dolu sətri: doğru mahnı olub-olmadığını anlamaq üçün.
  String _firstLine(Lyrics l) {
    for (final line in l.lines) {
      if (line.text.trim().isNotEmpty) return line.text.trim();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h * 0.8,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Şarkı sözü ara',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Bir sonuca dokun: sözü bu şarkıya eklenir. Aranan metin lrclib.net\'e gönderilir.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Sanatçı ve şarkı adı veya bir söz satırı',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kGreen))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.white60)))
                      : (_searched && _results.isEmpty)
                          ? const Center(
                              child: Text('Sonuç yok, aramayı değiştir',
                                  style: TextStyle(color: Colors.white60)))
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (_, i) {
                                final r = _results[i];
                                final info = [
                                  if (r.artist.isNotEmpty) r.artist,
                                  if (r.album.isNotEmpty) r.album,
                                  if (r.duration != null)
                                    formatDuration(r.duration!),
                                  r.lyrics.synced ? 'Senkron' : 'Düz metin',
                                ].join(' • ');
                                final first = _firstLine(r.lyrics);
                                return ListTile(
                                  isThreeLine: first.isNotEmpty,
                                  title: Text(r.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      first.isEmpty ? info : '$info\n$first',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white60)),
                                  onTap: () => Navigator.pop(context, r),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> pickLyricsFor(BuildContext context, Song song) async {
  final ok = await PlayerController.instance.importLyricsFile(song);
  if (ok == null || !context.mounted) return; // vazgeçildi
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ok ? 'Şarkı sözü eklendi' : 'Dosyada söz bulunamadı'),
  ));
}

void openLyricsPage(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const LyricsPage(),
  ));
}

/// Tam ekran oynatıcının altındaki renkli "Şarkı sözleri" kartı.
class LyricsCard extends StatefulWidget {
  final Song song;
  const LyricsCard({super.key, required this.song});

  @override
  State<LyricsCard> createState() => _LyricsCardState();
}

class _LyricsCardState extends State<LyricsCard> {
  @override
  void initState() {
    super.initState();
    _kick();
  }

  @override
  void didUpdateWidget(LyricsCard old) {
    super.didUpdateWidget(old);
    if (old.song != widget.song) _kick();
  }

  // Gömülü söz yoksa internetten ara (build sırasında notify etmemek için kare sonrası)
  void _kick() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PlayerController.instance.loadLyricsOnline(widget.song);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      height: 380,
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
      decoration: BoxDecoration(
        color: lyricsBg(widget.song.tint),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => openLyricsPage(context),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Şarkı sözleri',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => showLyricsMenu(context, widget.song),
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_full, size: 20),
                  tooltip: 'Tam ekran',
                  onPressed: () => openLyricsPage(context),
                ),
              ],
            ),
          ),
          Expanded(child: LyricsView(song: widget.song, big: false)),
        ],
      ),
    );
  }
}

void showLyricsMenu(BuildContext context, Song song) {
  final c = PlayerController.instance;
  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Söz dosyası ekle (.lrc / .txt)'),
            onTap: () {
              Navigator.pop(ctx);
              pickLyricsFor(context, song);
            },
          ),
          if (kOnlineLyrics)
            ListTile(
              leading: const Icon(Icons.travel_explore),
              title: const Text('İnternetten ara'),
              subtitle: const Text('Şarkı adı ve sanatçı lrclib.net\'e gönderilir'),
              onTap: () {
                Navigator.pop(ctx);
                c.loadLyricsOnline(song, force: true);
              },
            ),
          if (kOnlineLyrics)
            ListTile(
              leading: const Icon(Icons.manage_search),
              title: const Text('Elle ara ve seç'),
              subtitle: const Text('Sonuç listesinden doğru sözü sen seç'),
              onTap: () {
                Navigator.pop(ctx);
                showLyricsSearch(context, song);
              },
            ),
          if (song.lyrics != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Sözleri kaldır'),
              onTap: () {
                Navigator.pop(ctx);
                c.clearLyrics(song);
              },
            ),
        ],
      ),
    ),
  );
}

/// Sözün kendisi: zamanlıysa çalan satırı vurgular ve kaydırır, değilse düz metin gösterir.
class LyricsView extends StatelessWidget {
  final Song song;
  final bool big;
  const LyricsView({super.key, required this.song, required this.big});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final l = song.lyrics;
        if (l == null) return _LyricsEmpty(song: song);
        if (l.synced) return _SyncedLyrics(key: ValueKey(l), lyrics: l, big: big);
        return SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12, bottom: 32, right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in l.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    line.text.isEmpty ? ' ' : line.text,
                    style: TextStyle(
                      fontSize: big ? 22 : 18,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LyricsEmpty extends StatelessWidget {
  final Song song;
  const _LyricsEmpty({required this.song});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    if (song.lyricsStatus == LyricsStatus.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(height: 12),
            Text('Sözler aranıyor…'),
          ],
        ),
      );
    }
    final error = song.lyricsStatus == LyricsStatus.error;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error
                ? 'Sözler yüklenemedi.\nBağlantını kontrol edip tekrar dene.'
                : 'Bu şarkı için söz bulunamadı.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              if (kOnlineLyrics)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => c.loadLyricsOnline(song, force: true),
                  child: Text(error ? 'Tekrar dene' : 'İnternetten ara'),
                ),
              if (kOnlineLyrics)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => showLyricsSearch(context, song),
                  child: const Text('Elle ara'),
                ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => pickLyricsFor(context, song),
                child: const Text('.lrc dosyası ekle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncedLyrics extends StatefulWidget {
  final Lyrics lyrics;
  final bool big;
  const _SyncedLyrics({super.key, required this.lyrics, required this.big});

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  final c = PlayerController.instance;
  late final List<GlobalKey> _keys;
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Duration>? _sub;
  int _idx = -1;

  // Satır, zamanından biraz önce vurgulansın (gözün okuması için)
  static const _lookahead = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
    _idx = widget.lyrics.indexAt(c.player.position + _lookahead);
    _sub = c.positionStream.listen(_onPos);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  void _onPos(Duration pos) {
    final i = widget.lyrics.indexAt(pos + _lookahead);
    if (i == _idx || !mounted) return;
    setState(() => _idx = i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  void _reveal({bool jump = false}) {
    if (!mounted || _idx < 0 || _idx >= _keys.length) return;
    final ctx = _keys[_idx].currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached) return;
    // Scrollable.ensureVisible üst sayfayı da kaydırırdı; sadece kendi listemizi kaydırıyoruz
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return;
    final target = viewport
        .getOffsetToReveal(ro, widget.big ? 0.4 : 0.3)
        .offset
        .clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent)
        .toDouble();
    if (jump) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    return SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.only(top: 16, bottom: widget.big ? 200 : 140, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            GestureDetector(
              key: _keys[i],
              behavior: HitTestBehavior.opaque,
              onTap: () => c.seek(lines[i].time!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: widget.big ? 28 : 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: i == _idx
                        ? Colors.white
                        : (i < _idx ? Colors.white38 : Colors.white54),
                  ),
                  child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tam ekran söz sayfası: renkli arka plan, büyük yazı, altta ilerleme çubuğu ve kontroller.
class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final song = c.current;
        if (song == null) return const Scaffold();
        return Scaffold(
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            color: lyricsBg(song.tint),
            child: SafeArea(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white70)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () => showLyricsMenu(context, song),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: LyricsView(song: song, big: true),
                    ),
                  ),
                  if (song.lyrics != null)
                    Text('Sözler: ${song.lyrics!.source}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white60)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: SeekBar(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: c.previous,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: IconButton(
                          iconSize: 36,
                          color: Colors.black,
                          icon: Icon(
                              c.isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: c.togglePlay,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.skip_next),
                        onPressed: c.hasNext ? c.next : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ================= Şarkı bilgisini düzenleme =================
void openEditSong(BuildContext context, Song song) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EditSongPage(song: song),
  ));
}

class EditSongPage extends StatefulWidget {
  final Song song;
  const EditSongPage({super.key, required this.song});

  @override
  State<EditSongPage> createState() => _EditSongPageState();
}

class _EditSongPageState extends State<EditSongPage> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  Uint8List? _cover;
  bool _coverChanged = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.song;
    _title = TextEditingController(text: s.title);
    _artist = TextEditingController(
        text: s.artist == kUnknownArtist ? '' : s.artist);
    _album = TextEditingController(text: s.album);
    _cover = s.cover;
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickCover() async {
    try {
      final b = await PlayerController.instance.pickCoverImage();
      if (b == null || !mounted) return;
      setState(() {
        _cover = b;
        _coverChanged = true;
      });
    } catch (_) {
      _toast('Resim okunamadı');
    }
  }

  /// İnternette serbest aramayla sonuç listesi açar; seçilen sonucun adı, sanatçısı,
  /// albümü ve kapağı alanlara doldurulur (Kaydet'e basana kadar değişmez).
  Future<void> _openSearch() async {
    final q = '${_artist.text} ${_title.text}'.trim();
    final picked = await showModalBottomSheet<CoverCandidate>(
      context: context,
      backgroundColor: kCard,
      shape: _sheetShape,
      isScrollControlled: true,
      builder: (_) => _CandidateSheet(initial: q),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    final img = await fetchCoverImage(picked.artUrl);
    if (!mounted) return;
    setState(() {
      _title.text = picked.title;
      _artist.text = picked.artist;
      _album.text = picked.album;
      if (img != null) {
        _cover = img;
        _coverChanged = true;
      }
      _busy = false;
    });
    if (img == null) _toast('Kapak indirilemedi, bilgiler dolduruldu');
  }

  Future<void> _save() async {
    await PlayerController.instance.updateSongInfo(
      widget.song,
      title: _title.text,
      artist: _artist.text,
      album: _album.text,
      cover: _cover,
      coverChanged: _coverChanged,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Şarkı bilgilerini düzenle'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: const Text('Kaydet',
                style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _pickCover,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Cover(size: 180, bytes: _cover),
                  if (_busy)
                    const CircularProgressIndicator(color: kGreen),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickCover,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Resim seç'),
              ),
              if (kOnlineCovers)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('İnternette ara'),
                ),
              if (_cover != null)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _cover = null;
                            _coverChanged = true;
                          }),
                  icon: const Icon(Icons.hide_image_outlined),
                  label: const Text('Kapağı kaldır'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Başlık'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _artist,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Sanatçı'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _album,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Albüm'),
          ),
        ],
      ),
    );
  }
}


// ================= Çalma ayarları: crossfade + ses seviyesi dengeleme =================
String crossfadeLabel(double v) {
  if (v <= 0) return 'Kapalı';
  if (v < 1) return 'Boşluksuz geçiş';
  return '${v.round()} saniye';
}

void showPlaybackSettingsSheet(BuildContext context) {
  final c = PlayerController.instance;
  const options = <double>[0, 0.25, 3, 5, 8, 12];
  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Çalma ayarları',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (c.crossfadeSupported) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('Şarkılar arası geçiş',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w600)),
                ),
                for (final o in options)
                  ListTile(
                    dense: true,
                    title: Text(crossfadeLabel(o)),
                    trailing: c.crossfadeSecs == o
                        ? const Icon(Icons.check, color: kGreen)
                        : null,
                    onTap: () => c.setCrossfade(o),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                      'Sıradaki şarkı otomatik geçişte önceden hazırlanır. '
                      'Tek şarkı tekrarında ve uyku zamanlayıcısı "şarkı bitince" iken uygulanmaz.',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
                const Divider(height: 1),
              ],
              SwitchListTile(
                activeThumbColor: kGreen,
                title: const Text('Ses seviyesini dengele'),
                subtitle: Text(
                    'Şarkılar arası ses farkını azaltır (ReplayGain etiketine göre). '
                    '${c.gainTaggedCount}/${c.songs.length} şarkıda etiket var.',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                value: c.normalizeOn,
                onChanged: c.setNormalize,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}


/// "İnternette ara" penceresi: serbest metinle arar, sonuç listesinden seçtirir.
class _CandidateSheet extends StatefulWidget {
  final String initial;
  const _CandidateSheet({required this.initial});

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  late final TextEditingController _q;
  List<CoverCandidate> _results = const [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: widget.initial);
    if (widget.initial.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await searchCandidates(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Arama yapılamadı, bağlantını kontrol et';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h * 0.8,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('İnternette ara',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Bir sonuca dokun: ad, sanatçı, albüm ve kapak doldurulur.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Sanatçı ve şarkı adı',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kGreen))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.white60)))
                      : (_searched && _results.isEmpty)
                          ? const Center(
                              child: Text('Sonuç yok, aramayı değiştir',
                                  style: TextStyle(color: Colors.white60)))
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (_, i) {
                                final r = _results[i];
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      r.thumbUrl,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 48,
                                        height: 48,
                                        color: Colors.grey.shade800,
                                        child: const Icon(Icons.music_note),
                                      ),
                                    ),
                                  ),
                                  title: Text(r.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      r.album.isEmpty
                                          ? r.artist
                                          : '${r.artist} • ${r.album}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white60)),
                                  onTap: () => Navigator.pop(context, r),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
