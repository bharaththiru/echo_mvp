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
    final screenWidth = MediaQuery.of(context).size.width;
    final contentHorizontalPadding = EchoLayout.contentHorizontalPadding(
      context,
    );
    final topSpacing = EchoLayout.space(context, 8);
    final sectionSpacing = EchoLayout.space(context, 8);
    final itemSpacing = EchoLayout.space(context, 6);
    final blockSpacing = EchoLayout.space(context, 12);
    final bottomSpacing = EchoLayout.space(context, 10);
    final safeTopInset = MediaQuery.paddingOf(context).top;
    final availableWidth = screenWidth;
    final cardWidth =
        (availableWidth * 0.75).clamp(180.0, 240.0).toDouble();
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

    final forYourVibe = filtered.take(3).toList();
    final popularNow = filtered.skip(3).take(4).toList();
    final newAndNiche = filtered.skip(7).toList();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            contentHorizontalPadding,
            safeTopInset + topSpacing,
            contentHorizontalPadding,
            sectionSpacing,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Listen', style: theme.textTheme.displaySmall),
              SizedBox(height: sectionSpacing),
              EchoInput(
                controller: _searchController,
                hintText: 'Search moods, tones',
                prefixIcon: Icons.search,
                onChanged: _onSearchChanged,
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (isLoading && allHashtags.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (loadError != null && allHashtags.isEmpty) {
                return _EmptyState(
                  title: 'Unable to load hashtags',
                  subtitle: loadError,
                  onRetry: () => appState.refreshHashtags(force: true),
                );
              }
              if (allHashtags.isEmpty) {
                return _EmptyState(
                  title: 'No hashtags yet',
                  subtitle: 'Add hashtags in Firebase to get started.',
                  onRetry: () => appState.refreshHashtags(force: true),
                );
              }

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (_query.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        contentHorizontalPadding,
                        0,
                        contentHorizontalPadding,
                        bottomSpacing,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const EchoSectionTitle('Your matches'),
                          SizedBox(height: sectionSpacing),
                          ...filtered.map(
                            (hashtag) => Padding(
                              padding: EdgeInsets.only(bottom: itemSpacing),
                              child: _HashtagListTile(
                                hashtag: hashtag,
                                onTap: () =>
                                    context.push('/hashtag/${hashtag.id}'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    if (forYourVibe.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          contentHorizontalPadding,
                          0,
                          contentHorizontalPadding,
                          sectionSpacing,
                        ),
                        child: const EchoSectionTitle('Set the tone'),
                      ),
                      SizedBox(
                        height: 200,
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            final hashtag = forYourVibe[index];
                            return _HashtagCard(
                              hashtag: hashtag,
                              moodTintEnabled:
                                  appState.settings.moodTintEnabled,
                              onTap: () =>
                                  context.push('/hashtag/${hashtag.id}'),
                              width: cardWidth,
                            );
                          },
                          separatorBuilder: (context, index) =>
                              SizedBox(width: blockSpacing),
                          itemCount: forYourVibe.length,
                        ),
                      ),
                      SizedBox(height: blockSpacing),
                    ],
                    if (popularNow.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          contentHorizontalPadding,
                          0,
                          contentHorizontalPadding,
                          bottomSpacing,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const EchoSectionTitle('Slow drift'),
                            SizedBox(height: sectionSpacing),
                            ...popularNow.map(
                              (hashtag) => Padding(
                                padding: EdgeInsets.only(bottom: itemSpacing),
                                child: _HashtagListTile(
                                  hashtag: hashtag,
                                  onTap: () =>
                                      context.push('/hashtag/${hashtag.id}'),
                                ),
                              ),
                            ),
                            SizedBox(height: sectionSpacing),
                          ],
                        ),
                      ),
                    ],
                    if (newAndNiche.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          contentHorizontalPadding,
                          0,
                          contentHorizontalPadding,
                          bottomSpacing,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const EchoSectionTitle('Quiet corners'),
                            SizedBox(height: sectionSpacing),
                            _HashtagGrid(
                              hashtags: newAndNiche,
                              onTap: (hashtag) =>
                                  context.push('/hashtag/${hashtag.id}'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  SizedBox(height: bottomSpacing),
                ],
              );
            },
          ),
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

class _HashtagCard extends StatelessWidget {
  const _HashtagCard({
    required this.hashtag,
    required this.moodTintEnabled,
    required this.onTap,
    required this.width,
  });

  final Hashtag hashtag;
  final bool moodTintEnabled;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final tint = hashtag.gradient.first;
    final cardColor = moodTintEnabled
        ? Color.lerp(tokens.surface1, tint, 0.55) ?? tokens.surface1
        : tokens.surface1;
    final borderColor = moodTintEnabled
        ? tint.withValues(alpha: 0.6)
        : tokens.borderSubtle;

    return SizedBox(
      width: width,
      child: EchoCard(
        onTap: onTap,
        radius: 24,
        padding: const EdgeInsets.all(18),
        color: cardColor,
        borderColor: borderColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(hashtag.icon, size: 34, color: tokens.accentPrimary),
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.accentPrimary.withValues(alpha: 0.16),
                    border: Border.all(
                      color: tokens.accentPrimary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(Icons.play_arrow, color: tokens.accentPrimary),
                ),
              ],
            ),
            const Spacer(),
            Text(hashtag.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              hashtag.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HashtagListTile extends StatelessWidget {
  const _HashtagListTile({required this.hashtag, required this.onTap});

  final Hashtag hashtag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;

    return EchoCard(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              color: tokens.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Icon(hashtag.icon, color: tokens.accentPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hashtag.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  hashtag.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.accentPrimary.withValues(alpha: 0.16),
              border: Border.all(
                color: tokens.accentPrimary.withValues(alpha: 0.32),
              ),
            ),
            child: Icon(
              Icons.play_arrow,
              color: tokens.accentPrimary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _HashtagGrid extends StatelessWidget {
  const _HashtagGrid({required this.hashtags, required this.onTap});

  final List<Hashtag> hashtags;
  final ValueChanged<Hashtag> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 360 ? 1 : 2;
        final childAspectRatio = crossAxisCount == 1 ? 2.2 : 1.1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: hashtags.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) {
            final hashtag = hashtags[index];
            return EchoCard(
              onTap: () => onTap(hashtag),
              radius: 18,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(hashtag.icon, color: tokens.accentPrimary, size: 28),
                  const Spacer(),
                  Text(hashtag.name, style: theme.textTheme.titleMedium),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
