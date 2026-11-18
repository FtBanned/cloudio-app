import 'package:flutter/material.dart';

import 'main.dart';
import 'player_controller.dart';

/// Tam ekran oynatıcıdakı "Sıra" düyməsi bunu açır.
void openQueue(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const QueuePage()),
  );
}

/// Sıra: hazırda çalan mahnı + ardınca nə çalacaq.
/// Qarışıq rejim açılanda və ya bağlananda siyahı dərhal yenilənir.
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  bool _edit = false;

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final cur = c.current;
        final next = c.upNext;

        final repeatLabel = switch (c.repeatKind) {
          RepeatKind.off => 'Tekrarla',
          RepeatKind.all => 'Tekrar: hepsi',
          RepeatKind.one => 'Tekrar: bir',
        };

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sıra',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold)),
                            Text('Çalan: ${c.queueName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: kText60)),
                            if (next.isNotEmpty)
                              Text('Sırada: ${countAndTotal(next)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: kText38, fontSize: 12)),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: (_edit || next.isNotEmpty)
                            ? () => setState(() => _edit = !_edit)
                            : null,
                        child: Text(_edit ? 'Bitti' : 'Düzenle'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (cur != null)
                  ListTile(
                    leading: Cover(size: 48, bytes: cur.cover),
                    title: Text(cur.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: kGreen, fontWeight: FontWeight.bold)),
                    subtitle: Text(cur.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: kText60)),
                    trailing: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: kText, shape: BoxShape.circle),
                      child: IconButton(
                        color: kBg,
                        icon: Icon(c.isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: c.togglePlay,
                      ),
                    ),
                  ),
                Expanded(
                  child: next.isEmpty
                      ? Center(
                          child: Text('Sırada başka şarkı yok',
                              style: TextStyle(color: kText60)),
                        )
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: next.length,
                          onReorder: (oldI, newI) {
                            if (newI > oldI) newI--;
                            c.reorderUpNext(oldI, newI);
                          },
                          itemBuilder: (context, i) {
                            final s = next[i];
                            return ListTile(
                              key: ValueKey(s.id),
                              leading: Cover(size: 48, bytes: s.cover),
                              title: Text(s.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(s.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: kText60)),
                              onTap: _edit ? null : () => c.playUpNext(i),
                              trailing: _edit
                                  ? IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.redAccent),
                                      onPressed: () => c.removeFromUpNext(i),
                                    )
                                  : ReorderableDragStartListener(
                                      index: i,
                                      child: Icon(Icons.drag_handle,
                                          color: kText70),
                                    ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QueueButton(
                          icon: shuffleIconFor(c),
                          label: c.smartShuffle ? 'Ağıllı mix' : 'Karışık çal',
                          active: c.shuffleOn,
                          onTap: () => showShuffleSheet(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QueueButton(
                          icon: c.repeatKind == RepeatKind.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                          label: repeatLabel,
                          active: c.repeatKind != RepeatKind.off,
                          onTap: c.cycleRepeat,
                        ),
                      ),
                    ],
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

class _QueueButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _QueueButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? kGreen : kText;
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
