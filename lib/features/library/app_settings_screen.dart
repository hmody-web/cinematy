import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/stores/app_settings_store.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'إعدادات التطبيق',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: [
          Text(
            'عام',
            style: TextStyle(
              color: Colors.white.withOpacity(.46),
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _SettingsCard(
            child: ListTile(
              leading: const _IconBox(Icons.language_rounded),
              title: const Text('اللغة', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text('العربية • اتجاه كامل من اليمين إلى اليسار'),
              trailing: const Text(
                'العربية',
                style: TextStyle(
                  color: AppColors.redBright,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  leading: _IconBox(Icons.font_download_rounded),
                  title: Text('خط التطبيق', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('غيّر شكل الكتابة في كل واجهات سينماتي'),
                ),
                const Divider(height: 1),
                ...AppSettingsStore.fonts.map(
                  (font) => RadioListTile<String>(
                    value: font.family,
                    groupValue: settings.fontFamily,
                    title: Text(
                      font.label,
                      style: TextStyle(
                        fontFamily: font.family,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'سينماتي • أفلام ومسلسلات',
                      style: TextStyle(
                        fontFamily: font.family,
                        color: Colors.white54,
                      ),
                    ),
                    activeColor: AppColors.redBright,
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appSettingsProvider).setFontFamily(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.035),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.06),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, size: 21),
      );
}
