import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_playback_controller.dart';
import 'echo_audio_handler.dart';
import 'native_audio_service.dart';

enum AudioEnginePhase { idle, loading, buffering, ready, completed, error }

class AudioEngineSnapshot {
  const AudioEngineSnapshot({
    required this.sourceId,
    required this.path,
    required this.queueIndex,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.isPlaying,
    required this.volume,
    required this.phase,
    required this.interrupted,
    required this.errorMessage,
  });

  final String? sourceId;
  final String? path;
  final int? queueIndex;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final bool isPlaying;
  final double volume;
  final AudioEnginePhase phase;
  final bool interrupted;
  final String? errorMessage;

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

  AudioEngineSnapshot copyWith({
    String? sourceId,
    String? path,
    Object? queueIndex = _unsetQueueIndex,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? isPlaying,
    double? volume,
    AudioEnginePhase? phase,
    bool? interrupted,
    Object? errorMessage = _unsetErrorMessage,
  }) {
    final resolvedQueueIndex = identical(queueIndex, _unsetQueueIndex)
        ? this.queueIndex
        : queueIndex as int?;
    final resolvedError = identical(errorMessage, _unsetErrorMessage)
        ? this.errorMessage
        : errorMessage as String?;
    return AudioEngineSnapshot(
      sourceId: sourceId ?? this.sourceId,
      path: path ?? this.path,
      queueIndex: resolvedQueueIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      volume: volume ?? this.volume,
      phase: phase ?? this.phase,
      interrupted: interrupted ?? this.interrupted,
      errorMessage: resolvedError,
    );
  }

  static const _unsetErrorMessage = Object();
  static const _unsetQueueIndex = Object();

  static const empty = AudioEngineSnapshot(
    sourceId: null,
    path: null,
    queueIndex: null,
    position: Duration.zero,
    duration: Duration.zero,
    bufferedPosition: Duration.zero,
    isPlaying: false,
    volume: 0.8,
    phase: AudioEnginePhase.idle,
    interrupted: false,
    errorMessage: null,
  );
}

abstract class AudioEngine {
  AudioEngineSnapshot get snapshot;
  Stream<AudioEngineSnapshot> get snapshots;
  Stream<EchoAudioEvent> get events;

  Future<void> setQueue({
    required List<AudioQueueItem> queue,
    int initialIndex = 0,
    Duration? startPosition,
  });

  Future<void> appendQueue(List<AudioQueueItem> queue);
  Future<void> seekToIndex(int index, {Duration? position});
  Future<void> skipToNext();
  Future<void> skipToPrevious();

