import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import 'audio_engine.dart';
import 'audio_playback_controller.dart';
import 'audio_playback_state.dart';
import 'echo_audio_handler.dart';
import 'native_audio_service.dart';

export 'audio_playback_state.dart';

class AudioController extends ChangeNotifier
    implements AudioPlaybackController {
  AudioController._({
    required AudioEngine engine,
    NativeAudioService? recordingService,
  }) : _engine = engine,
       _recordingService = recordingService ?? NativeAudioService() {
    _bindEngine();
  }

  final AudioEngine _engine;
  final NativeAudioService _recordingService;
  final BehaviorSubject<PlaybackMetrics> _metrics =
      BehaviorSubject<PlaybackMetrics>.seeded(PlaybackMetrics.empty);
  AudioPlaybackState _state = AudioPlaybackState.empty;
  int _operationToken = 0;
  bool _isDisposed = false;
  DateTime? _lastEngineUpdate;
  DateTime? _lastPositionTick;
  DateTime? _lastProgressAt;
  String? _lastProgressSourceId;
  int? _lastProgressQueueIndex;
  Duration _lastProgressPosition = Duration.zero;
  Timer? _positionTimer;

  StreamSubscription<AudioEngineSnapshot>? _engineSub;
  StreamSubscription<EchoAudioEvent>? _engineEventSub;
  static const _unsetMetricsQueueIndex = Object();

  static Future<AudioController> create({AudioEngine? engine}) async {
    if (engine != null) {
      return AudioController._(engine: engine);
    }
    try {
      final resolvedEngine = await AudioServiceEngine.create();
      return AudioController._(engine: resolvedEngine);
    } catch (error, stackTrace) {
      debugPrint(
        'AudioServiceEngine init failed, using native fallback: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      final fallbackEngine = NativeAudioEngine();
      return AudioController._(engine: fallbackEngine);
    }
  }

  @override
  AudioPlaybackState get state => _state;

  @override
  PlaybackMetrics get currentMetrics => _metrics.value;

  @override
  Stream<PlaybackMetrics> get playbackMetrics => _metrics.stream;

  Future<bool> requestMicrophonePermission() {
    return _recordingService.requestMicrophonePermission();
  }

  Future<bool> startRecording(String path) {
    return _recordingService.startRecording(path);
  }

  Future<bool> stopRecording() {
    return _recordingService.stopRecording();
  }

  void _bindEngine() {
    _engineSub = _engine.snapshots
        .throttleTime(
          const Duration(milliseconds: 100),
          leading: true,
          trailing: true,
        )
        .listen(_handleEngineSnapshot);
    _engineEventSub = _engine.events.listen(_handleEngineEvent);
  }

  void _handleEngineSnapshot(AudioEngineSnapshot snapshot) {
    if (_isDisposed) {
      return;
    }
    _lastEngineUpdate = DateTime.now();
    _lastPositionTick = _lastEngineUpdate;
    final nextPhase = _mapPhase(snapshot);
    final processingState = _mapProcessingState(snapshot);
    final resolvedPosition = _resolveSnapshotPosition(snapshot);
    _trackProgress(snapshot, resolvedPosition);
    _state = _state.copyWith(
      sourceId: snapshot.sourceId,
      path: snapshot.path,
      queueIndex: snapshot.queueIndex,
      position: resolvedPosition,
      duration: snapshot.duration,
      bufferedPosition: snapshot.bufferedPosition,
      isPlaying: snapshot.isPlaying,
      volume: snapshot.volume,
      phase: nextPhase,
      interrupted: snapshot.interrupted,
      errorMessage: snapshot.errorMessage,
    );
    _emitMetrics(
      position: resolvedPosition,
      duration: snapshot.duration,
      bufferedPosition: snapshot.bufferedPosition,
      playing: snapshot.isPlaying,
      processingState: processingState,
    );
    notifyListeners();
    _syncPositionTimer();
  }

  void _trackProgress(
    AudioEngineSnapshot snapshot,
    Duration resolvedPosition,
  ) {
    final sourceId = snapshot.sourceId;
    final queueIndex = snapshot.queueIndex;
    final sameStream = sourceId != null &&
        sourceId == _lastProgressSourceId &&
        queueIndex == _lastProgressQueueIndex;
    if (!sameStream) {
      _lastProgressSourceId = sourceId;
      _lastProgressQueueIndex = queueIndex;
      _lastProgressPosition = resolvedPosition;
      _lastProgressAt = null;
      return;
    }
    if (resolvedPosition > _lastProgressPosition) {
      _lastProgressPosition = resolvedPosition;
      _lastProgressAt = DateTime.now();
    }
  }

  bool _hasRecentProgress(AudioEngineSnapshot snapshot) {
    final sourceId = snapshot.sourceId;
    if (sourceId == null || sourceId != _lastProgressSourceId) {
      return false;
    }
    if (snapshot.queueIndex != _lastProgressQueueIndex) {
      return false;
    }
    final last = _lastProgressAt;
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) <= const Duration(seconds: 1);
  }

  void _handleEngineEvent(EchoAudioEvent event) {
    if (_isDisposed) {
      return;
    }
    switch (event.type) {
      case EchoAudioEventType.interruptionBegan:
        _state = _state.copyWith(
          isPlaying: false,
          phase: AudioPlaybackPhase.interrupted,
          interrupted: true,
          errorMessage: null,
        );
        _emitMetrics(
          playing: false,
          processingState: PlaybackProcessingState.interrupted,
        );
        notifyListeners();
        _syncPositionTimer();
        break;
      case EchoAudioEventType.interruptionEnded:
        _state = _state.copyWith(
          interrupted: false,
          phase: _state.isPlaying
              ? AudioPlaybackPhase.playing
              : AudioPlaybackPhase.paused,
          errorMessage: null,
        );
        _emitMetrics(processingState: PlaybackProcessingState.ready);
        notifyListeners();
        _syncPositionTimer();
        break;
      case EchoAudioEventType.duckBegan:
      case EchoAudioEventType.duckEnded:
      case EchoAudioEventType.becameNoisy:
        _state = _state.copyWith(errorMessage: null);
        _emitMetrics();
        notifyListeners();
        _syncPositionTimer();
        break;
      case EchoAudioEventType.error:
        _state = _state.copyWith(
          isPlaying: false,
          phase: AudioPlaybackPhase.error,
          errorMessage: event.message ?? 'Playback error.',
        );
        _emitMetrics(
          playing: false,
          processingState: PlaybackProcessingState.error,
        );
        notifyListeners();
        _syncPositionTimer();
        break;
    }
  }

  Duration _resolveSnapshotPosition(AudioEngineSnapshot snapshot) {
    final sameSource = _state.sourceId == snapshot.sourceId;
    final sameQueueIndex = _state.queueIndex == snapshot.queueIndex;
    if (snapshot.isPlaying &&
        _state.isPlaying &&
        sameSource &&
        sameQueueIndex &&
        snapshot.position < _state.position) {
      final diff = _state.position - snapshot.position;
      final nearTrackEnd =
          _state.duration.inMilliseconds > 0 &&
          (_state.duration - _state.position) <= const Duration(seconds: 2);
      final looksLikeTrackReset =
          nearTrackEnd && snapshot.position <= const Duration(seconds: 2);
      if (diff > const Duration(milliseconds: 700) && !looksLikeTrackReset) {
        return _state.position;
      }
    }
    return snapshot.position;
  }

  AudioPlaybackPhase _mapPhase(AudioEngineSnapshot snapshot) {
    if (snapshot.interrupted) {
      return AudioPlaybackPhase.interrupted;
    }
    switch (snapshot.phase) {
      case AudioEnginePhase.idle:
        return AudioPlaybackPhase.idle;
      case AudioEnginePhase.loading:
        if (snapshot.isPlaying || _hasRecentProgress(snapshot)) {
          return AudioPlaybackPhase.playing;
        }
        return AudioPlaybackPhase.loading;
      case AudioEnginePhase.buffering:
        if (snapshot.isPlaying) {
          return AudioPlaybackPhase.playing;
        }
        if (_hasRecentProgress(snapshot)) {
          return AudioPlaybackPhase.playing;
        }
        if (_state.isPlaying && snapshot.position > _state.position) {
          return AudioPlaybackPhase.playing;
        }
        if (_state.isPlaying &&
            _state.sourceId == snapshot.sourceId &&
            _state.queueIndex == snapshot.queueIndex &&
            snapshot.bufferedPosition >
                snapshot.position + const Duration(milliseconds: 350)) {
          return AudioPlaybackPhase.playing;
        }
        return AudioPlaybackPhase.buffering;
      case AudioEnginePhase.ready:
        return snapshot.isPlaying
            ? AudioPlaybackPhase.playing
            : AudioPlaybackPhase.paused;
      case AudioEnginePhase.completed:
        return AudioPlaybackPhase.completed;
      case AudioEnginePhase.error:
        return AudioPlaybackPhase.error;
    }
  }

  PlaybackProcessingState _mapProcessingState(AudioEngineSnapshot snapshot) {
    if (snapshot.interrupted) {
      return PlaybackProcessingState.interrupted;
    }
    switch (snapshot.phase) {
      case AudioEnginePhase.idle:
        return PlaybackProcessingState.idle;
      case AudioEnginePhase.loading:
        return PlaybackProcessingState.loading;
      case AudioEnginePhase.buffering:
        return PlaybackProcessingState.buffering;
      case AudioEnginePhase.ready:
        return PlaybackProcessingState.ready;
      case AudioEnginePhase.completed:
        return PlaybackProcessingState.completed;
      case AudioEnginePhase.error:
        return PlaybackProcessingState.error;
    }
  }

  @override
  Future<void> play({
    required String sourceId,
    required String path,
    Duration? duration,
    String? title,
  }) async {
    final token = ++_operationToken;
    _state = _state.copyWith(
      sourceId: sourceId,
      path: path,
      queueIndex: null,
      position: Duration.zero,
      duration: duration ?? _state.duration,
      bufferedPosition: Duration.zero,
      isPlaying: false,
      phase: AudioPlaybackPhase.loading,
      interrupted: false,
      errorMessage: null,
    );
    _emitMetrics(
      sourceId: sourceId,
      queueIndex: null,
      position: Duration.zero,
      duration: duration ?? _state.duration,
      bufferedPosition: Duration.zero,
      playing: false,
      processingState: PlaybackProcessingState.loading,
    );
    notifyListeners();
    _syncPositionTimer();
    try {
      await _engine.stop();
      await _engine.setSource(
        sourceId: sourceId,
        path: path,
        title: title,
        duration: duration,
      );
      if (token != _operationToken || _isDisposed) {
        return;
      }
      await _engine.setVolume(_state.volume);
      if (token != _operationToken || _isDisposed) {
        return;
      }
      await _engine.play();
    } catch (_) {
      if (token != _operationToken || _isDisposed) {
        return;
      }
      _state = _state.copyWith(
        isPlaying: false,
        phase: AudioPlaybackPhase.error,
        errorMessage: 'Unable to play this clip.',
      );
      _emitMetrics(
        playing: false,
        processingState: PlaybackProcessingState.error,
      );
      notifyListeners();
      _syncPositionTimer();
      return;
    }
  }

  @override
  Future<void> playQueue({
    required List<AudioQueueItem> queue,
    int initialIndex = 0,
    Duration? startPosition,
  }) async {
    if (queue.isEmpty) {
      return;
    }
    final resolvedIndex = initialIndex.clamp(0, queue.length - 1).toInt();
    final item = queue[resolvedIndex];
    final token = ++_operationToken;
    _state = _state.copyWith(
      sourceId: item.sourceId,
      path: item.path,
      queueIndex: resolvedIndex,
      position: startPosition ?? Duration.zero,
      duration: item.duration ?? _state.duration,
      bufferedPosition: Duration.zero,
      isPlaying: false,
      phase: AudioPlaybackPhase.loading,
      interrupted: false,
      errorMessage: null,
    );
    _emitMetrics(
      sourceId: item.sourceId,
      queueIndex: resolvedIndex,
      position: startPosition ?? Duration.zero,
      duration: item.duration ?? _state.duration,
      bufferedPosition: Duration.zero,
      playing: false,
      processingState: PlaybackProcessingState.loading,
    );
    notifyListeners();
    _syncPositionTimer();
    try {
      await _engine.setQueue(
        queue: queue,
        initialIndex: resolvedIndex,
        startPosition: startPosition,
      );
      if (token != _operationToken || _isDisposed) {
        return;
      }
      await _engine.setVolume(_state.volume);
      if (token != _operationToken || _isDisposed) {
        return;
      }
      await _engine.play();
      if (token != _operationToken || _isDisposed) {
        return;
      }
      // Optimistically mark as playing so the Ticker in the progress widget
      // activates immediately, without waiting for the first engine snapshot
      // (~100 ms throttle).  Mirrors what resume() does.
      _state = _state.copyWith(
        isPlaying: true,
        phase: AudioPlaybackPhase.playing,
        errorMessage: null,
      );
      _emitMetrics(playing: true, processingState: PlaybackProcessingState.ready);
      notifyListeners();
      _syncPositionTimer();
    } catch (_) {
      if (token != _operationToken || _isDisposed) {
        return;
      }
      _state = _state.copyWith(
        isPlaying: false,
        phase: AudioPlaybackPhase.error,
        errorMessage: 'Unable to play this clip.',
      );
      _emitMetrics(
        playing: false,
        processingState: PlaybackProcessingState.error,
      );
      notifyListeners();
      _syncPositionTimer();
    }
  }

  @override
  Future<void> appendQueue(List<AudioQueueItem> queue) async {
    if (queue.isEmpty) {
      return;
    }
    await _engine.appendQueue(queue);
  }

  @override
  Future<void> seekToIndex(int index, {Duration? position}) async {
    await _engine.seekToIndex(index, position: position);
  }

  @override
  Future<void> skipToNext() async {
    await _engine.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _engine.skipToPrevious();
  }

  @override
  Future<void> pause() async {
    _operationToken++;
    await _engine.pause();
    _state = _state.copyWith(
      isPlaying: false,
      phase: AudioPlaybackPhase.paused,
      errorMessage: null,
    );
    _emitMetrics(playing: false, processingState: PlaybackProcessingState.ready);
    notifyListeners();
    _syncPositionTimer();
  }

  @override
  Future<void> resume() async {
    _operationToken++;
    final isReady = _state.isActive;
    if (!isReady) {
      return;
    }
    await _engine.play();
    _state = _state.copyWith(
      isPlaying: true,
      phase: AudioPlaybackPhase.playing,
      errorMessage: null,
    );
    _emitMetrics(playing: true, processingState: PlaybackProcessingState.ready);
    notifyListeners();
    _syncPositionTimer();
  }

  @override
  Future<void> stop() async {
    _operationToken++;
    await _engine.stop();
    _state = _state.copyWith(
      isPlaying: false,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      queueIndex: null,
      phase: AudioPlaybackPhase.idle,
      interrupted: false,
      errorMessage: null,
    );
    _emitMetrics(
      queueIndex: null,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      playing: false,
      processingState: PlaybackProcessingState.idle,
    );
    notifyListeners();
    _syncPositionTimer();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_state.isActive) {
      return;
    }
    await _engine.seek(position);
    _state = _state.copyWith(position: position);
    _emitMetrics(position: position);
    notifyListeners();
    _lastPositionTick = DateTime.now();
    _syncPositionTimer();
  }

  Future<void> toggle({required String sourceId, required String path}) async {
    if (_state.sourceId == sourceId && _state.path == path) {
      if (_state.isPlaying) {
        await pause();
      } else {
        await resume();
      }
      return;
    }
    await play(sourceId: sourceId, path: path);
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    _state = _state.copyWith(volume: clamped);
    await _engine.setVolume(clamped);
    _emitMetrics();
    notifyListeners();
  }

  Future<Duration> getAudioDuration(String path) async {
    return _recordingService.getAudioDuration(path);
  }

  bool _isPositionAdvancing({
    String? sourceId,
    int? queueIndex,
    bool? playing,
  }) {
    final resolvedSourceId = sourceId ?? _state.sourceId;
    final resolvedQueueIndex = queueIndex ?? _state.queueIndex;
    final isPlayingNow = playing ?? _state.isPlaying;
    if (!isPlayingNow || resolvedSourceId == null) {
      return false;
    }
    if (resolvedSourceId != _lastProgressSourceId ||
        resolvedQueueIndex != _lastProgressQueueIndex) {
      return false;
    }
    final last = _lastProgressAt;
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) <= const Duration(milliseconds: 900);
  }

  void _emitMetrics({
    String? sourceId,
    Object? queueIndex = _unsetMetricsQueueIndex,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? playing,
    PlaybackProcessingState? processingState,
  }) {
    if (_isDisposed || _metrics.isClosed) {
      return;
    }
    final resolvedSourceId = sourceId ?? _state.sourceId;
    final resolvedQueueIndex =
        identical(queueIndex, _unsetMetricsQueueIndex)
        ? _state.queueIndex
        : queueIndex as int?;
    final resolvedPosition = position ?? _state.position;
    final resolvedDuration = duration ?? _state.duration;
    final resolvedBuffered = bufferedPosition ?? _state.bufferedPosition;
    final resolvedPlaying = playing ?? _state.isPlaying;
    final resolvedProcessingState =
        processingState ??
        (_state.interrupted
            ? PlaybackProcessingState.interrupted
            : _state.phase == AudioPlaybackPhase.loading
                ? PlaybackProcessingState.loading
                : _state.phase == AudioPlaybackPhase.buffering
                    ? PlaybackProcessingState.buffering
                    : _state.phase == AudioPlaybackPhase.completed
                        ? PlaybackProcessingState.completed
                        : _state.phase == AudioPlaybackPhase.error
                            ? PlaybackProcessingState.error
                            : _state.phase == AudioPlaybackPhase.idle
                                ? PlaybackProcessingState.idle
                                : PlaybackProcessingState.ready);
    final next = PlaybackMetrics(
      sourceId: resolvedSourceId,
      queueIndex: resolvedQueueIndex,
      position: resolvedPosition,
      duration: resolvedDuration,
      bufferedPosition: resolvedBuffered,
      playing: resolvedPlaying,
      processingState: resolvedProcessingState,
      isPositionAdvancing: _isPositionAdvancing(
        sourceId: resolvedSourceId,
        queueIndex: resolvedQueueIndex,
        playing: resolvedPlaying,
      ),
    );
    _metrics.add(next);
  }

  void _syncPositionTimer() {
    if (_isDisposed) {
      return;
    }
    if (_state.isPlaying) {
      _positionTimer ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _tickPosition(),
      );
    } else {
      _positionTimer?.cancel();
      _positionTimer = null;
      _lastPositionTick = null;
    }
  }

  void _tickPosition() {
    if (_isDisposed) {
      return;
    }
    if (!_state.isPlaying) {
      _positionTimer?.cancel();
      _positionTimer = null;
      _lastPositionTick = null;
      return;
    }
    final now = DateTime.now();
    final lastTick = _lastPositionTick ?? now;
    _lastPositionTick = now;
    final lastEngine = _lastEngineUpdate;
    if (lastEngine != null &&
        now.difference(lastEngine) <= const Duration(milliseconds: 450)) {
      return;
    }
    final delta = now.difference(lastTick);
    final next = _state.position + delta;
    final durationMs = _state.duration.inMilliseconds;
    final clamped = durationMs > 0
        ? Duration(milliseconds: min(next.inMilliseconds, durationMs))
        : next;
    if (clamped == _state.position) {
      return;
    }
    if (_state.sourceId != null &&
        _state.sourceId == _lastProgressSourceId &&
        _state.queueIndex == _lastProgressQueueIndex &&
        clamped > _lastProgressPosition) {
      _lastProgressPosition = clamped;
      _lastProgressAt = now;
    }
    _state = _state.copyWith(position: clamped);
    _emitMetrics(position: clamped);
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _operationToken++;
    _positionTimer?.cancel();
    _engineSub?.cancel();
    _engineEventSub?.cancel();
    _metrics.close();
    _engine.dispose();
    super.dispose();
  }
}
