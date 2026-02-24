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

  Future<void> _onRefresh() async {
    final appState = AppScope.of(context);
    await appState.refreshHashtags(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final contentPadding = EchoLayout.contentHorizontalPadding(context);
    final appState = AppScope.of(context);
    final allHashtags = appState.hashtags;
    final isLoading = appState.hashtagsLoading;
    final loadError = appState.hashtagsError;
    final recentStations = appState.recentHashtags(limit: 6);
    final hasRecent = recentStations.isNotEmpty;

    return Stack(
      children: [
        // ── Ambient background gradient ──
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.6),
                radius: 1.2,
                colors: [
                  tokens.accentPrimary.withValues(alpha: 0.05),
                  tokens.bg,
                ],
                stops: const [0.0, 0.6],
              ),
            ),
          ),
        ),
        // ── Scrollable content with pull-to-refresh ──
        RefreshIndicator(
          onRefresh: _onRefresh,
          color: tokens.accentPrimary,
          backgroundColor: tokens.surface1,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // ── Header ──
              SliverToBoxAdapter(
                child: _ListenHeader(contentPadding: contentPadding),
              ),

              // ── Loading / error / empty states ──
              if (isLoading && allHashtags.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (loadError != null && allHashtags.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    title: 'Unable to load stations',
                    subtitle: loadError,
                    onRetry: _onRefresh,
                  ),
                )
              else if (allHashtags.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    title: 'No stations yet',
                    subtitle: 'Stations will appear here once they are created.',
                    onRetry: _onRefresh,
                  ),
                )
              else ...[
                // ── Recent stations (horizontal scroll with fade) ──
                if (hasRecent) ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      contentPadding,
                      EchoLayout.space(context, 4),
                      contentPadding,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SectionLabel(title: 'Recent'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: EchoLayout.space(context, 56),
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.white,
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.05, 0.85, 1.0],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            horizontal: contentPadding,
                            vertical: EchoLayout.space(context, 8),
                          ),
                          itemCount: recentStations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final station = recentStations[index];
                            return _RecentChip(
                              station: station,
                              onTap: () => _openStation(station),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],

                // ── All stations heading ──
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    contentPadding,
                    EchoLayout.space(context, hasRecent ? 18 : 4),
                    contentPadding,
                    EchoLayout.space(context, 10),
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _SectionLabel(
                      title: 'Stations',
                      trailing: Text(
                        '${allHashtags.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Station grid (vertical 2-column) ──
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    contentPadding,
                    0,
                    contentPadding,
                    MediaQuery.paddingOf(context).bottom +
                        EchoLayout.space(context, 20),
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: EchoLayout.space(context, 10),
                      crossAxisSpacing: EchoLayout.space(context, 10),
                      childAspectRatio: 0.88,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final hashtag = allHashtags[index];
                        return _StationCard(
                          hashtag: hashtag,
                          onTap: () => _openStation(hashtag),
                        );
                      },
                      childCount: allHashtags.length,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Header with ambient glow ──

class _ListenHeader extends StatelessWidget {
  const _ListenHeader({required this.contentPadding});

  final double contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final topSafe = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        contentPadding,
        topSafe + EchoLayout.space(context, 18),
        contentPadding,
        EchoLayout.space(context, 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Listen',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Browse stations and discover voices.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ──

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

// ── Recent station chip (compact horizontal) ──

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.station, required this.onTap});

  final Hashtag station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final accentColor = Color.lerp(station.color, tokens.surface2, 0.35)!;
    final noteLabel = '${station.noteCount}';

    return Material(
      color: accentColor,
      borderRadius: BorderRadius.circular(EchoRadii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStateProperty.all(
          EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                station.icon,
                size: 16,
                color: tokens.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                station.name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                noteLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tokens.textPrimary.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Station card (vertical grid) ──

class _StationCard extends StatelessWidget {
  const _StationCard({required this.hashtag, required this.onTap});

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
        Color.lerp(hashtag.color, tokens.surface2, 0.22)!,
        Color.lerp(tokens.surface1, hashtag.color, 0.28)!,
      ],
    );
    final noteLabel = hashtag.noteCount == 1
        ? '1 note'
        : '${hashtag.noteCount} notes';

    return EchoGradientCard(
      onTap: onTap,
      radius: 20,
      gradient: gradient,
      glow: true,
      overlayColor: EchoColorUtils.pressedOverlay(tokens.surface1, alpha: 0.14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon with visible accent ring
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.surface2.withValues(alpha: 0.55),
              border: Border.all(
                color: tokens.textPrimary.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Icon(
              hashtag.icon,
              size: 22,
              color: tokens.textPrimary,
            ),
          ),
          const Spacer(),
          // Station name
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
          // Description
          Text(
            hashtag.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textPrimary.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          // Note count
          Text(
            noteLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.textPrimary.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ──

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final String title;
  final String subtitle;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: EchoLayout.contentHorizontalPadding(context) + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headphones_rounded,
              size: 40,
              color: tokens.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 120,
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
