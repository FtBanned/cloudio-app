part of '../main.dart';

enum _CollectionKind { all, liked, playlist, artist, album, genre }

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
  const CollectionPage.genre(String name, {super.key})
      : kind = _CollectionKind.genre,
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
              if ((kind == _CollectionKind.genre ? s.genre.trim() : _groupName(s, byAlbum))
                      .toLowerCase() ==
                  key)
                s,
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
          case _CollectionKind.genre:
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
        // albom səhifəsində "Varsayılan" sıra: disk və trek nömrəsinə görə
        final list = kind == _CollectionKind.album && _sort == SongSort.standard
            ? albumOrder(base)
            : sortedSongs(base, _sort);

        Color? tint;
        for (final s in base) {
          if (s.tint != null) {
            tint = s.tint;
            break;
          }
        }
        final topDark = shadeTint(tint, const Color(0xFF3A2E5C));
        final top = AppTheme.instance.isLight
            ? Color.lerp(kBg, topDark, 0.22)!
            : topDark;
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
                    child: Text(
                        kind == _CollectionKind.album
                            ? albumInfo(list)
                            : countAndTotal(list),
                        style: TextStyle(color: kText60)),
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
                          icon: Icon(shuffleIconFor(c),
                              size: 28,
                              color: c.shuffleOn ? kGreen : kText),
                          onPressed: () => showShuffleSheet(context),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
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
                                  color: _editing ? kGreen : kText,
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
                            _CollectionKind.genre ||
                            _CollectionKind.album =>
                              'Bu bölümde şarkı yok.',
                          },
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kText60),
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
            style: TextStyle(color: kText60)),
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
                      ? Center(
                          child: Text('Henüz kayıt yok',
                              style: TextStyle(color: kText60)),
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
                                  style: TextStyle(
                                      color: kText60, fontSize: 13)),
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
          color: kText12,
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
          child: Text('Tamam', style: TextStyle(color: kGreen)),
        ),
      ],
    ),
  );
}

ShapeBorder get _sheetShape => const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    );
