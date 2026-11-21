import 'package:material_ui/material_ui.dart';

import 'booster.dart';
import 'main.dart' show kBg, kCard, kGreen, kText, kText38, kText54;

/// Şarkı ekranından açılan sürətli panel (1x..10x + aydınlıq).
void showBoosterSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: kCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BoosterPanel(advanced: false),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openBoosterPage(context);
                  },
                  child: Text('Gelişmiş ayarlar', style: TextStyle(color: kGreen)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Tam səhifə (Ayarlar-dan və "Gelişmiş ayarlar"-dan).
void openBoosterPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const BoosterPage()),
  );
}

class BoosterPage extends StatelessWidget {
  const BoosterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Ses güçlendirici',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: const [BoosterPanel(advanced: true)],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kGreen : kBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.black : kText,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class BoosterPanel extends StatelessWidget {
  final bool advanced;
  const BoosterPanel({super.key, required this.advanced});

  /// Dəyişiklik tətbiq olunduqdan sonra: təhlükəli səviyyəyə keçilibsə ekrana xəbərdarlıq çıxar.
  static Future<void> _afterChange(BuildContext context) async {
    final b = Booster.instance;
    if (!b.checkDangerTransition()) return;
    if (!context.mounted) return;
    final lower = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40),
        title: const Text('Tehlikeli ses seviyesi'),
        content: Text(
          'Bu ayarlarla ses çok yüksek olabilir (yaklaşık ${b.effectiveDb.toStringAsFixed(0)} dB güçlendirme). '
          '100 dB üstü seviyeler dakikalar içinde kalıcı işitme kaybına yol açabilir. '
          'Kulaklıkta risk daha da fazladır. Telefonun sesini önce düşür.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Güvenli seviyeye indir', style: TextStyle(color: kGreen)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Devam et', style: TextStyle(color: kText54)),
          ),
        ],
      ),
    );
    if (lower == true) b.lowerToSafe();
  }

  @override
  Widget build(BuildContext context) {
    final b = Booster.instance;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) {
        final multTxt = b.mult.toStringAsFixed(b.mult == b.mult.roundToDouble() ? 0 : 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: kGreen,
              title: const Text('Ses güçlendirici',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: Text(
                  b.engineReady
                      ? 'Açıkken ses ${multTxt}x (+${b.targetDb.toStringAsFixed(1)} dB) güçlenir'
                      : 'Ses motoru başlamadı: güçlendirici çalışmaz',
                  style: TextStyle(color: kText54, fontSize: 12)),
              value: b.enabled,
              onChanged: b.engineReady
                  ? (v) {
                      b.setEnabled(v);
                      _afterChange(context);
                    }
                  : null,
            ),
            const SizedBox(height: 4),
            Text('Güçlendirme: ${multTxt}x',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in Booster.kMults)
                  _Chip(
                    label: '${m.toStringAsFixed(0)}x',
                    selected: b.enabled && (b.mult - m).abs() < 0.05,
                    onTap: () {
                      b.setMult(m);
                      _afterChange(context);
                    },
                  ),
              ],
            ),
            Slider(
              activeColor: kGreen,
              value: b.mult,
              min: 1,
              max: 10,
              divisions: 18,
              label: '${multTxt}x',
              onChanged: b.previewMult, // tətbiq onChangeEnd-də
              onChangeEnd: (v) {
                b.setMult(v);
                _afterChange(context);
              },
            ),
            if (b.danger)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'TEHLİKELİ SEVİYE: işitmene kalıcı zarar verebilir. Sesi düşür.',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              )
            else if (b.enabled && b.mult >= 5)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                    'Yüksek seviye: kulaklıkla çok dikkatli ol. Önce telefonun sesini azalt.',
                    style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 4),
            const Text('Netlik',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in Booster.kClarityNames.entries)
                  _Chip(
                    label: e.value,
                    selected: b.clarity == e.key,
                    onTap: () => b.setClarity(e.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: kCard,
                    title: const Text('Ayarlar sıfırlansın mı?'),
                    content: const Text(
                        'Güçlendirici kapanır, tüm değerler varsayılana döner.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Vazgeç', style: TextStyle(color: kText54)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          b.reset();
                        },
                        child: Text('Sıfırla', style: TextStyle(color: kGreen)),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Ayarları sıfırla'),
              ),
            ),
            if (advanced) ...[
              const SizedBox(height: 16),
              Text('Gelişmiş (elle)',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: kText54)),
              _slider(
                'Ek güçlendirme: +${b.extraDb.toStringAsFixed(0)} dB',
                b.extraDb, 0, 12, 12,
                b.previewExtra,
                (v) {
                  b.setExtraDb(v);
                  _afterChange(context);
                },
              ),
              _slider(
                'Sıkıştırma oranı: ${b.ratio.toStringAsFixed(1)} (1 = yok)',
                b.ratio, 1, 8, 14,
                (v) => b.setAdvanced(ratio: v),
                (v) {
                  b.setAdvanced(ratio: v, commit: true);
                  _afterChange(context);
                },
              ),
              _slider(
                'Sıkıştırma eşiği: ${b.threshold.toStringAsFixed(0)} dB',
                b.threshold, -60, 0, 60,
                (v) => b.setAdvanced(threshold: v),
                (v) {
                  b.setAdvanced(threshold: v, commit: true);
                  _afterChange(context);
                },
              ),
              _slider(
                'Limiter sürüklemesi: ${b.limThreshold.toStringAsFixed(0)} dB (düşük = daha yüksek/sıkı)',
                b.limThreshold, -24, 0, 24,
                (v) => b.setAdvanced(limThreshold: v),
                (v) {
                  b.setAdvanced(limThreshold: v, commit: true);
                  _afterChange(context);
                },
              ),
              _slider(
                'Tavan: ${b.limCeiling.toStringAsFixed(1)} dB (0\'a yakın = daha yüksek, riskli)',
                b.limCeiling, -12, 0, 24,
                (v) => b.setAdvanced(limCeiling: v),
                (v) {
                  b.setAdvanced(limCeiling: v, commit: true);
                  _afterChange(context);
                },
              ),
              const SizedBox(height: 8),
              Text('EQ bantları (1.0 = değişmez, 2.0 ≈ +6 dB)',
                  style: TextStyle(color: kText54, fontSize: 12)),
              for (var i = 0; i < Booster.kBands; i++)
                Row(
                  children: [
                    SizedBox(
                        width: 28,
                        child: Text('${i + 1}',
                            style: TextStyle(color: kText38, fontSize: 12))),
                    Expanded(
                      child: Slider(
                        activeColor: kGreen,
                        value: b.bandGain[i],
                        min: 0,
                        max: 4,
                        onChanged: (v) =>
                            b.setAdvanced(band: i, bandValue: v),
                        onChangeEnd: (v) =>
                            b.setAdvanced(band: i, bandValue: v, commit: true),
                      ),
                    ),
                    SizedBox(
                        width: 36,
                        child: Text(b.bandGain[i].toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12))),
                  ],
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _slider(String text, double value, double min, double max, int div,
      ValueChanged<double> onChanged, ValueChanged<double> onEnd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(fontSize: 14)),
        Slider(
          activeColor: kGreen,
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: div,
          onChanged: onChanged,
          onChangeEnd: onEnd,
        ),
      ],
    );
  }
}
