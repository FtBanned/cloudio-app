import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:share_plus/share_plus.dart';

import 'lyrics.dart';
import 'main.dart'
    show kBg, kGreen, kText, kText38, kText54, kText60, lyricsBg, shadeTint;
import 'player_controller.dart';

/// Şarkı sözü paylaşma kartı səhifəsini açır.
void openLyricsShare(BuildContext context, Song song) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LyricsSharePage(song: song)),
  );
}

/// Sözlərdən 1-6 sətir seçilir, kapak fonlu şəkil kartı yaranır və paylaşılır.
class LyricsSharePage extends StatefulWidget {
  final Song song;
  const LyricsSharePage({super.key, required this.song});

  @override
  State<LyricsSharePage> createState() => _LyricsSharePageState();
}

class _LyricsSharePageState extends State<LyricsSharePage> {
  static const _maxLines = 6;
  final GlobalKey _boundaryKey = GlobalKey();
  final Set<int> _sel = <int>{};
  bool _busy = false;

  List<LyricLine> get _lines => widget.song.lyrics?.lines ?? const <LyricLine>[];

  String get _quote {
    final idx = _sel.toList()..sort();
    return [for (final i in idx) _lines[i].text.trim()].join('\n');
  }

  void _toggle(int i) {
    setState(() {
      if (_sel.contains(i)) {
        _sel.remove(i);
      } else if (_sel.length >= _maxLines) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En fazla 6 satır seçebilirsin')),
        );
      } else {
        _sel.add(i);
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _share(BuildContext btnContext) async {
    if (_busy || _sel.isEmpty) return;
    // iPad üçün paylaşma pəncərəsinin yeri (await-dən əvvəl hesablanır)
    final box = btnContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final b = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (b == null) throw Exception('Kart hazır değil');
      // pixelRatio 1.0: kartın içi 1080x1350 olduğu üçün çıxış da 1080x1350 piksel olur
      final img = await b.toImage(pixelRatio: 1.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('Görsel oluşturulamadı');
      final bytes = data.buffer.asUint8List();
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(bytes,
              mimeType: 'image/png', name: 'cloudio_soz_karti.png')
        ],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      _snack('Paylaşılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final previewH = MediaQuery.of(context).size.height * 0.40;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Söz kartı',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: lines.isEmpty
          ? Center(
              child: Text('Bu şarkının sözü yok.',
                  style: TextStyle(color: kText60)),
            )
          : Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  height: previewH,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1080 / 1350,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: RepaintBoundary(
                          key: _boundaryKey,
                          child: SizedBox(
                            width: 1080,
                            height: 1350,
                            child: _QuoteCard(song: widget.song, quote: _quote),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Kartta görünmesini istediğin satırlara dokun (${_sel.length}/$_maxLines)',
                        style: TextStyle(color: kText54, fontSize: 12)),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final t = lines[i].text.trim();
                      if (t.isEmpty) return const SizedBox(height: 10);
                      final on = _sel.contains(i);
                      return InkWell(
                        onTap: () => _toggle(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 9),
                          child: Row(
                            children: [
                              Icon(
                                  on
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: on ? kGreen : kText38,
                                  size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: on
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: on ? kGreen : kText)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Builder(
                      builder: (btnCtx) => SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              (_sel.isEmpty || _busy) ? null : () => _share(btnCtx),
                          icon: const Icon(Icons.ios_share),
                          label: Text(_busy ? 'Hazırlanıyor...' : 'Paylaş'),
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

/// 1080x1350 (4:5) kart: bulanık kapak fonu, seçilmiş sətirlər, şarkı adı/sənətçi.
class _QuoteCard extends StatelessWidget {
  final Song song;
  final String quote;
  const _QuoteCard({required this.song, required this.quote});

  @override
  Widget build(BuildContext context) {
    final cover = song.cover;
    final base = shadeTint(song.tint, const Color(0xFF1A1A1A));
    final n = quote.length;
    final fontSize = n <= 60 ? 84.0 : (n <= 120 ? 72.0 : (n <= 200 ? 62.0 : 54.0));

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null) ...[
            Transform.scale(
              scale: 1.4,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Image.memory(cover,
                    fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: 0.45)),
          ] else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [lyricsBg(song.tint), base],
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(90),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: cover != null
                        ? Image.memory(cover,
                            fit: BoxFit.cover, gaplessPlayback: true)
                        : Container(
                            color: Colors.white24,
                            child: const Icon(Icons.music_note,
                                size: 110, color: Colors.white70),
                          ),
                  ),
                ),
                const SizedBox(height: 60),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 900,
                        child: Text(
                          quote.isEmpty ? 'Bir satır seç' : quote,
                          style: TextStyle(
                            color: quote.isEmpty ? Colors.white54 : Colors.white,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 52,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 38)),
                    ),
                    const SizedBox(width: 20),
                    const Text('Cloudio',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 34,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
