import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/voice_note.dart';
import 'autoplay_data_source.dart';
import 'autoplay_feed_queue_builder.dart';
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

enum _QueueItemStatus { pending, ready, failed }

enum _ClipFailureKind { transient, terminal }

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

  bool get isLoading => phase == AutoplayPhase.loading || isLoadingNotes;

  bool get isBuffering => phase == AutoplayPhase.buffering;

  int get queueLength => queue.length;

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
    required AutoplayFeedQueueBuilder feedQueueBuilder,
    required AudioPlaybackController audio,
  }) : _dataSource = dataSource,
       _feedQueueBuilder = feedQueueBuilder,
       _audio = audio,
       _playerInstanceId = identityHashCode(audio),
       _userVolume = audio.state.volume,
       _state = AutoplayState.empty.copyWith(
         volume: audio.state.volume,
         isMuted: false,
       ) {
    _audio.addListener(_handleAudioChanged);
  }

  void _log(String message) {
    if (kDebugMode) {
      final queueCursor = _playbackQueueIndex < 0 ? '-' : '$_playbackQueueIndex';
      debugPrint(
        '[Autoplay s=$_sessionToken p=$_playToken pid=$_playerInstanceId q=$queueCursor/${_playbackQueueIds.length}] $message',
      );
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
  final AutoplayFeedQueueBuilder _feedQueueBuilder;
  final AudioPlaybackController _audio;
  final int _playerInstanceId;

  AutoplayState _state;
  AutoplayState get state => _state;

  final Set<String> _playedIds = <String>{};
  final ListQueue<String> _recentlyPlayedIds = ListQueue<String>();
  final Set<String> _failedIds = <String>{};
  final Set<String> _suppressedNoteIds = <String>{};
  final Set<String> _suppressedAuthorIds = <String>{};
  final Set<String> _preloadInFlight = <String>{};
  final Map<String, _QueueItemStatus> _queueItemStatus =
      <String, _QueueItemStatus>{};
  final Map<String, String> _cachedPaths = <String, String>{};
  final Map<String, VoiceNote> _playbackQueueNotes =
      <String, VoiceNote>{};
  Future<void> _eventPipeline = Future<void>.value();
  int _eventSerial = 0;
  Timer? _stallTimer;
  int _stallToken = 0;
  String? _stallNoteId;
  Duration _stallPosition = Duration.zero;
  Duration _stallBuffered = Duration.zero;
  DateTime? _stallObservedAt;
  DateTime? _lastQueueRefreshAt;
  DateTime? _lastPrefetchNoopAt;
  DateTime? _lastPrefetchLogAt;
  int _lastLoggedPrefetchRemaining = -1;
  int _lastLoggedPrefetchTotal = -1;
  int _lastLoggedPrefetchDesired = -1;
  bool _skipInFlight = false;
  Timer? _messageTimer;
  Timer? _transitionCueTimer;
  int _transitionCueToken = 0;
  String? _transitionCueNoteId;
  bool _transitionCueFired = false;
  int _consecutiveFailures = 0;
  int _sessionToken = 0;
  Future<void>? _pendingStop;
  bool _failureRecoveryInFlight = false;
  bool _fatalErrorLatched = false;
  bool _fatalErrorInFlight = false;
  String? _lastFailureNoteId;
  DateTime? _lastFailureAt;
  DateTime? _lastAutoResumeAt;
  final Map<String, int> _fastRetryAttemptsByNote = <String, int>{};
  final Map<String, int> _autoResumeCountByClip = <String, int>{};
  Duration _feedBackoffDelay = Duration.zero;
  DateTime? _nextFeedRetryAt;

  bool _attached = false;
  String? _activeHashtagId;
  String _notesSignature = '';
  String? _feedCursor;
  bool _feedHasMore = true;
  bool _feedRequestInFlight = false;
  int _playToken = 0;
  bool _resumeAfterInterruption = false;
  Duration? _resumePosition;
  String? _resumeNoteId;
  String? _mutedNoteId;
  double _userVolume;
  final List<String> _playbackQueueIds = <String>[];
  int _playbackQueueIndex = -1;
  bool _queueFillInFlight = false;
  bool _completionEnqueued = false;
  bool _userManualControl = false;
  bool _isDisposed = false;
  String? _positionNoteId;
  Duration _lastObservedPosition = Duration.zero;
  int _positionResetCount = 0;
  String? _lastLoggedSourceId;
  int? _lastLoggedQueueIndex;
  final Random _tortureRandom = Random();
  bool _tortureModeEnabled = false;
  double _tortureResolveFailureRate = 0.0;
  int _tortureResolveMinDelayMs = 0;
  int _tortureResolveMaxDelayMs = 0;
  bool _loopEnabled = true;
  int _fadeToken = 0;
  bool _pendingBoundaryFadeIn = false;
  bool _isVolumeAutomationActive = false;
  int _volumeAutomationToken = 0;

  static const _resolveTimeout = Duration(seconds: 8);
  static const _maxConsecutiveFailures = 3;
  static const _stallTimeout = Duration(seconds: 5);
  static const _stallPositionThreshold = Duration(milliseconds: 220);
  static const _stallBufferedThreshold = Duration(milliseconds: 320);
  static const _queueRefreshCooldown = Duration(seconds: 30);
  static const _metadataBufferMin = 15;
  static const _metadataBufferTarget = 30;
  static const _metadataBufferMax = 30;
  static const _metadataHistoryWindow = 4;
  static const _failureDedupeWindow = Duration(milliseconds: 900);
  static const _positionResetMinPosition = Duration(seconds: 4);
  static const _positionResetThreshold = Duration(seconds: 2);
  static const _maxPositionResetsPerClip = 2;
  static const _readyBufferMin = 3;
  static const _readyBufferTarget = 5;
  static const _readyBufferMax = 6;
  static const _prefetchNoopCooldown = Duration(milliseconds: 900);
  static const _prefetchLogCooldown = Duration(seconds: 2);
  static const _recentPlaybackWindow = 3;
  static const _feedPageSize = 50;
  static const _boundaryFadeDuration = Duration(milliseconds: 80);
  static const _boundaryFadeSteps = 4;
  static const _maxFastRetriesPerClip = 2;
  static const _fastRetryBaseDelayMs = 180;
  static const _fastRetryMaxDelayMs = 720;
  static const _feedBackoffInitial = Duration(seconds: 2);
  static const _feedBackoffMax = Duration(seconds: 30);
  static const _maxAutoResumesPerClip = 3;
  static const _fallbackStationLimit = 6;

  Future<void> _enqueueEvent(
    Future<void> Function() task, {
    required String reason,
  }) {
    final expectedSession = _sessionToken;
    final serial = ++_eventSerial;
    _eventPipeline = _eventPipeline.then((_) async {
      if (!_isSessionCurrent(expectedSession)) {
        _log(
          'ignored stale callback reason=$reason serial=$serial expectedSession=$expectedSession',
        );
        return;
      }
      try {
        await task();
      } catch (error, stackTrace) {
        _log(
          'event pipeline failure reason=$reason serial=$serial error=$error',
        );
        if (kDebugMode) {
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    });
    return _eventPipeline;
  }

  void configureAutoplayTortureMode({
    required bool enabled,
    double resolveFailureRate = 0.10,
    int resolveMinDelayMs = 25,
    int resolveMaxDelayMs = 220,
  }) {
    _tortureModeEnabled = enabled;
    _tortureResolveFailureRate = resolveFailureRate.clamp(0.0, 1.0);
    _tortureResolveMinDelayMs = resolveMinDelayMs.clamp(0, 2000);
    _tortureResolveMaxDelayMs = resolveMaxDelayMs.clamp(
      _tortureResolveMinDelayMs,
      3000,
    );
    _log(
      'torture mode enabled=$_tortureModeEnabled failure=${_tortureResolveFailureRate.toStringAsFixed(2)} delayMs=$_tortureResolveMinDelayMs-$_tortureResolveMaxDelayMs',
    );
  }

  int _playableNoteCount() {
    var count = 0;
    for (final note in _state.queue) {
      if (_isSuppressedNote(note) || _failedIds.contains(note.id)) {
        continue;
      }
      count += 1;
    }
    return count;
  }

  int _playableUpcomingCount() {
    if (_state.queue.isEmpty) {
      return 0;
    }
    var count = 0;
    final currentId = _state.currentNote?.id;
    final currentExists = currentId != null &&
        _state.queue.any((note) => note.id == currentId);
    var reachedCurrent = currentId == null || !currentExists;
    for (final note in _state.queue) {
      if (!reachedCurrent) {
        if (note.id == currentId) {
          reachedCurrent = true;
        }
        continue;
      }
      if (_isSuppressedNote(note) || _failedIds.contains(note.id)) {
        continue;
      }
      if (currentId != null && note.id == currentId) {
        continue;
      }
      count += 1;
    }
    return count;
  }

  int _desiredReadyQueueDepth() {
    final playableUpcoming = _playableUpcomingCount();
    if (playableUpcoming <= 0) {
      return 0;
    }
    final target = playableUpcoming < _readyBufferTarget
        ? playableUpcoming
        : _readyBufferTarget;
    return target > _readyBufferMax ? _readyBufferMax : target;
  }

  int _readyRemainingCount() {
    if (_playbackQueueIds.isEmpty || _playbackQueueIndex < 0) {
      return 0;
    }
    var ready = 0;
    for (var i = _playbackQueueIndex + 1; i < _playbackQueueIds.length; i++) {
      final id = _playbackQueueIds[i];
      final status = _queueItemStatus[id];
      if (status == _QueueItemStatus.failed) {
        continue;
      }
      if (status == _QueueItemStatus.ready || status == null) {
        ready += 1;
      }
    }
    return ready;
  }

  void _logPrefetch({
    required int remaining,
    required int desired,
    required int total,
    required bool force,
  }) {
    final now = DateTime.now();
    final changed = remaining != _lastLoggedPrefetchRemaining ||
        desired != _lastLoggedPrefetchDesired ||
        total != _lastLoggedPrefetchTotal;
    final cooledDown =
        _lastPrefetchLogAt == null ||
        now.difference(_lastPrefetchLogAt!) >= _prefetchLogCooldown;
    if (!force && !changed && !cooledDown) {
      return;
    }
    _lastPrefetchLogAt = now;
    _lastLoggedPrefetchRemaining = remaining;
    _lastLoggedPrefetchDesired = desired;
    _lastLoggedPrefetchTotal = total;
    _log('prefetch remaining=$remaining target=$desired total=$total');
  }

  void attach(String hashtagId, {bool forceRefresh = false}) {
    if (_isDisposed) {
      return;
    }
    _log('attach hashtag=$hashtagId force=$forceRefresh');
    final hashtagChanged = _activeHashtagId != hashtagId;
    _activeHashtagId = hashtagId;
    if (!_attached) {
      _attached = true;
    }
    if (hashtagChanged) {
      _resetSession(hashtagId: hashtagId, stopPlayback: true);
    }
    syncFromPlayer();
    unawaited(
      _enqueueEvent(
        () async => _ensureNotesLoaded(force: forceRefresh || hashtagChanged),
        reason: 'attachLoad',
      ),
    );
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
    _feedRequestInFlight = false;
    _cancelBoundaryFade();
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
    unawaited(
      _enqueueEvent(
        () async => _advanceFromSuppression(shouldAdvance),
        reason: 'syncSuppressed',
      ),
    );
    _applyNotesSnapshot(_state.queue, forceRebuild: true);
  }

  Future<void> suppressNote(String noteId, {String? message}) async {
    if (noteId.trim().isEmpty || _isDisposed) {
      return;
    }
    final shouldAdvance =
        _audio.state.sourceId == noteId || _state.currentNote?.id == noteId;
    _suppressedNoteIds.add(noteId);
    await _advanceFromSuppression(shouldAdvance, message: message);
    _applyNotesSnapshot(_state.queue, forceRebuild: true);
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
    _applyNotesSnapshot(_state.queue, forceRebuild: true);
  }

  Future<void> _ensureNotesLoaded({required bool force}) async {
    final hashtagId = _activeHashtagId;
    if (hashtagId == null || _isDisposed) {
      return;
    }
    if (_feedRequestInFlight) {
      return;
    }
    if (!force && _state.queue.isNotEmpty) {
      _applyNotesSnapshot(_state.queue);
      syncFromPlayer();
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
    final notes = await _loadFeedPage(stationId: hashtagId, reset: true);
    if (_activeHashtagId != hashtagId || _isDisposed) {
      return;
    }
    if (notes == null) {
      if (_state.queue.isEmpty) {
        final recovered = await _tryFallbackStationRecovery(
          ignoreFeedBackoff: true,
        );
        if (recovered || _isDisposed || _activeHashtagId != hashtagId) {
          return;
        }
      } else {
        _applyNotesSnapshot(_state.queue);
        return;
      }
      _setState(
        _state.copyWith(
          hashtagId: hashtagId,
          isLoadingNotes: false,
          loadError: null,
          statusText: 'Reconnecting...',
          errorMessage: null,
          phase: _state.queue.isEmpty ? AutoplayPhase.completed : _state.phase,
        ),
      );
      return;
    }
    if (notes.isEmpty && _state.queue.isEmpty) {
      final recovered = await _tryFallbackStationRecovery(
        ignoreFeedBackoff: true,
      );
      if (recovered || _isDisposed || _activeHashtagId != hashtagId) {
        return;
      }
      _setState(
        _state.copyWith(
          hashtagId: hashtagId,
          isLoadingNotes: false,
          loadError: null,
          statusText: 'No clips right now.',
          errorMessage: null,
          phase: AutoplayPhase.completed,
        ),
      );
      return;
    }
    _applyNotesSnapshot(notes, forceRebuild: true);
  }

  bool _canAttemptFeedFetch({required bool reset}) {
    if (reset) {
      return true;
    }
    final nextRetryAt = _nextFeedRetryAt;
    if (nextRetryAt == null) {
      return true;
    }
    final now = DateTime.now();
    return !now.isBefore(nextRetryAt);
  }

  void _recordFeedFetchSuccess() {
    _feedBackoffDelay = Duration.zero;
    _nextFeedRetryAt = null;
  }

  void _recordFeedFetchFailure() {
    final previous = _feedBackoffDelay;
    final next = previous == Duration.zero
        ? _feedBackoffInitial
        : Duration(
            milliseconds: (previous.inMilliseconds * 2)
                .clamp(
                  _feedBackoffInitial.inMilliseconds,
                  _feedBackoffMax.inMilliseconds,
                )
                .toInt(),
          );
    _feedBackoffDelay = next;
    _nextFeedRetryAt = DateTime.now().add(next);
  }

  Future<List<VoiceNote>?> _loadFeedPage({
    required String stationId,
    required bool reset,
  }) async {
    if (_feedRequestInFlight) {
      return null;
    }
    if (!_canAttemptFeedFetch(reset: reset)) {
      return List<VoiceNote>.from(_state.queue);
    }
    if (!reset && !_feedHasMore) {
      return List<VoiceNote>.from(_state.queue);
    }
    _feedRequestInFlight = true;
    try {
      final page = await _feedQueueBuilder.loadPage(
        stationId: stationId,
        limit: _feedPageSize,
        cursor: reset ? null : _feedCursor,
      );
      if (_isDisposed || _activeHashtagId != stationId) {
        return null;
      }
      _recordFeedFetchSuccess();
      _feedCursor = page.nextCursor;
      _feedHasMore = page.hasMore;
      if (reset) {
        return List<VoiceNote>.from(page.notes);
      }
      return _mergeFeedNotes(_state.queue, page.notes);
    } catch (error) {
      if (_isDisposed || _activeHashtagId != stationId) {
        return null;
      }
      _recordFeedFetchFailure();
      _log(
        'feed fetch failed station=$stationId backoffMs=${_feedBackoffDelay.inMilliseconds} error=$error',
      );
      if (_state.queue.isNotEmpty) {
        return List<VoiceNote>.from(_state.queue);
      }
      return null;
    } finally {
      _feedRequestInFlight = false;
    }
  }

  List<VoiceNote> _mergeFeedNotes(
    List<VoiceNote> existing,
    List<VoiceNote> incoming,
  ) {
    if (incoming.isEmpty) {
      return List<VoiceNote>.from(existing);
    }
    final mergedById = <String, VoiceNote>{};
    for (final note in existing) {
      mergedById[note.id] = note;
    }
    for (final note in incoming) {
      mergedById[note.id] = note;
    }
    final merged = mergedById.values.toList()
      ..sort((a, b) {
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) {
          return byCreated;
        }
        return b.id.compareTo(a.id);
      });
    return merged;
  }

  List<VoiceNote> _toMetadataRing(List<VoiceNote> notes) {
    if (notes.isEmpty) {
      return const <VoiceNote>[];
    }
    final dedupedById = <String, VoiceNote>{};
    for (final note in notes) {
      dedupedById[note.id] = note;
    }
    final ordered = dedupedById.values.toList()
      ..sort((a, b) {
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) {
          return byCreated;
        }
        return b.id.compareTo(a.id);
      });
    if (ordered.length <= _metadataBufferMax) {
      return ordered;
    }
    final currentId = _state.currentNote?.id;
    if (currentId == null) {
      return ordered.take(_metadataBufferTarget).toList();
    }
    final currentIndex = ordered.indexWhere((note) => note.id == currentId);
    if (currentIndex < 0) {
      return ordered.take(_metadataBufferTarget).toList();
    }
    var start = currentIndex - _metadataHistoryWindow;
    if (start < 0) {
      start = 0;
    }
    var end = start + _metadataBufferMax;
    if (end > ordered.length) {
      end = ordered.length;
      start = (end - _metadataBufferMax).clamp(0, end).toInt();
    }
    return ordered.sublist(start, end);
  }

  void _applyNotesSnapshot(
    List<VoiceNote> notes, {
    bool forceRebuild = false,
    bool isLoadingNotes = false,
    String? loadError,
  }) {
    final hashtagId = _activeHashtagId;
    if (hashtagId == null) {
      return;
    }
    final ringNotes = _toMetadataRing(notes);
    final signature = ringNotes.map((note) => note.id).join('|');
    final changed = signature != _notesSignature;
    _notesSignature = signature;

    _setState(
      _state.copyWith(
        hashtagId: hashtagId,
        isLoadingNotes: isLoadingNotes,
        loadError: loadError,
        statusText: loadError == null ? _state.statusText : null,
        errorMessage: loadError,
      ),
    );

    if (ringNotes.isEmpty) {
      if (!isLoadingNotes && loadError != null) {
        _setState(
          _state.copyWith(phase: AutoplayPhase.error, errorMessage: loadError),
        );
      }
      if (!isLoadingNotes && loadError == null) {
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
        unawaited(
          _enqueueEvent(
            () async => _audio.stop(),
            reason: 'emptyQueueStop',
          ),
        );
      }
      return;
    }

    if (changed || forceRebuild) {
      _rebuildQueue(ringNotes);
    }

    final shouldStart =
        !_state.userPaused &&
        !_state.isPreparing &&
        !_state.isTransitioning &&
        (_state.phase == AutoplayPhase.idle ||
            _state.phase == AutoplayPhase.loading);
    if (shouldStart) {
      unawaited(
        _enqueueEvent(
          () async => _startAutoplay(),
          reason: 'autoStart',
        ),
      );
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
    final queueIds = queue.map((note) => note.id).toSet();
    _queueItemStatus.removeWhere((id, _) => !queueIds.contains(id));
    for (final note in queue) {
      if (_failedIds.contains(note.id)) {
        _queueItemStatus[note.id] = _QueueItemStatus.failed;
      } else if (_cachedPaths.containsKey(note.id)) {
        _queueItemStatus[note.id] = _QueueItemStatus.ready;
      } else {
        _queueItemStatus[note.id] ??= _QueueItemStatus.pending;
      }
    }
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
    if (queue.length > _metadataBufferMax) {
      queue.removeRange(_metadataBufferMax, queue.length);
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
    if (_state.queue.isEmpty) {
      return;
    }
    _log('start autoplay hashtag=$hashtagId notes=${_state.queue.length}');
    _rebuildQueue(_state.queue);
    if (_state.queue.isEmpty) {
      return;
    }
    var nextIndex = _nextPlayableIndex(fromIndex: -1);
    if (nextIndex == null) {
      final replenished = await _tryReplenishQueueAfterExhaustion();
      if (replenished) {
        nextIndex = _nextPlayableIndex(fromIndex: -1);
      }
    }
    if (nextIndex == null) {
      _setState(_state.copyWith(phase: AutoplayPhase.completed));
      return;
    }
    await _playIndex(nextIndex, phaseOverride: AutoplayPhase.loading);
  }

  Future<void> togglePlayPause() async {
    final audioState = _audio.state;
    final activeId = _resolveActiveId(audioState) ?? audioState.sourceId;
    final hasActiveEngine = activeId != null && activeId.isNotEmpty;
    if (_state.isTransitioning && !hasActiveEngine) {
      return;
    }
    if (_state.phase == AutoplayPhase.error) {
      _setState(_state.copyWith(userPaused: false, errorMessage: null));
      await restart();
      return;
    }
    if (audioState.phase == AudioPlaybackPhase.completed ||
        _state.phase == AutoplayPhase.completed) {
      _setState(_state.copyWith(
        userPaused: false,
        errorMessage: null,
        statusText: null,
      ));
      await restart();
      return;
    }
    final currentNote = _state.currentNote;
    if (currentNote == null) {
      await _startAutoplay();
      return;
    }
    if (audioState.phase == AudioPlaybackPhase.completed) {
      _resumeAfterInterruption = false;
      _setState(
        _state.copyWith(
          userPaused: false,
          phase: AutoplayPhase.playing,
          statusText: null,
          errorMessage: null,
        ),
      );
      if (_playbackQueueIndex >= 0 &&
          _playbackQueueIndex + 1 < _playbackQueueIds.length) {
        await _audio.seekToIndex(_playbackQueueIndex + 1, position: Duration.zero);
        await _audio.resume();
        return;
      }
      final nextIndex = _nextPlayableIndex(
        fromIndex: _state.currentIndex,
        allowLoop: _loopEnabled,
      );
      if (nextIndex != null) {
        await _playIndex(nextIndex, phaseOverride: AutoplayPhase.loading);
        return;
      }
      await _audio.seek(Duration.zero);
      await _audio.resume();
      return;
    }
    final isCurrentlyPlaying = audioState.isPlaying || _state.isPlaying;
    if (isCurrentlyPlaying) {
      _userManualControl = true;
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
    _userManualControl = false;
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

  void syncFromPlayer() {
    _handleAudioChanged();
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
    _cancelBoundaryFade();
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
    _cancelBoundaryFade();
    _userVolume = clamped;
    _setState(_state.copyWith(volume: clamped));
    if (_isCurrentMuted()) {
      return;
    }
    await _audio.setVolume(clamped);
  }

  Future<void> restart() async {
    _playToken++;
    _completionEnqueued = false;
    _userManualControl = false;
    _cancelBoundaryFade();
    _cancelStallGuard();
    _cancelTransitionCue();
    _resumeAfterInterruption = false;
    _resumePosition = null;
    _resumeNoteId = null;
    _mutedNoteId = null;
    _consecutiveFailures = 0;
    _clearTransientMessage();
    _playedIds.clear();
    _recentlyPlayedIds.clear();
    _failedIds.clear();
    _queueItemStatus.clear();
    _failureRecoveryInFlight = false;
    _fatalErrorLatched = false;
    _fatalErrorInFlight = false;
    _lastFailureNoteId = null;
    _lastFailureAt = null;
    _lastAutoResumeAt = null;
    _fastRetryAttemptsByNote.clear();
    _autoResumeCountByClip.clear();
    _feedBackoffDelay = Duration.zero;
    _nextFeedRetryAt = null;
    _lastPrefetchNoopAt = null;
    _lastPrefetchLogAt = null;
    _lastLoggedPrefetchRemaining = -1;
    _lastLoggedPrefetchDesired = -1;
    _lastLoggedPrefetchTotal = -1;
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
    _resetTransitionCue(note.id);
    if (_activeHashtagId == null || note.hashtagId != _activeHashtagId) {
      return;
    }
    _log(
      'play index=$index note=${note.id} queue=${_state.queue.length} phase=${phaseOverride ?? AutoplayPhase.loading}',
    );
    _cancelStallGuard();
    // Clear cached path so a fresh Firebase download URL is resolved at
    // playback time instead of reusing a potentially stale cached URL.
    _cachedPaths.remove(note.id);
    _queueItemStatus[note.id] ??= _QueueItemStatus.pending;
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
    for (final item in queueItems) {
      _queueItemStatus[item.sourceId] = _QueueItemStatus.ready;
    }
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
    _fastRetryAttemptsByNote.remove(note.id);
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
      _queueItemStatus[note.id] = _QueueItemStatus.ready;
      return cached;
    }
    final local = note.localPath;
    if (local != null && local.isNotEmpty) {
      _cachedPaths[note.id] = local;
      _queueItemStatus[note.id] = _QueueItemStatus.ready;
      return local;
    }
    if (_tortureModeEnabled) {
      final delayRange = _tortureResolveMaxDelayMs - _tortureResolveMinDelayMs;
      final delay = _tortureResolveMinDelayMs +
          (delayRange <= 0 ? 0 : _tortureRandom.nextInt(delayRange + 1));
      if (delay > 0) {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      if (_tortureRandom.nextDouble() < _tortureResolveFailureRate) {
        _queueItemStatus[note.id] = _QueueItemStatus.failed;
        return null;
      }
    }
    debugPrint('[AutoplayController] resolving path for storagePath=${note.storagePath}'); // TODO: remove before release
    final path = await _dataSource.ensureLocalAudioPath(note);
    debugPrint('[AutoplayController] resolved path=$path'); // TODO: remove before release
    if (!_isTokenCurrent(token)) {
      return path;
    }
    if (path == null || path.isEmpty) {
      _queueItemStatus[note.id] = _QueueItemStatus.failed;
      return path;
    }
    _cachedPaths[note.id] = path;
    _queueItemStatus[note.id] = _QueueItemStatus.ready;
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
    final playable = _playableNoteCount();
    final desired = (_desiredReadyQueueDepth() + 1).clamp(1, playable).toInt();
    final visited = <String>{};
    var cursor = startIndex;
    var attempts = 0;
    while (attempts < _state.queue.length &&
        (desired == 0 ? items.isEmpty : items.length < desired)) {
      final note = _state.queue[cursor];
      attempts += 1;
      if (_isSuppressedNote(note) ||
          _failedIds.contains(note.id) ||
          visited.contains(note.id)) {
        final nextIndex = _nextSequentialIndex(fromIndex: cursor);
        if (nextIndex == null) {
          break;
        }
        cursor = nextIndex;
        continue;
      }
      visited.add(note.id);
      String? path;
      try {
        path = await _resolvePath(note, token: token).timeout(_resolveTimeout);
      } on TimeoutException {
        path = null;
      }
      if (!_isTokenCurrent(token)) {
        return const <AudioQueueItem>[];
      }
      if (path == null || path.isEmpty) {
        _failedIds.add(note.id);
        _queueItemStatus[note.id] = _QueueItemStatus.failed;
        if (cursor == startIndex) {
          _log('resolve failed note=${note.id}');
          await _handleClipFailure(
            noteId: note.id,
            message: 'Clip unavailable. Skipping...',
            kind: _ClipFailureKind.terminal,
          );
          return const <AudioQueueItem>[];
        }
      } else {
        items.add(
          AudioQueueItem(
            sourceId: note.id,
            path: path,
            duration: note.duration,
            title: note.hashtagLabel,
          ),
        );
      }
      final nextIndex = _nextSequentialIndex(fromIndex: cursor);
      if (nextIndex == null) {
        break;
      }
      cursor = nextIndex;
    }
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
    _userManualControl = false;
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
    var nextIndex = _nextPlayableIndex(
      fromIndex: _state.currentIndex,
      allowLoop: true,
    );
    if (nextIndex == null) {
      final replenished = await _tryReplenishQueueAfterExhaustion();
      if (replenished) {
        nextIndex = _nextPlayableIndex(fromIndex: _state.currentIndex);
      }
    }
    _log('advance reason=$reason nextIndex=$nextIndex');
    if (nextIndex == null) {
      final recovered = await _tryFallbackStationRecovery(
        ignoreFeedBackoff: true,
      );
      if (recovered) {
        return;
      }
      if (_allNotesFailed()) {
        await _finishQueue(message: 'No more clips right now.');
        return;
      }
      await _finishQueue(message: 'No more clips right now.');
      return;
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
    var queueIndex = _playbackQueueIds.indexOf(targetId);
    if (queueIndex == -1) {
      final ensured = await _ensureTargetQueued(index);
      if (ensured) {
        queueIndex = _playbackQueueIds.indexOf(targetId);
      }
    }
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

  Future<bool> _ensureTargetQueued(int targetStateIndex) async {
    if (_state.queue.isEmpty ||
        _playbackQueueIds.isEmpty ||
        targetStateIndex < 0 ||
        targetStateIndex >= _state.queue.length) {
      return false;
    }
    final targetId = _state.queue[targetStateIndex].id;
    if (_playbackQueueIds.contains(targetId)) {
      return true;
    }
    final token = _playToken;
    final sessionToken = _sessionToken;
    final lastQueuedId = _playbackQueueIds.last;
    var cursorIndex = _state.queue.indexWhere((note) => note.id == lastQueuedId);
    if (cursorIndex < 0) {
      return false;
    }
    final toAppend = <AudioQueueItem>[];
    final visited = <String>{..._playbackQueueIds};
    var attempts = 0;
    while (attempts < _state.queue.length) {
      final nextIndex = _nextSequentialIndex(fromIndex: cursorIndex);
      if (nextIndex == null) {
        break;
      }
      cursorIndex = nextIndex;
      attempts += 1;
      final note = _state.queue[nextIndex];
      if (_isSuppressedNote(note) ||
          _failedIds.contains(note.id) ||
          visited.contains(note.id)) {
        continue;
      }
      visited.add(note.id);
      String? path;
      try {
        path = await _resolvePath(note, token: token).timeout(_resolveTimeout);
      } on TimeoutException {
        path = null;
      }
      if (!_isTokenCurrent(token) ||
          !_isSessionCurrent(sessionToken) ||
          _isDisposed) {
        return false;
      }
      if (path == null || path.isEmpty) {
        _failedIds.add(note.id);
        _queueItemStatus[note.id] = _QueueItemStatus.failed;
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
      _queueItemStatus[note.id] = _QueueItemStatus.ready;
      _playbackQueueNotes[note.id] = note;
      if (note.id == targetId) {
        break;
      }
    }
    if (!_isSessionCurrent(sessionToken) || _isDisposed) {
      return false;
    }
    if (toAppend.isNotEmpty) {
      await _audio.appendQueue(toAppend);
      _playbackQueueIds.addAll(toAppend.map((item) => item.sourceId));
      _log(
        'queue extend for target=$targetId appended=${toAppend.length} total=${_playbackQueueIds.length}',
      );
    }
    return _playbackQueueIds.contains(targetId);
  }

  Future<bool> _tryReplenishQueueAfterExhaustion() async {
    final hashtagId = _activeHashtagId;
    if (hashtagId == null || _isDisposed) {
      return false;
    }
    if (_feedRequestInFlight || !_feedHasMore) {
      return false;
    }
    final beforeIds = _state.queue.map((note) => note.id).toSet();
    final mergedNotes = await _loadFeedPage(stationId: hashtagId, reset: false);
    if (_isDisposed || _activeHashtagId != hashtagId || mergedNotes == null) {
      return false;
    }
    if (mergedNotes.isEmpty) {
      return false;
    }
    _applyNotesSnapshot(mergedNotes, forceRebuild: true);
    final hasNewPlayable = _state.queue.any(
      (note) =>
          !beforeIds.contains(note.id) &&
          !_failedIds.contains(note.id) &&
          !_isSuppressedNote(note),
    );
    _log(
      'replenish fetched notes=${mergedNotes.length} hasNewPlayable=$hasNewPlayable',
    );
    return hasNewPlayable;
  }

  Future<bool> _tryFallbackStationRecovery({
    bool ignoreFeedBackoff = false,
  }) async {
    final currentStationId = _activeHashtagId;
    if (currentStationId == null || _isDisposed) {
      return false;
    }
    if (!ignoreFeedBackoff && !_canAttemptFeedFetch(reset: false)) {
      return false;
    }
    _setState(
      _state.copyWith(
        phase: AutoplayPhase.loading,
        isPreparing: true,
        isTransitioning: false,
        statusText: 'Finding more clips...',
        errorMessage: null,
      ),
    );
    final fallbackIds = await _feedQueueBuilder.fallbackStationIds(
      currentStationId: currentStationId,
      limit: _fallbackStationLimit,
    );
    if (fallbackIds.isEmpty) {
      _setState(_state.copyWith(isPreparing: false));
      return false;
    }
    for (final stationId in fallbackIds) {
      if (_isDisposed) {
        return false;
      }
      final normalized = stationId.trim();
      if (normalized.isEmpty || normalized == currentStationId) {
        continue;
      }
      try {
        final page = await _feedQueueBuilder.loadPage(
          stationId: normalized,
          limit: _feedPageSize,
          cursor: null,
        );
        if (_isDisposed) {
          return false;
        }
        if (page.notes.isEmpty) {
          continue;
        }
        final playable = page.notes.any(
          (note) => !_isSuppressedNote(note),
        );
        if (!playable) {
          continue;
        }
        _log('fallback station recovered station=$normalized');
        _activeHashtagId = normalized;
        _feedCursor = page.nextCursor;
        _feedHasMore = page.hasMore;
        _recordFeedFetchSuccess();
        _playToken++;
        _cancelStallGuard();
        _cancelTransitionCue();
        _playedIds.clear();
        _recentlyPlayedIds.clear();
        _failedIds.clear();
        _queueItemStatus.clear();
        _playbackQueueIds.clear();
        _playbackQueueIndex = -1;
        _playbackQueueNotes.clear();
        _notesSignature = '';
        _lastLoggedSourceId = null;
        _lastLoggedQueueIndex = null;
        _positionNoteId = null;
        _lastObservedPosition = Duration.zero;
        _positionResetCount = 0;
        _consecutiveFailures = 0;
        _lastFailureNoteId = null;
        _lastFailureAt = null;
        _fastRetryAttemptsByNote.clear();
        _setState(
          _state.copyWith(
            hashtagId: normalized,
            queue: const <VoiceNote>[],
            currentIndex: -1,
            currentNote: null,
            phase: AutoplayPhase.loading,
            isPreparing: false,
            isTransitioning: false,
            userPaused: false,
            isLoadingNotes: false,
            loadError: null,
            statusText: null,
            errorMessage: null,
            isMuted: false,
            position: Duration.zero,
            duration: Duration.zero,
            bufferedPosition: Duration.zero,
          ),
        );
        _applyNotesSnapshot(page.notes, forceRebuild: true);
        _failureRecoveryInFlight = false;
        await _startAutoplay();
        return true;
      } catch (_) {
        _recordFeedFetchFailure();
        // Try next fallback station id.
      }
    }
    _setState(_state.copyWith(isPreparing: false));
    return false;
  }

  Future<void> _handleClipFailure({
    required String noteId,
    required String message,
    _ClipFailureKind kind = _ClipFailureKind.transient,
  }) async {
    if (_isDisposed || _fatalErrorLatched || _fatalErrorInFlight) {
      return;
    }
    if (_failureRecoveryInFlight) {
      _log('clip failure ignored note=$noteId reason=recoveryInFlight');
      return;
    }
    final now = DateTime.now();
    final recentDuplicate =
        _lastFailureNoteId == noteId &&
        _lastFailureAt != null &&
        now.difference(_lastFailureAt!) < _failureDedupeWindow;
    if (recentDuplicate || _failedIds.contains(noteId)) {
      _log('clip failure ignored note=$noteId reason=duplicate');
      return;
    }
    _failureRecoveryInFlight = true;
    _lastFailureNoteId = noteId;
    _lastFailureAt = now;
    _log('clip failure note=$noteId kind=$kind message=$message');
    try {
      final shouldTryFastRetry =
          kind == _ClipFailureKind.transient &&
          !_state.userPaused &&
          _state.currentNote?.id == noteId &&
          !_failedIds.contains(noteId);
      if (shouldTryFastRetry) {
        final recovered = await _retryCurrentClipFast(noteId: noteId);
        if (recovered) {
          _log('clip recovered via fast retry note=$noteId');
          _consecutiveFailures = 0;
          return;
        }
      }
      _fastRetryAttemptsByNote.remove(noteId);
      _failedIds.add(noteId);
      _queueItemStatus[noteId] = _QueueItemStatus.failed;
      _consecutiveFailures += 1;

      final skippedToReady = await _skipToNextReadyQueuedClip(noteId: noteId);
      if (skippedToReady) {
        _consecutiveFailures = 0;
        return;
      }

      if (_consecutiveFailures >= _maxConsecutiveFailures || _allNotesFailed()) {
        final recovered = await _tryFallbackStationRecovery();
        if (recovered) {
          return;
        }
        await _finishQueue(message: 'No more clips right now.');
        return;
      }

      await _advance(_AdvanceReason.errorRecovery, stopCurrent: true);
    } finally {
      _failureRecoveryInFlight = false;
    }
  }

  Future<bool> _retryCurrentClipFast({required String noteId}) async {
    final current = _state.currentNote;
    if (_isDisposed || current == null || current.id != noteId) {
      return false;
    }
    final currentIndex = _state.currentIndex;
    if (currentIndex < 0 || currentIndex >= _state.queue.length) {
      return false;
    }
    final attempted = _fastRetryAttemptsByNote[noteId] ?? 0;
    if (attempted >= _maxFastRetriesPerClip) {
      return false;
    }
    final nextAttempt = attempted + 1;
    _fastRetryAttemptsByNote[noteId] = nextAttempt;
    final waitMs = (_fastRetryBaseDelayMs * (1 << (nextAttempt - 1)))
        .clamp(
          _fastRetryBaseDelayMs,
          _fastRetryMaxDelayMs,
        )
        .toInt();
    if (waitMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
    if (_isDisposed ||
        _state.userPaused ||
        _state.currentNote?.id != noteId ||
        _state.isTransitioning) {
      return false;
    }
    await _playIndex(
      currentIndex,
      phaseOverride: AutoplayPhase.loading,
      startPosition: _state.position,
    );
    if (_isDisposed) {
      return false;
    }
    final phase = _audio.state.phase;
    final recovered =
        _state.currentNote?.id == noteId && phase != AudioPlaybackPhase.error;
    if (recovered) {
      _fastRetryAttemptsByNote.remove(noteId);
    }
    return recovered;
  }

  Future<bool> _skipToNextReadyQueuedClip({required String noteId}) async {
    if (_playbackQueueIds.isEmpty) {
      return false;
    }
    var start = _playbackQueueIds.indexOf(noteId);
    if (start < 0) {
      start = _playbackQueueIndex;
    }
    if (start < -1) {
      start = -1;
    }
    for (var i = start + 1; i < _playbackQueueIds.length; i++) {
      final queuedId = _playbackQueueIds[i];
      if (_failedIds.contains(queuedId)) {
        continue;
      }
      final status = _queueItemStatus[queuedId];
      final hasCachedPath =
          _cachedPaths[queuedId] != null && _cachedPaths[queuedId]!.isNotEmpty;
      if (status != _QueueItemStatus.ready && !hasCachedPath) {
        continue;
      }
      final resolvedIndex =
          _state.queue.indexWhere((note) => note.id == queuedId);
      final queuedNote = _playbackQueueNotes[queuedId] ??
          (resolvedIndex == -1 ? null : _state.queue[resolvedIndex]);
      if (queuedNote == null || _isSuppressedNote(queuedNote)) {
        continue;
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
      _playbackQueueIndex = i;
      await _audio.seekToIndex(i);
      _log('recovery skipped to cached queue index=$i id=$queuedId');
      return true;
    }
    return false;
  }

  Future<void> _handleQueueCompleted() async {
    _log('handle queue completed');
    if (_state.queue.isEmpty) {
      final recovered = await _tryFallbackStationRecovery(
        ignoreFeedBackoff: true,
      );
      if (recovered) {
        return;
      }
      await _finishQueue(message: 'No more clips right now.');
      return;
    }
    if (_loopEnabled && _playbackQueueIds.isNotEmpty) {
      _playToken++;
      _cancelStallGuard();
      _playedIds.clear();
      _recentlyPlayedIds.clear();
      final firstId = _playbackQueueIds.first;
      final firstStateIndex = _state.queue.indexWhere((note) => note.id == firstId);
      final firstNote = firstStateIndex == -1
          ? _playbackQueueNotes[firstId]
          : _state.queue[firstStateIndex];
      _resetTransitionCue(firstId);
      _setState(
        _state.copyWith(
          phase: AutoplayPhase.transitioning,
          isPreparing: false,
          isTransitioning: true,
          userPaused: false,
          statusText: null,
          errorMessage: null,
          currentIndex: firstStateIndex == -1 ? _state.currentIndex : firstStateIndex,
          currentNote: firstNote ?? _state.currentNote,
          isMuted: _isMutedNote(firstId),
        ),
      );
      try {
        _playbackQueueIndex = 0;
        _positionNoteId = firstId;
        _lastObservedPosition = Duration.zero;
        _positionResetCount = 0;
        await _audio.seekToIndex(0, position: Duration.zero);
        // If the engine is still in completed state after seek (just_audio
        // edge case), fall back to _playIndex which sets up a fresh source.
        if (_audio.state.phase == AudioPlaybackPhase.completed) {
          _log('loop restart: still completed after seek, using _playIndex');
          await _playIndex(firstStateIndex == -1 ? 0 : firstStateIndex);
          return;
        }
        await _audio.resume();
        _log('loop restart queueIndex=0 note=$firstId');
        return;
      } catch (_) {
        _log('loop restart failed, falling back to advance');
      }
    }
    await _advance(_AdvanceReason.autoplay);
  }

  Future<void> _finishQueue({String? message}) async {
    if (_fatalErrorLatched || _fatalErrorInFlight) {
      return;
    }
    _log('finish queue message=${message ?? ''}');
    _cancelStallGuard();
    final audioState = _audio.state;
    final shouldStop = audioState.isPlaying ||
        (audioState.phase != AudioPlaybackPhase.idle &&
            audioState.phase != AudioPlaybackPhase.completed);
    if (shouldStop) {
      try {
        await _audio.stop();
      } catch (_) {
        // Stop failures should not crash playback recovery.
      }
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
    if (_isDisposed || _fatalErrorInFlight || _fatalErrorLatched) {
      return;
    }
    _fatalErrorInFlight = true;
    _playToken++;
    _cancelBoundaryFade();
    _log('fatal error message=$message');
    _cancelStallGuard();
    _failureRecoveryInFlight = false;
    try {
      await _audio.stop();
    } catch (_) {
      // Keep fatal error state even if underlying stop fails.
    } finally {
      _pendingStop = null;
    }
    if (_isDisposed) {
      _fatalErrorInFlight = false;
      return;
    }
    _fatalErrorLatched = true;
    _playbackQueueIds.clear();
    _playbackQueueIndex = -1;
    _playbackQueueNotes.clear();
    _lastLoggedSourceId = null;
    _lastLoggedQueueIndex = null;
    _positionNoteId = null;
    _lastObservedPosition = Duration.zero;
    _positionResetCount = 0;
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
    _fatalErrorInFlight = false;
  }

  bool _allNotesFailed() {
    if (_state.queue.isEmpty) {
      return false;
    }
    return _state.queue.every((note) => _failedIds.contains(note.id));
  }

  int? _nextPlayableIndex({
    required int fromIndex,
    bool allowLoop = false,
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
    if (_allNotesFailed() || !allowLoop || !_loopEnabled) {
      return null;
    }
    // Loop autoplay to the first playable clip when the queue is exhausted.
    _playedIds.clear();
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
    unawaited(
      _enqueueEvent(
        () async => _fillQueueAhead(),
        reason: 'preloadNext',
      ),
    );
  }

  Future<void> _fillQueueAhead() async {
    if (_queueFillInFlight ||
        _playbackQueueIds.isEmpty ||
        _playbackQueueIndex < 0 ||
        _state.queue.isEmpty) {
      return;
    }
    if (_fatalErrorLatched || _fatalErrorInFlight) {
      return;
    }
    final now = DateTime.now();
    if (_lastPrefetchNoopAt != null &&
        now.difference(_lastPrefetchNoopAt!) < _prefetchNoopCooldown) {
      return;
    }
    final desiredReady = _desiredReadyQueueDepth();
    if (desiredReady <= 0) {
      return;
    }
    final readyRemaining = _readyRemainingCount();
    if (readyRemaining >= _readyBufferMin) {
      return;
    }
    _logPrefetch(
      remaining: readyRemaining,
      desired: desiredReady,
      total: _playbackQueueIds.length,
      force: false,
    );
    _queueFillInFlight = true;
    final sessionToken = _sessionToken;
    final token = _playToken;
    var appendedCount = 0;
    try {
      final hashtagId = _activeHashtagId;
      final metadataRemaining = _state.queue.length - _state.currentIndex - 1;
      if (hashtagId != null &&
          !_feedRequestInFlight &&
          _feedHasMore &&
          metadataRemaining < _metadataBufferMin) {
        final merged = await _loadFeedPage(stationId: hashtagId, reset: false);
        if (!_isSessionCurrent(sessionToken) || _isDisposed) {
          return;
        }
        if (merged != null) {
          _applyNotesSnapshot(merged, forceRebuild: true);
        }
      }
      final lastId = _playbackQueueIds.last;
      var cursorIndex =
          _state.queue.indexWhere((note) => note.id == lastId);
      if (cursorIndex < 0) {
        return;
      }
      final toAppend = <AudioQueueItem>[];
      final visited = <String>{..._playbackQueueIds};
      var attempts = 0;
      while (readyRemaining + toAppend.length < desiredReady &&
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
          _queueItemStatus[note.id] = _QueueItemStatus.ready;
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
          _failedIds.add(note.id);
          _queueItemStatus[note.id] = _QueueItemStatus.failed;
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
        _queueItemStatus[note.id] = _QueueItemStatus.ready;
        _playbackQueueNotes[note.id] = note;
      }
      if (!_isSessionCurrent(sessionToken) || _isDisposed) {
        return;
      }
      if (toAppend.isNotEmpty) {
        await _audio.appendQueue(toAppend);
        _playbackQueueIds.addAll(toAppend.map((item) => item.sourceId));
        appendedCount = toAppend.length;
        _log(
          'prefetch appended=$appendedCount ready=${_readyRemainingCount()} target=$desiredReady total=${_playbackQueueIds.length}',
        );
      }
    } finally {
      _queueFillInFlight = false;
      if (appendedCount == 0) {
        _lastPrefetchNoopAt = DateTime.now();
      } else {
        _lastPrefetchNoopAt = null;
      }
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
    if (_feedRequestInFlight || !_feedHasMore) {
      return;
    }
    final remaining = _state.queue.length - index - 1;
    if (remaining >= _metadataBufferMin) {
      return;
    }
    final now = DateTime.now();
    final lastRefresh = _lastQueueRefreshAt;
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _queueRefreshCooldown) {
      return;
    }
    _lastQueueRefreshAt = now;
    unawaited(
      _enqueueEvent(() async {
        final merged = await _loadFeedPage(stationId: hashtagId, reset: false);
        if (_isDisposed || _activeHashtagId != hashtagId || merged == null) {
          return;
        }
        _applyNotesSnapshot(merged, forceRebuild: true);
      }, reason: 'refreshQueue'),
    );
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

  void _cancelBoundaryFade({bool clearPendingFadeIn = true}) {
    _fadeToken += 1;
    _isVolumeAutomationActive = false;
    if (clearPendingFadeIn) {
      _pendingBoundaryFadeIn = false;
    }
  }

  Future<void> _runBoundaryFadeOut(String noteId) async {
    if (_isDisposed ||
        _state.userPaused ||
        _state.isPreparing ||
        _state.isTransitioning) {
      return;
    }
    if (_state.currentNote?.id != noteId || _isMutedNote(noteId)) {
      return;
    }
    final fromVolume = _audio.state.volume.clamp(0.0, 1.0).toDouble();
    if (fromVolume <= 0.001) {
      _pendingBoundaryFadeIn = true;
      return;
    }
    final token = ++_fadeToken;
    _pendingBoundaryFadeIn = true;
    await _animateBoundaryVolume(
      from: fromVolume,
      to: 0.0,
      duration: _boundaryFadeDuration,
      steps: _boundaryFadeSteps,
      token: token,
    );
  }

  Future<void> _runBoundaryFadeIn(String noteId) async {
    final shouldFade = _pendingBoundaryFadeIn;
    _pendingBoundaryFadeIn = false;
    if (_isDisposed) {
      return;
    }
    if (_isMutedNote(noteId)) {
      _cancelBoundaryFade(clearPendingFadeIn: false);
      if (_audio.state.volume != 0) {
        await _audio.setVolume(0);
      }
      return;
    }
    final targetVolume = _userVolume.clamp(0.0, 1.0).toDouble();
    if (!shouldFade) {
      _cancelBoundaryFade(clearPendingFadeIn: false);
      if (_audio.state.volume != targetVolume) {
        await _audio.setVolume(targetVolume);
      }
      return;
    }
    final token = ++_fadeToken;
    if (_audio.state.volume != 0) {
      await _audio.setVolume(0);
    }
    await _animateBoundaryVolume(
      from: 0,
      to: targetVolume,
      duration: _boundaryFadeDuration,
      steps: _boundaryFadeSteps,
      token: token,
    );
  }

  Future<void> _animateBoundaryVolume({
    required double from,
    required double to,
    required Duration duration,
    required int steps,
    required int token,
  }) async {
    if (steps <= 0) {
      if (!_isDisposed && token == _fadeToken) {
        await _audio.setVolume(to.clamp(0.0, 1.0).toDouble());
      }
      return;
    }
    final automationToken = ++_volumeAutomationToken;
    _isVolumeAutomationActive = true;
    final clampedFrom = from.clamp(0.0, 1.0).toDouble();
    final clampedTo = to.clamp(0.0, 1.0).toDouble();
    final perStepMs =
        (duration.inMilliseconds / steps).round().clamp(1, 1000) as int;
    final perStep = Duration(milliseconds: perStepMs);
    try {
      for (var i = 1; i <= steps; i++) {
        if (_isDisposed || token != _fadeToken) {
          return;
        }
        final t = i / steps;
        final next = clampedFrom + ((clampedTo - clampedFrom) * t);
        await _audio.setVolume(next.clamp(0.0, 1.0).toDouble());
        if (i < steps) {
          await Future<void>.delayed(perStep);
        }
      }
    } finally {
      if (_volumeAutomationToken == automationToken) {
        _isVolumeAutomationActive = false;
      }
    }
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
    if (_fatalErrorLatched || _fatalErrorInFlight) {
      return;
    }
    final audioState = _audio.state;
    final previousPhase = _state.phase;
    final currentNote = _state.currentNote;
    final activeId = _resolveActiveId(audioState);
    final queueIndex = audioState.queueIndex;
    if (activeId != null &&
        _state.queue.every((note) => note.id != activeId) &&
        !_playbackQueueIds.contains(activeId)) {
      _log('ignored stale audio update source=$activeId');
      return;
    }

    if (queueIndex != null &&
        queueIndex >= 0 &&
        queueIndex < _playbackQueueIds.length) {
      _playbackQueueIndex = queueIndex;
      if (_lastLoggedQueueIndex != queueIndex) {
        _log('queue index=$queueIndex');
        _lastLoggedQueueIndex = queueIndex;
        unawaited(
          _enqueueEvent(
            () async => _fillQueueAhead(),
            reason: 'queueIndexSync',
          ),
        );
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
          _resetMuteForNote(queuedId);
          _resetTransitionCue(queuedId);
          unawaited(_runBoundaryFadeIn(queuedId));
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
          if (resolvedIndex != -1) {
            _maybeRefreshQueue(resolvedIndex);
            _preloadNextFrom(resolvedIndex);
          }
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
        _resetTransitionCue(activeId);
        unawaited(_runBoundaryFadeIn(activeId));
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
        unawaited(
          _enqueueEvent(
            () async => _fillQueueAhead(),
            reason: 'activeIdSync',
          ),
        );
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
    // Include the loading phase so that AutoplayState position/phase are
    // still synced at line 2729 while the engine has not yet resolved a
    // sourceId (activeId == null).  Without this, the early-return at
    // `!isCurrentActive` skips the _setState call, leaving AutoplayState
    // frozen on the previous clip's position during initial buffering.
    final isCurrentActive = resolvedCurrent != null &&
        (activeId == null
            ? audioState.phase == AudioPlaybackPhase.playing ||
                audioState.phase == AudioPlaybackPhase.buffering ||
                audioState.phase == AudioPlaybackPhase.loading
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
      final resumedExternally =
          audioState.isPlaying &&
          (audioState.phase == AudioPlaybackPhase.playing ||
              audioState.phase == AudioPlaybackPhase.buffering);
      final shouldResumeLocally =
          _resumeAfterInterruption && !_state.userPaused && !resumedExternally;
      _resumeAfterInterruption = false;
      if (shouldResumeLocally) {
        final resumePosition =
            _resumeNoteId == resolvedCurrent?.id ? _resumePosition : null;
        _resumeNoteId = null;
        _resumePosition = null;
        unawaited(
          _enqueueEvent(
            () async => _resumePlayback(resumePosition),
            reason: 'resumeAfterInterruption',
          ),
        );
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

    var mappedPhase = _mapFromAudio(audioState);
    final engineBuffering =
        audioState.phase == AudioPlaybackPhase.loading ||
        audioState.phase == AudioPlaybackPhase.buffering;
    final hasPositionProgress =
        audioState.position > Duration.zero ||
        audioState.position > _state.position ||
        _lastObservedPosition > Duration.zero;
    if (audioState.isPlaying &&
        (mappedPhase == AutoplayPhase.loading ||
            mappedPhase == AutoplayPhase.buffering ||
            mappedPhase == AutoplayPhase.paused ||
            mappedPhase == AutoplayPhase.idle)) {
      mappedPhase = AutoplayPhase.playing;
    }
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
    final isUnexpectedPause =
        mappedPhase == AutoplayPhase.paused &&
        !_state.userPaused &&
        !_state.isTransitioning &&
        !_state.isPreparing &&
        audioState.phase == AudioPlaybackPhase.paused;
    if (isUnexpectedPause) {
      final duration = audioState.duration;
      final nearEnd =
          duration.inMilliseconds > 0 &&
          audioState.position >= duration - const Duration(milliseconds: 250);
      if (!nearEnd) {
        mappedPhase = previousPhase == AutoplayPhase.playing
            ? AutoplayPhase.buffering
            : AutoplayPhase.loading;
        final now = DateTime.now();
        final canAutoResume =
            _lastAutoResumeAt == null ||
            now.difference(_lastAutoResumeAt!) >=
                const Duration(milliseconds: 900);
        // Cap auto-resume attempts per clip to prevent a fight loop with
        // the system repeatedly reclaiming audio focus.
        final clipId = resolved.id;
        final resumeCount = _autoResumeCountByClip[clipId] ?? 0;
        if (canAutoResume && resumeCount < _maxAutoResumesPerClip) {
          _autoResumeCountByClip[clipId] = resumeCount + 1;
          _lastAutoResumeAt = now;
          unawaited(
            _enqueueEvent(
              () async => _audio.resume(),
              reason: 'unexpectedPauseAutoResume',
            ),
          );
        }
      }
    }
    final isMuted = _isMutedNote(resolved.id);
    if (!isMuted &&
        !_state.isPreparing &&
        !_state.isTransitioning &&
        !_isVolumeAutomationActive &&
        audioState.volume != _userVolume) {
      _userVolume = audioState.volume;
    }
    if (mappedPhase != previousPhase) {
      _log('phase $previousPhase -> $mappedPhase');
    }
    _updateStallGuard(resolved.id, audioState);
    _scheduleTransitionCue(audioState, resolved);
    final stalledWhilePlaying =
        engineBuffering && audioState.isPlaying && !hasPositionProgress;
    final statusText = (mappedPhase == AutoplayPhase.buffering ||
            stalledWhilePlaying)
        ? audioState.statusText
        : null;
    // Keep isPreparing alive while the engine hasn't resolved a playable
    // state yet.  Without this, an engine snapshot arriving while
    // _buildInitialQueue is still resolving paths would clear isPreparing
    // and leave the UI in a brief limbo (no spinner, no playing indicator).
    final shouldKeepPreparing = _state.isPreparing &&
        !audioState.isPlaying &&
        audioState.position <= Duration.zero &&
        _state.position <= Duration.zero &&
        (mappedPhase == AutoplayPhase.loading ||
            mappedPhase == AutoplayPhase.idle ||
            mappedPhase == AutoplayPhase.buffering);
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
        isPreparing: shouldKeepPreparing ? true : false,
        isTransitioning: false,
        isMuted: isMuted,
      ),
    );

    _trackPositionResets(audioState, resolved, activeId);

    if (audioState.phase == AudioPlaybackPhase.completed &&
        !_state.isTransitioning &&
        !_state.isPreparing &&
        previousPhase != AutoplayPhase.completed &&
        !_completionEnqueued &&
        !_userManualControl) {
      _completionEnqueued = true;
      _log('queue completed');
      debugPrint('[AutoplayController] queue advancing from index=${_state.currentIndex} clip=${_state.currentNote?.id}'); // TODO: remove before release
      unawaited(
        _enqueueEvent(
          () async {
            _completionEnqueued = false;
            await _handleQueueCompleted();
          },
          reason: 'audioCompleted',
        ),
      );
      return;
    }

    if (audioState.phase == AudioPlaybackPhase.error &&
        !_state.isTransitioning &&
        !_state.isPreparing) {
      final failedId = activeId ?? resolved.id;
      _log('clip error=$failedId');
      unawaited(
        _enqueueEvent(
          () async => _handleClipFailure(
            noteId: failedId,
            message: 'Clip unavailable. Skipping...',
          ),
          reason: 'audioError',
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
        unawaited(_audio.seek(resumeAt));
      } else {
        unawaited(
          _enqueueEvent(
            () async => _handleClipFailure(
              noteId: currentNote.id,
              message: 'Playback kept restarting. Skipping...',
              kind: _ClipFailureKind.terminal,
            ),
            reason: 'positionResetRecovery',
          ),
        );
      }
      return;
    }
    if (position >= _lastObservedPosition) {
      _lastObservedPosition = position;
    }
  }

  void _updateStallGuard(String noteId, AudioPlaybackState audioState) {
    if (_state.userPaused ||
        _state.phase == AutoplayPhase.interrupted ||
        !audioState.isPlaying) {
      _cancelStallGuard();
      return;
    }
    final engineBuffering =
        audioState.phase == AudioPlaybackPhase.loading ||
        audioState.phase == AudioPlaybackPhase.buffering;
    if (!engineBuffering) {
      _cancelStallGuard();
      return;
    }
    final nextPosition = audioState.position;
    final nextBuffered = audioState.bufferedPosition;
    final noteChanged = _stallNoteId != noteId;
    final advancedPosition =
        nextPosition - _stallPosition >= _stallPositionThreshold;
    final advancedBuffered =
        nextBuffered - _stallBuffered >= _stallBufferedThreshold;
    if (noteChanged ||
        _stallObservedAt == null ||
        advancedPosition ||
        advancedBuffered) {
      _stallNoteId = noteId;
      _stallPosition = nextPosition;
      _stallBuffered = nextBuffered;
      _stallObservedAt = DateTime.now();
      _armStallGuard(noteId);
      return;
    }
    if (_stallTimer == null) {
      _armStallGuard(noteId);
    }
  }

  void _armStallGuard(String noteId) {
    _stallTimer?.cancel();
    final token = ++_stallToken;
    _stallTimer = Timer(_stallTimeout, () {
      if (_isDisposed || token != _stallToken) {
        return;
      }
      if (_state.userPaused || _state.phase == AutoplayPhase.interrupted) {
        _cancelStallGuard();
        return;
      }
      if (_state.currentNote?.id != noteId || _stallNoteId != noteId) {
        _cancelStallGuard();
        return;
      }
      final audioState = _audio.state;
      final phase = audioState.phase;
      final stillBuffering =
          audioState.isPlaying &&
          (phase == AudioPlaybackPhase.loading ||
              phase == AudioPlaybackPhase.buffering);
      if (!stillBuffering) {
        _cancelStallGuard();
        return;
      }
      final advancedPosition =
          audioState.position - _stallPosition >= _stallPositionThreshold;
      final advancedBuffered =
          audioState.bufferedPosition - _stallBuffered >=
          _stallBufferedThreshold;
      if (advancedPosition || advancedBuffered) {
        _stallPosition = audioState.position;
        _stallBuffered = audioState.bufferedPosition;
        _stallObservedAt = DateTime.now();
        _armStallGuard(noteId);
        return;
      }
      unawaited(
        _enqueueEvent(
          () async => _handleClipFailure(
            noteId: noteId,
            message: 'Connection stalled. Skipping...',
          ),
          reason: 'stallRecovery',
        ),
      );
    });
  }

  void _cancelStallGuard() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _stallToken += 1;
    _stallNoteId = null;
    _stallObservedAt = null;
    _stallPosition = Duration.zero;
    _stallBuffered = Duration.zero;
  }

  void _resetTransitionCue(String noteId) {
    _transitionCueNoteId = noteId;
    _transitionCueFired = false;
    _transitionCueToken += 1;
    _transitionCueTimer?.cancel();
    _transitionCueTimer = null;
  }

  void _cancelTransitionCue() {
    _transitionCueToken += 1;
    _transitionCueFired = false;
    _transitionCueNoteId = null;
    _transitionCueTimer?.cancel();
    _transitionCueTimer = null;
  }

  void _scheduleTransitionCue(
    AudioPlaybackState audioState,
    VoiceNote note,
  ) {
    if (_state.userPaused ||
        _state.isPreparing ||
        _state.isTransitioning ||
        audioState.phase != AudioPlaybackPhase.playing) {
      _transitionCueTimer?.cancel();
      _transitionCueTimer = null;
      return;
    }
    if (_transitionCueNoteId != note.id) {
      _resetTransitionCue(note.id);
    }
    if (_transitionCueFired) {
      return;
    }
    final duration = audioState.duration;
    if (duration.inMilliseconds <= 0) {
      return;
    }
    final remaining = duration - audioState.position;
    const lead = Duration(milliseconds: 200);
    if (remaining <= lead) {
      _fireTransitionCue(note.id);
      return;
    }
    if (_transitionCueTimer != null) {
      return;
    }
    final delay = remaining - lead;
    final expectedToken = ++_transitionCueToken;
    final expectedPlayToken = _playToken;
    _transitionCueTimer = Timer(delay, () {
      if (_isDisposed) {
        return;
      }
      if (expectedToken != _transitionCueToken ||
          expectedPlayToken != _playToken) {
        return;
      }
      if (_state.currentNote?.id != note.id) {
        return;
      }
      _fireTransitionCue(note.id);
    });
  }

  void _fireTransitionCue(String noteId) {
    if (_transitionCueFired || _transitionCueNoteId != noteId) {
      return;
    }
    _transitionCueFired = true;
    _transitionCueTimer?.cancel();
    _transitionCueTimer = null;
    unawaited(HapticFeedback.heavyImpact().catchError((_) {}));
    unawaited(_runBoundaryFadeOut(noteId));
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
    _cancelBoundaryFade();
    _sessionToken++;
    _log('reset session hashtag=$hashtagId stop=$stopPlayback');
    _completionEnqueued = false;
    _userManualControl = false;
    _playedIds.clear();
    _recentlyPlayedIds.clear();
    _failedIds.clear();
    _preloadInFlight.clear();
    _queueItemStatus.clear();
    _cachedPaths.clear();
    _playbackQueueIds.clear();
    _playbackQueueIndex = -1;
    _playbackQueueNotes.clear();
    _lastLoggedSourceId = null;
    _lastLoggedQueueIndex = null;
    _cancelStallGuard();
    _cancelTransitionCue();
    _resumeAfterInterruption = false;
    _resumePosition = null;
    _resumeNoteId = null;
    _mutedNoteId = null;
    _consecutiveFailures = 0;
    _failureRecoveryInFlight = false;
    _fatalErrorLatched = false;
    _fatalErrorInFlight = false;
    _lastFailureNoteId = null;
    _lastFailureAt = null;
    _lastAutoResumeAt = null;
    _fastRetryAttemptsByNote.clear();
    _autoResumeCountByClip.clear();
    _feedBackoffDelay = Duration.zero;
    _nextFeedRetryAt = null;
    _lastPrefetchNoopAt = null;
    _lastPrefetchLogAt = null;
    _lastLoggedPrefetchRemaining = -1;
    _lastLoggedPrefetchDesired = -1;
    _lastLoggedPrefetchTotal = -1;
    _clearTransientMessage();
    _notesSignature = '';
    _feedCursor = null;
    _feedHasMore = true;
    _feedRequestInFlight = false;
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
    final previous = _state;
    _state = next.copyWith(
      queueDepth: _playbackQueueIds.length,
      queueRemaining: _queueRemaining(),
    );
    if (kDebugMode) {
      final previousId = previous.currentNote?.id;
      final nextId = _state.currentNote?.id;
      final phaseChanged = previous.phase != _state.phase;
      final noteChanged = previousId != nextId;
      final flagsChanged = previous.isTransitioning != _state.isTransitioning ||
          previous.isPreparing != _state.isPreparing ||
          previous.isMuted != _state.isMuted;
      final messageChanged = previous.errorMessage != _state.errorMessage ||
          previous.statusText != _state.statusText ||
          previous.transientMessage != _state.transientMessage;
      if (phaseChanged || noteChanged || flagsChanged || messageChanged) {
        _log(
          'state phase=${previous.phase.name}->${_state.phase.name} note=$previousId->$nextId '
          'prep=${previous.isPreparing}->${_state.isPreparing} '
          'transition=${previous.isTransitioning}->${_state.isTransitioning} '
          'muted=${previous.isMuted}->${_state.isMuted} '
          'err=${_state.errorMessage ?? '-'} status=${_state.statusText ?? '-'}',
        );
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _playToken++;
    _cancelBoundaryFade();
    _cancelStallGuard();
    _cancelTransitionCue();
    _clearTransientMessage();
    _attached = false;
    _audio.removeListener(_handleAudioChanged);
    super.dispose();
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
