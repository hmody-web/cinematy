import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/stores/app_settings_store.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';

class TvServerSettingsScreen extends ConsumerWidget {
  const TvServerSettingsScreen({super.key});

  Future<void> _addServer(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final server = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<TvServerProfile>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة سيرفر تلفاز'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _field(name, 'اسم السيرفر', requiredField: true),
                  _field(server, 'رابط السيرفر', hint: 'http://example.com:8080', requiredField: true),
                  _field(username, 'اسم المستخدم', requiredField: true),
                  _field(password, 'كلمة المرور', requiredField: true, obscure: true),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                var url = server.text.trim().replaceAll(RegExp(r'/+$'), '');
                if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
                Navigator.pop(dialogContext, TvServerProfile(
                  id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(), server: url,
                  username: username.text.trim(), password: password.text,
                ));
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await ref.read(appSettingsProvider).addTvServer(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة السيرفر. فعّله من القائمة لتبديل مصدر التلفاز.')));
      }
    }
  }

  static Widget _field(TextEditingController controller, String label, {String? hint, bool requiredField = false, bool obscure = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
      validator: requiredField ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null : null,
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: CinematyTopBar(section: 'سيرفرات التلفاز', showQuickActions: false, onBack: () => Navigator.pop(context)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('اختر سيرفر واحداً فقط. عند تفعيل سيرفر جديد، يتوقف استخدام السيرفر السابق تلقائياً.', style: TextStyle(color: Colors.white70, height: 1.6)),
          const SizedBox(height: 16),
          ...settings.tvServerProfiles.map((profile) {
            final active = profile.id == settings.activeTvProfileId;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(18), border: Border.all(color: active ? AppColors.redBright.withOpacity(.8) : Colors.white12)),
              child: SwitchListTile.adaptive(
                value: active,
                activeColor: AppColors.redBright,
                onChanged: (value) { if (value) ref.read(appSettingsProvider).activateTvServer(profile.id); },
                title: Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${profile.server}\nالمستخدم: ${profile.username}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, height: 1.6)),
                secondary: profile.id == 'original' ? const Icon(Icons.dns_rounded) : IconButton(
                  tooltip: 'حذف السيرفر', icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  onPressed: () => showDialog<void>(context: context, builder: (c) => AlertDialog(
                    title: const Text('حذف السيرفر؟'), content: Text('سيتم حذف ${profile.name} من القائمة.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), TextButton(onPressed: () { ref.read(appSettingsProvider).removeTvServer(profile.id); Navigator.pop(c); }, child: const Text('حذف'))],
                  )),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _addServer(context, ref),
            icon: const Icon(Icons.add_rounded), label: const Text('إضافة سيرفر جديد'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.redBright, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
          ),
        ],
      ),
    );
  }
}
