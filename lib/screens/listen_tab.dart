import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../models/hashtag.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import '../widgets/echo_components.dart';

class ListenTab extends StatefulWidget {
  const ListenTab({super.key});

  @override
  State<ListenTab> createState() => _ListenTabState();
}

class _ListenTabState extends State<ListenTab> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final appState = AppScope.of(context);
    if (appState.hashtags.isEmpty && !appState.hashtagsLoading) {
      appState.refreshHashtags();
    }
  }

  void _openStation(Hashtag hashtag) {
    final appState = AppScope.of(context);
    appState.markStationListened(hashtag.id);
    context.push('/hashtag/${hashtag.id}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final contentPadding = EchoLayout.contentHorizontalPadding(context);
    final gridSpacing = EchoLayout.space(context, 10);
    final appState = AppScope.of(context);
    final allHashtags = appState.hashtags;
    final isLoading = appState.hashtagsLoading;
    final loadError = appState.hashtagsError;
    final recentStations = appState.recentHashtags(limit: 6);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: tokens.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: contentPadding,
          title: Text(
            'Listen',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          toolbarHeight: EchoLayout.space(context, 56),
        ),
        if (isLoading && allHashtags.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (loadError != null && allHashtags.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              title: 'Unable to load hashtags',
              subtitle: loadError,
              onRetry: () => appState.refreshHashtags(force: true),
            ),
          )
        else if (allHashtags.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              title: 'No hashtags yet',
              subtitle: 'Add hashtags in Firebase to get started.',
              onRetry: () => appState.refreshHashtags(force: true),
            ),
          )
        else ...[
          SliverPadding(
            padding: EchoLayout.listPadding(
              context,
              top: 8,
              bottom: 12,
              includeBottomSafeArea: false,
            ),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: EchoLayout.space(context, 346)
                    .clamp(286.0, 380.0)
                    .toDouble(),
                child: GridView.builder(
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: EchoLayout.space(context, 190)
                        .clamp(168.0, 222.0)
                        .toDouble(),
                    mainAxisSpacing: gridSpacing,
                    crossAxisSpacing: gridSpacing,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: allHashtags.length,
                  itemBuilder: (context, index) {
                    final hashtag = allHashtags[index];
                    return _StationGridCard(
                      hashtag: hashtag,
                      onTap: () => _openStation(hashtag),
                    );
                  },
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EchoLayout.listPadding(
              context,
              top: 2,
              bottom: 4,
              includeBottomSafeArea: false,
            ),
            sliver: SliverToBoxAdapter(
              child: _SectionHeading(
                title: 'Recent',
                subtitle: 'Stations based on your latest listening activity.',
              ),
            ),
          ),
          SliverPadding(
            padding: EchoLayout.listPadding(
              context,
              top: 0,
              bottom: 12,
              includeBottomSafeArea: true,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final station = recentStations[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentStationTile(
                    station: station,
                    onTap: () => _openStation(station),
                  ),
                );
              }, childCount: recentStations.length),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StationGridCard extends StatelessWidget {
  const _StationGridCard({required this.hashtag, required this.onTap});

  final Hashtag hashtag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(hashtag.color, tokens.surface2, 0.18)!,
        Color.lerp(tokens.surface1, hashtag.color, 0.35)!,
      ],
    );

    return EchoGradientCard(
      onTap: onTap,
      radius: 22,
      gradient: gradient,
      glow: true,
      overlayColor: EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.bg.withValues(alpha: 0.2),
                  border: Border.all(
                    color: tokens.textPrimary.withValues(alpha: 0.16),
                    width: 1,
                  ),
                ),
                child: Icon(
                  hashtag.icon,
                  size: 28,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _noteCountLabel(hashtag.noteCount),
              style: theme.textTheme.labelSmall?.copyWith(
                  color: tokens.textPrimary.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            hashtag.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hashtag.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textPrimary.withValues(alpha: 0.78),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentStationTile extends StatelessWidget {
  const _RecentStationTile({required this.station, required this.onTap});

  final Hashtag station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final circleGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(station.color, tokens.surface2, 0.25)!,
        Color.lerp(tokens.surface1, station.color, 0.45)!,
      ],
    );

    return EchoCard(
      onTap: onTap,
      radius: 18,
      color: tokens.surface1,
      overlayColor: EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: circleGradient,
            ),
            child: Icon(
              station.icon,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_noteCountLabel(station.noteCount)} in this station',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.play_arrow_rounded,
            size: 26,
            color: tokens.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: EchoLayout.contentHorizontalPadding(context),
        ),
        child: EchoCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

String _noteCountLabel(int count) {
  return '$count ${count == 1 ? 'note' : 'notes'}';
}
