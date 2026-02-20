import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/voice_note.dart';
import 'firebase_repository.dart';

class AbuseActionResult {
  const AbuseActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

/// Manages hidden notes and blocked authors: in-memory ID sets persisted to
/// SharedPreferences, with best-effort remote sync via FirebaseRepository.
///
/// Side-effects that touch AppState (feed maps, listeners, autoplay) are
/// delivered through the callbacks supplied at construction time.
class ModerationService {
  ModerationService({
    required SharedPreferences prefs,
    required FirebaseRepository repository,
    required String? Function() userId,
    required bool Function() isDevUnauthed,
    required void Function(String noteId) onNoteRemoved,
    required void Function(String authorId) onAuthorRemoved,
    required void Function() onStateChanged,
    required Future<void> Function(String, {String? message}) onSuppressNote,
    required Future<void> Function(String, {String? message}) onSuppressAuthor,
  })  : _prefs = prefs,
        _repository = repository,
        _userId = userId,
        _isDevUnauthed = isDevUnauthed,
        _onNoteRemoved = onNoteRemoved,
        _onAuthorRemoved = onAuthorRemoved,
        _onStateChanged = onStateChanged,
        _onSuppressNote = onSuppressNote,
        _onSuppressAuthor = onSuppressAuthor {
    final blocked = prefs.getStringList(_blockedAuthorIdsKey) ?? const [];
    final hidden = prefs.getStringList(_hiddenNoteIdsKey) ?? const [];
    _blockedAuthorIds.addAll(blocked.where((id) => id.trim().isNotEmpty));
    _hiddenNoteIds.addAll(hidden.where((id) => id.trim().isNotEmpty));
  }

  static const _blockedAuthorIdsKey = 'blocked_author_ids';
  static const _hiddenNoteIdsKey = 'hidden_note_ids';

  final SharedPreferences _prefs;
  final FirebaseRepository _repository;
  final String? Function() _userId;
  final bool Function() _isDevUnauthed;
  final void Function(String) _onNoteRemoved;
  final void Function(String) _onAuthorRemoved;
  final void Function() _onStateChanged;
  final Future<void> Function(String, {String? message}) _onSuppressNote;
  final Future<void> Function(String, {String? message}) _onSuppressAuthor;

  final Set<String> _blockedAuthorIds = {};
  final Set<String> _hiddenNoteIds = {};

  /// Unmodifiable views used for autoplay seeding.
  Set<String> get hiddenNoteIds => Set.unmodifiable(_hiddenNoteIds);
  Set<String> get blockedAuthorIds => Set.unmodifiable(_blockedAuthorIds);

  bool isAuthorBlocked(String? authorId) {
    if (authorId == null || authorId.isEmpty) return false;
    return _blockedAuthorIds.contains(authorId);
  }

  bool isNoteHidden(String noteId) {
    if (noteId.isEmpty) return false;
    return _hiddenNoteIds.contains(noteId);
  }

  List<VoiceNote> filterNotes(List<VoiceNote> notes) {
    if (_blockedAuthorIds.isEmpty && _hiddenNoteIds.isEmpty) return notes;
    return notes
        .where(
          (note) =>
              !_hiddenNoteIds.contains(note.id) &&
              !isAuthorBlocked(note.authorId),
        )
        .toList();
  }

  Future<AbuseActionResult> reportClip({
    required VoiceNote note,
    required String reason,
    String? details,
  }) async {
    _hideNoteLocally(note);
    final currentUser = _userId();
    if (currentUser == null || _isDevUnauthed()) {
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
    if (authorId == _userId()) {
      return const AbuseActionResult(
        success: false,
        message: 'You cannot block yourself.',
      );
    }
    final wasNew = _blockedAuthorIds.add(authorId);
    _persistBlockedAuthors();
    _onAuthorRemoved(authorId);
    unawaited(_onSuppressAuthor(authorId, message: 'User blocked.'));
    _onStateChanged();

    final currentUser = _userId();
    if (currentUser == null || _isDevUnauthed()) {
      return AbuseActionResult(
        success: false,
        message:
            wasNew ? 'User blocked locally.' : 'User already blocked locally.',
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
        message:
            wasNew ? 'Block saved locally.' : 'User already blocked locally.',
      );
    }
  }

  AbuseActionResult hideClip(VoiceNote note) {
    if (_hideNoteLocally(note)) {
      return const AbuseActionResult(success: true, message: 'Clip hidden.');
    }
    return const AbuseActionResult(
        success: true, message: 'Clip already hidden.');
  }

  bool _hideNoteLocally(VoiceNote note) {
    if (note.id.isEmpty) return false;
    final wasNew = _hiddenNoteIds.add(note.id);
    if (wasNew) {
      _persistHiddenNotes();
      _onNoteRemoved(note.id);
      unawaited(_onSuppressNote(note.id, message: 'Clip hidden.'));
      _onStateChanged();
    }
    return wasNew;
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
    final list =
        _blockedAuthorIds.where((id) => id.trim().isNotEmpty).toList();
    _prefs.setStringList(_blockedAuthorIdsKey, list);
  }
}
