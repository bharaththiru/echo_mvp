import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hashtag.dart';
import '../models/voice_note.dart';
import 'autoplay_feed_queue_builder.dart';
import 'firebase_repository.dart';
import 'moderation_service.dart';

class FeedService implements AutoplayFeedQueueBuilder {
  FeedService({
    required SharedPreferences prefs,
    required FirebaseRepository repository,
    required ModerationService moderation,
    required String? Function() userId,
    required bool Function() isDevUnauthed,
    required void Function() onStateChanged,
    required List<String> initialSavedHashtags,
    required List<String> initialRecentHashtagIds,
  }) : _prefs = prefs,
       _repository = repository,
       _moderation = moderation,
       _userId = userId,
       _isDevUnauthed = isDevUnauthed,
       _onStateChanged = onStateChanged,
       savedHashtags = List<String>.from(initialSavedHashtags),
       recentHashtagIds = List<String>.from(initialRecentHashtagIds);

  static const _savedHashtagsKey = 'saved_hashtags';
  static const _recentHashtagIdsKey = 'recent_hashtag_ids';
  static const _localFeedCursorPrefix = 'local:';
  static const _autoplayFeedWindow = 50;
  static const _remoteFeedTransientCooldown = Duration(seconds: 45);
  static const _remoteFeedPolicyCooldown = Duration(minutes: 10);

  final SharedPreferences _prefs;
  final FirebaseRepository _repository;
  final ModerationService _moderation;
  final String? Function() _userId;
  final bool Function() _isDevUnauthed;
  final void Function() _onStateChanged;

  final List<Hashtag> _hashtags = [];
  final Map<String, List<VoiceNote>> _notesByHashtag = {};
  final Map<String, List<VoiceNote>> _localDevNotesByHashtag = {};
  final Map<String, bool> _notesRemoteAttempted = {};
  final Map<String, bool> _notesLoading = {};
  final Map<String, String?> _notesError = {};
  List<VoiceNote> _myPosts = [];
  bool _hashtagsLoading = false;
  bool _myPostsLoading = false;
  String? _hashtagsError;
  String? _myPostsError;
  DateTime? _remoteFeedCooldownUntil;

  List<String> savedHashtags;
  List<String> recentHashtagIds;

  // ── Snapshot initialisation ───────────────────────────────────────────────

  void initFromSnapshot({
    required List<Hashtag> hashtags,
    required Map<String, List<VoiceNote>> notesByHashtag,
  }) {
    _hashtags
      ..clear()
      ..addAll(hashtags);
    _notesByHashtag
      ..clear()
      ..addAll(notesByHashtag);
    _notesLoading.clear();
    _notesError.clear();
  }

  // ── Hashtag accessors ─────────────────────────────────────────────────────

  List<Hashtag> get hashtags => List<Hashtag>.unmodifiable(_hashtags);

  bool get hashtagsLoading => _hashtagsLoading;

  String? get hashtagsError => _hashtagsError;

  Hashtag? hashtagById(String id) {
    for (final tag in _hashtags) {
      if (tag.id == id) {
        return tag;
      }
    }
    return null;
  }

  // ── Hashtag preferences ───────────────────────────────────────────────────

  void addSavedHashtag(String tag) {
    if (savedHashtags.contains(tag)) {
      return;
    }
    savedHashtags = [...savedHashtags, tag];
    _prefs.setStringList(_savedHashtagsKey, savedHashtags);
    _onStateChanged();
  }

  void setSavedHashtags(List<String> tags) {
    savedHashtags = List<String>.from(tags);
    _prefs.setStringList(_savedHashtagsKey, savedHashtags);
  }

  void markStationListened(String hashtagId) {
    final normalized = hashtagId.trim();
    if (normalized.isEmpty) {
      return;
    }
    final reordered = [
      normalized,
      ...recentHashtagIds.where((id) => id != normalized),
    ];
    const maxRecent = 20;
    final trimmed =
        reordered.length > maxRecent ? reordered.sublist(0, maxRecent) : reordered;
    if (_sameList(recentHashtagIds, trimmed)) {
      return;
    }
    recentHashtagIds = trimmed;
    _prefs.setStringList(_recentHashtagIdsKey, recentHashtagIds);
    _onStateChanged();
  }

