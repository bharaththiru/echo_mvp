import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/hashtag.dart';
import '../models/voice_note.dart';
import '../utils/id_generator.dart';
import 'audio_controller.dart';
import 'feed_service.dart';
import 'firebase_repository.dart';

class PostService {
  PostService({
    required SharedPreferences prefs,
    required FirebaseRepository repository,
    required FeedService feed,
    required AudioController audio,
    required String? Function() userId,
    required bool Function() isDevUnauthed,
    required bool Function() skipAuth,
    required void Function() onStateChanged,
    required String recordingsDirectory,
    PendingPostDraft? initialDraft,
    String? initialRecordingPath,
  }) : _prefs = prefs,
       _repository = repository,
       _feed = feed,
       _audio = audio,
       _userId = userId,
       _isDevUnauthed = isDevUnauthed,
       _skipAuth = skipAuth,
       _onStateChanged = onStateChanged,
       _recordingsDirectory = recordingsDirectory,
       _pendingPostDraft = initialDraft,
       pendingRecordingPath = initialRecordingPath;

  static const _postRateLimitKey = 'post_rate_limit';
  static const _pendingRecordingKey = 'pending_recording_path';
  static const _pendingPostDraftKey = 'pending_post_draft';
  static const _uploadTimeout = Duration(seconds: 20);
  static const _postTimeout = Duration(seconds: 12);
  static const _postRateLimitWindow = Duration(hours: 1);
  static const _postRateLimitMax = 20;

  final SharedPreferences _prefs;
  final FirebaseRepository _repository;
  final FeedService _feed;
  final AudioController _audio;
  final String? Function() _userId;
  final bool Function() _isDevUnauthed;
  final bool Function() _skipAuth;
  final void Function() _onStateChanged;
  final String _recordingsDirectory;
  final IdGenerator _idGenerator = IdGenerator();

  PendingPostDraft? _pendingPostDraft;
  Future<VoiceNote>? _postInFlight;
  String? pendingRecordingPath;

  // ── Startup resolution ────────────────────────────────────────────────────

  static Future<({PendingPostDraft? draft, String? recordingPath})>
  resolveStartup(SharedPreferences prefs) async {
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
    return (draft: pendingDraft, recordingPath: resolvedRecordingPath);
  }

  // ── Accessors ─────────────────────────────────────────────────────────────

  bool get isPosting => _postInFlight != null;

  PendingPostDraft? get pendingPostDraft => _pendingPostDraft;

  // ── ID / path creation ────────────────────────────────────────────────────

  String createNoteId() => _idGenerator.next();

  String createRecordingPath() {
    final id = _idGenerator.next();
    return '$_recordingsDirectory${Platform.pathSeparator}echo_$id.m4a';
  }

  // ── Draft / recording management ──────────────────────────────────────────

  void savePendingPostDraft(PendingPostDraft draft) {
    _pendingPostDraft = draft;
    _prefs.setString(_pendingPostDraftKey, jsonEncode(draft.toJson()));
    _onStateChanged();
  }

  void clearPendingPostDraft() {
    _pendingPostDraft = null;
    _prefs.remove(_pendingPostDraftKey);
    _onStateChanged();
  }

  void setPendingRecordingPath(String path) {
    pendingRecordingPath = path;
    if (path.isEmpty) {
      _prefs.remove(_pendingRecordingKey);
    } else {
      _prefs.setString(_pendingRecordingKey, path);
    }
    _onStateChanged();
  }

  void clearPendingRecording() {
    pendingRecordingPath = null;
    _prefs.remove(_pendingRecordingKey);
    _onStateChanged();
  }

  // ── Post ──────────────────────────────────────────────────────────────────

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
    _onStateChanged();
    try {
      return await future;
    } finally {
      if (_postInFlight == future) {
        _postInFlight = null;
        _onStateChanged();
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
    final currentUser = _userId();
    if (currentUser == null) {
      if (!_isDevUnauthed()) {
        if (_skipAuth()) {
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
    final duration = await _audio.getAudioDuration(recordingPath);
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
    final expiresAt =
        expiresIn24h ? DateTime.now().add(const Duration(hours: 24)) : null;

    if (_isDevUnauthed()) {
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
      _feed.cacheNote(localNote, localOnly: true);
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
      // Firestore write failed — remove the already-uploaded Storage file so
      // it does not become a permanent orphan.  This is best-effort: the
      // internal catch inside deleteAudio ensures cleanup errors never mask
      // the original failure reported to the caller.
      unawaited(_repository.deleteAudio(storagePath));
      throw PostException('Post timed out. Please retry.');
    } catch (_) {
      unawaited(_repository.deleteAudio(storagePath));
      throw PostException('Unable to publish right now.');
    }
    final updated = note.copyWith(localPath: recordingPath);
    _feed.cacheNote(updated);
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

  // ── Rate limit ────────────────────────────────────────────────────────────

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

  // ── File helpers ──────────────────────────────────────────────────────────

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
      created =
          createdRaw == null ? DateTime.now() : DateTime.parse(createdRaw);
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
