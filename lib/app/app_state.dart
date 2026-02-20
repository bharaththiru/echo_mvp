import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../services/feed_service.dart';
import '../services/moderation_service.dart';
import '../services/skip_quota_service.dart';
import '../services/autoplay_controller.dart';
import '../services/autoplay_data_source.dart';
import '../services/firebase_repository.dart';
import '../utils/id_generator.dart';
import 'firebase_config.dart';

class AppState extends ChangeNotifier implements AutoplayDataSource {
  AppState._({
    required SharedPreferences prefs,
    required this.settings,
    required this.audio,
    required AuthService authService,
    required AudioCacheService audioCache,
    required SkipQuotaService skipQuotaService,
    required ModerationService moderationService,
    required FeedService feedService,
    required FirebaseRepository repository,
    required String recordingsDirectory,
    required this.onboardingComplete,
    required this.onboardingInterests,
  }) : _prefs = prefs,
        _authService = authService,
        _audioCache = audioCache,
        _skipQuota = skipQuotaService,
        _moderation = moderationService,
        _feed = feedService,
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

  final SharedPreferences _prefs;
  final IdGenerator _idGenerator;
  final AuthService _authService;
  final AudioCacheService _audioCache;
  final SkipQuotaService _skipQuota;
  final ModerationService _moderation;
  final FeedService _feed;
  final FirebaseRepository _repository;
  final AudioController audio;
  late final AutoplayController autoplay;
  final String _recordingsDirectory;
  PendingPostDraft? _pendingPostDraft;
  Future<VoiceNote>? _postInFlight;

  AppSettings settings;
  bool onboardingComplete;
  List<String> onboardingInterests;
  String? pendingRecordingPath;

  List<String> get savedHashtags => _feed.savedHashtags;
  List<String> get recentHashtagIds => _feed.recentHashtagIds;

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
    final feed = FeedService(
      prefs: prefs,
      repository: repository,
      moderation: moderation,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
      onStateChanged: () => stateRef!.notifyListeners(),
      initialSavedHashtags: savedHashtags,
      initialRecentHashtagIds: recentHashtagIds,
    );
    final state = AppState._(
      prefs: prefs,
      settings: settings,
      audio: audio,
      authService: authService,
      audioCache: audioCache,
      skipQuotaService: skipQuota,
      moderationService: moderation,
      feedService: feed,
      repository: repository,
      recordingsDirectory: recordingsDirectory,
      onboardingComplete: onboardingComplete,
      onboardingInterests: onboardingInterests,
    );
    stateRef = state;
    state.pendingRecordingPath = resolvedRecordingPath;
    state._pendingPostDraft = pendingDraft;
    state.autoplay = AutoplayController(
      dataSource: state,
      feedQueueBuilder: state._feed,
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
    final feed = FeedService(
      prefs: prefs,
      repository: resolvedRepository,
      moderation: moderation,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
      onStateChanged: () => stateRef!.notifyListeners(),
      initialSavedHashtags: saved,
      initialRecentHashtagIds: const [],
    );
    final state = AppState._(
      prefs: prefs,
      settings: resolvedSettings,
      audio: audio,
      authService: authService,
      audioCache: audioCache,
      skipQuotaService: skipQuota,
      moderationService: moderation,
      feedService: feed,
      repository: resolvedRepository,
      recordingsDirectory: recordingsDirectory,
      onboardingComplete: onboardingComplete,
      onboardingInterests: saved,
    );
    stateRef = state;
    state.autoplay = AutoplayController(
      dataSource: state,
      feedQueueBuilder: state._feed,
      audio: audio,
    );
    state.autoplay.syncSuppressed(
      noteIds: moderation.hiddenNoteIds,
      authorIds: moderation.blockedAuthorIds,
    );
    feed.initFromSnapshot(hashtags: hashtags, notesByHashtag: notesByHashtag);
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

  List<Hashtag> get hashtags => _feed.hashtags;

  bool get hashtagsLoading => _feed.hashtagsLoading;

  String? get hashtagsError => _feed.hashtagsError;

  Hashtag? hashtagById(String id) => _feed.hashtagById(id);

  Future<void> refreshHashtags({bool force = false}) =>
      _feed.refreshHashtags(force: force);

  List<Hashtag> recentHashtags({int limit = 6}) =>
      _feed.recentHashtags(limit: limit);

  List<VoiceNote> notesForHashtag(String hashtagId) =>
      _feed.notesForHashtag(hashtagId);

  bool isLoadingNotes(String hashtagId) => _feed.isLoadingNotes(hashtagId);

  String? notesError(String hashtagId) => _feed.notesError(hashtagId);

  Future<void> loadNotesForHashtag(
    String hashtagId, {
    bool force = false,
  }) => _feed.loadNotesForHashtag(hashtagId, force: force);

  List<VoiceNote> userPosts() => _feed.userPosts();

  bool get myPostsLoading => _feed.myPostsLoading;

  String? get myPostsError => _feed.myPostsError;

  Future<void> refreshMyPosts({bool force = false}) =>
      _feed.refreshMyPosts(force: force);

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
    _feed.setSavedHashtags(interests);
    _prefs.setStringList(_onboardingInterestsKey, onboardingInterests);
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

  void addSavedHashtag(String tag) => _feed.addSavedHashtag(tag);

  void markStationListened(String hashtagId) =>
      _feed.markStationListened(hashtagId);

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

  void _removeNoteById(String noteId) => _feed.removeNoteById(noteId);

  void _removeNotesByAuthor(String authorId) =>
      _feed.removeNotesByAuthor(authorId);

  void _cacheNote(VoiceNote note, {bool localOnly = false}) =>
      _feed.cacheNote(note, localOnly: localOnly);

  void _replaceNote(VoiceNote note) => _feed.replaceNote(note);

  @override
  void dispose() {
    _authService.dispose();
    autoplay.dispose();
    audio.dispose();
    super.dispose();
  }
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