  // ── Hashtag ops ───────────────────────────────────────────────────────────

  Future<void> refreshHashtags({bool force = false}) async {
    if (_hashtagsLoading) {
      return;
    }
    if (!force && _hashtags.isNotEmpty) {
      return;
    }
    _hashtagsLoading = true;
    _hashtagsError = null;
    _onStateChanged();
    try {
      final fetched = await _repository.fetchHashtags();
      _hashtags
        ..clear()
        ..addAll(fetched);
      _syncSavedHashtags();
      _syncRecentHashtags();
    } catch (_) {
      _hashtagsError = 'Unable to load hashtags.';
    } finally {
      _hashtagsLoading = false;
      _onStateChanged();
    }
  }

  void _syncSavedHashtags() {
    if (_hashtags.isEmpty) {
      return;
    }
    final available = _hashtags.map((tag) => tag.name).toSet();
    final filtered = savedHashtags.where(available.contains).toList();
    if (filtered.isEmpty) {
      savedHashtags = _hashtags.take(3).map((tag) => tag.name).toList();
      _prefs.setStringList(_savedHashtagsKey, savedHashtags);
      return;
    }
    if (filtered.length != savedHashtags.length) {
      savedHashtags = filtered;
      _prefs.setStringList(_savedHashtagsKey, savedHashtags);
    }
  }

  void _syncRecentHashtags() {
    if (_hashtags.isEmpty || recentHashtagIds.isEmpty) {
      return;
    }
    final available = _hashtags.map((tag) => tag.id).toSet();
    final filtered = recentHashtagIds.where(available.contains).toList();
    if (filtered.length != recentHashtagIds.length) {
      recentHashtagIds = filtered;
      _prefs.setStringList(_recentHashtagIdsKey, recentHashtagIds);
    }
  }

  List<Hashtag> recentHashtags({int limit = 6}) {
    if (_hashtags.isEmpty || limit <= 0) {
      return const [];
    }
    final byId = {for (final tag in _hashtags) tag.id: tag};
    final seen = <String>{};
    final resolved = <Hashtag>[];
    for (final id in recentHashtagIds) {
      final tag = byId[id];
      if (tag == null || seen.contains(tag.id)) {
        continue;
      }
      resolved.add(tag);
      seen.add(tag.id);
      if (resolved.length >= limit) {
        return resolved;
      }
    }
    if (resolved.isNotEmpty) {
      return resolved;
    }
    final fallback = List<Hashtag>.from(_hashtags)
      ..sort((a, b) {
        final countOrder = b.noteCount.compareTo(a.noteCount);
        if (countOrder != 0) {
          return countOrder;
        }
        return a.name.compareTo(b.name);
      });
    if (fallback.length > limit) {
      return fallback.sublist(0, limit);
    }
    return fallback;
  }

  // ── Note accessors ────────────────────────────────────────────────────────

  List<VoiceNote> notesForHashtag(String hashtagId) {
    final notes = _notesByHashtag[hashtagId] ?? <VoiceNote>[];
    return List<VoiceNote>.from(_filterNotes(notes));
  }

  bool isLoadingNotes(String hashtagId) => _notesLoading[hashtagId] ?? false;

  String? notesError(String hashtagId) => _notesError[hashtagId];

