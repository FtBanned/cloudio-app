part of '../main.dart';

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
          style: TextStyle(color: kText60)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.duration != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(formatDuration(song.duration!),
                  style: TextStyle(color: kText54, fontSize: 13)),
            ),
          if (song.liked)
            Icon(Icons.check_circle, color: kGreen, size: 20),
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
    // profil şəkli: toxunanda Ayarlar açılır
    return GestureDetector(
      onTap: () => openSettings(context),
      child: const ProfileCircle(radius: 18),
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
            color: selected ? Colors.black : kText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
