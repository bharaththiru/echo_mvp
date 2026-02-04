import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/voice_note.dart';
import 'autoplay_data_source.dart';
import 'audio_playback_controller.dart';
import 'audio_playback_state.dart';

enum AutoplayPhase {
  idle,
  loading,
  playing,
  paused,
  buffering,
  completed,
  transitioning,
  interrupted,
  error,
}

enum _AdvanceReason { autoplay, userSkip, errorRecovery }

class AutoplayState {
  const AutoplayState({
    required this.hashtagId,
    required this.queue,
    required this.queueDepth,
    required this.queueRemaining,
    required this.currentIndex,
    required this.currentNote,
    required this.phase,
    required this.isPreparing,
    required this.isTransitioning,
    required this.userPaused,
    required this.handsFree,
    required this.volume,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.isLoadingNotes,
    required this.loadError,
    required this.statusText,
    required this.errorMessage,
    required this.preloadingNoteId,
    required this.transientMessage,
    required this.isMuted,
  });

  final String? hashtagId;
  final List<VoiceNote> queue;
  final int queueDepth;
  final int queueRemaining;
  final int currentIndex;
  final VoiceNote? currentNote;
  final AutoplayPhase phase;
  final bool isPreparing;
  final bool isTransitioning;
  final bool userPaused;
  final bool handsFree;
  final double volume;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final bool isLoadingNotes;
  final String? loadError;
  final String? statusText;
  final String? errorMessage;
  final String? preloadingNoteId;
  final String? transientMessage;
  final bool isMuted;

  bool get hasNotes => queue.isNotEmpty;

  bool get isPlaying => phase == AutoplayPhase.playing;

  bool get isBuffering =>
      phase == AutoplayPhase.loading || phase == AutoplayPhase.buffering;

  double get progress {
    if (duration.inMilliseconds <= 0) {
      return 0;
    }
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    if (ratio.isNaN) {
      return 0;
    }
    return ratio.clamp(0, 1);
  }

  List<VoiceNote> upcoming({int take = 3}) {
    if (queue.isEmpty) {
      return const [];
    }
    final start = (currentIndex + 1).clamp(0, queue.length).toInt();
    return queue.skip(start).take(take).toList();
  }

