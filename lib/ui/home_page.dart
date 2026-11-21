part of '../main.dart';

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
        final count = _musicOnly ? songs.length : (songs.length < 6 ? songs.length : 6);

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
          if (c.missingAudioCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Material(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                  title: Text('${c.missingAudioCount} şarkının ses dosyası yok'),
                  subtitle: Text(
                    'Dosyaları seçip yeniden bağla',
                    style: TextStyle(color: kText60, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right, color: kText38),
                  onTap: () => openBackupPage(context),
                ),
              ),
            ),
          const BackupReminderBanner(),
          if (!_musicOnly) const ThrowbackCard(),
          if (recent.isNotEmpty) _SongShelf(title: 'Son çaldıkların', songs: recent),
          if (top.isNotEmpty)
            _SongShelf(title: 'En çok dinlediklerin', songs: top, showCount: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              _musicOnly ? 'Tüm şarkılar' : 'Dinlemeye başla',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          if (songs.isEmpty)
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'Henüz şarkı yok.\nKitaplığın sekmesinden şarkı ekle.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kText60),
                    ),
                    if (c.restored && c.backupSupported) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => openBackupPage(context),
                        icon: const Icon(Icons.restore),
                        label: const Text('Yedekten geri yükle'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ];

        return ListView.builder(
          padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom),
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
  const _SongShelf({required this.title, required this.songs, this.showCount = false});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 212,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
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
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: playing ? kGreen : kText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        showCount ? '${s.playCount} kez çalındı' : s.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: kText60),
                      ),
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
