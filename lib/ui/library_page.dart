part of '../main.dart';

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
                  if (kOnlineCovers || kOnlineLyrics)
                    IconButton(
                      icon: Icon(c.coversRunning ? Icons.close : Icons.refresh,
                          size: 26),
                      tooltip: c.coversRunning
                          ? 'Aramayı durdur'
                          : 'Listeyi yenile (eksik kapak ve sözleri bul)',
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
                    Text('Kapaklar ve sözler aranıyor… ${c.coversDone}/${c.coversTotal}',
                        style: TextStyle(
                            fontSize: 12, color: kText60)),
                  ],
                ),
              )
            else if (c.coversNote != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(c.coversNote!,
                    style:
                        TextStyle(fontSize: 12, color: kText60)),
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
              leading: _IconSquare(
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
              Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Henüz şarkı yok.\nSağ üstteki + ile şarkı ekle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kText60),
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
          style: TextStyle(color: kText60, fontSize: 13)),
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