  AutoplayState copyWith({
    String? hashtagId,
    List<VoiceNote>? queue,
    int? queueDepth,
    int? queueRemaining,
    int? currentIndex,
    VoiceNote? currentNote,
    AutoplayPhase? phase,
    bool? isPreparing,
    bool? isTransitioning,
    bool? userPaused,
    bool? handsFree,
    double? volume,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? isLoadingNotes,
    Object? loadError = _unset,
    Object? statusText = _unset,
    Object? errorMessage = _unset,
    Object? preloadingNoteId = _unset,
    Object? transientMessage = _unset,
    bool? isMuted,
  }) {
    return AutoplayState(
      hashtagId: hashtagId ?? this.hashtagId,
      queue: queue ?? this.queue,
      queueDepth: queueDepth ?? this.queueDepth,
      queueRemaining: queueRemaining ?? this.queueRemaining,
      currentIndex: currentIndex ?? this.currentIndex,
      currentNote: currentNote ?? this.currentNote,
      phase: phase ?? this.phase,
      isPreparing: isPreparing ?? this.isPreparing,
      isTransitioning: isTransitioning ?? this.isTransitioning,
      userPaused: userPaused ?? this.userPaused,
      handsFree: handsFree ?? this.handsFree,
      volume: volume ?? this.volume,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      isLoadingNotes: isLoadingNotes ?? this.isLoadingNotes,
      loadError: identical(loadError, _unset)
          ? this.loadError
          : loadError as String?,
      statusText: identical(statusText, _unset)
          ? this.statusText
          : statusText as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      preloadingNoteId: identical(preloadingNoteId, _unset)
          ? this.preloadingNoteId
          : preloadingNoteId as String?,
      transientMessage: identical(transientMessage, _unset)
          ? this.transientMessage
          : transientMessage as String?,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  static const _unset = Object();

  static const empty = AutoplayState(
    hashtagId: null,
    queue: [],
    queueDepth: 0,
    queueRemaining: 0,
    currentIndex: 0,
    currentNote: null,
    phase: AutoplayPhase.idle,
    isPreparing: false,
    isTransitioning: false,
    userPaused: false,
    handsFree: false,
    volume: 0.8,
    position: Duration.zero,
    duration: Duration.zero,
    bufferedPosition: Duration.zero,
    isLoadingNotes: false,
    loadError: null,
    statusText: null,
    errorMessage: null,
    preloadingNoteId: null,
    transientMessage: null,
    isMuted: false,
  );
}

class AutoplayController extends ChangeNotifier {
  AutoplayController({
    required AutoplayDataSource dataSource,
    required AudioPlaybackController audio,
  }) : _dataSource = dataSource,
       _audio = audio,
       _userVolume = audio.state.volume,
       _state = AutoplayState.empty.copyWith(
         volume: audio.state.volume,
         isMuted: false,
       ) {
    _audio.addListener(_handleAudioChanged);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[Autoplay] $message');
    }
  }

  int _queueRemaining() {
    if (_playbackQueueIds.isEmpty || _playbackQueueIndex < 0) {
      return 0;
    }
    final remaining = _playbackQueueIds.length - _playbackQueueIndex - 1;
    return remaining < 0 ? 0 : remaining;
  }

  bool _shouldAvoidRecent() {
    return _state.queue.length > _recentPlaybackWindow &&
        _recentlyPlayedIds.isNotEmpty;
  }

  void _markPlayed(String noteId) {
    if (noteId.isEmpty) {
      return;
    }
    _playedIds.add(noteId);
    _recentlyPlayedIds.remove(noteId);
    _recentlyPlayedIds.add(noteId);
    while (_recentlyPlayedIds.length > _recentPlaybackWindow) {
      _recentlyPlayedIds.removeFirst();
    }
  }

  String? _resolveActiveId(AudioPlaybackState audioState) {
    final queueIndex = audioState.queueIndex;
    if (queueIndex != null &&
        queueIndex >= 0 &&
        queueIndex < _playbackQueueIds.length) {
      return _playbackQueueIds[queueIndex];
    }
    final direct = audioState.sourceId;
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final path = audioState.path;
    if (path != null && path.isNotEmpty) {
      for (final entry in _cachedPaths.entries) {
        if (entry.value == path) {
          return entry.key;
        }
      }
    }
    return null;
  }

  final AutoplayDataSource _dataSource;
  final AudioPlaybackController _audio;

  AutoplayState _state;
  AutoplayState get state => _state;

  final Set<String> _playedIds = <String>{};
  final ListQueue<String> _recentlyPlayedIds = ListQueue<String>();
  final Set<String> _failedIds = <String>{};
  final Set<String> _suppressedNoteIds = <String>{};
  final Set<String> _suppressedAuthorIds = <String>{};
  final Set<String> _preloadInFlight = <String>{};
  final Map<String, String> _cachedPaths = <String, String>{};
  final Map<String, VoiceNote> _playbackQueueNotes =
      <String, VoiceNote>{};
  Timer? _stallTimer;
  int _stallToken = 0;
  DateTime? _lastQueueRefreshAt;
  bool _skipInFlight = false;
  Timer? _messageTimer;
  int _consecutiveFailures = 0;
  int _sessionToken = 0;
  Future<void>? _pendingStop;

  bool _attached = false;
  String? _activeHashtagId;
  String _notesSignature = '';
  int _playToken = 0;
  bool _resumeAfterInterruption = false;
  Duration? _resumePosition;
  String? _resumeNoteId;
  String? _mutedNoteId;
  double _userVolume;
  final List<String> _playbackQueueIds = <String>[];
  int _playbackQueueIndex = -1;
  bool _queueFillInFlight = false;
  bool _isDisposed = false;
  bool _wrappedQueue = false;
  String? _positionNoteId;
  Duration _lastObservedPosition = Duration.zero;
  int _positionResetCount = 0;
  String? _lastLoggedSourceId;
  int? _lastLoggedQueueIndex;

  static const _resolveTimeout = Duration(seconds: 8);
  static const _maxConsecutiveFailures = 3;
  static const _stallTimeout = Duration(seconds: 10);
  static const _queueRefreshCooldown = Duration(seconds: 30);
  static const _queueRefreshThreshold = 2;
  static const _positionResetMinPosition = Duration(seconds: 4);
  static const _positionResetThreshold = Duration(seconds: 2);
  static const _maxPositionResetsPerClip = 2;
  static const _queueFillTarget = 4;
  static const _queueRefillThreshold = 2;
  static const _recentPlaybackWindow = 3;

  void attach(String hashtagId, {bool forceRefresh = false}) {
    if (_isDisposed) {
      return;
    }
    _log('attach hashtag=$hashtagId force=$forceRefresh');
    final hashtagChanged = _activeHashtagId != hashtagId;
    _activeHashtagId = hashtagId;
    if (!_attached) {
      _attached = true;
      _dataSource.addListener(_handleDataSourceChanged);
    }
    if (hashtagChanged) {
      _resetSession(hashtagId: hashtagId, stopPlayback: true);
    }
    unawaited(_ensureNotesLoaded(force: forceRefresh || hashtagChanged));
  }

  Future<void> detach({bool stopPlayback = true, String? hashtagId}) async {
    if (!_attached) {
      return;
    }
    _log('detach hashtag=$hashtagId stop=$stopPlayback');
    if (hashtagId != null && _activeHashtagId != null) {
      if (hashtagId != _activeHashtagId) {
        return;
      }
    }
    _attached = false;
    _activeHashtagId = null;
    _dataSource.removeListener(_handleDataSourceChanged);
    _cancelStallGuard();
    _clearTransientMessage();
    if (stopPlayback) {
      final pending = _audio.stop();
      _pendingStop = pending;
      try {
        await pending;
      } finally {
        if (_pendingStop == pending) {
          _pendingStop = null;
        }
      }
    }
  }

  void syncSuppressed({
    Iterable<String> noteIds = const [],
    Iterable<String> authorIds = const [],
  }) {
    if (_isDisposed) {
      return;
    }
    final currentId = _audio.state.sourceId ?? _state.currentNote?.id;
    final currentAuthor = _state.currentNote?.authorId;
    _suppressedNoteIds
      ..clear()
      ..addAll(noteIds.where((id) => id.trim().isNotEmpty));
    _suppressedAuthorIds
      ..clear()
      ..addAll(authorIds.where((id) => id.trim().isNotEmpty));
    final shouldAdvance =
        (currentId != null && _suppressedNoteIds.contains(currentId)) ||
        (currentAuthor != null && _suppressedAuthorIds.contains(currentAuthor));
    unawaited(_advanceFromSuppression(shouldAdvance));
    _refreshFromDataSource(forceRebuild: true);
  }

  Future<void> suppressNote(String noteId, {String? message}) async {
    if (noteId.trim().isEmpty || _isDisposed) {
      return;
    }
    final shouldAdvance =
        _audio.state.sourceId == noteId || _state.currentNote?.id == noteId;
    _suppressedNoteIds.add(noteId);
    await _advanceFromSuppression(shouldAdvance, message: message);
    _refreshFromDataSource(forceRebuild: true);
  }

  Future<void> suppressAuthor(String authorId, {String? message}) async {
    if (authorId.trim().isEmpty || _isDisposed) {
      return;
    }
    final currentNote = _state.currentNote;
    final shouldAdvance =
        currentNote != null && currentNote.authorId == authorId;
    _suppressedAuthorIds.add(authorId);
    await _advanceFromSuppression(shouldAdvance, message: message);
    _refreshFromDataSource(forceRebuild: true);
  }

  Future<void> _ensureNotesLoaded({required bool force}) async {
    final hashtagId = _activeHashtagId;
    if (hashtagId == null) {
      return;
    }
    final sessionToken = _sessionToken;
    final isLoading = _dataSource.isLoadingNotes(hashtagId);
    final hasNotes = _dataSource.notesForHashtag(hashtagId).isNotEmpty;
    if (isLoading || (!force && hasNotes)) {
      _refreshFromDataSource();
      return;
    }
    _setState(
      _state.copyWith(
        hashtagId: hashtagId,
        isLoadingNotes: true,
        phase: AutoplayPhase.loading,
        loadError: null,
        statusText: null,
        errorMessage: null,
      ),
    );
    await _dataSource.loadNotesForHashtag(hashtagId, force: force);
    if (_activeHashtagId != hashtagId ||
        !_isSessionCurrent(sessionToken) ||
        _isDisposed) {
      return;
    }
    _refreshFromDataSource(forceRebuild: true);
  }

  void _handleDataSourceChanged() {
    if (_activeHashtagId == null || _isDisposed) {
      return;
    }
    _refreshFromDataSource();
  }

  void _refreshFromDataSource({bool forceRebuild = false}) {
    final hashtagId = _activeHashtagId;
    if (hashtagId == null) {
      return;
    }
    final notes = _dataSource.notesForHashtag(hashtagId);
    final signature = notes.map((note) => note.id).join('|');
    final changed = signature != _notesSignature;
    _notesSignature = signature;
    final loading = _dataSource.isLoadingNotes(hashtagId);
    final loadError = _dataSource.notesError(hashtagId);

    _setState(
      _state.copyWith(
        hashtagId: hashtagId,
        isLoadingNotes: loading,
        loadError: loadError,
        statusText: loadError == null ? _state.statusText : null,
        errorMessage: loadError,
      ),
    );

    if (notes.isEmpty) {
      if (!loading && loadError != null) {
        _setState(
          _state.copyWith(phase: AutoplayPhase.error, errorMessage: loadError),
        );
      }
      if (!loading && loadError == null) {
        _setState(
          _state.copyWith(
            queue: const [],
            currentIndex: 0,
            currentNote: null,
            phase: AutoplayPhase.completed,
            isPreparing: false,
            isTransitioning: false,
            statusText: "It's quiet here. Check back later.",
            errorMessage: null,
            isMuted: false,
          ),
        );
        unawaited(_audio.stop());
      }
      return;
    }

    if (changed || forceRebuild) {
      _rebuildQueue(notes);
    }

    final shouldStart =
        !_state.userPaused &&
        !_state.isPreparing &&
        !_state.isTransitioning &&
        (_state.phase == AutoplayPhase.idle ||
            _state.phase == AutoplayPhase.loading);
    if (shouldStart) {
      unawaited(_startAutoplay());
    }
  }

  void _rebuildQueue(List<VoiceNote> notes) {
    final deduped = <String, VoiceNote>{};
    for (final note in notes) {
      if (_isSuppressedNote(note)) {
        continue;
      }
      deduped[note.id] = note;
    }
    final queue = deduped.values.toList();
    final availableIds = deduped.keys.toSet();
    _playedIds.removeWhere((id) => !availableIds.contains(id));
    _failedIds.removeWhere((id) => !availableIds.contains(id));
    final currentNote = _state.currentNote;
    final currentId = currentNote?.id;
    final currentSuppressed =
        currentNote != null && _isSuppressedNote(currentNote);
    if (currentNote != null &&
        !deduped.containsKey(currentNote.id) &&
        !currentSuppressed) {
      queue.insert(0, currentNote);
    }
    final currentIndex = currentId == null
        ? 0
        : queue.indexWhere((note) => note.id == currentId);
    final resolvedIndex = currentIndex < 0 ? 0 : currentIndex;
    final safeIndex = queue.isEmpty
        ? 0
        : resolvedIndex.clamp(0, queue.length - 1).toInt();
    final resolvedNote = queue.isEmpty ? null : queue[safeIndex];
    if (resolvedNote != null) {
      _resetMuteForNote(resolvedNote.id);
    }
    _setState(
      _state.copyWith(
        queue: queue,
        currentIndex: resolvedNote == null ? 0 : safeIndex,
        currentNote: resolvedNote,
        errorMessage: null,
        isMuted: resolvedNote != null && _isMutedNote(resolvedNote.id),
      ),
    );
    if (resolvedNote != null) {
      _preloadNextFrom(safeIndex);
    }
  }

  Future<void> _startAutoplay() async {
    final hashtagId = _activeHashtagId;
    if (hashtagId == null || _isDisposed) {
      return;
    }
    final notes = _dataSource.notesForHashtag(hashtagId);
    if (notes.isEmpty) {
      return;
    }
    _log('start autoplay hashtag=$hashtagId notes=${notes.length}');
    _rebuildQueue(notes);
    if (_state.queue.isEmpty) {
      return;
    }
    final nextIndex = _nextPlayableIndex(fromIndex: -1);
    if (nextIndex == null) {
      _setState(_state.copyWith(phase: AutoplayPhase.completed));
      return;
    }
    await _playIndex(nextIndex, phaseOverride: AutoplayPhase.loading);
  }

  Future<void> togglePlayPause() async {
    if (_state.isPreparing || _state.isTransitioning) {
      return;
    }
    if (_state.phase == AutoplayPhase.error) {
      _setState(_state.copyWith(userPaused: false, errorMessage: null));
      await restart();
      return;
    }
    final currentNote = _state.currentNote;
    if (currentNote == null) {
      await _startAutoplay();
      return;
    }
    if (_state.isPlaying) {
      _setState(
        _state.copyWith(
          userPaused: true,
          phase: AutoplayPhase.paused,
          statusText: null,
          errorMessage: null,
        ),
      );
      await _audio.pause();
      return;
    }
    _resumeAfterInterruption = false;
    _setState(
      _state.copyWith(
        userPaused: false,
        phase: AutoplayPhase.playing,
        statusText: null,
        errorMessage: null,
      ),
    );
    if (_audio.state.sourceId == currentNote.id) {
      await _audio.resume();
      return;
    }
    await _playIndex(_state.currentIndex, phaseOverride: AutoplayPhase.loading);
  }

  Future<void> skip() async {
    if (_state.isTransitioning || _skipInFlight) {
      return;
    }
    if (_state.queue.length <= 1 || _state.currentNote == null) {
      return;
    }
    _skipInFlight = true;
    try {
      final result = await _dataSource.consumeSkip();
      if (!result.allowed) {
        _showTransientMessage(result.message ?? 'No skips left today.');
        return;
      }
      await _advance(_AdvanceReason.userSkip, stopCurrent: true);
    } catch (_) {
      _showTransientMessage('Skip unavailable right now.');
    } finally {
      _skipInFlight = false;
    }
  }

  Future<void> toggleMute() async {
    final currentNote = _state.currentNote;
    if (currentNote == null) {
      return;
    }
    final isMuted = _mutedNoteId == currentNote.id;
    if (isMuted) {
      _mutedNoteId = null;
      _setState(_state.copyWith(isMuted: false));
      await _audio.setVolume(_userVolume);
      return;
    }
    _mutedNoteId = currentNote.id;
    _setState(_state.copyWith(isMuted: true));
    await _audio.setVolume(0);
  }

  Future<void> muteCurrentClip() async {
    await toggleMute();
  }

  Future<void> playPrevious() async {
    if (_state.isTransitioning) {
      return;
    }
    if (_state.queue.isEmpty || _state.currentIndex <= 0) {
      return;
    }
    final previousIndex = _state.currentIndex - 1;
    await _jumpToIndex(previousIndex);
  }

  Future<void> playFromUpNext(int absoluteIndex) async {
    if (_state.isTransitioning) {
      return;
    }
    if (_state.queue.isEmpty) {
      return;
    }
    if (absoluteIndex < 0 || absoluteIndex >= _state.queue.length) {
      return;
    }
    await _jumpToIndex(absoluteIndex);
  }

  void setHandsFree(bool value) {
    if (_state.handsFree == value) {
      return;
    }
    _setState(_state.copyWith(handsFree: value));
  }

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    _userVolume = clamped;
    _setState(_state.copyWith(volume: clamped));
    if (_isCurrentMuted()) {
      return;
    }
    await _audio.setVolume(clamped);
  }

