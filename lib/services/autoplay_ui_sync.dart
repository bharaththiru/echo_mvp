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
  });

  final bool metricsMatchCurrent;
  final bool isEnginePlaying;
  final bool isEngineBuffering;
  final bool hasPlaybackStarted;
  final bool isUiLoading;
  final bool showSpinner;
  final String statusLabel;
}

AutoplayUiSnapshot resolveAutoplayUiSnapshot({
  required AutoplayState state,
  required PlaybackMetrics metrics,
  required String currentNoteId,
  String fallbackReadyLabel = 'Ready',
}) {
  final metricsMatchCurrent = metrics.sourceId == currentNoteId;
  // When metrics haven't caught up to the new note yet, also treat
  // transitioning/loading phases (when the user hasn't paused) as "playing"
  // so the play/pause button icon doesn't flicker to the play icon
  // for a frame before switching back to pause.
  final isEnginePlaying = metricsMatchCurrent
      ? (metrics.playing &&
          metrics.processingState != PlaybackProcessingState.completed)
      : (state.currentNote?.id == currentNoteId &&
          (state.isPlaying ||
              (!state.userPaused &&
                  (state.phase == AutoplayPhase.transitioning ||
                      state.phase == AutoplayPhase.loading ||
                      state.phase == AutoplayPhase.buffering))));
  final isEngineBuffering = metricsMatchCurrent &&
      (metrics.processingState == PlaybackProcessingState.loading ||
          metrics.processingState == PlaybackProcessingState.buffering);
  final hasPlaybackStarted = metricsMatchCurrent
      ? (metrics.position > Duration.zero || metrics.playing)
      : (state.position > Duration.zero || state.isPlaying);
  final isUiLoading = !isEnginePlaying &&
      ((metricsMatchCurrent &&
              metrics.processingState == PlaybackProcessingState.loading) ||
          ((state.phase == AutoplayPhase.loading || state.isPreparing) &&
              !hasPlaybackStarted));
  final showSpinner = isUiLoading || (isEngineBuffering && !isEnginePlaying);

  final statusLabel = resolveAutoplayStatusLabel(
    state,
    metrics: metrics,
    currentNoteId: currentNoteId,
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
  );
}

String? resolveAutoplayStatusLabel(
  AutoplayState state, {
  required PlaybackMetrics metrics,
  required String currentNoteId,
}) {
  if (state.transientMessage != null && state.transientMessage!.isNotEmpty) {
    return state.transientMessage;
  }
  if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
    return state.errorMessage;
  }
  final metricsMatchCurrent = metrics.sourceId == currentNoteId;
  final isEngineBuffering =
      metricsMatchCurrent &&
      (metrics.processingState == PlaybackProcessingState.loading ||
          metrics.processingState == PlaybackProcessingState.buffering);
  if (isEngineBuffering && !metrics.playing) {
    return 'Buffering...';
  }
  if (isEngineBuffering && metrics.playing && !metrics.isPositionAdvancing) {
    return 'Buffering...';
  }
  final hasStarted = metricsMatchCurrent
      ? (metrics.position > Duration.zero || metrics.playing)
      : (state.position > Duration.zero || state.isPlaying);
  if ((state.phase == AutoplayPhase.loading || state.isPreparing) &&
      !hasStarted) {
    return 'Loading clip...';
  }
  if (state.phase == AutoplayPhase.transitioning) {
    return 'Moving to next clip...';
  }
  final isActuallyPlaying = metricsMatchCurrent
      ? (metrics.playing &&
          metrics.processingState != PlaybackProcessingState.completed)
      : state.isPlaying;
  if (isActuallyPlaying) {
    return 'Now listening';
  }
  if (state.phase == AutoplayPhase.paused) {
    return 'Paused';
  }
  if (state.phase == AutoplayPhase.completed) {
    return state.statusText ?? 'Moving to next clip...';
  }
  return state.statusText;
}
