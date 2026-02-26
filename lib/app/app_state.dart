import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../services/post_service.dart';
import '../services/skip_quota_service.dart';
import '../services/autoplay_controller.dart';
import '../services/autoplay_data_source.dart';
import '../services/firebase_repository.dart';
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
    required PostService postService,
    required this.onboardingComplete,
    required this.onboardingInterests,
  }) : _prefs = prefs,
        _authService = authService,
        _audioCache = audioCache,
        _skipQuota = skipQuotaService,
        _moderation = moderationService,
        _feed = feedService,
        _post = postService;

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

  final SharedPreferences _prefs;
  final AuthService _authService;
  final AudioCacheService _audioCache;
  final SkipQuotaService _skipQuota;
  final ModerationService _moderation;
  final FeedService _feed;
  final PostService _post;
  final AudioController audio;
  late final AutoplayController autoplay;

  AppSettings settings;
  bool onboardingComplete;
  List<String> onboardingInterests;

  List<String> get savedHashtags => _feed.savedHashtags;
  List<String> get recentHashtagIds => _feed.recentHashtagIds;
  String? get pendingRecordingPath => _post.pendingRecordingPath;

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.fromPrefs(prefs);
    final audio = await AudioController.create();
    final authService = AuthService.create();
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
    final startup = await PostService.resolveStartup(prefs);
    // Closures below capture `stateRef` by reference so they resolve correctly
    // at call time even though services are created before `state`.
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
    final post = PostService(
      prefs: prefs,
      repository: repository,
      feed: feed,
      audio: audio,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
      onStateChanged: () => stateRef!.notifyListeners(),
      recordingsDirectory: recordingsDirectory,
      initialDraft: startup.draft,
      initialRecordingPath: startup.recordingPath,
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
      postService: post,
      onboardingComplete: onboardingComplete,
      onboardingInterests: onboardingInterests,
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
    authService.bind(() {
      state.refreshMyPosts(force: true);
      state.notifyListeners();
    });
    // Avoid blocking the first frame on network/auth work.
    unawaited(state.refreshHashtags());
    unawaited(state.refreshMyPosts());
    unawaited(audioCache.prune());
    return state;
  }

  static Future<AppState> forTest({
    required AudioController audio,
    required List<Hashtag> hashtags,
    required Map<String, List<VoiceNote>> notesByHashtag,
    FirebaseRepository? repository,
    AppSettings? settings,
    bool onboardingComplete = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedSettings = settings ?? AppSettings.fromPrefs(prefs);
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
    final authService = AuthService.create();
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
    final post = PostService(
      prefs: prefs,
      repository: resolvedRepository,
      feed: feed,
      audio: audio,
      userId: () => authService.userId,
      isDevUnauthed: () => authService.isDevUnauthed,
      onStateChanged: () => stateRef!.notifyListeners(),
      recordingsDirectory: recordingsDirectory,
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
      postService: post,
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

  bool get isAuthenticated => _authService.isAuthenticated;


  String? get userEmail => _authService.userEmail;

  String? get userId => _authService.userId;

  PendingPostDraft? get pendingPostDraft => _post.pendingPostDraft;

  bool get isPosting => _post.isPosting;

  Future<void> signOut() => _authService.signOut();

  Future<void> deleteAccount() => _authService.deleteAccount();

  String? currentClerkUserId() => _authService.userId;

  Future<String> requireClerkUserIdOrThrow() =>
      _authService.requireClerkUserIdOrThrow();


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

  String createRecordingPath() => _post.createRecordingPath();

  String createNoteId() => _post.createNoteId();

  void setPendingRecordingPath(String path) =>
      _post.setPendingRecordingPath(path);

  void clearPendingRecording() => _post.clearPendingRecording();

  void savePendingPostDraft(PendingPostDraft draft) =>
      _post.savePendingPostDraft(draft);

  void clearPendingPostDraft() => _post.clearPendingPostDraft();

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
  }) => _post.postNote(
    recordingPath: recordingPath,
    hashtag: hashtag,
    allowReplies: allowReplies,
    expiresIn24h: expiresIn24h,
    caption: caption,
  );

  @override
  Future<String?> ensureLocalAudioPath(VoiceNote note) =>
      _audioCache.ensureLocalAudioPath(note);

  @override
  Future<SkipQuotaResult> consumeSkip() => _skipQuota.consumeSkip();

  void _removeNoteById(String noteId) => _feed.removeNoteById(noteId);

  void _removeNotesByAuthor(String authorId) =>
      _feed.removeNotesByAuthor(authorId);

  @override
  void dispose() {
    _authService.dispose();
    autoplay.dispose();
    audio.dispose();
    super.dispose();
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
