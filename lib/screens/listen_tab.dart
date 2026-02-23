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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Listen',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                'Voice stations, curated',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textTertiary,
                  letterSpacing: 0.1,
                  height: 1.3,
                ),
              ),
            ],
          ),
          toolbarHeight: EchoLayout.space(context, 72),
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
            padding: EdgeInsets.only(
              top: EchoLayout.space(context, 8),
              bottom: EchoLayout.space(context, 12),
            ),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: EchoLayout.space(context, 346)
                    .clamp(286.0, 380.0)
                    .toDouble(),
                child: GridView.builder(
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: contentPadding),
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
          if (recentStations.isNotEmpty) ...[
            SliverPadding(
              padding: EchoLayout.listPadding(
                context,
                top: 2,
                bottom: 6,
                includeBottomSafeArea: false,
              ),
              sliver: SliverToBoxAdapter(
                child: _SectionHeading(title: 'Recent'),
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
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 0.5,
          color: tokens.textTertiary.withValues(alpha: 0.20),
        ),
        const SizedBox(height: 14),
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: tokens.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
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

    // Atmospheric gradient: station color at top-left fading to near-black at bottom-right
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(hashtag.color, tokens.surface1, 0.35)!,
        Color.lerp(tokens.bg, hashtag.color, 0.18)!,
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
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.bg.withValues(alpha: 0.28),
            ),
            child: Icon(
              hashtag.icon,
              size: 26,
              color: tokens.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            hashtag.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.05,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hashtag.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textPrimary.withValues(alpha: 0.68),
              height: 1.35,
            ),
          ),
          if (hashtag.noteCount > 0) ...[
            const SizedBox(height: 5),
            Text(
              '${hashtag.noteCount} ${hashtag.noteCount == 1 ? 'note' : 'notes'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textPrimary.withValues(alpha: 0.48),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
        Color.lerp(station.color, tokens.surface1, 0.35)!,
        Color.lerp(tokens.bg, station.color, 0.28)!,
      ],
    );

    return EchoCard(
      onTap: onTap,
      radius: 18,
      color: tokens.surface1,
      overlayColor: EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            height: 50,
            width: 50,
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (station.noteCount > 0)
                  Text(
                    '${station.noteCount} ${station.noteCount == 1 ? 'note' : 'notes'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textTertiary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.play_arrow_rounded,
            size: 26,
            color: tokens.accentPrimary,
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
