part of '../main.dart';

// ================= Şarkı sözleri =================
Color lyricsBg(Color? tint) {
  if (tint == null) return const Color(0xFF6C63B8);
  final h = HSLColor.fromColor(tint);
  return h.withLightness(0.34).withSaturation(h.saturation.clamp(0.25, 0.7).toDouble()).toColor();
}

/// Serbest metinlə internette söz axtarır, siyahıdan seçilən sözü mahnıya bağlayır.
Future<void> showLyricsSearch(BuildContext context, Song song) async {
  final initial = cleanForSearch(
    song.artist == kUnknownArtist ? song.title : '${song.artist} ${song.title}',
  );
  final picked = await showModalBottomSheet<LyricsCandidate>(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    isScrollControlled: true,
    builder: (_) => _LyricsSearchSheet(initial: initial),
  );
  if (picked == null) return;
  // Söz, sayfa kapanmış olsa bile mutlaka kaydedilir; sadece bildirim context ister
  PlayerController.instance.setLyrics(song, picked.lyrics);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Şarkı sözü eklendi')));
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
                child: Text(
                  'Şarkı sözü ara',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bir sonuca dokun: sözü bu şarkıya eklenir. Aranan metin lrclib.net\'e gönderilir.',
                  style: TextStyle(color: kText54, fontSize: 12),
                ),
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
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: kGreen))
                  : _error != null
                  ? Center(
                      child: Text(_error!, style: TextStyle(color: kText60)),
                    )
                  : (_searched && _results.isEmpty)
                  ? Center(
                      child: Text('Sonuç yok, aramayı değiştir', style: TextStyle(color: kText60)),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        final info = [
                          if (r.artist.isNotEmpty) r.artist,
                          if (r.album.isNotEmpty) r.album,
                          if (r.duration != null) formatDuration(r.duration!),
                          r.lyrics.synced ? 'Senkron' : 'Düz metin',
                        ].join(' • ');
                        final first = _firstLine(r.lyrics);
                        return ListTile(
                          isThreeLine: first.isNotEmpty,
                          title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            first.isEmpty ? info : '$info\n$first',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: kText60),
                          ),
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
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(ok ? 'Şarkı sözü eklendi' : 'Dosyada söz bulunamadı')));
}

void openLyricsPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const DarkZone(child: LyricsPage())),
  );
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
                  child: Text(
                    'Şarkı sözleri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
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
          if (song.lyrics != null)
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Söz kartı oluştur ve paylaş'),
              onTap: () {
                Navigator.pop(ctx);
                openLyricsShare(context, song);
              },
            ),
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
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
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
                    color: i == _idx ? Colors.white : (i < _idx ? Colors.white38 : Colors.white54),
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
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.ios_share),
                        tooltip: 'Söz kartı',
                        onPressed: song.lyrics == null
                            ? null
                            : () => openLyricsShare(context, song),
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
                    Text(
                      'Sözler: ${song.lyrics!.source}',
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: SeekBar()),
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
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          iconSize: 36,
                          color: Colors.black,
                          icon: Icon(c.isPlaying ? Icons.pause : Icons.play_arrow),
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
