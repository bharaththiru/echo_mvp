import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../data/seed_data.dart';
import '../models/hashtag.dart';
import '../models/voice_note.dart';
import '../services/audio_controller.dart';
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
    required FirebaseAuth auth,
    required FirebaseRepository repository,
    required User? user,
    required String recordingsDirectory,
    required String audioCacheDirectory,
    required this.onboardingComplete,
    required this.onboardingInterests,
    required this.savedHashtags,
    required this.recentHashtagIds,
  }) : _prefs = prefs,
        _auth = auth,
        _repository = repository,
        _user = user,
        _recordingsDirectory = recordingsDirectory,
        _audioCacheDirectory = audioCacheDirectory,
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
  static const _skipQuotaDateKey = 'skip_quota_date';
  static const _skipQuotaRemainingKey = 'skip_quota_remaining';
  static const _blockedAuthorIdsKey = 'blocked_author_ids';
  static const _hiddenNoteIdsKey = 'hidden_note_ids';
  static const _postRateLimitKey = 'post_rate_limit';
  static const _pendingRecordingKey = 'pending_recording_path';
  static const _pendingPostDraftKey = 'pending_post_draft';
  static const _uploadTimeout = Duration(seconds: 20);
  static const _postTimeout = Duration(seconds: 12);
  static const _postRateLimitWindow = Duration(hours: 1);
  static const _postRateLimitMax = 20;
  static const _audioDiskCacheMaxEntries = 300;
  static const _remoteFeedTransientCooldown = Duration(seconds: 45);
  static const _remoteFeedPolicyCooldown = Duration(minutes: 10);

  final SharedPreferences _prefs;
  final IdGenerator _idGenerator;
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final FirebaseRepository _repository;
  late final StreamSubscription<User?> _authSubscription;
  User? _user;
  final AudioController audio;
  late final AutoplayController autoplay;
  final String _recordingsDirectory;
  final String _audioCacheDirectory;
  final List<Hashtag> _hashtags = [];
  final Map<String, List<VoiceNote>> _notesByHashtag = {};
  final Map<String, List<VoiceNote>> _localDevNotesByHashtag = {};
  final Map<String, bool> _notesRemoteAttempted = {};
  final Map<String, bool> _notesLoading = {};
  final Map<String, String?> _notesError = {};
  final Set<String> _blockedAuthorIds = <String>{};
  final Set<String> _hiddenNoteIds = <String>{};
  List<VoiceNote> _myPosts = [];
  bool _hashtagsLoading = false;
  bool _myPostsLoading = false;
  String? _hashtagsError;
  String? _myPostsError;
  final Map<String, String> _audioPathCache = <String, String>{};
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
    final auth = FirebaseAuth.instance;
    final repository = FirebaseRepository(
      firestore: FirebaseFirestore.instance,
      storage: FirebaseStorage.instance,
      storageCdnBaseUrl: FirebaseConfig.storageCdnBaseUrl,
    );
    final user = auth.currentUser;
    final recordingsDirectory = await _prepareRecordingsDirectory();
    final audioCacheDirectory = await _prepareAudioCacheDirectory();
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
    final blockedAuthors =
        prefs.getStringList(_blockedAuthorIdsKey) ?? <String>[];
    final hiddenNotes =
        prefs.getStringList(_hiddenNoteIdsKey) ?? <String>[];
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
    final state = AppState._(
      prefs: prefs,
      settings: settings,
      audio: audio,
      auth: auth,
      repository: repository,
      user: user,
      recordingsDirectory: recordingsDirectory,
      audioCacheDirectory: audioCacheDirectory,
      onboardingComplete: onboardingComplete,
      onboardingInterests: onboardingInterests,
      savedHashtags: savedHashtags,
      recentHashtagIds: recentHashtagIds,
    );
    state.pendingRecordingPath = resolvedRecordingPath;
    state._pendingPostDraft = pendingDraft;
    state._blockedAuthorIds
      ..clear()
      ..addAll(blockedAuthors.where((id) => id.trim().isNotEmpty));
    state._hiddenNoteIds
      ..clear()
      ..addAll(hiddenNotes.where((id) => id.trim().isNotEmpty));
    state.autoplay = AutoplayController(
      dataSource: state,
      feedQueueBuilder: state,
      audio: audio,
    );
    state.autoplay.syncSuppressed(
      noteIds: state._hiddenNoteIds,
      authorIds: state._blockedAuthorIds,
    );
    state._bindAuth();
    // Avoid blocking the first frame on network/auth work.
    unawaited(state._maybeAutoSignIn());
    unawaited(state.refreshHashtags());
    unawaited(state.refreshMyPosts());
    unawaited(state._pruneAudioDiskCacheLru());
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
    final audioCacheDirectory = audioCacheDir.path;
    final saved = hashtags.take(3).map((tag) => tag.name).toList();
    final state = AppState._(
      prefs: prefs,
      settings: resolvedSettings,
      audio: audio,
      auth: resolvedAuth,
      repository: resolvedRepository,
      user: null,
      recordingsDirectory: recordingsDirectory,
      audioCacheDirectory: audioCacheDirectory,
      onboardingComplete: onboardingComplete,
      onboardingInterests: saved,
      savedHashtags: saved,
      recentHashtagIds: const [],
    );
    state.autoplay = AutoplayController(
      dataSource: state,
      feedQueueBuilder: state,
      audio: audio,
    );
    state.autoplay.syncSuppressed(noteIds: const [], authorIds: const []);
    state._authSubscription = const Stream<User?>.empty().listen((_) {});
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

  static Future<String> _prepareAudioCacheDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final cache = Directory('${directory.path}/audio_cache');
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    return cache.path;
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

  Future<void> _maybeAutoSignIn() async {
    if (!FirebaseConfig.skipAuth || _user != null) {
      return;
    }
    final email = FirebaseConfig.devEmail;
    final password = FirebaseConfig.devPassword;
    if (email.isEmpty || password.isEmpty) {
      return;
    }
    try {
      final response = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = response.user;
    } on FirebaseAuthException {
      return;
    } catch (_) {
      return;
    }
  }

  void _bindAuth() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _user = user;
      refreshMyPosts(force: true);
      notifyListeners();
    });
  }

  bool get isAuthenticated => _user != null;

  bool get skipAuth => FirebaseConfig.skipAuth;

  String? get userEmail => _user?.email;

  String? get userId => _user?.uid;

  bool get _isDevUnauthed => skipAuth && _user == null;

  PendingPostDraft? get pendingPostDraft => _pendingPostDraft;

  bool get isPosting => _postInFlight != null;

  Future<UserCredential> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<UserCredential?> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return null;
    }
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential?> signInWithApple() async {
    final isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      throw FirebaseAuthException(
        code: 'apple-sign-in-unavailable',
        message: 'Sign in with Apple is not available on this device.',
      );
    }
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'apple-sign-in-failed',
        message: 'Unable to retrieve Apple identity token.',
      );
    }
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );
    return _auth.signInWithCredential(oauthCredential);
  }

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

  List<VoiceNote> _filterNotes(List<VoiceNote> notes) {
    if (_blockedAuthorIds.isEmpty && _hiddenNoteIds.isEmpty) {
      return notes;
    }
    return notes
        .where(
          (note) =>
              !_hiddenNoteIds.contains(note.id) &&
              !isAuthorBlocked(note.authorId),
        )
        .toList();
  }

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

  bool isAuthorBlocked(String? authorId) {
    if (authorId == null || authorId.isEmpty) {
      return false;
    }
    return _blockedAuthorIds.contains(authorId);
  }

  bool isNoteHidden(String noteId) {
    if (noteId.isEmpty) {
      return false;
    }
    return _hiddenNoteIds.contains(noteId);
  }

  Future<AbuseActionResult> reportClip({
    required VoiceNote note,
    required String reason,
    String? details,
  }) async {
    _hideNoteLocally(note);
    final currentUser = userId;
    if (currentUser == null || _isDevUnauthed) {
      return const AbuseActionResult(
        success: false,
        message: 'Report saved locally.',
      );
    }
    try {
      await _repository.reportClip(
        reporterUserId: currentUser,
        clipId: note.id,
        reason: reason,
        details: details,
      );
      return const AbuseActionResult(
        success: true,
        message: 'Report submitted.',
      );
    } catch (_) {
      return const AbuseActionResult(
        success: false,
        message: 'Report failed to send. Clip hidden locally.',
      );
    }
  }

  Future<AbuseActionResult> blockAuthor(VoiceNote note) async {
    final authorId = note.authorId;
    if (authorId == null || authorId.isEmpty) {
      _hideNoteLocally(note);
      return const AbuseActionResult(
        success: false,
        message: 'This clip cannot be blocked. Hidden locally instead.',
      );
    }
    if (authorId == userId) {
      return const AbuseActionResult(
        success: false,
        message: 'You cannot block yourself.',
      );
    }
    final wasNew = _blockedAuthorIds.add(authorId);
    _persistBlockedAuthors();
    _removeNotesByAuthor(authorId);
    unawaited(autoplay.suppressAuthor(authorId, message: 'User blocked.'));
    notifyListeners();

    final currentUser = userId;
    if (currentUser == null || _isDevUnauthed) {
      return AbuseActionResult(
        success: false,
        message: wasNew
            ? 'User blocked locally.'
            : 'User already blocked locally.',
      );
    }
    try {
      await _repository.blockUser(
        blockerUserId: currentUser,
        blockedUserId: authorId,
      );
      return AbuseActionResult(
        success: true,
        message: wasNew ? 'User blocked.' : 'User already blocked.',
      );
    } catch (_) {
      return AbuseActionResult(
        success: false,
        message: wasNew
            ? 'Block saved locally.'
            : 'User already blocked locally.',
      );
    }
  }

  AbuseActionResult hideClip(VoiceNote note) {
    if (_hideNoteLocally(note)) {
      return const AbuseActionResult(
        success: true,
        message: 'Clip hidden.',
      );
    }
    return const AbuseActionResult(
      success: true,
      message: 'Clip already hidden.',
    );
  }

  bool _hideNoteLocally(VoiceNote note) {
    if (note.id.isEmpty) {
      return false;
    }
    final wasNew = _hiddenNoteIds.add(note.id);
    if (wasNew) {
      _persistHiddenNotes();
      _removeNoteById(note.id);
      unawaited(autoplay.suppressNote(note.id, message: 'Clip hidden.'));
      notifyListeners();
    }
    return wasNew;
  }

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
  Future<String?> ensureLocalAudioPath(VoiceNote note) async {
    if (note.localPath != null && await File(note.localPath!).exists()) {
      await _touchCachedFile(File(note.localPath!));
      return note.localPath;
    }
    final cachedPath = _audioPathCache[note.id];
    if (cachedPath != null && cachedPath.isNotEmpty) {
      if (_isRemotePath(cachedPath)) {
        return cachedPath;
      }
      final cachedFile = File(cachedPath);
      if (await cachedFile.exists()) {
        final size = await cachedFile.length();
        if (size > 0) {
          await _touchCachedFile(cachedFile);
          return cachedPath;
        }
      }
      _audioPathCache.remove(note.id);
    }
    if (note.storagePath.isEmpty) {
      return note.localPath;
    }
    final diskPath = await _ensureAudioDownloadedToDisk(note);
    if (diskPath != null && diskPath.isNotEmpty) {
      _audioPathCache[note.id] = diskPath;
      return diskPath;
    }
    try {
      final url = await _repository.fetchAudioUrl(note.storagePath);
      _audioPathCache[note.id] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  bool _isRemotePath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  String _cachePathForStorage(String storagePath) {
    final digest = sha1.convert(utf8.encode(storagePath)).toString();
    final ext = _extensionForStoragePath(storagePath);
    return '$_audioCacheDirectory${Platform.pathSeparator}$digest$ext';
  }

  String _extensionForStoragePath(String storagePath) {
    final dot = storagePath.lastIndexOf('.');
    if (dot < 0 || dot >= storagePath.length - 1) {
      return '.m4a';
    }
    final ext = storagePath.substring(dot);
    if (ext.length > 8 || ext.contains('/') || ext.contains('\\')) {
      return '.m4a';
    }
    return ext;
  }

  Future<String?> _ensureAudioDownloadedToDisk(VoiceNote note) async {
    if (note.storagePath.isEmpty) {
      return null;
    }
    final cachePath = _cachePathForStorage(note.storagePath);
    final file = File(cachePath);
    if (await file.exists()) {
      try {
        final size = await file.length();
        if (size > 0) {
          await _touchCachedFile(file);
          return file.path;
        }
        await file.delete();
      } catch (_) {
        // Attempt fresh download when cached file is invalid.
      }
    }
    try {
      final bytes = await _repository.downloadAudio(note.storagePath);
      if (bytes.isEmpty) {
        return null;
      }
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await _touchCachedFile(file);
      _audioPathCache[note.id] = file.path;
      unawaited(_pruneAudioDiskCacheLru());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _touchCachedFile(File file) async {
    try {
      await file.setLastModified(DateTime.now().toUtc());
    } catch (_) {
      // Ignore file timestamp updates.
    }
  }

  Future<void> _pruneAudioDiskCacheLru() async {
    final dir = Directory(_audioCacheDirectory);
    if (!await dir.exists()) {
      return;
    }
    final entities = await dir.list(followLinks: false).toList();
    final files = <_CachedDiskFile>[];
    for (final entity in entities) {
      if (entity is! File) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        files.add(_CachedDiskFile(file: entity, modified: stat.modified));
      } catch (_) {
        // Skip files that cannot be inspected.
      }
    }
    if (files.length <= _audioDiskCacheMaxEntries) {
      return;
    }
    files.sort((a, b) => a.modified.compareTo(b.modified));
    final toDelete = files.length - _audioDiskCacheMaxEntries;
    for (var i = 0; i < toDelete; i++) {
      final path = files[i].file.path;
      try {
        await files[i].file.delete();
      } catch (_) {
        // Skip files that cannot be deleted.
      }
      _audioPathCache.removeWhere((_, value) => value == path);
    }
  }

  @override
  Future<SkipQuotaResult> consumeSkip() async {
    if (_isDevUnauthed) {
      return _consumeSkipLocal(scope: 'dev');
    }
    final currentUser = userId;
    if (currentUser == null) {
      return _consumeSkipLocal(scope: 'anon');
    }
    try {
      final response = await _repository.consumeSkip(userId: currentUser);
      final ok = response['ok'] == true;
      final skipsLeft = _parseInt(response['skips_left']);
      final date = response['local_date']?.toString() ?? _localDateKey();
      _writeSkipCache(scope: currentUser, date: date, remaining: skipsLeft);
      return SkipQuotaResult(
        allowed: ok,
        skipsLeft: skipsLeft,
        message: ok ? null : 'No skips left today.',
      );
    } catch (_) {
      return _consumeSkipFromCache(scope: currentUser);
    }
  }

  SkipQuotaResult _consumeSkipLocal({required String scope}) {
    final today = _localDateKey();
    final cached = _readSkipCache(scope: scope);
    final remaining = cached != null && cached.date == today
        ? cached.remaining
        : 3;
    if (remaining <= 0) {
      _writeSkipCache(scope: scope, date: today, remaining: 0);
      return const SkipQuotaResult(
        allowed: false,
        skipsLeft: 0,
        message: 'No skips left today.',
      );
    }
    final nextRemaining = remaining - 1;
    _writeSkipCache(scope: scope, date: today, remaining: nextRemaining);
    return SkipQuotaResult(allowed: true, skipsLeft: nextRemaining);
  }

  SkipQuotaResult _consumeSkipFromCache({required String scope}) {
    final cached = _readSkipCache(scope: scope);
    if (cached == null) {
      return const SkipQuotaResult(
        allowed: false,
        skipsLeft: 0,
        message: 'Skip unavailable offline. Reconnect to refresh your quota.',
      );
    }
    final today = _localDateKey();
    if (cached.date != today) {
      return SkipQuotaResult(
        allowed: false,
        skipsLeft: cached.remaining,
        message: 'Skip unavailable offline. Reconnect to refresh your quota.',
      );
    }
    if (cached.remaining <= 0) {
      return const SkipQuotaResult(
        allowed: false,
        skipsLeft: 0,
        message: 'No skips left today.',
      );
    }
    final nextRemaining = cached.remaining - 1;
    _writeSkipCache(scope: scope, date: cached.date, remaining: nextRemaining);
    return SkipQuotaResult(allowed: true, skipsLeft: nextRemaining);
  }

  void _writeSkipCache({
    required String scope,
    required String date,
    required int remaining,
  }) {
    _prefs.setString(_skipCacheKey(scope, _skipQuotaDateKey), date);
    _prefs.setInt(_skipCacheKey(scope, _skipQuotaRemainingKey), remaining);
  }

  _SkipQuotaCache? _readSkipCache({required String scope}) {
    final date = _prefs.getString(_skipCacheKey(scope, _skipQuotaDateKey));
    final remaining =
        _prefs.getInt(_skipCacheKey(scope, _skipQuotaRemainingKey));
    if (date == null || remaining == null) {
      return null;
    }
    return _SkipQuotaCache(date: date, remaining: remaining);
  }

  String _skipCacheKey(String scope, String key) => '$key:$scope';

  String _localDateKey() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

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

  int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  void _persistHiddenNotes() {
    const maxEntries = 200;
    final list = _hiddenNoteIds.where((id) => id.trim().isNotEmpty).toList();
    if (list.length > maxEntries) {
      final trimmed = list.sublist(list.length - maxEntries);
      _hiddenNoteIds
        ..clear()
        ..addAll(trimmed);
      _prefs.setStringList(_hiddenNoteIdsKey, trimmed);
      return;
    }
    _prefs.setStringList(_hiddenNoteIdsKey, list);
  }

  void _persistBlockedAuthors() {
    final list = _blockedAuthorIds.where((id) => id.trim().isNotEmpty).toList();
    _prefs.setStringList(_blockedAuthorIdsKey, list);
  }

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
    _authSubscription.cancel();
    autoplay.dispose();
    audio.dispose();
    super.dispose();
  }
}

String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List<String>.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
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

class _SkipQuotaCache {
  const _SkipQuotaCache({required this.date, required this.remaining});

  final String date;
  final int remaining;
}

class _CachedDiskFile {
  const _CachedDiskFile({required this.file, required this.modified});

  final File file;
  final DateTime modified;
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

class AbuseActionResult {
  const AbuseActionResult({required this.success, required this.message});

  final bool success;
  final String message;
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
