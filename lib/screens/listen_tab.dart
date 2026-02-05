import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import '../models/hashtag.dart';
import '../utils/responsive.dart';
import '../widgets/echo_components.dart';

class ListenTab extends StatefulWidget {
  const ListenTab({super.key});

  @override
  State<ListenTab> createState() => _ListenTabState();
}

class _ListenTabState extends State<ListenTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentHorizontalPadding = EchoLayout.contentHorizontalPadding(
      context,
    );
    final tokens = context.echo;
    final searchBottomSpacing = EchoLayout.space(context, 8);
    final gridSpacing = EchoLayout.space(context, 10);
    final appState = AppScope.of(context);
    final allHashtags = appState.hashtags;
    final isLoading = appState.hashtagsLoading;
    final loadError = appState.hashtagsError;
    final filtered = _query.isEmpty
        ? allHashtags
        : allHashtags
              .where(
                (tag) =>
                    tag.name.toLowerCase().contains(_query.toLowerCase()) ||
                    tag.description.toLowerCase().contains(
                      _query.toLowerCase(),
                    ),
              )
              .toList();

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
          titleSpacing: contentHorizontalPadding,
          title: Text('Listen', style: theme.textTheme.displaySmall),
          toolbarHeight: EchoLayout.space(context, 54),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              EchoLayout.space(context, 62),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                contentHorizontalPadding,
                0,
                contentHorizontalPadding,
                searchBottomSpacing,
              ),
              child: EchoInput(
                controller: _searchController,
                hintText: 'Search moods, tones',
                prefixIcon: Icons.search,
                onChanged: _onSearchChanged,
              ),
            ),
          ),
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
        else if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              title: 'No matches yet',
              subtitle: 'Try a different search phrase.',
              onRetry: () {
                _searchController.clear();
                _onSearchChanged('');
              },
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final usableWidth = width - (contentHorizontalPadding * 2);
              final targetTileWidth = 180.0;
              final crossAxisCount =
                  (usableWidth / targetTileWidth).floor().clamp(2, 3);
              final aspectRatio = crossAxisCount == 2 ? 0.9 : 1.05;
              return SliverPadding(
                padding: EchoLayout.listPadding(
                  context,
                  top: 6,
                  bottom: 12,
                  includeBottomSafeArea: true,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: gridSpacing,
                    crossAxisSpacing: gridSpacing,
                    childAspectRatio: aspectRatio,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final hashtag = filtered[index];
                      return _HashtagGridCard(
                        hashtag: hashtag,
                        onTap: () => context.push('/hashtag/${hashtag.id}'),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              );
            },
          ),
      ],
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

class _HashtagGridCard extends StatelessWidget {
  const _HashtagGridCard({
    required this.hashtag,
    required this.onTap,
  });

  final Hashtag hashtag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final cardGradient = EchoGradients.hashtagCard(tokens, theme.brightness);

    return EchoGradientCard(
      onTap: onTap,
      radius: 22,
      glow: true,
      padding: const EdgeInsets.all(16),
      gradient: cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                hashtag.icon,
                size: 28,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(hashtag.name, style: theme.textTheme.titleMedium),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              hashtag.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