  Future<void> restart() async {
    _playToken++;
    _cancelStallGuard();
    _resumeAfterInterruption = false;
    _resumePosition = null;
    _resumeNoteId = null;
    _mutedNoteId = null;
    _consecutiveFailures = 0;
    _clearTransientMessage();
    _playedIds.clear();
    _recentlyPlayedIds.clear();
    _failedIds.clear();
    _playbackQueueIds.clear();
    _playbackQueueIndex = -1;
    _playbackQueueNotes.clear();
    _lastLoggedSourceId = null;
    _lastLoggedQueueIndex = null;
    await _startAutoplay();
  }

  Future<void> _playIndex(
    int index, {
    AutoplayPhase? phaseOverride,
    Duration? startPosition,
  }) async {
    if (_isDisposed || _activeHashtagId == null) {
      return;
    }
    if (index < 0 || index >= _state.queue.length) {
      return;
    }
    final token = ++_playToken;
    final note = _state.queue[index];
    if (_activeHashtagId == null || note.hashtagId != _activeHashtagId) {
      return;
    }
    _log(
      'play index=$index note=${note.id} queue=${_state.queue.length} phase=${phaseOverride ?? AutoplayPhase.loading}',
    );
    _cancelStallGuard();
    _resetMuteForNote(note.id);
    _setState(
      _state.copyWith(
        currentIndex: index,
        currentNote: note,
        phase: phaseOverride ?? AutoplayPhase.loading,
        isPreparing: true,
        isTransitioning: phaseOverride == AutoplayPhase.transitioning,
        statusText: null,
        errorMessage: null,
        isMuted: _isMutedNote(note.id),
      ),
    );
    await _awaitPendingStop();
    if (!_isTokenCurrent(token)) {
      return;
    }

    final queueItems = await _buildInitialQueue(index, token: token);
    if (!_isTokenCurrent(token) || queueItems.isEmpty) {
      return;
    }
    _playbackQueueIds
      ..clear()
      ..addAll(queueItems.map((item) => item.sourceId));
    _playbackQueueNotes
      ..clear()
      ..addEntries(
        queueItems.map((item) {
          final resolvedNote = _state.queue.firstWhere(
            (n) => n.id == item.sourceId,
            orElse: () => note,
          );
          return MapEntry(item.sourceId, resolvedNote);
        }),
      );
    _playbackQueueIndex = 0;
    await _audio.playQueue(
      queue: queueItems,
      initialIndex: 0,
      startPosition: startPosition,
    );
    if (!_isTokenCurrent(token)) {
      return;
    }

    _consecutiveFailures = 0;
    final mappedPhase = _mapFromAudio(_audio.state);
    final statusText = mappedPhase == AutoplayPhase.buffering
        ? _audio.state.statusText
        : null;
    _setState(
      _state.copyWith(
        isPreparing: false,
        isTransitioning: false,
        phase: mappedPhase,
        userPaused: false,
        statusText: statusText,
        errorMessage: mappedPhase == AutoplayPhase.error
            ? _audio.state.errorMessage
            : null,
      ),
    );
    _maybeRefreshQueue(index);
    _preloadNextFrom(index);
  }

