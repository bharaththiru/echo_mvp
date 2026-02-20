import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/seed_data.dart';
import '../models/hashtag.dart';
import '../models/voice_note.dart';
import '../services/audio_cache_service.dart';
import '../services/audio_controller.dart';
import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import '../services/skip_quota_service.dart';
import '../services/autoplay_controller.dart';
import '../services/autoplay_data_source.dart';
import '../services/autoplay_feed_queue_builder.dart';
import '../services/firebase_repository.dart';
import '../utils/id_generator.dart';
import 'firebase_config.dart';

class AppState extends ChangeNotifier
    implements AutoplayDataSource, AutoplayFeedQueueBuilder {
  AppState._({
    required SharedPreferences prefs,
    required this.settings,
    required this.audio,
    required AuthService authService,
    required AudioCacheService audioCache,
    required SkipQuotaService skipQuotaService,
    required ModerationService moderationService,
    required FirebaseRepository repository,
    required String recordingsDirectory,
    required this.onboardingComplete,
    required this.onboardingInterests,
    required this.savedHashtags,
    required this.recentHashtagIds,
  }) : _prefs = prefs,
        _authService = authService,
        _audioCache = audioCache,
        _skipQuota = skipQuotaService,
        _moderation = moderationService,
        _repository = repository,
        _recordingsDirectory = recordingsDirectory,
        _idGenerator = IdGenerator();

  static const _themeModeKey = 'theme_mode';
  static const _moodTintKey = 'mood_tint';
  static const _transcriptsKey = 'transcripts';
  static const _reduceMotionKey = 'reduce_motion';
  static const _repliesNotifKey = 'replies_notifications';
  static const _hashtagNotifKey = 'hashtag_notifications';
  static const _onboardingCompleteKey = 'onboarding_complete';
  static const _onboardingInterestsKey = 'onboarding_interests';
  static const _savedHashtagsKey = 'saved_hashtags';
  static const _recentHashtagIdsKey = 'recent_hashtag_ids';
  static const _postRateLimitKey = 'post_rate_limit';
  static const _pendingRecordingKey = 'pending_recording_path';
  static const _pendingPostDraftKey = 'pending_post_draft';
  static const _uploadTimeout = Duration(seconds: 20);
  static const _postTimeout = Duration(seconds: 12);
  static const _postRateLimitWindow = Duration(hours: 1);
  static const _postRateLimitMax = 20;
  static const _remoteFeedTransientCooldown = Duration(seconds: 45);
  static const _remoteFeedPolicyCooldown = Duration(minutes: 10);

  final SharedPreferences _prefs;
  final IdGenerator _idGenerator;
  final AuthService _authService;
  final AudioCacheService _audioCache;
  final SkipQuotaService _skipQuota;
  final ModerationService _moderation;
  final FirebaseRepository _repository;
  final AudioController audio;
  late final AutoplayController autoplay;
  final String _recordingsDirectory;
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
  PendingPostDraft? _pendingPostDraft;
  Future<VoiceNote>? _postInFlight;
  DateTime? _remoteFeedCooldownUntil;

  AppSettings settings;
  bool onboardingComplete;
  List<String> onboardingInterests;
  List<String> savedHashtags;
  List<String> recentHashtagIds;
  String? pendingRecordingPath;

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.fromPrefs(prefs);
    final audio = await AudioController.create();
    final authService = AuthService.create(auth: FirebaseAuth.instance);
    final repository = FirebaseRepository(
      firestore: FirebaseFirestore.instance,
      storage: FirebaseStorage.instance,
      storageCdnBaseUrl: FirebaseConfig.storageCdnBaseUrl,
    );
    final recordingsDirectory = await _prepareRecordingsDirectory();
    final audioCache = await AudioCacheService.create(repository: repository);
    final skipQuota = SkipQuotaService(
      prefs: prefs,
      repository: repository,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
    );
    final onboardingComplete = prefs.getBool(_onboardingCompleteKey) ?? false;
    final onboardingInterests =
        prefs.getStringList(_onboardingInterestsKey) ?? <String>[];
    final savedHashtags =
        prefs.getStringList(_savedHashtagsKey) ??
        (onboardingInterests.isNotEmpty
            ? onboardingInterests
            : suggestedHashtags.take(3).toList());
    final recentHashtagIds =
        prefs.getStringList(_recentHashtagIdsKey) ?? <String>[];
    final pendingRecordingPath = prefs.getString(_pendingRecordingKey);
    PendingPostDraft? pendingDraft;
    final draftRaw = prefs.getString(_pendingPostDraftKey);
    if (draftRaw != null && draftRaw.isNotEmpty) {
      try {
        pendingDraft = PendingPostDraft.fromJson(
          jsonDecode(draftRaw) as Map<String, dynamic>,
        );
      } catch (_) {
        pendingDraft = null;
        prefs.remove(_pendingPostDraftKey);
      }
    }
    if (pendingDraft != null &&
        (pendingDraft.id.isEmpty ||
            pendingDraft.recordingPath.isEmpty ||
            pendingDraft.hashtagId.isEmpty)) {
      pendingDraft = null;
      prefs.remove(_pendingPostDraftKey);
    }
    String? resolvedRecordingPath;
    if (pendingDraft != null) {
      final valid = await _recordingExists(pendingDraft.recordingPath);
      if (valid) {
        resolvedRecordingPath = pendingDraft.recordingPath;
      } else {
        pendingDraft = null;
        prefs.remove(_pendingPostDraftKey);
      }
    }
    if (resolvedRecordingPath == null && pendingRecordingPath != null) {
      final valid = await _recordingExists(pendingRecordingPath);
      if (valid) {
        resolvedRecordingPath = pendingRecordingPath;
      } else {
        prefs.remove(_pendingRecordingKey);
      }
    }
    // Closures below capture `stateRef` by reference so they resolve correctly
    // at call time even though ModerationService is created before `state`.
    AppState? stateRef;
    final moderation = ModerationService(
      prefs: prefs,
      repository: repository,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
      onNoteRemoved: (id) => stateRef!._removeNoteById(id),
      onAuthorRemoved: (id) => stateRef!._removeNotesByAuthor(id),
      onStateChanged: () => stateRef!.notifyListeners(),
      onSuppressNote: (id, {message}) =>
          stateRef!.autoplay.suppressNote(id, message: message),
      onSuppressAuthor: (id, {message}) =>
          stateRef!.autoplay.suppressAuthor(id, message: message),
    );
    final state = AppState._(
      prefs: prefs,
      settings: settings,
      audio: audio,
      authService: authService,
      audioCache: audioCache,
      skipQuotaService: skipQuota,
      moderationService: moderation,
      repository: repository,
      recordingsDirectory: recordingsDirectory,
      onboardingComplete: onboardingComplete,
      onboardingInterests: onboardingInterests,
      savedHashtags: savedHashtags,
      recentHashtagIds: recentHashtagIds,
    );
    stateRef = state;
    state.pendingRecordingPath = resolvedRecordingPath;
    state._pendingPostDraft = pendingDraft;
    state.autoplay = AutoplayController(
      dataSource: state,
      feedQueueBuilder: state,
      audio: audio,
    );
    state.autoplay.syncSuppressed(
      noteIds: moderation.hiddenNoteIds,
      authorIds: moderation.blockedAuthorIds,
    );
    authService.bind(() {
      state.refreshMyPosts(force: true);
      state.notifyListeners();
    });
    // Avoid blocking the first frame on network/auth work.
    unawaited(authService.maybeAutoSignIn());
    unawaited(state.refreshHashtags());
    unawaited(state.refreshMyPosts());
    unawaited(audioCache.prune());
    return state;
  }

  static Future<AppState> forTest({
    required AudioController audio,
    required List<Hashtag> hashtags,
    required Map<String, List<VoiceNote>> notesByHashtag,
    FirebaseAuth? auth,
    FirebaseRepository? repository,
    AppSettings? settings,
    bool onboardingComplete = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedSettings = settings ?? AppSettings.fromPrefs(prefs);
    final resolvedAuth = auth ?? FirebaseAuth.instance;
    final resolvedRepository =
        repository ??
        FirebaseRepository(
          firestore: FirebaseFirestore.instance,
          storage: FirebaseStorage.instance,
          storageCdnBaseUrl: FirebaseConfig.storageCdnBaseUrl,
        );
    final recordingsDirectory = Directory.systemTemp
        .createTempSync('echo_test')
        .path;
    final audioCacheDir = Directory(
      '$recordingsDirectory${Platform.pathSeparator}audio_cache',
    );
    audioCacheDir.createSync(recursive: true);
    final saved = hashtags.take(3).map((tag) => tag.name).toList();
    final authService = AuthService.create(
      auth: resolvedAuth,
      initialUser: null,
    );
    authService.bindNoop();
    final audioCache = AudioCacheService.forTest(
      repository: resolvedRepository,
      cacheDirectory: audioCacheDir.path,
    );
    final skipQuota = SkipQuotaService(
      prefs: prefs,
      repository: resolvedRepository,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
    );
    AppState? stateRef;
    final moderation = ModerationService(
      prefs: prefs,
      repository: resolvedRepository,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
      onNoteRemoved: (id) => stateRef!._removeNoteById(id),
      onAuthorRemoved: (id) => stateRef!._removeNotesByAuthor(id),
      onStateChanged: () => stateRef!.notifyListeners(),
      onSuppressNote: (id, {message}) =>
          stateRef!.autoplay.suppressNote(id, message: message),
      onSuppressAuthor: (id, {message}) =>
          stateRef!.autoplay.suppressAuthor(id, message: message),
    );
    final state = AppState._(
      prefs: prefs,
      settings: resolvedSettings,
      audio: audio,
      authService: authService,
      audioCache: audioCache,
      skipQuotaService: skipQuota,
      moderationService: moderation,
      repository: resolvedRepository,
      recordingsDirectory: recordingsDirectory,
      onboardingComplete: onboardingComplete,
      onboardingInterests: saved,
      savedHashtags: saved,
      recentHashtagIds: const [],
    );
    stateRef = state;
    state.autoplay = AutoplayController(
      dataSource: state,
      feedQueueBuilder: state,
      audio: audio,
    );
    state.autoplay.syncSuppressed(
      noteIds: moderation.hiddenNoteIds,
      authorIds: moderation.blockedAuthorIds,
    );
    state._hashtags
      ..clear()
      ..addAll(hashtags);
    state._notesByHashtag
      ..clear()
      ..addAll(notesByHashtag);
    state._notesLoading.clear();
    state._notesError.clear();
    return state;
  }

  static Future<String> _prepareRecordingsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final recordings = Directory('${directory.path}/recordings');
    if (!await recordings.exists()) {
      await recordings.create(recursive: true);
    }
    return recordings.path;
  }

  static Future<bool> _recordingExists(String path) async {
    if (path.isEmpty) {
      return false;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }
      final size = await file.length();
      return size > 0;
    } catch (_) {
      return false;
    }
  }

  bool get isAuthenticated => _authService.isAuthenticated;

  bool get skipAuth => _authService.skipAuth;

  String? get userEmail => _authService.userEmail;

  String? get userId => _authService.userId;

  bool get _isDevUnauthed => _authService.isDevUnauthed;

  PendingPostDraft? get pendingPostDraft => _pendingPostDraft;

  bool get isPosting => _postInFlight != null;

  Future<UserCredential> signInWithPassword({
    required String email,
    required String password,
  }) => _authService.signInWithPassword(email: email, password: password);

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) => _authService.signUp(email: email, password: password);

  Future<void> signOut() => _authService.signOut();

  Future<UserCredential?> signInWithGoogle() => _authService.signInWithGoogle();

  Future<UserCredential?> signInWithApple() => _authService.signInWithApple();

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

  Future<void> refreshHashtags({bool force = false}) async {
    if (_hashtagsLoading) {
      return;
    }
    if (!force && _hashtags.isNotEmpty) {
      return;
    }
    _hashtagsLoading = true;
    _hashtagsError = null;
    notifyListeners();
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
      notifyListeners();
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

  static const _localFeedCursorPrefix = 'local:';
  static const _autoplayFeedWindow = 50;
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
    if (_isDevUnauthed) {
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

  AutoplayFeedPage _localFeedPage({
    required String stationId,
    required int limit,
    String? cursor,
  }) {
    final mergedById = <String, VoiceNote>{};
    for (final note in _notesByHashtag[stationId] ?? const <VoiceNote>[]) {
      mergedById[note.id] = note;
    }
    for (final note in _localDevNotesByHashtag[stationId] ?? const <VoiceNote>[]) {
      mergedById[note.id] = note;
    }
    final sorted = _filterNotes(mergedById.values.toList())..sort((a, b) {
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

  List<VoiceNote> notesForHashtag(String hashtagId) {
    final notes = _notesByHashtag[hashtagId] ?? <VoiceNote>[];
    return List<VoiceNote>.from(_filterNotes(notes));
  }

  bool isLoadingNotes(String hashtagId) => _notesLoading[hashtagId] ?? false;

  String? notesError(String hashtagId) => _notesError[hashtagId];

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
    notifyListeners();
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
      notifyListeners();
    }
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

  List<VoiceNote> userPosts() {
    final notes = List<VoiceNote>.from(_myPosts);
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  bool get myPostsLoading => _myPostsLoading;

  String? get myPostsError => _myPostsError;

  Future<void> refreshMyPosts({bool force = false}) async {
    if (_myPostsLoading) {
      return;
    }
    if (!force && _myPosts.isNotEmpty) {
      return;
    }
    final currentUser = userId;
    if (currentUser == null) {
      if (_isDevUnauthed) {
        final local = _localDevNotesByHashtag.values
            .expand((notes) => notes)
            .toList();
        local.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _myPosts = _filterNotes(local);
      } else {
        _myPosts = [];
      }
      _myPostsError = null;
      notifyListeners();
      return;
    }
    _myPostsLoading = true;
    _myPostsError = null;
    notifyListeners();
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
      notifyListeners();
    }
  }

  String createRecordingPath() {
    final id = _idGenerator.next();
    return '$_recordingsDirectory${Platform.pathSeparator}echo_$id.m4a';
  }

  String createNoteId() => _idGenerator.next();

  void setPendingRecordingPath(String path) {
    pendingRecordingPath = path;
    if (path.isEmpty) {
      _prefs.remove(_pendingRecordingKey);
    } else {
      _prefs.setString(_pendingRecordingKey, path);
    }
    notifyListeners();
  }

  void clearPendingRecording() {
    pendingRecordingPath = null;
    _prefs.remove(_pendingRecordingKey);
    notifyListeners();
  }

  void savePendingPostDraft(PendingPostDraft draft) {
    _pendingPostDraft = draft;
    _prefs.setString(_pendingPostDraftKey, jsonEncode(draft.toJson()));
    notifyListeners();
  }

  void clearPendingPostDraft() {
    _pendingPostDraft = null;
    _prefs.remove(_pendingPostDraftKey);
    notifyListeners();
  }

  void setOnboardingInterests(List<String> interests) {
    onboardingInterests = List<String>.from(interests);
    savedHashtags = List<String>.from(interests);
    _prefs.setStringList(_onboardingInterestsKey, onboardingInterests);
    _prefs.setStringList(_savedHashtagsKey, savedHashtags);
    notifyListeners();
  }

  void completeOnboarding() {
    onboardingComplete = true;
    _prefs.setBool(_onboardingCompleteKey, true);
    notifyListeners();
  }

  void updateThemeMode(ThemeMode mode) {
    settings = settings.copyWith(themeMode: mode);
    _prefs.setString(_themeModeKey, mode.name);
    notifyListeners();
  }

  void updateMoodTint(bool value) {
    settings = settings.copyWith(moodTintEnabled: value);
    _prefs.setBool(_moodTintKey, value);
    notifyListeners();
  }

  void updateTranscripts(bool value) {
    settings = settings.copyWith(transcriptsEnabled: value);
    _prefs.setBool(_transcriptsKey, value);
    notifyListeners();
  }

  void updateReduceMotion(bool value) {
    settings = settings.copyWith(reduceMotion: value);
    _prefs.setBool(_reduceMotionKey, value);
    notifyListeners();
  }

  void updateRepliesNotifications(bool value) {
    settings = settings.copyWith(repliesNotifications: value);
    _prefs.setBool(_repliesNotifKey, value);
    notifyListeners();
  }

  void updateHashtagNotifications(bool value) {
    settings = settings.copyWith(hashtagNotifications: value);
    _prefs.setBool(_hashtagNotifKey, value);
    notifyListeners();
  }

  void addSavedHashtag(String tag) {
    if (savedHashtags.contains(tag)) {
      return;
    }
    savedHashtags = [...savedHashtags, tag];
    _prefs.setStringList(_savedHashtagsKey, savedHashtags);
    notifyListeners();
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
    final trimmed = reordered.length > maxRecent
        ? reordered.sublist(0, maxRecent)
        : reordered;
    if (_sameList(recentHashtagIds, trimmed)) {
      return;
    }
    recentHashtagIds = trimmed;
    _prefs.setStringList(_recentHashtagIdsKey, recentHashtagIds);
    notifyListeners();
  }

  bool isAuthorBlocked(String? authorId) => _moderation.isAuthorBlocked(authorId);
  bool isNoteHidden(String noteId) => _moderation.isNoteHidden(noteId);

  Future<AbuseActionResult> reportClip({
    required VoiceNote note,
    required String reason,
    String? details,
  }) => _moderation.reportClip(note: note, reason: reason, details: details);

  Future<AbuseActionResult> blockAuthor(VoiceNote note) =>
      _moderation.blockAuthor(note);

  AbuseActionResult hideClip(VoiceNote note) => _moderation.hideClip(note);

  Future<VoiceNote> postNote({
    required String recordingPath,
    required Hashtag hashtag,
    required bool allowReplies,
    required bool expiresIn24h,
    required String? caption,
  }) async {
    if (_postInFlight != null) {
      throw PostException('A post is already in progress.');
    }
    final future = _postNoteInternal(
      recordingPath: recordingPath,
      hashtag: hashtag,
      allowReplies: allowReplies,
      expiresIn24h: expiresIn24h,
      caption: caption,
    );
    _postInFlight = future;
    notifyListeners();
    try {
      return await future;
    } finally {
      if (_postInFlight == future) {
        _postInFlight = null;
        notifyListeners();
      }
    }
  }

  Future<VoiceNote> _postNoteInternal({
    required String recordingPath,
    required Hashtag hashtag,
    required bool allowReplies,
    required bool expiresIn24h,
    required String? caption,
  }) async {
    final currentUser = userId;
    if (currentUser == null) {
      if (!_isDevUnauthed) {
        if (skipAuth) {
          throw PostException(
            'Dev mode requires DEV_EMAIL and DEV_PASSWORD to post.',
          );
        }
        throw PostException('Sign in required to post.');
      }
    }
    final rateScope = currentUser ?? 'dev';
    if (_isPostRateLimited(rateScope)) {
      throw PostException(
        'You have posted a lot recently. Please wait before posting again.',
      );
    }
    await _ensureRecordingReady(recordingPath);
    final duration = await audio.getAudioDuration(recordingPath);
    final trimmedCaption = caption?.trim();
    final normalizedCaption =
        trimmedCaption == null || trimmedCaption.isEmpty
            ? null
            : trimmedCaption;
    final existingDraft = _pendingPostDraft;
    final noteId =
        existingDraft != null && existingDraft.recordingPath == recordingPath
            ? existingDraft.id
            : createNoteId();
    final draft = PendingPostDraft(
      id: noteId,
      recordingPath: recordingPath,
      hashtagId: hashtag.id,
      allowReplies: allowReplies,
      expiresIn24h: expiresIn24h,
      caption: normalizedCaption,
      createdAt: DateTime.now().toUtc(),
    );
    savePendingPostDraft(draft);
    setPendingRecordingPath(recordingPath);
    final expiresAt = expiresIn24h
        ? DateTime.now().add(const Duration(hours: 24))
        : null;

    if (_isDevUnauthed) {
      final seconds = duration.inSeconds == 0 ? 12 : duration.inSeconds;
      final localNote = VoiceNote(
        id: noteId,
        hashtagId: hashtag.id,
        hashtagLabel: hashtag.name,
        createdAt: DateTime.now(),
        duration: Duration(seconds: seconds),
        storagePath: '',
        allowReplies: allowReplies,
        expiresAt: expiresAt,
        authorId: 'dev-user',
        transcriptPreview: normalizedCaption,
        localPath: recordingPath,
      );
      _cacheNote(localNote, localOnly: true);
      _recordPostTimestamp(rateScope);
      clearPendingPostDraft();
      clearPendingRecording();
      return localNote;
    }

    String storagePath;
    try {
      storagePath = await _repository
          .uploadAudio(
            userId: currentUser!,
            noteId: noteId,
            filePath: recordingPath,
          )
          .timeout(_uploadTimeout);
    } on TimeoutException {
      throw PostException('Upload timed out. Please retry.');
    } catch (_) {
      throw PostException('Upload failed. Please retry.');
    }
    if (storagePath.isEmpty) {
      throw PostException('Upload failed. Please retry.');
    }

    VoiceNote note;
    try {
      note = await _repository
          .createNote(
            id: noteId,
            hashtagId: hashtag.id,
            hashtagLabel: hashtag.name,
            durationSeconds: duration.inSeconds == 0 ? 12 : duration.inSeconds,
            storagePath: storagePath,
            allowReplies: allowReplies,
            expiresAt: expiresAt,
            caption: normalizedCaption,
            authorId: currentUser,
          )
          .timeout(_postTimeout);
    } on TimeoutException {
      throw PostException('Post timed out. Please retry.');
    } catch (_) {
      throw PostException('Unable to publish right now.');
    }
    final updated = note.copyWith(localPath: recordingPath);
    _cacheNote(updated);
    _recordPostTimestamp(rateScope);
    clearPendingPostDraft();
    clearPendingRecording();
    return updated;
  }

  Future<void> _ensureRecordingReady(String recordingPath) async {
    final isValid = await _recordingExists(recordingPath);
    if (isValid) {
      return;
    }
    if (_pendingPostDraft?.recordingPath == recordingPath) {
      clearPendingPostDraft();
    }
    if (pendingRecordingPath == recordingPath) {
      clearPendingRecording();
    }
    throw PostException('Recording not found. Please record again.');
  }

  @override
  Future<String?> ensureLocalAudioPath(VoiceNote note) =>
      _audioCache.ensureLocalAudioPath(note);

  @override
  Future<SkipQuotaResult> consumeSkip() => _skipQuota.consumeSkip();

  bool _isPostRateLimited(String scope) {
    final now = DateTime.now().toUtc();
    final timestamps = _readPostTimestamps(scope, now);
    return timestamps.length >= _postRateLimitMax;
  }

  void _recordPostTimestamp(String scope) {
    final now = DateTime.now().toUtc();
    final timestamps = _readPostTimestamps(scope, now);
    timestamps.add(now);
    _prefs.setStringList(
      _postRateLimitScopeKey(scope),
      timestamps.map((time) => time.toIso8601String()).toList(),
    );
  }

  List<DateTime> _readPostTimestamps(String scope, DateTime now) {
    final raw = _prefs.getStringList(_postRateLimitScopeKey(scope)) ?? const [];
    final filtered = <DateTime>[];
    for (final entry in raw) {
      try {
        final parsed = DateTime.parse(entry).toUtc();
        if (now.difference(parsed) <= _postRateLimitWindow) {
          filtered.add(parsed);
        }
      } catch (_) {
        // Ignore malformed timestamps.
      }
    }
    if (filtered.length != raw.length) {
      _prefs.setStringList(
        _postRateLimitScopeKey(scope),
        filtered.map((time) => time.toIso8601String()).toList(),
      );
    }
    return filtered;
  }

  String _postRateLimitScopeKey(String scope) => '$_postRateLimitKey:$scope';

  void _removeNoteById(String noteId) {
    if (noteId.isEmpty) {
      return;
    }
    for (final entry in _notesByHashtag.entries) {
      final updated =
          entry.value.where((note) => note.id != noteId).toList();
      _notesByHashtag[entry.key] = updated;
    }
    for (final entry in _localDevNotesByHashtag.entries) {
      final updated =
          entry.value.where((note) => note.id != noteId).toList();
      _localDevNotesByHashtag[entry.key] = updated;
    }
    _myPosts = _myPosts.where((note) => note.id != noteId).toList();
  }

  void _removeNotesByAuthor(String authorId) {
    if (authorId.isEmpty) {
      return;
    }
    for (final entry in _notesByHashtag.entries) {
      final updated =
          entry.value.where((note) => note.authorId != authorId).toList();
      _notesByHashtag[entry.key] = updated;
    }
    for (final entry in _localDevNotesByHashtag.entries) {
      final updated =
          entry.value.where((note) => note.authorId != authorId).toList();
      _localDevNotesByHashtag[entry.key] = updated;
    }
    _myPosts = _myPosts.where((note) => note.authorId != authorId).toList();
  }

  void _cacheNote(VoiceNote note, {bool localOnly = false}) {
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
    final isMine = note.authorId == userId || (localOnly && _isDevUnauthed);
    if (isMine) {
      final mine = List<VoiceNote>.from(_myPosts);
      mine.removeWhere((item) => item.id == note.id);
      mine.insert(0, note);
      _myPosts = mine;
    }
    notifyListeners();
  }

  void _replaceNote(VoiceNote note) {
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
    notifyListeners();
  }

  @override
  void dispose() {
    _authService.dispose();
    autoplay.dispose();
    audio.dispose();
    super.dispose();
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

class PostException implements Exception {
  PostException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PendingPostDraft {
  const PendingPostDraft({
    required this.id,
    required this.recordingPath,
    required this.hashtagId,
    required this.allowReplies,
    required this.expiresIn24h,
    required this.caption,
    required this.createdAt,
  });

  final String id;
  final String recordingPath;
  final String hashtagId;
  final bool allowReplies;
  final bool expiresIn24h;
  final String? caption;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recordingPath': recordingPath,
      'hashtagId': hashtagId,
      'allowReplies': allowReplies,
      'expiresIn24h': expiresIn24h,
      'caption': caption,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PendingPostDraft.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['createdAt'] as String?;
    DateTime created;
    try {
      created = createdRaw == null ? DateTime.now() : DateTime.parse(createdRaw);
    } catch (_) {
      created = DateTime.now();
    }
    return PendingPostDraft(
      id: json['id'] as String? ?? '',
      recordingPath: json['recordingPath'] as String? ?? '',
      hashtagId: json['hashtagId'] as String? ?? '',
      allowReplies: json['allowReplies'] as bool? ?? false,
      expiresIn24h: json['expiresIn24h'] as bool? ?? false,
      caption: json['caption'] as String?,
      createdAt: created,
    );
  }
}

class AppSettings {
  AppSettings({
    required this.themeMode,
    required this.moodTintEnabled,
    required this.transcriptsEnabled,
    required this.reduceMotion,
    required this.repliesNotifications,
    required this.hashtagNotifications,
  });

  final ThemeMode themeMode;
  final bool moodTintEnabled;
  final bool transcriptsEnabled;
  final bool reduceMotion;
  final bool repliesNotifications;
  final bool hashtagNotifications;

  static AppSettings fromPrefs(SharedPreferences prefs) {
    final modeName = prefs.getString(AppState._themeModeKey) ?? 'dark';
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => ThemeMode.dark,
      ),
      moodTintEnabled: prefs.getBool(AppState._moodTintKey) ?? true,
      transcriptsEnabled: prefs.getBool(AppState._transcriptsKey) ?? true,
      reduceMotion: prefs.getBool(AppState._reduceMotionKey) ?? false,
      repliesNotifications: prefs.getBool(AppState._repliesNotifKey) ?? false,
      hashtagNotifications: prefs.getBool(AppState._hashtagNotifKey) ?? false,
    );
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? moodTintEnabled,
    bool? transcriptsEnabled,
    bool? reduceMotion,
    bool? repliesNotifications,
    bool? hashtagNotifications,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      moodTintEnabled: moodTintEnabled ?? this.moodTintEnabled,
      transcriptsEnabled: transcriptsEnabled ?? this.transcriptsEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      repliesNotifications: repliesNotifications ?? this.repliesNotifications,
      hashtagNotifications: hashtagNotifications ?? this.hashtagNotifications,
    );
  }
}
