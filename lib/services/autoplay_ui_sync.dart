import 'autoplay_controller.dart';
import 'audio_playback_controller.dart';

class AutoplayUiSnapshot {
  const AutoplayUiSnapshot({
    required this.metricsMatchCurrent,
    required this.isEnginePlaying,
    required this.isEngineBuffering,
    required this.hasPlaybackStarted,
    required this.isUiLoading,
    required this.showSpinner,
    required this.statusLabel,
    required this.playbackStatus,
  });

  final bool metricsMatchCurrent;
  final bool isEnginePlaying;
  final bool isEngineBuffering;
  final bool hasPlaybackStarted;
  final bool isUiLoading;
  final bool showSpinner;
  final String statusLabel;
  final PlaybackViewStatus playbackStatus;
}

enum PlaybackViewStatus { loading, buffering, playing, paused, completed, error }

AutoplayUiSnapshot resolveAutoplayUiSnapshot({
  required AutoplayState state,
  required PlaybackMetrics metrics,
  required String currentNoteId,
  String fallbackReadyLabel = 'Ready',
}) {
  final metricsMatchCurrent = metrics.sourceId == currentNoteId;
  final playbackStatus = _resolvePlaybackStatus(
    state: state,
    metrics: metrics,
    metricsMatchCurrent: metricsMatchCurrent,
  );
  final isEnginePlaying = _isEnginePlaying(
    state: state,
    metrics: metrics,
    currentNoteId: currentNoteId,
    metricsMatchCurrent: metricsMatchCurrent,
  );
  final isEngineBuffering = _isEngineBuffering(
    metrics: metrics,
    metricsMatchCurrent: metricsMatchCurrent,
  );
  final hasPlaybackStarted = _hasPlaybackStarted(
    state: state,
    metrics: metrics,
    metricsMatchCurrent: metricsMatchCurrent,
  );
  final isUiLoading = !isEnginePlaying &&
      (playbackStatus == PlaybackViewStatus.loading ||
          ((state.phase == AutoplayPhase.loading || state.isPreparing) &&
              !hasPlaybackStarted));
  final showSpinner = isUiLoading || (isEngineBuffering && !isEnginePlaying);

  final statusLabel = resolveAutoplayStatusLabel(
    state: state,
    metrics: metrics,
    metricsMatchCurrent: metricsMatchCurrent,
    playbackStatus: playbackStatus,
  );

  return AutoplayUiSnapshot(
    metricsMatchCurrent: metricsMatchCurrent,
    isEnginePlaying: isEnginePlaying,
    isEngineBuffering: isEngineBuffering,
    hasPlaybackStarted: hasPlaybackStarted,
    isUiLoading: isUiLoading,
    showSpinner: showSpinner,
    statusLabel: (statusLabel == null || statusLabel.trim().isEmpty)
        ? fallbackReadyLabel
        : statusLabel,
    playbackStatus: playbackStatus,
  );
}

PlaybackViewStatus _resolvePlaybackStatus({
  required AutoplayState state,
  required PlaybackMetrics metrics,
  required bool metricsMatchCurrent,
}) {
  if (metricsMatchCurrent) {
    switch (metrics.processingState) {
      case PlaybackProcessingState.error:
        return PlaybackViewStatus.error;
      case PlaybackProcessingState.completed:
        return PlaybackViewStatus.completed;
      case PlaybackProcessingState.loading:
        return PlaybackViewStatus.loading;
      case PlaybackProcessingState.buffering:
        return PlaybackViewStatus.buffering;
      case PlaybackProcessingState.ready:
      case PlaybackProcessingState.idle:
      case PlaybackProcessingState.interrupted:
        return metrics.playing ? PlaybackViewStatus.playing : PlaybackViewStatus.paused;
    }
  }

  switch (state.phase) {
    case AutoplayPhase.error:
      return PlaybackViewStatus.error;
    case AutoplayPhase.completed:
      return PlaybackViewStatus.completed;
    case AutoplayPhase.loading:
      return PlaybackViewStatus.loading;
    case AutoplayPhase.buffering:
    case AutoplayPhase.transitioning:
      return PlaybackViewStatus.buffering;
    case AutoplayPhase.playing:
      return PlaybackViewStatus.playing;
    case AutoplayPhase.paused:
    case AutoplayPhase.idle:
    case AutoplayPhase.interrupted:
      return PlaybackViewStatus.paused;
  }
}

bool _isEnginePlaying({
  required AutoplayState state,
  required PlaybackMetrics metrics,
  required String currentNoteId,
  required bool metricsMatchCurrent,
}) {
  if (metricsMatchCurrent) {
    return metrics.playing &&
        metrics.processingState != PlaybackProcessingState.completed;
  }

  // During transitions, metrics can briefly point at the previous note.
  // Preserve "playing" intent from autoplay state to avoid icon flicker.
  return state.currentNote?.id == currentNoteId &&
      (state.isPlaying ||
          (!state.userPaused &&
              (state.phase == AutoplayPhase.transitioning ||
                  state.phase == AutoplayPhase.loading ||
                  state.phase == AutoplayPhase.buffering)));
}

bool _isEngineBuffering({
  required PlaybackMetrics metrics,
  required bool metricsMatchCurrent,
}) {
  if (!metricsMatchCurrent) {
    return false;
  }
  return metrics.processingState == PlaybackProcessingState.loading ||
      metrics.processingState == PlaybackProcessingState.buffering;
}

bool _hasPlaybackStarted({
  required AutoplayState state,
  required PlaybackMetrics metrics,
  required bool metricsMatchCurrent,
}) {
  if (metricsMatchCurrent) {
    return metrics.position > Duration.zero || metrics.playing;
  }
  return state.position > Duration.zero || state.isPlaying;
}

String? resolveAutoplayStatusLabel({
  required AutoplayState state,
  required PlaybackMetrics metrics,
  required bool metricsMatchCurrent,
  required PlaybackViewStatus playbackStatus,
}) {
  if (state.transientMessage != null && state.transientMessage!.isNotEmpty) {
    return state.transientMessage;
  }
  if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
    return state.errorMessage;
  }

  final isEngineBuffering = _isEngineBuffering(
    metrics: metrics,
    metricsMatchCurrent: metricsMatchCurrent,
  );
  if (isEngineBuffering && (!metrics.playing || !metrics.isPositionAdvancing)) {
    return 'Buffering...';
  }

  final hasStarted = _hasPlaybackStarted(
    state: state,
    metrics: metrics,
    metricsMatchCurrent: metricsMatchCurrent,
  );
  if ((state.phase == AutoplayPhase.loading || state.isPreparing) && !hasStarted) {
    return 'Loading clip...';
  }
  if (state.phase == AutoplayPhase.transitioning) {
    return 'Moving to next clip...';
  }

  switch (playbackStatus) {
    case PlaybackViewStatus.error:
      return state.errorMessage ?? 'Playback issue';
    case PlaybackViewStatus.completed:
      return state.statusText ?? 'Moving to next clip...';
    case PlaybackViewStatus.loading:
      return 'Loading clip...';
    case PlaybackViewStatus.buffering:
      return 'Buffering...';
    case PlaybackViewStatus.playing:
      return 'Now listening';
    case PlaybackViewStatus.paused:
      return state.phase == AutoplayPhase.paused ? 'Paused' : state.statusText;
  }
}
