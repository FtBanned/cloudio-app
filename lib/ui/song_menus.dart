part of '../main.dart';

/// Şarkı "⋯" menüsü.
Future<void> showSongMenu(BuildContext context, Song song, {Playlist? playlist}) {
  final c = PlayerController.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kCard,
    shape: _sheetShape,
    builder: (ctx) => SafeArea(
      child: Column(
        key: TourKeys.songMenu, // animasiyalı rehber üçün
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Cover(size: 48, bytes: song.cover),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              song.liked ? Icons.check_circle : Icons.add_circle_outline,
              color: song.liked ? kGreen : null,
            ),
            title: Text(song.liked ? 'Beğenilenlerden kaldır' : 'Beğenilenlere ekle'),
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
            title: Text(
              song.lyrics == null
                  ? 'Şarkı sözü ekle (.lrc / .txt)'
                  : 'Şarkı sözünü değiştir (.lrc / .txt)',
            ),
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
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Çalma listesine ekle',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: CircleAvatar(backgroundColor: kText12, child: Icon(Icons.add)),
              title: const Text('Yeni çalma listesi'),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await askText(
                  context,
                  title: 'Çalma listesine ad ver',
                  initial: 'Çalma listem #${c.playlists.length + 1}',
                );
                if (name == null) return;
                final p = c.createPlaylist(name);
                c.addToPlaylist(p, [song]);
              },
            ),
            for (final p in c.playlists)
              ListTile(
                leading: MosaicCover(songs: p.songs, size: 44),
                title: Text(p.name),
                subtitle: Text(
                  p.songs.contains(song) ? 'Zaten listede' : '${p.songs.length} şarkı',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  c.addToPlaylist(p, [song]);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('"${p.name}" listesine eklendi')));
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
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Şarkı ekle',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
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
                          picked.length == candidates.length ? 'Seçimi kaldır' : 'Tümünü seç',
                          style: TextStyle(color: kText, fontWeight: FontWeight.bold),
                        ),
                      ),
                    TextButton(
                      onPressed: picked.isEmpty
                          ? null
                          : () {
                              c.addToPlaylist(p, picked);
                              Navigator.pop(ctx);
                            },
                      child: Text(
                        'Ekle (${picked.length})',
                        style: TextStyle(
                          color: picked.isEmpty ? kText30 : kGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (candidates.isEmpty)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Eklenecek şarkı kalmadı.\nÖnce Kitaplığından şarkı yükle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kText60),
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
                          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
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
              final name = await askText(context, title: 'Yeni ad', initial: p.name);
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
