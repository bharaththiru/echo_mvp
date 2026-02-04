import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_playback_controller.dart';
enum EchoAudioEventType { interruptionBegan, interruptionEnded, error }

class EchoAudioEvent {
  const EchoAudioEvent(this.type, {this.message});

  final EchoAudioEventType type;
  final String? message;
}

class EchoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  EchoAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _init();
  }

  final AudioPlayer _player;
  ConcatenatingAudioSource? _playlist;
  final List<MediaItem> _queueItems = <MediaItem>[];
  bool _queueMode = false;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<SequenceState?>? _sequenceSub;
  AudioSession? _session;
  final _eventController = StreamController<EchoAudioEvent>.broadcast();

  String? _lastErrorMessage;
  bool _isDisposed = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSub;

  Stream<EchoAudioEvent> get events => _eventController.stream;


  Future<void> _init() async {
    if (kIsWeb) {
      _listenToPlayer();
      return;
    }
    final session = await AudioSession.instance;
    _session = session;
    final config = const AudioSessionConfiguration.speech().copyWith(
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp |
          AVAudioSessionCategoryOptions.allowAirPlay,
      avAudioSessionSetActiveOptions:
          AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      androidWillPauseWhenDucked: true,
    );
    await session.configure(config);
    _interruptionSub = session.interruptionEventStream.listen(
      _handleInterruption,
    );
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
      _handleBecomingNoisy();
    });
    _devicesChangedSub = session.devicesChangedEventStream.listen(
      _handleDevicesChanged,
    );
    _listenToPlayer();
  }

  void _handleInterruption(AudioInterruptionEvent event) {
    if (_isDisposed) {
      return;
    }
    if (event.begin) {
      _eventController.add(
        const EchoAudioEvent(EchoAudioEventType.interruptionBegan),
      );
      if (_player.playing) {
        unawaited(pause());
      }
      return;
    }
    _eventController.add(
      const EchoAudioEvent(EchoAudioEventType.interruptionEnded),
    );
  }

  void _handleBecomingNoisy() {
    if (_isDisposed) {
      return;
    }
    if (_player.playing) {
      unawaited(pause());
    }
  }

  void _handleDevicesChanged(AudioDevicesChangedEvent event) {
    if (_isDisposed) {
      return;
    }
    final removedOutputs =
        event.devicesRemoved.where((device) => device.isOutput);
    if (removedOutputs.isNotEmpty && _player.playing) {
      unawaited(pause());
    }
  }

  void _listenToPlayer() {
    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stackTrace) {
        _lastErrorMessage = error.toString();
        _eventController.add(
          EchoAudioEvent(EchoAudioEventType.error, message: _lastErrorMessage),
        );
        _broadcastState(forceError: true);
      },
    );
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _broadcastState(forceCompleted: true);
      }
    });
    _player.positionStream.listen((_) => _broadcastState());
    _player.bufferedPositionStream.listen((_) => _broadcastState());
    _player.durationStream.listen((duration) {
      final item = mediaItem.valueOrNull;
      if (item == null || duration == null) {
        return;
      }
      mediaItem.add(item.copyWith(duration: duration));
      _broadcastState();
    });
    _indexSub = _player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= _queueItems.length) {
        return;
      }
      if (!_queueMode) {
        return;
      }
      mediaItem.add(_queueItems[index]);
      _broadcastState();
    });
    _sequenceSub = _player.sequenceStateStream.listen((state) {
      final tag = state?.currentSource?.tag;
      if (tag is MediaItem) {
        mediaItem.add(tag);
        _broadcastState();
      }
    });
  }

  MediaItem _buildMediaItem(AudioQueueItem item) {
    return MediaItem(
      id: item.sourceId,
      title: item.title ?? 'Echo clip',
      duration: item.duration,
      extras: {'path': item.path, 'sourceId': item.sourceId},
    );
  }

  Future<void> setSource({
    required String sourceId,
    required String path,
    String? title,
    Duration? duration,
  }) async {
    _lastErrorMessage = null;
    _queueMode = false;
    _queueItems.clear();
    queue.add(const <MediaItem>[]);
    final uri = _resolveUri(path);
    final source = AudioSource.uri(uri);
    await _player.setAudioSource(source, preload: true);
    final resolvedDuration = duration ?? _player.duration;
    mediaItem.add(
      MediaItem(
        id: sourceId,
        title: title ?? 'Echo clip',
        duration: resolvedDuration,
        extras: {'path': path, 'sourceId': sourceId},
      ),
    );
    _broadcastState();
  }

  Future<void> setQueue(
    List<AudioQueueItem> items, {
    int initialIndex = 0,
    Duration? startPosition,
  }) async {
    _lastErrorMessage = null;
    _queueMode = true;
    _queueItems.clear();
    final sources = <AudioSource>[];
    for (final item in items) {
      final media = _buildMediaItem(item);
      _queueItems.add(media);
      sources.add(AudioSource.uri(_resolveUri(item.path), tag: media));
    }
    _playlist = ConcatenatingAudioSource(
      useLazyPreparation: false,
      children: sources,
    );
    queue.add(List<MediaItem>.from(_queueItems));
    await _player.setAudioSource(
      _playlist!,
      initialIndex: initialIndex,
      initialPosition: startPosition,
      preload: true,
    );
    if (initialIndex >= 0 && initialIndex < _queueItems.length) {
      mediaItem.add(_queueItems[initialIndex]);
    }
    _broadcastState();
  }

  Future<void> appendQueue(List<AudioQueueItem> items) async {
    if (_playlist == null) {
      await setQueue(items);
      return;
    }
    final sources = <AudioSource>[];
    for (final item in items) {
      final media = _buildMediaItem(item);
      _queueItems.add(media);
      sources.add(AudioSource.uri(_resolveUri(item.path), tag: media));
    }
    await _playlist!.addAll(sources);
    queue.add(List<MediaItem>.from(_queueItems));
  }

  Future<void> seekToIndex(int index, {Duration? position}) async {
    if (_queueMode) {
      await _player.seek(position ?? Duration.zero, index: index);
      _broadcastState();
    }
  }

  Uri _resolveUri(String path) {
    final uri = Uri.tryParse(path);
    if (uri == null) {
      return Uri.file(path);
    }
    if (uri.hasScheme) {
      return uri;
    }
    return Uri.file(path);
  }

  @override
  Future<void> play() async {
    await _session?.setActive(true);
    await _player.play();
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState();
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      await _player.play();
    }
    _broadcastState();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      await _player.play();
    }
    _broadcastState();
  }

  void _broadcastState({bool forceCompleted = false, bool forceError = false}) {
    if (_isDisposed) {
      return;
    }
    final playerState = _player.playerState;
    final processingState = _mapProcessingState(
      playerState.processingState,
      forceCompleted: forceCompleted,
      forceError: forceError,
    );
    final playing = playerState.playing;
    final position = _player.position;
    final bufferedPosition = _player.bufferedPosition;
    final speed = _player.speed;
    final controls = <MediaControl>[
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
    ];
    final actions = const <MediaAction>{
      MediaAction.play,
      MediaAction.pause,
      MediaAction.stop,
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
    };
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: actions,
        androidCompactActionIndices: const [0, 1],
        processingState: processingState,
        playing: playing,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: speed,
        queueIndex: _player.currentIndex,
        errorMessage: processingState == AudioProcessingState.error
            ? _lastErrorMessage
            : null,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(
    ProcessingState state, {
    required bool forceCompleted,
    required bool forceError,
  }) {
    if (forceError) {
      return AudioProcessingState.error;
    }
    if (forceCompleted) {
      return AudioProcessingState.completed;
    }
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    await _devicesChangedSub?.cancel();
    await _indexSub?.cancel();
    await _sequenceSub?.cancel();
    await _eventController.close();
    await _player.dispose();
  }
}
