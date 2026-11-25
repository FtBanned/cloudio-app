part of '../main.dart';

class CloudioApp extends StatelessWidget {
  const CloudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppTheme.instance,
      builder: (context, _) => MaterialApp(
        title: 'Cloudio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.instance.themeData,
        // "Sırada" kartı bütün ekranların (Now Playing daxil) üstündə göstərilir
        builder: (context, child) =>
            Stack(children: [
          child ?? const SizedBox.shrink(),
          const _UpNextOverlay(),
          const GuidedTourHost(), // animasiyalı büyücü rehberi (hamısının üstündə)
        ]),
        home: const MainShell(),
      ),
    );
  }
}

/// Mahnı bitməzdən az əvvəl yuxarıdan sürüşən kiçik "Sırada" kartı.
/// Toxunanda növbəti mahnıya keçir, ✕ ilə bağlanır, 7 saniyədən sonra özü itir.
class _UpNextOverlay extends StatelessWidget {
  const _UpNextOverlay();

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final song = c.upNextSong;
        final visible = c.upNextVisible && song != null;
        return Positioned(
          top: top + 8,
          left: 12,
          right: 12,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, -1.6),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: song == null
                    ? const SizedBox.shrink()
                    : DarkZone(
                        child: GestureDetector(
                          onTap: () {
                            c.dismissUpNext();
                            c.next();
                          },
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF282828),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: kGreen.withValues(alpha: 0.5)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Cover(size: 44, bytes: song.cover),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'SIRADA',
                                        style: TextStyle(
                                          color: kGreen,
                                          fontSize: 10,
                                          letterSpacing: 1,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20, color: Colors.white54),
                                  onPressed: c.dismissUpNext,
                                ),
                              ],
                            ),
                          ),
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

  @override
  void initState() {
    super.initState();
    // Animasiyalı rehber tabları və "Oluştur" pəncərəsini buradan idarə edir
    TourBridge.selectTab = _tourSelectTab;
    TourBridge.setCreateOpen = _tourSetCreate;
    TourBridge.openSongMenu = _tourOpenSongMenu;
    TourBridge.closeSongMenu = _tourCloseSongMenu;
    // İlk quraşdırmada qarşılama ekranı (yalnız təzə, boş kitabxanada)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(maybeShowOnboarding(context));
    });
  }

  @override
  void dispose() {
    TourBridge.selectTab = null;
    TourBridge.setCreateOpen = null;
    TourBridge.openSongMenu = null;
    TourBridge.closeSongMenu = null;
    super.dispose();
  }

  void _tourSelectTab(int i) {
    if (!mounted) return;
    setState(() {
      _createOpen = false;
      _index = i;
    });
  }

  bool _tourMenuOpen = false;

  /// Rehber "⋯" mahnı menyusunu özü açır (artıq açıqdırsa təkrar açmır).
  void _tourOpenSongMenu(Song song) {
    if (!mounted || _tourMenuOpen) return;
    _tourMenuOpen = true;
    showSongMenu(context, song).whenComplete(() => _tourMenuOpen = false);
  }

  void _tourCloseSongMenu() {
    if (!mounted || !_tourMenuOpen) return;
    _tourMenuOpen = false;
    Navigator.of(context).maybePop();
  }

  void _tourSetCreate(bool open) {
    if (!mounted || _createOpen == open) return;
    if (open) {
      final h = _barKey.currentContext?.size?.height ?? 80;
      setState(() {
        _barH = h;
        _createOpen = true;
      });
    } else {
      setState(() => _createOpen = false);
    }
  }

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
    final name = await askText(
      context,
      title: 'Çalma listesine ad ver',
      initial: 'Çalma listem #${PlayerController.instance.playlists.length + 1}',
    );
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
                KeyedSubtree(key: TourKeys.miniPlayer, child: const MiniPlayer()),
                SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 72,
                    child: Row(
                      children: [
                        _NavItem(
                          tourKey: TourKeys.home,
                          label: 'Ana Sayfa',
                          selected: !_createOpen && _index == 0,
                          icon: const Icon(Icons.home_outlined),
                          selectedIcon: const Icon(Icons.home),
                          onTap: () => _onTap(0),
                        ),
                        _NavItem(
                          tourKey: TourKeys.search,
                          label: 'Arama',
                          selected: !_createOpen && _index == 1,
                          icon: const Icon(Icons.search),
                          onTap: () => _onTap(1),
                        ),
                        _NavItem(
                          tourKey: TourKeys.library,
                          label: 'Kitaplığın',
                          selected: !_createOpen && _index == 2,
                          icon: const _LibraryIcon(filled: false),
                          selectedIcon: const _LibraryIcon(filled: true),
                          onTap: () => _onTap(2),
                        ),
                        _NavItem(
                          tourKey: TourKeys.create,
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
  final GlobalKey? tourKey; // rehberin işıq salması üçün
  const _NavItem({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.selectedIcon,
    this.hideLabel = false,
    this.tourKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? kText : const Color(0xFFB3B3B3);
    return Expanded(
      child: GestureDetector(
        key: tourKey,
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
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
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
      decoration: BoxDecoration(shape: BoxShape.circle, color: open ? kText : Colors.transparent),
      child: AnimatedRotation(
        turns: open ? 0.125 : 0, // 45°: "+" → "×"
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 300),
          tween: ColorTween(end: open ? kBg : const Color(0xFFB3B3B3)),
          builder: (_, c, _) => Icon(Icons.add, size: 30, color: c),
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
              key: TourKeys.createPanel,
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundColor: kText12,
                        child: Icon(Icons.music_note),
                      ),
                      title: const Text(
                        'Çalma Listesi',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Şarkı içeren bir çalma listesi oluştur'),
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
      child: CustomPaint(painter: _LibraryIconPainter(theme.color ?? Colors.white, filled)),
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
    canvas.drawRRect(bar(-3 + i, -8 + i, 6 - 2 * i, 16 - 2 * i), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LibraryIconPainter old) => old.color != color || old.filled != filled;
}
