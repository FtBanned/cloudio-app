part of '../main.dart';

// ================= Mini oynatıcı =================
/// Mini pleyer kapaqdan rənglənir, ona görə seçilmiş temadan asılı olmayaraq tünd qalır.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) => const DarkZone(child: _MiniPlayerBody());
}

class _MiniPlayerBody extends StatelessWidget {
  const _MiniPlayerBody();

  void _openFull(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const DarkZone(child: NowPlayingPage()),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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
                    color: shadeTint(song.tint, const Color(0xFF1B3A28)).withAlpha(215),
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
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(c.isPlaying ? Icons.pause : Icons.play_arrow, size: 30),
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
                          final v = dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0).toDouble();
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
          body: CoverBackground(
            cover: song.cover,
            fallback: top,
            rich: c.dynamicBg,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  // İlk ekran oynatıcı; altta söz kartının üst kısmı görünür kalır (Spotify gibi)
                  final firstH = box.maxHeight - 72 < 520 ? 520.0 : box.maxHeight - 72;
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
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            boxShadow: [
                                              BoxShadow(
                                                color: (song.tint ?? Colors.black).withValues(
                                                  alpha: 0.55,
                                                ),
                                                blurRadius: 40,
                                                spreadRadius: -4,
                                                offset: const Offset(0, 18),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: song.cover == null
                                                ? Container(
                                                    color: Colors.grey.shade800,
                                                    child: const Icon(Icons.music_note, size: 96),
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
                                ),
                                const SizedBox(height: 12),
                                if (song.lyrics != null && song.lyrics!.synced)
                                  _CoverLyricLine(key: ValueKey(song.lyrics), lyrics: song.lyrics!),
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
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            song.album.isEmpty
                                                ? song.artist
                                                : '${song.artist} • ${song.album}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.white60,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      iconSize: 30,
                                      tooltip: song.liked ? 'Beğenmekten vazgeç' : 'Beğen',
                                      icon: Icon(
                                        song.liked ? Icons.check_circle : Icons.add_circle_outline,
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
                                      icon: Icon(
                                        shuffleIconFor(c),
                                        color: c.shuffleOn ? kGreen : Colors.white,
                                      ),
                                      onPressed: () => showShuffleSheet(context),
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
                                        icon: Icon(c.isPlaying ? Icons.pause : Icons.play_arrow),
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
                                    const _BoosterButton(),
                                    IconButton(
                                      tooltip: 'Çalma ayarları',
                                      icon: const Icon(Icons.tune),
                                      onPressed: () => openSettings(context),
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
          icon: Icon(Icons.bedtime, color: kGreen),
          label: Text(
            text,
            style: TextStyle(color: kGreen, fontWeight: FontWeight.bold),
          ),
        );
        final ends = c.sleepEndsAt;
        if (ends == null) return btn('Şarkı bitince');
        // Qalan vaxt hər saniyə yenilənir
        return StreamBuilder<int>(
          stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
          builder: (context, _) => btn(formatDuration(ends.difference(DateTime.now()))),
        );
      },
    );
  }
}

IconData shuffleIconFor(PlayerController c) => c.smartShuffle ? Icons.auto_awesome : Icons.shuffle;

/// Qarışıq çalma seçimi: Qarışıq / Ağıllı mix (seçilmiş olana yenidən toxunmaq söndürür).
void showShuffleSheet(BuildContext context) {
  final c = PlayerController.instance;
  Widget option(BuildContext ctx, ShuffleMode m, IconData icon, String title, String sub) {
    final on = c.shuffleMode == m;
    return ListTile(
      leading: Icon(icon, color: on ? kGreen : kText70),
      title: Text(
        title,
        style: TextStyle(color: on ? kGreen : kText, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(sub, style: TextStyle(color: kText54, fontSize: 12)),
      trailing: on ? Icon(Icons.check, color: kGreen) : null,
      onTap: () {
        Navigator.pop(ctx);
        c.setShuffleMode(on ? ShuffleMode.off : m);
      },
    );
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Karışık çalma',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          option(
            ctx,
            ShuffleMode.normal,
            Icons.shuffle,
            'Karışık',
            'Liste tamamen rastgele sırayla çalınır.',
          ),
          option(
            ctx,
            ShuffleMode.smart,
            Icons.auto_awesome,
            'Akıllı mix',
            'Çok dinlediklerin ve uzun zamandır çalmadıkların öne çıkar, '
                'bugün çalınanlar geri düşer, aynı sanatçı üst üste gelmez.',
          ),
          if (c.shuffleOn)
            ListTile(
              leading: Icon(Icons.close, color: kText70),
              title: const Text('Kapat'),
              onTap: () {
                Navigator.pop(ctx);
                c.setShuffleMode(ShuffleMode.off);
              },
            ),
        ],
      ),
    ),
  );
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
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Uyku zamanlayıcısı',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
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
                leading: Icon(Icons.close, color: kGreen),
                title: Text('Zamanlayıcıyı kapat', style: TextStyle(color: kGreen)),
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
              position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(anim),
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class SeekBar extends StatefulWidget {
  const SeekBar({super.key});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  /// Sürüşdürmə zamanı yalnız bu dəyər dəyişir; real seek barmaq qalxanda edilir.
  /// (Əvvəl hər onChanged-də seek edilirdi: diskdən oxunan MP3-də saniyədə onlarla
  /// seek donmaya səbəb olurdu.)
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return StreamBuilder<Duration>(
      stream: c.positionStream,
      builder: (context, snap) {
        final dur = c.player.duration ?? Duration.zero;
        final maxMs = dur.inMilliseconds;
        final upper = maxMs <= 0 ? 0 : maxMs;
        final posMs =
            _dragMs?.round() ?? (snap.data ?? Duration.zero).inMilliseconds.clamp(0, upper);
        final pos = Duration(milliseconds: posMs);

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: posMs.clamp(0, maxMs <= 0 ? 1 : maxMs).toDouble(),
                min: 0,
                max: maxMs <= 0 ? 1 : maxMs.toDouble(),
                onChangeStart: (v) => setState(() => _dragMs = v),
                onChanged: (v) => setState(() => _dragMs = v),
                onChangeEnd: (v) async {
                  await c.seek(Duration(milliseconds: v.toInt()));
                  if (mounted) setState(() => _dragMs = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(pos),
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  Text(
                    '-${formatDuration(dur - pos)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Səs gücləndirici: şarkı ekranında sürətli aç (1x..10x, aydınlıq).
class _BoosterButton extends StatelessWidget {
  const _BoosterButton();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Booster.instance,
      builder: (context, _) {
        final on = Booster.instance.enabled;
        return IconButton(
          tooltip: 'Ses güçlendirici',
          icon: Icon(Icons.graphic_eq, color: on ? kGreen : null),
          onPressed: () => showBoosterSheet(context),
        );
      },
    );
  }
}
