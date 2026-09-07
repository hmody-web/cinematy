import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers.dart';
import '../../data/stores/subtitle_settings_store.dart';
import '../../widgets/cinematy_top_bar.dart';

class SubtitleSettingsScreen extends ConsumerWidget {
  const SubtitleSettingsScreen({super.key});

  static const _colors = <Color>[
    Colors.white, Colors.black, Color(0xFFFFE082), Color(0xFF81D4FA),
    Color(0xFFA5D6A7), Color(0xFFEF9A9A), Color(0xFFCE93D8),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(subtitleSettingsProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'إعدادات الترجمة',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'تخصيص الترجمة',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: s.reset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('إعادة ضبط'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 190,
            decoration: BoxDecoration(color: const Color(0xFF151515), borderRadius: BorderRadius.circular(24)),
            alignment: Alignment.center,
            child: _Preview(settings: s),
          ),
          const SizedBox(height: 24),
          _FontSelector(settings: s),
          const SizedBox(height: 8),
          _SliderTile(title: 'حجم الخط', value: s.fontSize, min: 30, max: 200, onChanged: s.setFontSize, valueLabel: '${s.fontSize.round()}'),
          _ColorRow(title: 'لون النص', selected: s.textColor, colors: _colors, onChanged: s.setTextColor),
          _ColorRow(title: 'لون الحواف', selected: s.outlineColor, colors: _colors, onChanged: s.setOutlineColor),
          _SliderTile(title: 'سماكة الحواف', value: s.outlineWidth, min: 0, max: 5, onChanged: s.setOutlineWidth, valueLabel: s.outlineWidth.toStringAsFixed(1)),
          _SliderTile(title: 'شفافية الحواف', value: s.outlineOpacity, min: 0, max: 1, onChanged: s.setOutlineOpacity, valueLabel: '${(s.outlineOpacity * 100).round()}٪'),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('خلفية للترجمة'), subtitle: const Text('مبدئياً بدون خلفية'), value: s.backgroundEnabled, onChanged: s.setBackgroundEnabled),
          if (s.backgroundEnabled) ...[
            _ColorRow(title: 'لون الخلفية', selected: s.backgroundColor, colors: _colors, onChanged: s.setBackgroundColor),
            _SliderTile(title: 'شفافية الخلفية', value: s.backgroundOpacity, min: 0, max: 1, onChanged: s.setBackgroundOpacity, valueLabel: '${(s.backgroundOpacity * 100).round()}٪'),
          ],
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.settings});
  final dynamic settings;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: settings.backgroundEnabled ? settings.backgroundColor.withOpacity(settings.backgroundOpacity) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Stack(children: [
      Text('هذه معاينة الترجمة العربية', textAlign: TextAlign.center, style: TextStyle(fontFamily: settings.fontFamily, fontSize: settings.fontSize.clamp(18.0, 80.0).toDouble(), foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = settings.outlineWidth * 2..color = settings.outlineColor.withOpacity(settings.outlineOpacity))),
      Text('هذه معاينة الترجمة العربية', textAlign: TextAlign.center, style: TextStyle(fontFamily: settings.fontFamily, fontSize: settings.fontSize.clamp(18.0, 80.0).toDouble(), color: settings.textColor)),
    ]),
  );
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({required this.title, required this.value, required this.min, required this.max, required this.onChanged, required this.valueLabel});
  final String title, valueLabel; final double value, min, max; final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(children: [
      Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(valueLabel, style: TextStyle(color: Colors.white.withOpacity(.5)))]),
      Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged),
    ]),
  );
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.title, required this.selected, required this.colors, required this.onChanged});
  final String title; final Color selected; final List<Color> colors; final ValueChanged<Color> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: colors.map((c) => GestureDetector(onTap: () => onChanged(c), child: Container(width: 38, height: 38, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: selected.value == c.value ? AppColors.redBright : Colors.white24, width: selected.value == c.value ? 3 : 1))))).toList()),
    ]),
  );
}


class _FontSelector extends StatelessWidget {
  const _FontSelector({required this.settings});
  final SubtitleSettingsStore settings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('نوع خط الترجمة', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: SubtitleSettingsStore.fonts.map((font) => ChoiceChip(
          selected: settings.fontFamily == font.family,
          label: Text(font.label, style: TextStyle(fontFamily: font.family)),
          onSelected: (_) => settings.setFontFamily(font.family),
        )).toList(),
      ),
    ]),
  );
}
