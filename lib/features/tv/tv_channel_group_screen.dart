import 'package:flutter/material.dart';

import '../../core/navigation/cinematy_page_route.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/network_image.dart';
import 'tv_models.dart';
import 'tv_player_screen.dart';
import 'xtream_tv_service.dart';

class TvChannelGroupScreen extends StatelessWidget {
  const TvChannelGroupScreen({
    super.key,
    required this.channel,
    required this.variants,
    required this.allChannels,
  });

  final TvChannel channel;
  final List<TvChannel> variants;
  final List<TvChannel> allChannels;

  @override
  Widget build(BuildContext context) {
    final service = XtreamTvService();
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'التلفاز',
        showQuickActions: false,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(.06)),
                    ),
                    child: CinematyNetworkImage(
                      url: channel.icon,
                      fit: BoxFit.contain,
                      memCacheWidth: 240,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${variants.length} نسخة متوفرة للبث المباشر',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
              child: Text(
                'اختر النسخة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverList.separated(
              itemCount: variants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = variants[index];
                return Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      CinematyPageRoute(
                        builder: (_) => TvPlayerScreen(
                          channel: item,
                          channels: allChannels,
                          service: service,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 48,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: CinematyNetworkImage(
                              url: item.icon,
                              fit: BoxFit.contain,
                              memCacheWidth: 180,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.redBright.withOpacity(.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: AppColors.redBright, size: 7),
                                SizedBox(width: 5),
                                Text('مشاهدة', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
