import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/content_source.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';

class ContentSourcesScreen extends ConsumerWidget {
  const ContentSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'قسم المصادر',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.redBright.withOpacity(.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.redBright.withOpacity(.18)),
            ),
            child: const Text(
              'يمكن تشغيل مصدر واحد فقط. عند اختيار مصدر جديد يتم إيقاف المصدر السابق تلقائياً وتتحول المكتبة والبحث والتفاصيل والحلقات والتشغيل إليه.',
              style: TextStyle(height: 1.55, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          ...settings.contentSources.map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SourceTile(
                source: source,
                selected: settings.activeContentSourceId == source.id,
                onTap: () async {
                  await ref.read(appSettingsProvider).setActiveContentSource(source.id);
                  await ref.read(apiProvider).clearApiCache();
                  ref.invalidate(homeFeedProvider);
                  ref.invalidate(categoriesProvider);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final ContentSourceDefinition source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.redBright.withOpacity(.10) : Colors.white.withOpacity(.035),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? AppColors.redBright.withOpacity(.55) : Colors.white.withOpacity(.07),
            ),
          ),
          child: Row(
            children: [
              _SourceLogo(source: source),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      source.id == 'cinemana'
                          ? 'المصدر الرئيسي لتطبيق سينماتي'
                          : 'مكتبة أكوام للأفلام والمسلسلات',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 48,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? AppColors.redBright : Colors.white12,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.all(3),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  alignment: selected ? Alignment.centerLeft : Alignment.centerRight,
                  child: const CircleAvatar(radius: 11, backgroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceLogo extends StatelessWidget {
  const _SourceLogo({required this.source});
  final ContentSourceDefinition source;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        source.id == 'akwam'
            ? 'assets/branding/akwam_logo.webp'
            : 'assets/branding/app_icon.jpg',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