  Future<void> setSource({
    required String sourceId,
    required String path,
    String? title,
    Duration? duration,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class AudioServiceEngine implements AudioEngine {
  AudioServiceEngine._(this._handler);

  final EchoAudioHandler _handler;
  final _snapshotController = StreamController<AudioEngineSnapshot>.broadcast(
    sync: true,
  );

  AudioEngineSnapshot _snapshot = AudioEngineSnapshot.empty;
  bool _interrupted = false;
  bool _isDisposed = false;

  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<EchoAudioEvent>? _eventSub;

  static Future<AudioServiceEngine> create() async {
    final handler = await AudioService.init(
      builder: () => EchoAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.echo.echo.audio',
        androidNotificationChannelName: 'Echo playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
    final engine = AudioServiceEngine._(handler);
    engine._bind();
    return engine;
  }

  void _bind() {
    _playbackStateSub = _handler.playbackState.listen(_handlePlaybackState);
    _mediaItemSub = _handler.mediaItem.listen((item) {
      _emitFromLatest(mediaItem: item);
    });
    _eventSub = _handler.events.listen(_handleEvent);
  }

  void _handleEvent(EchoAudioEvent event) {
    switch (event.type) {
      case EchoAudioEventType.interruptionBegan:
        _interrupted = true;
        _emitFromLatest(errorMessage: null);
        break;
      case EchoAudioEventType.interruptionEnded:
        _interrupted = false;
        _emitFromLatest(errorMessage: null);
        break;
      case EchoAudioEventType.duckBegan:
      case EchoAudioEventType.duckEnded:
      case EchoAudioEventType.becameNoisy:
        _emitFromLatest(errorMessage: null);
        break;
      case EchoAudioEventType.error:
        _emitFromLatest(
          phaseOverride: AudioEnginePhase.error,
          errorMessage: event.message ?? 'Playback error.',
        );
        break;
    }
  }

  void _handlePlaybackState(PlaybackState state) {
    _emitFromLatest(playbackState: state);
  }

  void _emitFromLatest({
    PlaybackState? playbackState,
    MediaItem? mediaItem,
    AudioEnginePhase? phaseOverride,
    String? errorMessage,
  }) {
    if (_isDisposed) {
      return;
    }
    final latestPlayback = playbackState ?? _handler.playbackState.valueOrNull;
    final latestItem = mediaItem ?? _handler.mediaItem.valueOrNull;
    if (latestPlayback == null) {
      return;
    }
    final queueItems = _handler.queue.valueOrNull;
    final queueIndex = latestPlayback.queueIndex;
    MediaItem? resolvedItem = latestItem;
    if (queueItems != null &&
        queueIndex != null &&
        queueIndex >= 0 &&
        queueIndex < queueItems.length) {
      final queued = queueItems[queueIndex];
      if (resolvedItem == null || resolvedItem.id != queued.id) {
        resolvedItem = queued;
      }
    }
    final resolvedSourceId =
        (resolvedItem?.extras?['sourceId'] as String?) ??
        resolvedItem?.id ??
        _snapshot.sourceId;
    final resolvedPath =
        (resolvedItem?.extras?['path'] as String?) ?? _snapshot.path;
    final resolvedDuration = resolvedItem?.duration ?? _snapshot.duration;
    final phase = phaseOverride ?? _mapPhase(latestPlayback.processingState);
    final next = AudioEngineSnapshot(
      sourceId: resolvedSourceId,
      path: resolvedPath,
      queueIndex: queueIndex,
      position: latestPlayback.updatePosition,
      duration: resolvedDuration,
      bufferedPosition: latestPlayback.bufferedPosition,
      isPlaying: latestPlayback.playing,
      volume: _snapshot.volume,
      phase: phase,
      interrupted: _interrupted,
      errorMessage: errorMessage,
    );
    _snapshot = next;
    _snapshotController.add(next);
  }

  AudioEnginePhase _mapPhase(AudioProcessingState state) {
    switch (state) {
      case AudioProcessingState.idle:
        return AudioEnginePhase.idle;
      case AudioProcessingState.loading:
        return AudioEnginePhase.loading;
      case AudioProcessingState.buffering:
        return AudioEnginePhase.buffering;
      case AudioProcessingState.ready:
        return AudioEnginePhase.ready;
      case AudioProcessingState.completed:
        return AudioEnginePhase.completed;
      case AudioProcessingState.error:
        return AudioEnginePhase.error;
    }
  }

  @override
  AudioEngineSnapshot get snapshot => _snapshot;

  @override
  Stream<AudioEngineSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<EchoAudioEvent> get events => _handler.events;

  @override
  Future<void> setQueue({
    required List<AudioQueueItem> queue,
    int initialIndex = 0,
    Duration? startPosition,
  }) async {
    _emitFromLatest(
      phaseOverride: AudioEnginePhase.loading,
      errorMessage: null,
    );
    await _handler.setQueue(
      queue,
      initialIndex: initialIndex,
      startPosition: startPosition,
    );
  }

  @override
  Future<void> appendQueue(List<AudioQueueItem> queue) async {
    await _handler.appendQueue(queue);
  }

  @override
  Future<void> seekToIndex(int index, {Duration? position}) async {
    await _handler.seekToIndex(index, position: position);
  }

  @override
  Future<void> skipToNext() async {
    await _handler.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _handler.skipToPrevious();
  }

  @override
  Future<void> setSource({
    required String sourceId,
    required String path,
    String? title,
    Duration? duration,
  }) async {
    _emitFromLatest(
      phaseOverride: AudioEnginePhase.loading,
      errorMessage: null,
    );
    await _handler.setSource(
      sourceId: sourceId,
      path: path,
      title: title,
      duration: duration,
    );
  }

  @override
  Future<void> play() async {
    await _handler.play();
  }

  @override
  Future<void> pause() async {
    await _handler.pause();
  }

  @override
  Future<void> stop() async {
    await _handler.stop();
    _emitFromLatest(phaseOverride: AudioEnginePhase.idle, errorMessage: null);
  }

  @override
  Future<void> seek(Duration position) async {
    await _handler.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    _snapshot = _snapshot.copyWith(volume: clamped);
    await _handler.setVolume(clamped);
    _snapshotController.add(_snapshot);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _playbackStateSub?.cancel();
    await _mediaItemSub?.cancel();
    await _eventSub?.cancel();
    await _handler.stop();
    await _handler.dispose();
    await _snapshotController.close();
  }
}

/// Fallback engine that uses the existing native method channel playback.
///
/// This keeps the app bootable in environments where `audio_service` cannot
/// initialize (misconfiguration, unsupported platform, etc.).
class NativeAudioEngine implements AudioEngine {
  NativeAudioEngine({NativeAudioService? service})
    : _service = service ?? NativeAudioService();

  final NativeAudioService _service;
  final _snapshotController = StreamController<AudioEngineSnapshot>.broadcast(
    sync: true,
  );
  final _eventController = StreamController<EchoAudioEvent>.broadcast(
    sync: true,
  );

  AudioEngineSnapshot _snapshot = AudioEngineSnapshot.empty;
  Timer? _pollTimer;
  String? _currentSourceId;
  String? _currentPath;
  final List<AudioQueueItem> _queue = <AudioQueueItem>[];
  int _queueIndex = 0;
  bool _isDisposed = false;

  @override
  AudioEngineSnapshot get snapshot => _snapshot;

  @override
  Stream<AudioEngineSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<EchoAudioEvent> get events => _eventController.stream;

  @override
  Future<void> setQueue({
    required List<AudioQueueItem> queue,
    int initialIndex = 0,
    Duration? startPosition,
  }) async {
    if (_isDisposed) {
      return;
    }
    _queue
      ..clear()
      ..addAll(queue);
    if (_queue.isEmpty) {
      return;
    }
    final resolvedIndex =
        initialIndex.clamp(0, _queue.length - 1).toInt();
    _queueIndex = resolvedIndex;
    final item = _queue[resolvedIndex];
    await setSource(
      sourceId: item.sourceId,
      path: item.path,
      title: item.title,
      duration: item.duration,
    );
    if (startPosition != null && startPosition > Duration.zero) {
      await seek(startPosition);
    }
  }

  @override
  Future<void> appendQueue(List<AudioQueueItem> queue) async {
    if (_isDisposed) {
      return;
    }
    _queue.addAll(queue);
  }

  @override
  Future<void> seekToIndex(int index, {Duration? position}) async {
    if (_isDisposed) {
      return;
    }
    if (index < 0 || index >= _queue.length) {
      return;
    }
    _queueIndex = index;
    final item = _queue[index];
    await setSource(
      sourceId: item.sourceId,
      path: item.path,
      title: item.title,
      duration: item.duration,
    );
    if (position != null && position > Duration.zero) {
      await seek(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty || _queueIndex >= _queue.length - 1) {
      return;
    }
    await seekToIndex(_queueIndex + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty || _queueIndex <= 0) {
      return;
    }
    await seekToIndex(_queueIndex - 1);
  }

  @override
  Future<void> setSource({
    required String sourceId,
    required String path,
    String? title,
    Duration? duration,
  }) async {
    if (_isDisposed) {
      return;
    }
    _currentSourceId = sourceId;
    _currentPath = path;
    _emit(
      _snapshot.copyWith(
        sourceId: sourceId,
        path: path,
        queueIndex: _queue.isEmpty ? null : _queueIndex,
        position: Duration.zero,
        duration: duration ?? _snapshot.duration,
        bufferedPosition: Duration.zero,
        isPlaying: false,
        phase: AudioEnginePhase.loading,
        interrupted: false,
        errorMessage: null,
      ),
    );

    await _service.stopPlayback();
    final started = await _service.startPlayback(path);
    if (!started) {
      _emitError('Playback unavailable on this device.');
      return;
    }
    await _service.setPlaybackVolume(_snapshot.volume);
    final resolvedDuration = duration ?? await _service.getPlaybackDuration();
    _emit(
      _snapshot.copyWith(
        sourceId: sourceId,
        path: path,
        queueIndex: _queue.isEmpty ? null : _queueIndex,
        duration: resolvedDuration,
        bufferedPosition: resolvedDuration,
        isPlaying: true,
        phase: AudioEnginePhase.ready,
        interrupted: false,
        errorMessage: null,
      ),
    );
    _startPolling();
  }

  @override
  Future<void> play() async {
    if (_isDisposed) {
      return;
    }
    final path = _currentPath;
    final sourceId = _currentSourceId;
    if (path == null || sourceId == null) {
      return;
    }
    final resumed = await _service.resumePlayback();
    if (!resumed) {
      final started = await _service.startPlayback(path);
      if (!started) {
        _emitError('Playback unavailable on this device.');
        return;
      }
    }
    _emit(
      _snapshot.copyWith(
        sourceId: sourceId,
        path: path,
        queueIndex: _queue.isEmpty ? null : _queueIndex,
        isPlaying: true,
        phase: AudioEnginePhase.ready,
        interrupted: false,
        errorMessage: null,
      ),
    );
    _startPolling();
  }

  @override
  Future<void> pause() async {
    if (_isDisposed) {
      return;
    }
    await _service.pausePlayback();
    _pollTimer?.cancel();
    _emit(
      _snapshot.copyWith(
        isPlaying: false,
        queueIndex: _queue.isEmpty ? null : _queueIndex,
        phase: AudioEnginePhase.ready,
        errorMessage: null,
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }
    _pollTimer?.cancel();
    await _service.stopPlayback();
    _emit(AudioEngineSnapshot.empty.copyWith(volume: _snapshot.volume));
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isDisposed) {
      return;
    }
    // Native fallback does not support seeking; update UI position only.
    _emit(_snapshot.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_isDisposed) {
      return;
    }
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    _emit(_snapshot.copyWith(volume: clamped));
    await _service.setPlaybackVolume(clamped);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 220), (_) async {
      if (_isDisposed) {
        return;
      }
      try {
        final position = await _service.getPlaybackPosition();
        final duration = _snapshot.duration.inMilliseconds == 0
            ? await _service.getPlaybackDuration()
            : _snapshot.duration;
        final isPlaying = await _service.isPlaying();
        final completed =
            !isPlaying && duration.inMilliseconds > 0 && position >= duration;
        final phase = completed
            ? AudioEnginePhase.completed
            : AudioEnginePhase.ready;
        _emit(
          _snapshot.copyWith(
            position: position,
            duration: duration,
            bufferedPosition: duration,
            isPlaying: isPlaying,
            queueIndex: _queue.isEmpty ? null : _queueIndex,
            phase: phase,
            errorMessage: null,
          ),
        );
        if (completed) {
          _pollTimer?.cancel();
        }
      } catch (error, stackTrace) {
        debugPrint('NativeAudioEngine polling error: $error');
        debugPrintStack(stackTrace: stackTrace);
        _emitError('Playback error.');
      }
    });
  }

  void _emit(AudioEngineSnapshot next) {
    if (_isDisposed || _snapshotController.isClosed) {
      return;
    }
    _snapshot = next;
    _snapshotController.add(next);
  }

  void _emitError(String message) {
    _eventController.add(
      EchoAudioEvent(EchoAudioEventType.error, message: message),
    );
    _emit(
      _snapshot.copyWith(
        isPlaying: false,
        queueIndex: _queue.isEmpty ? null : _queueIndex,
        phase: AudioEnginePhase.error,
        errorMessage: message,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _pollTimer?.cancel();
    await _snapshotController.close();
    await _eventController.close();
  }
}