  Future<String?> _resolvePath(VoiceNote note, {required int token}) async {
    final cached = _cachedPaths[note.id];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final local = note.localPath;
    if (local != null && local.isNotEmpty) {
      _cachedPaths[note.id] = local;
      return local;
    }
    final path = await _dataSource.ensureLocalAudioPath(note);
    if (!_isTokenCurrent(token) || path == null || path.isEmpty) {
      return path;
    }
    _cachedPaths[note.id] = path;
    return path;
  }

  Future<List<AudioQueueItem>> _buildInitialQueue(
    int startIndex, {
    required int token,
  }) async {
    if (startIndex < 0 || startIndex >= _state.queue.length) {
      return const <AudioQueueItem>[];
    }
    final items = <AudioQueueItem>[];
    final current = _state.queue[startIndex];
    String? currentPath;
    try {
      currentPath =
          await _resolvePath(current, token: token).timeout(_resolveTimeout);
    } on TimeoutException {
      currentPath = null;
    }
    if (!_isTokenCurrent(token) ||
        currentPath == null ||
        currentPath.isEmpty) {
      _log('resolve failed note=${current.id}');
      await _handleClipFailure(
        noteId: current.id,
        message: 'Clip unavailable. Skipping...',
      );
      return const <AudioQueueItem>[];
    }
    items.add(
      AudioQueueItem(
        sourceId: current.id,
        path: currentPath,
        duration: current.duration,
        title: current.hashtagLabel,
      ),
    );
    return items;
  }

  List<VoiceNote> _collectUpcomingSequential({
    required int fromIndex,
    required int take,
  }) {
    if (_state.queue.isEmpty) {
      return const <VoiceNote>[];
    }
    final upcoming = <VoiceNote>[];
    var cursor = fromIndex;
    for (var i = 0; i < take; i++) {
      final nextIndex = _nextSequentialIndex(fromIndex: cursor);
      if (nextIndex == null) {
        break;
      }
      upcoming.add(_state.queue[nextIndex]);
      cursor = nextIndex;
    }
    return upcoming;
  }

  int? _nextSequentialIndex({required int fromIndex}) {
    if (_state.queue.isEmpty) {
      return null;
    }
    int? pickNext({required bool avoidRecent}) {
      var cursor = fromIndex;
      for (var i = 0; i < _state.queue.length; i++) {
        final next = (cursor + 1) % _state.queue.length;
        final note = _state.queue[next];
        if (_isSuppressedNote(note) || _failedIds.contains(note.id)) {
          cursor = next;
          continue;
        }
        if (avoidRecent && _recentlyPlayedIds.contains(note.id)) {
          cursor = next;
          continue;
        }
        return next;
      }
      return null;
    }

    final avoidRecent = _shouldAvoidRecent();
    return pickNext(avoidRecent: avoidRecent) ??
        (avoidRecent ? pickNext(avoidRecent: false) : null);
  }