  List<VoiceNote> userPosts() {
    final notes = List<VoiceNote>.from(_myPosts);
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  bool get myPostsLoading => _myPostsLoading;

  String? get myPostsError => _myPostsError;

  // ── Note ops ──────────────────────────────────────────────────────────────

  Future<void> loadNotesForHashtag(
    String hashtagId, {
    bool force = false,
  }) async {
    if (_notesLoading[hashtagId] == true) {
      return;
    }
    if (!force && (_notesRemoteAttempted[hashtagId] ?? false)) {
      return;
    }
    if (force) {
      _notesRemoteAttempted[hashtagId] = false;
    }
    _notesLoading[hashtagId] = true;
    _notesError[hashtagId] = null;
    _onStateChanged();
    try {
      final notes = await _repository.fetchNotes(hashtagId: hashtagId);
      _notesByHashtag[hashtagId] = _mergeLocalDevNotes(hashtagId, notes);
    } catch (_) {
      final localNotes = _localDevNotesByHashtag[hashtagId] ?? const [];
      if (localNotes.isNotEmpty) {
        _notesByHashtag[hashtagId] = _mergeLocalDevNotes(hashtagId, const []);
        _notesError[hashtagId] = null;
      } else {
        _notesError[hashtagId] = 'Unable to load notes.';
      }
    } finally {
      _notesLoading[hashtagId] = false;
      _notesRemoteAttempted[hashtagId] = true;
      _onStateChanged();
    }
  }

  Future<void> refreshMyPosts({bool force = false}) async {
    if (_myPostsLoading) {
      return;
    }
    if (!force && _myPosts.isNotEmpty) {
      return;
    }
    final currentUser = _userId();
    if (currentUser == null) {
      if (_isDevUnauthed()) {
        final local = _localDevNotesByHashtag.values
            .expand((notes) => notes)
            .toList();
        local.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _myPosts = _filterNotes(local);
      } else {
        _myPosts = [];
      }
      _myPostsError = null;
      _onStateChanged();
      return;
    }
    _myPostsLoading = true;
    _myPostsError = null;
    _onStateChanged();
    try {
      final posts = await _repository.fetchNotes(
        authorId: currentUser,
        limit: 12,
      );
      final local = _localDevNotesByHashtag.values
          .expand((notes) => notes)
          .toList();
      if (local.isEmpty) {
        _myPosts = _filterNotes(posts);
      } else {
        final mergedById = <String, VoiceNote>{};
        for (final note in posts) {
          mergedById[note.id] = note;
        }
        for (final note in local) {
          mergedById[note.id] = note;
        }
        final merged = mergedById.values.toList();
        merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _myPosts = _filterNotes(merged);
      }
    } catch (_) {
      _myPostsError = 'Unable to load your posts.';
    } finally {
      _myPostsLoading = false;
      _onStateChanged();
    }
  }

  // ── Cache mutation ────────────────────────────────────────────────────────

  void cacheNote(VoiceNote note, {bool localOnly = false}) {
    if (localOnly) {
      final localExisting =
          _localDevNotesByHashtag[note.hashtagId] ?? const <VoiceNote>[];
      final localUpdated = List<VoiceNote>.from(localExisting);
      localUpdated.removeWhere((item) => item.id == note.id);
      localUpdated.insert(0, note);
      _localDevNotesByHashtag[note.hashtagId] = localUpdated;
    }
    final existing = _notesByHashtag[note.hashtagId] ?? <VoiceNote>[];
    final updated = List<VoiceNote>.from(existing);
    updated.removeWhere((item) => item.id == note.id);
    updated.insert(0, note);
    _notesByHashtag[note.hashtagId] = updated;
    final isMine = note.authorId == _userId() || (localOnly && _isDevUnauthed());
    if (isMine) {
      final mine = List<VoiceNote>.from(_myPosts);
      mine.removeWhere((item) => item.id == note.id);
      mine.insert(0, note);
      _myPosts = mine;
    }
    _onStateChanged();
  }

  void replaceNote(VoiceNote note) {
    final localByTag = _localDevNotesByHashtag[note.hashtagId];
    if (localByTag != null) {
      final updatedLocal = List<VoiceNote>.from(localByTag);
      final localIndex = updatedLocal.indexWhere((item) => item.id == note.id);
      if (localIndex != -1) {
        updatedLocal[localIndex] = note;
        _localDevNotesByHashtag[note.hashtagId] = updatedLocal;
      }
    }
    final byTag = _notesByHashtag[note.hashtagId];
    if (byTag != null) {
      final updated = List<VoiceNote>.from(byTag);
      final index = updated.indexWhere((item) => item.id == note.id);
      if (index != -1) {
        updated[index] = note;
        _notesByHashtag[note.hashtagId] = updated;
      }
    }
    final mineIndex = _myPosts.indexWhere((item) => item.id == note.id);
    if (mineIndex != -1) {
      final updatedMine = List<VoiceNote>.from(_myPosts);
      updatedMine[mineIndex] = note;
      _myPosts = updatedMine;
    }
    _onStateChanged();
  }

  void removeNoteById(String noteId) {
    if (noteId.isEmpty) {
      return;
    }
    for (final entry in _notesByHashtag.entries) {
      _notesByHashtag[entry.key] =
          entry.value.where((note) => note.id != noteId).toList();
    }
    for (final entry in _localDevNotesByHashtag.entries) {
      _localDevNotesByHashtag[entry.key] =
          entry.value.where((note) => note.id != noteId).toList();
    }
    _myPosts = _myPosts.where((note) => note.id != noteId).toList();
  }

  void removeNotesByAuthor(String authorId) {
    if (authorId.isEmpty) {
      return;
    }
    for (final entry in _notesByHashtag.entries) {
      _notesByHashtag[entry.key] =
          entry.value.where((note) => note.authorId != authorId).toList();
    }
    for (final entry in _localDevNotesByHashtag.entries) {
      _localDevNotesByHashtag[entry.key] =
          entry.value.where((note) => note.authorId != authorId).toList();
    }
    _myPosts = _myPosts.where((note) => note.authorId != authorId).toList();
  }

  // ── AutoplayFeedQueueBuilder ──────────────────────────────────────────────

  @override
  Future<AutoplayFeedPage> loadPage({
    required String stationId,
    required int limit,
    String? cursor,
  }) async {
    final normalizedStationId = stationId.trim();
    if (normalizedStationId.isEmpty || limit <= 0) {
      return const AutoplayFeedPage(
        stationId: '',
        notes: <VoiceNote>[],
        nextCursor: null,
        hasMore: false,
      );
    }
    if (_isDevUnauthed()) {
      final local = _localFeedPage(
        stationId: normalizedStationId,
        limit: max(limit, _autoplayFeedWindow),
        cursor: cursor,
      );
      final shuffled = _buildDeterministicFeedSlice(
        notes: _filterNotes(local.notes),
        stationId: normalizedStationId,
        cursor: cursor,
        take: limit,
      );
      return AutoplayFeedPage(
        stationId: normalizedStationId,
        notes: shuffled,
        nextCursor: local.nextCursor,
        hasMore: local.hasMore,
      );
    }
    final window = max(limit, _autoplayFeedWindow);
    if (_isRemoteFeedCoolingDown) {
      final fallback = _localFeedPage(
        stationId: normalizedStationId,
        limit: window,
        cursor: cursor,
      );
      final shuffled = _buildDeterministicFeedSlice(
        notes: _filterNotes(fallback.notes),
        stationId: normalizedStationId,
        cursor: cursor,
        take: limit,
      );
      return AutoplayFeedPage(
        stationId: normalizedStationId,
        notes: shuffled,
        nextCursor: fallback.nextCursor,
        hasMore: fallback.hasMore,
      );
    }
    try {
      final page = await _repository.fetchHashtagFeedPage(
        hashtagId: normalizedStationId,
        limit: window,
        cursor: cursor,
      );
      _recordRemoteFeedSuccess();
      final filtered = _filterNotes(page.notes);
      final shuffled = _buildDeterministicFeedSlice(
        notes: filtered,
        stationId: normalizedStationId,
        cursor: cursor,
        take: limit,
      );
      if (shuffled.isEmpty && (cursor == null || cursor.isEmpty)) {
        final fallback = _localFeedPage(
          stationId: normalizedStationId,
          limit: window,
          cursor: cursor,
        );
        final fallbackShuffled = _buildDeterministicFeedSlice(
          notes: _filterNotes(fallback.notes),
          stationId: normalizedStationId,
          cursor: cursor,
          take: limit,
        );
        if (fallbackShuffled.isNotEmpty) {
          return AutoplayFeedPage(
            stationId: normalizedStationId,
            notes: fallbackShuffled,
            nextCursor: fallback.nextCursor,
            hasMore: fallback.hasMore,
          );
        }
      }
      return AutoplayFeedPage(
        stationId: normalizedStationId,
        notes: shuffled,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } catch (error) {
      _recordRemoteFeedFailure(error);
      final fallback = _localFeedPage(
        stationId: normalizedStationId,
        limit: window,
        cursor: cursor,
      );
      final shuffled = _buildDeterministicFeedSlice(
        notes: _filterNotes(fallback.notes),
        stationId: normalizedStationId,
        cursor: cursor,
        take: limit,
      );
      if (fallback.notes.isNotEmpty || cursor == null || cursor.isEmpty) {
        return AutoplayFeedPage(
          stationId: normalizedStationId,
          notes: shuffled,
          nextCursor: fallback.nextCursor,
          hasMore: fallback.hasMore,
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<String>> fallbackStationIds({
    required String currentStationId,
    int limit = 6,
  }) async {
    final normalizedCurrent = currentStationId.trim();
    if (limit <= 0) {
      return const <String>[];
    }
    final resolved = <String>[];
    final seen = <String>{};
    bool addCandidate(String id) {
      final normalized = id.trim();
      if (normalized.isEmpty ||
          normalized == normalizedCurrent ||
          seen.contains(normalized)) {
        return false;
      }
      final cachedNotes = _localFeedPage(
        stationId: normalized,
        limit: 1,
        cursor: null,
      );
      if (cachedNotes.notes.isEmpty) {
        return false;
      }
      resolved.add(normalized);
      seen.add(normalized);
      return resolved.length >= limit;
    }

    for (final id in recentHashtagIds) {
      if (addCandidate(id)) {
        return resolved;
      }
    }
    for (final id in _notesByHashtag.keys) {
      if (addCandidate(id)) {
        return resolved;
      }
    }
    for (final id in _localDevNotesByHashtag.keys) {
      if (addCandidate(id)) {
        return resolved;
      }
    }

    if (_isRemoteFeedCoolingDown) {
      return resolved;
    }

    for (final id in recentHashtagIds) {
      final normalized = id.trim();
      if (normalized.isEmpty ||
          normalized == normalizedCurrent ||
          seen.contains(normalized)) {
        continue;
      }
      resolved.add(normalized);
      seen.add(normalized);
      if (resolved.length >= limit) {
        return resolved;
      }
    }
    final trending = List<Hashtag>.from(_hashtags)
      ..sort((a, b) {
        final byCount = b.noteCount.compareTo(a.noteCount);
        if (byCount != 0) {
          return byCount;
        }
        return a.name.compareTo(b.name);
      });
    for (final hashtag in trending) {
      final id = hashtag.id.trim();
      if (id.isEmpty || id == normalizedCurrent || seen.contains(id)) {
        continue;
      }
      resolved.add(id);
      seen.add(id);
      if (resolved.length >= limit) {
        break;
      }
    }
    return resolved;
  }

  // ── Remote feed cooldown ──────────────────────────────────────────────────

  bool get _isRemoteFeedCoolingDown {
    final until = _remoteFeedCooldownUntil;
    if (until == null) {
      return false;
    }
    return DateTime.now().isBefore(until);
  }

  void _recordRemoteFeedFailure(Object error) {
    final cooldown = _isPolicyFeedFailure(error)
        ? _remoteFeedPolicyCooldown
        : _remoteFeedTransientCooldown;
    _remoteFeedCooldownUntil = DateTime.now().add(cooldown);
  }

  void _recordRemoteFeedSuccess() {
    _remoteFeedCooldownUntil = null;
  }

  bool _isPolicyFeedFailure(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      return code == 'permission-denied' || code == 'failed-precondition';
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('permission-denied') ||
        raw.contains('failed-precondition') ||
        raw.contains('failed_precondition') ||
        raw.contains('missing or insufficient permissions') ||
        raw.contains('requires an index');
  }

  // ── Local feed helpers ────────────────────────────────────────────────────

  AutoplayFeedPage _localFeedPage({
    required String stationId,
    required int limit,
    String? cursor,
  }) {
    final mergedById = <String, VoiceNote>{};
    for (final note in _notesByHashtag[stationId] ?? const <VoiceNote>[]) {
      mergedById[note.id] = note;
    }
    for (final note
        in _localDevNotesByHashtag[stationId] ?? const <VoiceNote>[]) {
      mergedById[note.id] = note;
    }
    final sorted = _filterNotes(mergedById.values.toList())
      ..sort((a, b) {
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) {
          return byCreated;
        }
        return b.id.compareTo(a.id);
      });
    final start = _decodeLocalFeedCursor(cursor);
    if (start >= sorted.length) {
      return AutoplayFeedPage(
        stationId: stationId,
        notes: const <VoiceNote>[],
        nextCursor: null,
        hasMore: false,
      );
    }
    final end = min(start + limit, sorted.length);
    final notes = sorted.sublist(start, end);
    final hasMore = end < sorted.length;
    final nextCursor = hasMore ? '$_localFeedCursorPrefix$end' : null;
    return AutoplayFeedPage(
      stationId: stationId,
      notes: notes,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  int _decodeLocalFeedCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) {
      return 0;
    }
    if (!cursor.startsWith(_localFeedCursorPrefix)) {
      return 0;
    }
    final rawOffset = cursor.substring(_localFeedCursorPrefix.length);
    final offset = int.tryParse(rawOffset);
    if (offset == null || offset < 0) {
      return 0;
    }
    return offset;
  }

  List<VoiceNote> _buildDeterministicFeedSlice({
    required List<VoiceNote> notes,
    required String stationId,
    required String? cursor,
    required int take,
  }) {
    if (notes.isEmpty || take <= 0) {
      return const <VoiceNote>[];
    }
    if (notes.length <= 1) {
      return notes.take(take).toList();
    }
    final seed = '${stationId.trim()}|${cursor ?? 'root'}';
    final candidates = List<_FeedShuffleCandidate>.generate(notes.length, (
      index,
    ) {
      final note = notes[index];
      final hash = _stableFeedHash('$seed|${note.id}|$index');
      return _FeedShuffleCandidate(note: note, hash: hash, sourceIndex: index);
    })..sort((a, b) {
      final byHash = a.hash.compareTo(b.hash);
      if (byHash != 0) {
        return byHash;
      }
      return a.sourceIndex.compareTo(b.sourceIndex);
    });
    final selected = <VoiceNote>[];
    final usedIds = <String>{};
    String? lastAuthor;
    final pool = List<_FeedShuffleCandidate>.from(candidates);
    while (selected.length < take && pool.isNotEmpty) {
      int pick = -1;
      for (var i = 0; i < pool.length; i++) {
        final candidate = pool[i].note;
        if (usedIds.contains(candidate.id)) {
          continue;
        }
        final author = candidate.authorId;
        final sameAuthor =
            author != null &&
            author.isNotEmpty &&
            lastAuthor != null &&
            author == lastAuthor;
        if (sameAuthor) {
          continue;
        }
        pick = i;
        break;
      }
      if (pick == -1) {
        for (var i = 0; i < pool.length; i++) {
          final candidate = pool[i].note;
          if (!usedIds.contains(candidate.id)) {
            pick = i;
            break;
          }
        }
      }
      if (pick == -1) {
        break;
      }
      final chosen = pool.removeAt(pick).note;
      if (!usedIds.add(chosen.id)) {
        continue;
      }
      selected.add(chosen);
      final author = chosen.authorId;
      if (author != null && author.isNotEmpty) {
        lastAuthor = author;
      }
    }
    return selected;
  }

  int _stableFeedHash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  List<VoiceNote> _filterNotes(List<VoiceNote> notes) =>
      _moderation.filterNotes(notes);

  List<VoiceNote> _mergeLocalDevNotes(
    String hashtagId,
    List<VoiceNote> remote,
  ) {
    final local = _localDevNotesByHashtag[hashtagId] ?? const [];
    if (local.isEmpty) {
      return remote;
    }
    final mergedById = <String, VoiceNote>{};
    for (final note in remote) {
      mergedById[note.id] = note;
    }
    for (final note in local) {
      mergedById[note.id] = note;
    }
    final merged = mergedById.values.toList();
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _filterNotes(merged);
  }
}

bool _sameList(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

class _FeedShuffleCandidate {
  const _FeedShuffleCandidate({
    required this.note,
    required this.hash,
    required this.sourceIndex,
  });

  final VoiceNote note;
  final int hash;
  final int sourceIndex;
}
