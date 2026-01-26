import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/theme.dart';
import '../models/hashtag.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';

class PostOptions extends StatefulWidget {
  const PostOptions({super.key});

  @override
  State<PostOptions> createState() => _PostOptionsState();
}

class _PostOptionsState extends State<PostOptions> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();

  Hashtag? _selectedHashtag;
  bool _allowReplies = false;
  bool _disappearIn24h = false;
  String _query = '';
  bool _isPosting = false;
  bool _draftApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = AppScope.of(context);
    if (appState.hashtags.isEmpty && !appState.hashtagsLoading) {
      appState.refreshHashtags();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_isPosting) {
      return;
    }
    final appState = AppScope.of(context);
    if (appState.isPosting) {
      return;
    }
    final recordingPath = appState.pendingRecordingPath;
    if (recordingPath == null || recordingPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No recording found. Please record again.'),
        ),
      );
      return;
    }

    final hashtag = _selectedHashtag;
    if (hashtag == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a hashtag to post.')),
      );
      return;
    }

    if (!appState.isAuthenticated && !appState.skipAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sign in required to post.'),
          action: SnackBarAction(
            label: 'Sign in',
            onPressed: () => context.push('/auth'),
          ),
        ),
      );
      return;
    }

    setState(() => _isPosting = true);
    try {
      final note = await appState.postNote(
        recordingPath: recordingPath,
        hashtag: hashtag,
        allowReplies: _allowReplies,
        expiresIn24h: _disappearIn24h,
        caption: _captionController.text.isEmpty
            ? null
            : _captionController.text,
      );
      appState.addSavedHashtag(hashtag.name);
      appState.clearPendingRecording();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Posted ${formatRelativeTime(note.createdAt)}.'),
        ),
      );
      context.go('/listen');
    } on PostException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to post right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = AppScope.of(context);
    final hashtags = appState.hashtags;
    final posting = _isPosting || appState.isPosting;
    final pendingDraft = appState.pendingPostDraft;
    if (!_draftApplied && pendingDraft != null && hashtags.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _draftApplied) {
          return;
        }
        final selected = hashtags.firstWhere(
          (tag) => tag.id == pendingDraft.hashtagId,
          orElse: () => hashtags.first,
        );
        if (appState.pendingRecordingPath == null ||
            appState.pendingRecordingPath!.isEmpty) {
          appState.setPendingRecordingPath(pendingDraft.recordingPath);
        }
        setState(() {
          _selectedHashtag = selected;
          _allowReplies = pendingDraft.allowReplies;
          _disappearIn24h = pendingDraft.expiresIn24h;
          if (_captionController.text.isEmpty &&
              pendingDraft.caption != null) {
            _captionController.text = pendingDraft.caption!;
          }
          _draftApplied = true;
        });
      });
    } else if (_selectedHashtag == null && hashtags.isNotEmpty) {
      final saved = appState.savedHashtags.toSet();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedHashtag = hashtags.firstWhere(
            (tag) => saved.contains(tag.name),
            orElse: () {
              return hashtags.first;
            },
          );
        });
      });
    }
    final hashtagsError = appState.hashtagsError;
    final tags = hashtags.map((tag) => tag.name).toList();
    final filteredHashtags = tags.where((tag) {
      if (_query.isEmpty) {
        return true;
      }
      return tag.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return AppScaffold(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                const SizedBox(height: 12),
                Text('Post details', style: theme.textTheme.displaySmall),
                const SizedBox(height: 8),
                Text(
                  'No likes. No public comments. This is just a voice note.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: EchoColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                if (pendingDraft != null)
                  EchoCard(
                    padding: const EdgeInsets.all(16),
                    radius: 18,
                    color: EchoColors.muted,
                    borderColor: EchoColors.borderSubtle,
                    child: Text(
                      'Pending upload detected. You can retry posting this clip.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: EchoColors.textSecondary,
                      ),
                    ),
                  ),
                if (pendingDraft != null) const SizedBox(height: 16),
                Text('Choose one hashtag', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Required',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: EchoColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                EchoInput(
                  controller: _searchController,
                  hintText: 'Search hashtags...',
                  prefixIcon: Icons.search,
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
                const SizedBox(height: 16),
                Text(
                  'Suggested',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: EchoColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                if (hashtags.isEmpty)
                  EchoCard(
                    padding: const EdgeInsets.all(16),
                    radius: 18,
                    color: EchoColors.muted,
                    child: Text(
                      hashtagsError ??
                          'Hashtags are loading. Please try again shortly.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: EchoColors.textSecondary,
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: filteredHashtags.map((tag) {
                      final isSelected = _selectedHashtag?.name == tag;
                      final backgroundColor = isSelected
                          ? EchoColors.accent
                          : EchoColors.surface;
                      final borderColor = isSelected
                          ? EchoColors.accent.withValues(alpha: 0.75)
                          : EchoColors.borderSubtle;
                      final textColor = isSelected
                          ? EchoColors.background
                          : EchoColors.textPrimary;
                      return GestureDetector(
                        onTap: () {
                          final selected = hashtags.firstWhere(
                            (item) => item.name == tag,
                          );
                          setState(() => _selectedHashtag = selected);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: borderColor),
                          ),
                          child: Text(
                            tag,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),
                Text('Title or caption', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Optional - Max 60 characters',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: EchoColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                EchoInput(
                  controller: _captionController,
                  maxLength: 60,
                  hintText: 'Add a short title...',
                ),
                const SizedBox(height: 12),
                EchoCard(
                  padding: const EdgeInsets.all(16),
                  radius: 18,
                  color: EchoColors.muted,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Allow private replies',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Others can send you a private 12s reply',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: EchoColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _allowReplies,
                        onChanged: (value) =>
                            setState(() => _allowReplies = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                EchoCard(
                  padding: const EdgeInsets.all(16),
                  radius: 18,
                  color: EchoColors.muted,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Disappear after 24 hours',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your note will be automatically removed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: EchoColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _disappearIn24h,
                        onChanged: (value) =>
                            setState(() => _disappearIn24h = value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: EchoPrimaryButton(
              label: 'Post',
              isLoading: posting,
              onPressed: _selectedHashtag == null ? null : _post,
            ),
          ),
        ],
      ),
    );
  }
}