  Future<void> _advance(
    _AdvanceReason reason, {
    bool stopCurrent = false,
  }) async {
    if (_isDisposed || _state.queue.isEmpty) {
      return;
    }
    if (_state.isTransitioning) {
      return;
    }
    final sessionToken = _sessionToken;
    if (!_isSessionCurrent(sessionToken)) {
      return;
    }
    _playToken++;
    _cancelStallGuard();
    final currentNote = _state.currentNote;
    if (currentNote != null) {
      _markPlayed(currentNote.id);
    }
    _wrappedQueue = false;
    final nextIndex = _nextPlayableIndex(
      fromIndex: _state.currentIndex,
      markWrap: true,
    );
    _log('advance reason=$reason nextIndex=$nextIndex');
    if (nextIndex == null) {
      if (_allNotesFailed()) {
        await _enterFatalError(
          'Having trouble loading clips. Check your connection and try again.',
        );
        return;
      }
      await _finishQueue(message: 'No more clips right now.');
      return;
    }
    if (_wrappedQueue) {
      _showTransientMessage('Reached the end, starting over.');
      _wrappedQueue = false;
    }

    _setState(
      _state.copyWith(
        phase: AutoplayPhase.transitioning,
        isTransitioning: true,
        isPreparing: false,
        statusText: null,
        errorMessage: null,
      ),
    );
    if (stopCurrent && _playbackQueueIds.isEmpty) {
      await _audio.stop();
    }
    if (!_isSessionCurrent(sessionToken)) {
      return;
    }
    await _jumpToIndex(nextIndex);
  }

  Future<void> _jumpToIndex(int index) async {
    if (_state.queue.isEmpty) {
      return;
    }
    if (index < 0 || index >= _state.queue.length) {
      return;
    }
    final targetId = _state.queue[index].id;
    final queueIndex = _playbackQueueIds.indexOf(targetId);
    if (queueIndex != -1) {
      final currentQueueIndex = _playbackQueueIndex;
      if (currentQueueIndex != -1 && queueIndex == currentQueueIndex + 1) {
        await _audio.skipToNext();
      } else if (currentQueueIndex != -1 &&
          queueIndex == currentQueueIndex - 1) {
        await _audio.skipToPrevious();
      } else {
        await _audio.seekToIndex(queueIndex);
      }
      return;
    }
    await _playIndex(index, phaseOverride: AutoplayPhase.transitioning);
  }

  Future<void> _handleClipFailure({
    required String noteId,
    required String message,
  }) async {
    _log('clip failure note=$noteId message=$message');
    _failedIds.add(noteId);
    _consecutiveFailures += 1;
    _showTransientMessage(message);

    if (_consecutiveFailures >= _maxConsecutiveFailures || _allNotesFailed()) {
      await _enterFatalError(
        'Having trouble loading clips. Check your connection and try again.',
      );
      return;
    }

    await _advance(_AdvanceReason.errorRecovery, stopCurrent: true);
  }

  Future<void> _handleQueueCompleted() async {
    _log('handle queue completed');
    final currentNote = _state.currentNote;
    if (currentNote != null) {
      _markPlayed(currentNote.id);
    }
    if (_state.queue.isEmpty) {
      await _finishQueue(message: 'No more clips right now.');
      return;
    }
    if (_allNotesFailed()) {
      await _enterFatalError(
        'Having trouble loading clips. Check your connection and try again.',
      );
      return;
    }
    _playbackQueueIds.clear();
    _playbackQueueIndex = -1;
    final nextIndex = _nextPlayableIndex(fromIndex: -1, markWrap: true);
    if (nextIndex == null) {
      await _finishQueue(message: 'No more clips right now.');
      return;
    }
    if (_wrappedQueue) {
      _showTransientMessage('Reached the end, starting over.');
      _wrappedQueue = false;
    }
    await _playIndex(nextIndex, phaseOverride: AutoplayPhase.loading);
  }

  Future<void> _finishQueue({String? message}) async {
    _log('finish queue message=${message ?? ''}');
    _cancelStallGuard();
    try {
      await _audio.stop();
    } catch (_) {
      // Stop failures should not crash playback recovery.
    }
    _setState(
      _state.copyWith(
        phase: AutoplayPhase.completed,
        isPreparing: false,
        isTransitioning: false,
        statusText: message,
        errorMessage: null,
      ),
    );
  }

  Future<void> _advanceFromSuppression(
    bool shouldAdvance, {
    String? message,
  }) async {
    if (!shouldAdvance || _isDisposed) {
      return;
    }
    final resolvedMessage = message ?? 'Clip hidden.';
    _showTransientMessage(resolvedMessage);
    if (_state.isTransitioning) {
      _setState(_state.copyWith(isTransitioning: false, isPreparing: false));
    }
    if (_state.queue.isEmpty) {
      await _finishQueue(message: resolvedMessage);
      return;
    }
    await _advance(_AdvanceReason.errorRecovery, stopCurrent: true);
  }

  bool _isSuppressedNote(VoiceNote note) {
    if (_suppressedNoteIds.contains(note.id)) {
      return true;
    }
    final authorId = note.authorId;
    if (authorId == null || authorId.isEmpty) {
      return false;
    }
    return _suppressedAuthorIds.contains(authorId);
  }

  Future<void> _enterFatalError(String message) async {
    _log('fatal error message=$message');
    _cancelStallGuard();
    await _audio.stop();
    _setState(
      _state.copyWith(
        phase: AutoplayPhase.error,
        isPreparing: false,
        isTransitioning: false,
        statusText: null,
        errorMessage: message,
        transientMessage: null,
      ),
    );
  }

  bool _allNotesFailed() {
    if (_state.queue.isEmpty) {
      return false;
    }
    return _state.queue.every((note) => _failedIds.contains(note.id));
  }

  int? _nextPlayableIndex({
    required int fromIndex,
    bool markWrap = false,
  }) {
    if (_state.queue.isEmpty) {
      return null;
    }
    final avoidRecent = _shouldAvoidRecent();
    for (var i = fromIndex + 1; i < _state.queue.length; i++) {
      final note = _state.queue[i];
      if (_isSuppressedNote(note)) {
        continue;
      }
      final id = note.id;
      if (_playedIds.contains(id) || _failedIds.contains(id)) {
        continue;
      }
      return i;
    }
    if (_allNotesFailed()) {
      return null;
    }
    // Queue exhausted: allow replay in a calm, non-repeating order.
    _playedIds.clear();
    if (markWrap) {
      _wrappedQueue = true;
    }
    final lastId = (fromIndex >= 0 && fromIndex < _state.queue.length)
        ? _state.queue[fromIndex].id
        : null;
    int? pickWrap({required bool avoidRecent}) {
      for (var i = 0; i < _state.queue.length; i++) {
        final note = _state.queue[i];
        if (_isSuppressedNote(note)) {
          continue;
        }
        final id = note.id;
        if (_failedIds.contains(id)) {
          continue;
        }
        if (id == lastId && _state.queue.length > 1) {
          continue;
        }
        if (avoidRecent && _recentlyPlayedIds.contains(id)) {
          continue;
        }
        return i;
      }
      return null;
    }

    final candidate =
        pickWrap(avoidRecent: avoidRecent) ??
        (avoidRecent ? pickWrap(avoidRecent: false) : null);
    return candidate ?? 0;
  }

