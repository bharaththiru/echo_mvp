import 'audio_playback_state.dart';

enum PlaybackProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
  interrupted,
  error,
}

class PlaybackMetrics {
  const PlaybackMetrics({
    required this.sourceId,
    required this.queueIndex,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.playing,
    required this.processingState,
    required this.isPositionAdvancing,
  });

  final String? sourceId;
  final int? queueIndex;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final bool playing;
  final PlaybackProcessingState processingState;
  final bool isPositionAdvancing;

  bool get isActive => sourceId != null && sourceId!.isNotEmpty;

  PlaybackMetrics copyWith({
    String? sourceId,
    Object? queueIndex = _unsetQueueIndex,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? playing,
    PlaybackProcessingState? processingState,
    bool? isPositionAdvancing,
  }) {
    final resolvedQueueIndex = identical(queueIndex, _unsetQueueIndex)
        ? this.queueIndex
        : queueIndex as int?;
    return PlaybackMetrics(
      sourceId: sourceId ?? this.sourceId,
      queueIndex: resolvedQueueIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      playing: playing ?? this.playing,
      processingState: processingState ?? this.processingState,
      isPositionAdvancing: isPositionAdvancing ?? this.isPositionAdvancing,
    );
  }

  static const _unsetQueueIndex = Object();

  static const empty = PlaybackMetrics(
    sourceId: null,
    queueIndex: null,
    position: Duration.zero,
    duration: Duration.zero,
    bufferedPosition: Duration.zero,
    playing: false,
    processingState: PlaybackProcessingState.idle,
    isPositionAdvancing: false,
  );
}

class AudioQueueItem {
  const AudioQueueItem({
    required this.sourceId,
    required this.path,
    this.duration,
    this.title,
  });

  final String sourceId;
  final String path;
  final Duration? duration;
  final String? title;
}

abstract class AudioPlaybackController {
  AudioPlaybackState get state;
  PlaybackMetrics get currentMetrics;
  Stream<PlaybackMetrics> get playbackMetrics;

  Future<void> play({
    required String sourceId,
    required String path,
    Duration? duration,
    String? title,
  });

  Future<void> playQueue({
    required List<AudioQueueItem> queue,
    int initialIndex = 0,
    Duration? startPosition,
  });

  Future<void> appendQueue(List<AudioQueueItem> queue);
  Future<void> seekToIndex(int index, {Duration? position});
  Future<void> skipToNext();
  Future<void> skipToPrevious();

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
