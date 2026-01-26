enum AudioPlaybackPhase {
  idle,
  loading,
  playing,
  paused,
  buffering,
  completed,
  interrupted,
  error,
}

class AudioPlaybackState {
  const AudioPlaybackState({
    required this.sourceId,
    required this.path,
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
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final bool isPlaying;
  final double volume;
  final AudioPlaybackPhase phase;
  final bool interrupted;
  final String? errorMessage;

  double get progress {
    if (duration.inMilliseconds == 0) {
      return 0;
    }
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    if (ratio.isNaN) {
      return 0;
    }
    return ratio.clamp(0, 1);
  }

  bool get isBuffering =>
      phase == AudioPlaybackPhase.loading ||
      phase == AudioPlaybackPhase.buffering;

  bool get hasError =>
      phase == AudioPlaybackPhase.error && errorMessage != null;

  bool get isActive => sourceId != null && path != null;

  String? get statusText {
    switch (phase) {
      case AudioPlaybackPhase.buffering:
        return 'Buffering...';
      case AudioPlaybackPhase.interrupted:
        return 'Playback paused';
      case AudioPlaybackPhase.error:
        return errorMessage ?? 'Playback issue';
      default:
        return null;
    }
  }

  AudioPlaybackState copyWith({
    String? sourceId,
    String? path,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? isPlaying,
    double? volume,
    AudioPlaybackPhase? phase,
    bool? interrupted,
    Object? errorMessage = _unsetErrorMessage,
  }) {
    final resolvedError = identical(errorMessage, _unsetErrorMessage)
        ? this.errorMessage
        : errorMessage as String?;
    return AudioPlaybackState(
      sourceId: sourceId ?? this.sourceId,
      path: path ?? this.path,
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

  static const empty = AudioPlaybackState(
    sourceId: null,
    path: null,
    position: Duration.zero,
    duration: Duration.zero,
    bufferedPosition: Duration.zero,
    isPlaying: false,
    volume: 0.8,
    phase: AudioPlaybackPhase.idle,
    interrupted: false,
    errorMessage: null,
  );

  static const _unsetErrorMessage = Object();
}