  void _preloadNextFrom(int index) {
    final next = _state.upcoming(take: 1).firstOrNull;
    _setState(_state.copyWith(preloadingNoteId: next?.id));
    unawaited(_fillQueueAhead());
  }

  Future<void> _fillQueueAhead() async {
    if (_queueFillInFlight ||
        _playbackQueueIds.isEmpty ||
        _playbackQueueIndex < 0 ||
        _state.queue.isEmpty) {
      return;
    }
    final remaining = _playbackQueueIds.length - _playbackQueueIndex - 1;
    if (remaining > _queueRefillThreshold) {
      return;
    }
    _log(
      'prefetch remaining=$remaining target=$_queueFillTarget total=${_playbackQueueIds.length}',
    );
    _queueFillInFlight = true;
    final sessionToken = _sessionToken;
    final token = _playToken;
    try {
      final lastId = _playbackQueueIds.last;
      var cursorIndex =
          _state.queue.indexWhere((note) => note.id == lastId);
      if (cursorIndex < 0) {
        return;
      }
      final toAppend = <AudioQueueItem>[];
      final visited = <String>{..._playbackQueueIds};
      var attempts = 0;
      while (toAppend.length + remaining < _queueFillTarget &&
          attempts < _state.queue.length) {
        final nextIndex = _nextSequentialIndex(fromIndex: cursorIndex);
        if (nextIndex == null) {
          break;
        }
        cursorIndex = nextIndex;
        attempts += 1;
        final note = _state.queue[nextIndex];
        if (visited.contains(note.id)) {
          continue;
        }
        visited.add(note.id);
        if (_cachedPaths.containsKey(note.id)) {
          toAppend.add(
            AudioQueueItem(
              sourceId: note.id,
              path: _cachedPaths[note.id]!,
              duration: note.duration,
              title: note.hashtagLabel,
            ),
          );
          continue;
        }
        if (_preloadInFlight.contains(note.id)) {
          continue;
        }
        _preloadInFlight.add(note.id);
        String? path;
        try {
          path =
              await _resolvePath(note, token: token).timeout(_resolveTimeout);
        } on TimeoutException {
          path = null;
        } finally {
          _preloadInFlight.remove(note.id);
        }
        if (!_isTokenCurrent(token) ||
            !_isSessionCurrent(sessionToken) ||
            _isDisposed) {
          return;
        }
        if (path == null || path.isEmpty) {
          continue;
        }
        toAppend.add(
          AudioQueueItem(
            sourceId: note.id,
            path: path,
            duration: note.duration,
            title: note.hashtagLabel,
          ),
        );
        _playbackQueueNotes[note.id] = note;
      }
      if (!_isSessionCurrent(sessionToken) || _isDisposed) {
        return;
      }
      if (toAppend.isNotEmpty) {
        await _audio.appendQueue(toAppend);
        _playbackQueueIds.addAll(toAppend.map((item) => item.sourceId));
        _log('appended=${toAppend.length} total=${_playbackQueueIds.length}');
      }
    } finally {
      _queueFillInFlight = false;
      final next = _state.upcoming(take: 1).firstOrNull;
      _setState(_state.copyWith(preloadingNoteId: next?.id));
    }
  }

  List<VoiceNote> _collectUpcoming({
    required int fromIndex,
    required int take,
  }) {
    final upcoming = <VoiceNote>[];
    var cursor = fromIndex;
    for (var i = 0; i < take; i++) {
      final nextIndex = _nextPlayableIndex(fromIndex: cursor);
      if (nextIndex == null || nextIndex >= _state.queue.length) {
        break;
      }
      final note = _state.queue[nextIndex];
      upcoming.add(note);
      cursor = nextIndex;
    }
    return upcoming;
  }

