import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cinematy/core/navigation/cinematy_page_route.dart';
import '../../data/models/content_details.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/network_image.dart';
import '../../widgets/shimmer.dart';
import '../library/library_screen.dart';
import 'details_screen.dart';

class ActorScreen extends ConsumerStatefulWidget {
  const ActorScreen({super.key, required this.person});
  final Person person;

  @override
  ConsumerState<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends ConsumerState<ActorScreen> {
  late Future<List<MediaItem>> _works;
  Future<Person?>? _profile;

  @override
  void initState() {
    super.initState();
    final api = ref.read(apiProvider);
    _profile = widget.person.id.isEmpty
        ? Future.value(widget.person)
        : api.person(widget.person.id).catchError((_) => widget.person);
    _works = api.personWorks(widget.person).catchError((_) => <MediaItem>[]);
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: widget.person.name,
        downloadsCount: downloads.items.length + downloads.activeItems.length,
        onBack: () => Navigator.pop(context),
        onContinue: () => Navigator.push(
          context,
          CinematyPageRoute(builder: (_) => const ContinueWatchingScreen()),
        ),
        onDownloads: () => Navigator.push(
          context,
          CinematyPageRoute(builder: (_) => const DownloadsScreen()),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 255,
              child: FutureBuilder<Person?>(
                future: _profile,
                builder: (_, snap) {
                  final person = snap.data ?? widget.person;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CinematyNetworkImage(url: person.imageUrl),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x22000000), Color(0xF2070505)],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 20,
                        left: 20,
                        bottom: 22,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 92,
                              height: 92,
                              child: CinematyNetworkImage(
                                url: person.imageUrl,
                                borderRadius: BorderRadius.circular(46),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 24,
                                    ),
                                  ),
                                  if (person.role.isNotEmpty)
                                    Text(
                                      person.role,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(.58),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 22, 18, 12),
              child: Text(
                'الأعمال',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          FutureBuilder<List<MediaItem>>(
            future: _works,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
                  sliver: SliverGrid.builder(
                    itemCount: 9,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 16,
                      childAspectRatio: .52,
                    ),
                    itemBuilder: (_, __) =>
                        const SkeletonPosterCard(width: double.infinity),
                  ),
                );
              }
              final items = snap.data ?? const <MediaItem>[];
              if (items.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'لا توجد أعمال متاحة لهذا الممثل حالياً',
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
                sliver: SliverGrid.builder(
                  itemCount: items.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                    childAspectRatio: .52,
                  ),
                  itemBuilder: (_, i) => MediaPosterCard(
                    item: items[i],
                    width: double.infinity,
                    onTap: () => Navigator.of(context).push(
                      CinematyPageRoute(
                        builder: (_) => DetailsScreen(item: items[i]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