  void _maybeRefreshQueue(int index) {
    final hashtagId = _activeHashtagId;
    if (hashtagId == null) {
      return;
    }
    if (_dataSource.isLoadingNotes(hashtagId)) {
      return;
    }
    final remaining = _state.queue.length - index - 1;
    if (remaining > _queueRefreshThreshold) {
      return;
    }
    final now = DateTime.now();
    final lastRefresh = _lastQueueRefreshAt;
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _queueRefreshCooldown) {
      return;
    }
    _lastQueueRefreshAt = now;
    unawaited(_dataSource.loadNotesForHashtag(hashtagId, force: true));
  }

  bool _isMutedNote(String noteId) {
    return _mutedNoteId != null && _mutedNoteId == noteId;
  }

  bool _isCurrentMuted() {
    final currentId = _state.currentNote?.id;
    if (currentId == null) {
      return false;
    }
    return _isMutedNote(currentId);
  }

  void _resetMuteForNote(String noteId) {
    if (_mutedNoteId != null && _mutedNoteId != noteId) {
      _mutedNoteId = null;
    }
  }

  Future<void> _applyVolumeForClip(String noteId) async {
    final targetVolume = _isMutedNote(noteId) ? 0.0 : _userVolume;
    if (_audio.state.volume == targetVolume) {
      return;
    }
    await _audio.setVolume(targetVolume);
  }

  Future<void> _resumePlayback(Duration? position) async {
    final currentNote = _state.currentNote;
    if (_isDisposed || currentNote == null) {
      return;
    }
    if (_state.isPreparing || _state.isTransitioning) {
      return;
    }
    final activeId = _resolveActiveId(_audio.state);
    if (activeId != null && activeId == currentNote.id) {
      await _applyVolumeForClip(currentNote.id);
      if (position != null && position > Duration.zero) {
        await _audio.seek(_clampPosition(position, currentNote.duration));
      }
      await _audio.resume();
      return;
    }
    await _playIndex(
      _state.currentIndex,
      phaseOverride: AutoplayPhase.loading,
      startPosition: position,
    );
  }

  void _handleAudioChanged() {
    if (_isDisposed || _activeHashtagId == null) {
      return;
    }
    final audioState = _audio.state;
    final previousPhase = _state.phase;
    final currentNote = _state.currentNote;
    final activeId = _resolveActiveId(audioState);
    final queueIndex = audioState.queueIndex;

    if (queueIndex != null &&
        queueIndex >= 0 &&
        queueIndex < _playbackQueueIds.length) {
      _playbackQueueIndex = queueIndex;
      if (_lastLoggedQueueIndex != queueIndex) {
        _log('queue index=$queueIndex');
        _lastLoggedQueueIndex = queueIndex;
        unawaited(_fillQueueAhead());
      }
      final queuedId = _playbackQueueIds[queueIndex];
      if (currentNote == null || currentNote.id != queuedId) {
        final queuedNote = _playbackQueueNotes[queuedId];
        final resolvedIndex = queuedNote == null
            ? _state.queue.indexWhere((note) => note.id == queuedId)
            : _state.queue.indexWhere((note) => note.id == queuedNote.id);
        final nextNote = queuedNote ??
            (resolvedIndex == -1 ? null : _state.queue[resolvedIndex]);
        if (nextNote != null) {
          if (currentNote != null) {
            _markPlayed(currentNote.id);
          }
          _setState(
            _state.copyWith(
              currentIndex:
                  resolvedIndex == -1 ? _state.currentIndex : resolvedIndex,
              currentNote: nextNote,
              isPreparing: false,
              isTransitioning: false,
              isMuted: _isMutedNote(queuedId),
            ),
          );
          _positionNoteId = queuedId;
          _lastObservedPosition = Duration.zero;
          _positionResetCount = 0;
          _log('synced clip from queue index id=$queuedId');
        }
      }
    }

    if (activeId != null &&
        (currentNote == null || currentNote.id != activeId)) {
      final queuedNote = _playbackQueueNotes[activeId];
      final resolvedIndex = queuedNote == null
          ? _state.queue.indexWhere((note) => note.id == activeId)
          : _state.queue.indexWhere((note) => note.id == queuedNote.id);
      final nextNote = queuedNote ??
          (resolvedIndex == -1 ? null : _state.queue[resolvedIndex]);
      if (nextNote != null) {
        if (currentNote != null) {
          _markPlayed(currentNote.id);
        }
        _resetMuteForNote(activeId);
        if (!_isMutedNote(activeId) && _audio.state.volume != _userVolume) {
          unawaited(_audio.setVolume(_userVolume));
        }
        _setState(
          _state.copyWith(
            currentIndex:
                resolvedIndex == -1 ? _state.currentIndex : resolvedIndex,
            currentNote: nextNote,
            isPreparing: false,
            isTransitioning: false,
            isMuted: _isMutedNote(activeId),
          ),
        );
        if (resolvedIndex != -1) {
          _maybeRefreshQueue(resolvedIndex);
          _preloadNextFrom(resolvedIndex);
        }
      } else {
        _log('active id not found in queue: $activeId');
      }
      if (queueIndex == null) {
        _playbackQueueIndex = _playbackQueueIds.indexOf(activeId);
      }
      if (_playbackQueueIndex != -1) {
        unawaited(_fillQueueAhead());
      }
      if (_lastLoggedSourceId != activeId) {
        _log('active clip=$activeId queueIndex=$_playbackQueueIndex');
        _lastLoggedSourceId = activeId;
      }
      _positionNoteId = activeId;
      _lastObservedPosition = Duration.zero;
      _positionResetCount = 0;
    }

    if (activeId != null && _playbackQueueIndex == -1) {
      _playbackQueueIndex = _playbackQueueIds.indexOf(activeId);
    }
    final resolvedCurrent = _state.currentNote;
    final isCurrentActive = resolvedCurrent != null &&
        (activeId == null
            ? audioState.phase == AudioPlaybackPhase.playing ||
                audioState.phase == AudioPlaybackPhase.buffering
            : resolvedCurrent.id == activeId);

    if (resolvedCurrent != null && _positionNoteId != resolvedCurrent.id) {
      _positionNoteId = resolvedCurrent.id;
      _lastObservedPosition = Duration.zero;
      _positionResetCount = 0;
    }

    if (audioState.phase == AudioPlaybackPhase.interrupted) {
      final shouldResume = !_state.userPaused && _state.isPlaying;
      _resumeAfterInterruption = shouldResume;
      if (shouldResume) {
        _resumePosition = _state.position;
        _resumeNoteId = resolvedCurrent?.id;
      } else {
        _resumePosition = null;
        _resumeNoteId = null;
      }
      if (_state.phase != AutoplayPhase.interrupted) {
        _log('interruption began');
      }
      _setState(
        _state.copyWith(
          phase: AutoplayPhase.interrupted,
          statusText: audioState.statusText,
        ),
      );
      _cancelStallGuard();
      return;
    }

    if (_state.phase == AutoplayPhase.interrupted &&
        audioState.phase != AudioPlaybackPhase.interrupted) {
      if (_resumeAfterInterruption && !_state.userPaused) {
        final resumePosition =
            _resumeNoteId == resolvedCurrent?.id ? _resumePosition : null;
        _resumeAfterInterruption = false;
        _resumeNoteId = null;
        _resumePosition = null;
        unawaited(_resumePlayback(resumePosition));
      } else {
        _resumeNoteId = null;
        _resumePosition = null;
      }
      _log('interruption ended');
    }

    if (!isCurrentActive) {
      _cancelStallGuard();
      return;
    }

    final mappedPhase = _mapFromAudio(audioState);
    final suppressPhase =
        (_state.isTransitioning || _state.isPreparing) &&
        (mappedPhase == AutoplayPhase.idle ||
            mappedPhase == AutoplayPhase.paused ||
            mappedPhase == AutoplayPhase.completed);
    if (suppressPhase) {
      _cancelStallGuard();
      return;
    }
    final resolved = _state.currentNote;
    if (resolved == null) {
      _cancelStallGuard();
      return;
    }
    final isMuted = _isMutedNote(resolved.id);
    if (!isMuted &&
        !_state.isPreparing &&
        !_state.isTransitioning &&
        audioState.volume != _userVolume) {
      _userVolume = audioState.volume;
    }
    if (mappedPhase != previousPhase) {
      _log('phase $previousPhase -> $mappedPhase');
    }
    _updateStallGuard(mappedPhase, resolved.id);
    final statusText = mappedPhase == AutoplayPhase.buffering
        ? audioState.statusText
        : null;
    _setState(
      _state.copyWith(
        phase: mappedPhase,
        position: audioState.position,
        duration: audioState.duration,
        bufferedPosition: audioState.bufferedPosition,
        volume: _userVolume,
        statusText: statusText,
        errorMessage: mappedPhase == AutoplayPhase.error
            ? audioState.errorMessage
            : null,
        isMuted: isMuted,
      ),
    );

    _trackPositionResets(audioState, resolved, activeId);

    if (audioState.phase == AudioPlaybackPhase.completed &&
        !_state.isTransitioning &&
        !_state.isPreparing &&
        previousPhase != AutoplayPhase.completed) {
      _log('queue completed');
      unawaited(_handleQueueCompleted());
      return;
    }

    if (audioState.phase == AudioPlaybackPhase.error &&
        !_state.isTransitioning &&
        !_state.isPreparing) {
      final failedId = activeId ?? resolved.id;
      _log('clip error=$failedId');
      unawaited(
        _handleClipFailure(
          noteId: failedId,
          message: 'Clip unavailable. Skipping...',
        ),
      );
    }
  }

  void _trackPositionResets(
    AudioPlaybackState audioState,
    VoiceNote currentNote,
    String? activeId,
  ) {
    if (_isDisposed || _state.isPreparing || _state.isTransitioning) {
      return;
    }
    if (audioState.phase != AudioPlaybackPhase.playing &&
        audioState.phase != AudioPlaybackPhase.paused) {
      return;
    }
    if (_playbackQueueIds.isNotEmpty &&
        activeId != null &&
        activeId != currentNote.id) {
      return;
    }
    if (_positionNoteId != currentNote.id) {
      return;
    }
    final position = audioState.position;
    if (_lastObservedPosition >= _positionResetMinPosition &&
        position < const Duration(seconds: 1) &&
        _lastObservedPosition - position > _positionResetThreshold) {
      _positionResetCount += 1;
      if (_positionResetCount <= _maxPositionResetsPerClip) {
        final resumeAt = _clampPosition(_lastObservedPosition, audioState.duration);
        _showTransientMessage('Playback restarted. Resuming...');
        unawaited(_audio.seek(resumeAt));
      } else {
        unawaited(
          _handleClipFailure(
            noteId: currentNote.id,
            message: 'Playback kept restarting. Skipping...',
          ),
        );
      }
      return;
    }
    if (position >= _lastObservedPosition) {
      _lastObservedPosition = position;
    }
  }

  void _updateStallGuard(AutoplayPhase phase, String noteId) {
    if (_state.userPaused || _state.phase == AutoplayPhase.interrupted) {
      _cancelStallGuard();
      return;
    }
    if (phase == AutoplayPhase.loading || phase == AutoplayPhase.buffering) {
      _armStallGuard(noteId);
      return;
    }
    _cancelStallGuard();
  }

  void _armStallGuard(String noteId) {
    _stallTimer?.cancel();
    final token = ++_stallToken;
    _stallTimer = Timer(_stallTimeout, () {
      if (_isDisposed || token != _stallToken) {
        return;
      }
      if (_state.userPaused || _state.phase == AutoplayPhase.interrupted) {
        return;
      }
      if (_state.currentNote?.id != noteId) {
        return;
      }
      final phase = _audio.state.phase;
      if (phase != AudioPlaybackPhase.loading &&
          phase != AudioPlaybackPhase.buffering) {
        return;
      }
      unawaited(
        _handleClipFailure(
          noteId: noteId,
          message: 'Connection stalled. Skipping...',
        ),
      );
    });
  }

  void _cancelStallGuard() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  void _showTransientMessage(String message) {
    _messageTimer?.cancel();
    _setState(_state.copyWith(transientMessage: message));
    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (_isDisposed) {
        return;
      }
      _setState(_state.copyWith(transientMessage: null));
    });
  }

  void _clearTransientMessage() {
    _messageTimer?.cancel();
    _messageTimer = null;
    if (_state.transientMessage != null) {
      _setState(_state.copyWith(transientMessage: null));
    }
  }

  Duration _clampPosition(Duration position, Duration duration) {
    if (duration.inMilliseconds <= 0) {
      return position;
    }
    final clamped = position.inMilliseconds.clamp(
      0,
      duration.inMilliseconds,
    );
    return Duration(milliseconds: clamped);
  }

  AutoplayPhase _mapFromAudio(AudioPlaybackState audioState) {
    switch (audioState.phase) {
      case AudioPlaybackPhase.idle:
        return AutoplayPhase.idle;
      case AudioPlaybackPhase.loading:
        return AutoplayPhase.loading;
      case AudioPlaybackPhase.playing:
        return AutoplayPhase.playing;
      case AudioPlaybackPhase.paused:
        return AutoplayPhase.paused;
      case AudioPlaybackPhase.buffering:
        return AutoplayPhase.buffering;
      case AudioPlaybackPhase.completed:
        return AutoplayPhase.completed;
      case AudioPlaybackPhase.interrupted:
        return AutoplayPhase.interrupted;
      case AudioPlaybackPhase.error:
        return AutoplayPhase.error;
    }
  }

  void _resetSession({required String hashtagId, required bool stopPlayback}) {
    _playToken++;
    _sessionToken++;
    _log('reset session hashtag=$hashtagId stop=$stopPlayback');
    _playedIds.clear();
    _recentlyPlayedIds.clear();
    _failedIds.clear();
    _preloadInFlight.clear();
    _cachedPaths.clear();
    _playbackQueueIds.clear();
    _playbackQueueIndex = -1;
    _playbackQueueNotes.clear();
    _lastLoggedSourceId = null;
    _lastLoggedQueueIndex = null;
    _cancelStallGuard();
    _resumeAfterInterruption = false;
    _resumePosition = null;
    _resumeNoteId = null;
    _mutedNoteId = null;
    _consecutiveFailures = 0;
    _wrappedQueue = false;
    _clearTransientMessage();
    _notesSignature = '';
    _pendingStop = stopPlayback ? _audio.stop() : null;
    _state = AutoplayState.empty.copyWith(
      hashtagId: hashtagId,
      volume: _userVolume,
      phase: AutoplayPhase.loading,
      isLoadingNotes: true,
      isMuted: false,
    );
    notifyListeners();
  }

  bool _isSessionCurrent(int token) {
    return !_isDisposed && token == _sessionToken;
  }

  Future<void> _awaitPendingStop() async {
    final pending = _pendingStop;
    if (pending == null) {
      return;
    }
    try {
      await pending;
    } catch (_) {
      // Ignore stop failures; playback can still attempt to recover.
    } finally {
      if (_pendingStop == pending) {
        _pendingStop = null;
      }
    }
  }

  bool _isTokenCurrent(int token) {
    return !_isDisposed && token == _playToken;
  }

  void _setState(AutoplayState next) {
    if (_isDisposed) {
      return;
    }
    _state = next.copyWith(
      queueDepth: _playbackQueueIds.length,
      queueRemaining: _queueRemaining(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _playToken++;
    _cancelStallGuard();
    _clearTransientMessage();
    if (_attached) {
      _dataSource.removeListener(_handleDataSourceChanged);
      _attached = false;
    }
    _audio.removeListener(_handleAudioChanged);
    super.dispose();
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
