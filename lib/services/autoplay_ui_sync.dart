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
  final effectiveMetrics = metricsMatchCurrent
      ? metrics
      : PlaybackMetrics(
          sourceId: currentNoteId,
          queueIndex: state.currentIndex,
          position: state.position,
          duration: state.duration,
          bufferedPosition: state.bufferedPosition,
          playing: state.phase == AutoplayPhase.playing,
          processingState: _processingFromAutoplayPhase(state.phase),
          isPositionAdvancing: state.phase == AutoplayPhase.playing,
        );

  final playbackStatus = _resolvePlaybackStatus(effectiveMetrics);
  final isEnginePlaying = playbackStatus == PlaybackViewStatus.playing;
  final isEngineBuffering =
      playbackStatus == PlaybackViewStatus.loading ||
      playbackStatus == PlaybackViewStatus.buffering;
  final hasPlaybackStarted =
      effectiveMetrics.position > Duration.zero || effectiveMetrics.playing;
  final isUiLoading = playbackStatus == PlaybackViewStatus.loading &&
      ((state.phase == AutoplayPhase.loading || state.isPreparing)
          ? !hasPlaybackStarted
          : true);
  final showSpinner =
      playbackStatus == PlaybackViewStatus.loading ||
      playbackStatus == PlaybackViewStatus.buffering;

  final statusLabel = resolveAutoplayStatusLabel(
    state,
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

PlaybackViewStatus _resolvePlaybackStatus(PlaybackMetrics metrics) {
  final processingState = metrics.processingState;
  if (processingState == PlaybackProcessingState.error) {
    return PlaybackViewStatus.error;
  }
  if (processingState == PlaybackProcessingState.completed) {
    return PlaybackViewStatus.completed;
  }
  if (processingState == PlaybackProcessingState.loading) {
    return PlaybackViewStatus.loading;
  }
  if (processingState == PlaybackProcessingState.buffering) {
    return PlaybackViewStatus.buffering;
  }
  if (metrics.playing) {
    return PlaybackViewStatus.playing;
  }
  return PlaybackViewStatus.paused;
}

PlaybackProcessingState _processingFromAutoplayPhase(AutoplayPhase phase) {
  switch (phase) {
    case AutoplayPhase.idle:
      return PlaybackProcessingState.idle;
    case AutoplayPhase.loading:
      return PlaybackProcessingState.loading;
    case AutoplayPhase.playing:
    case AutoplayPhase.paused:
      return PlaybackProcessingState.ready;
    case AutoplayPhase.buffering:
    case AutoplayPhase.transitioning:
      return PlaybackProcessingState.buffering;
    case AutoplayPhase.completed:
      return PlaybackProcessingState.completed;
    case AutoplayPhase.interrupted:
      return PlaybackProcessingState.interrupted;
    case AutoplayPhase.error:
      return PlaybackProcessingState.error;
  }
}

String? resolveAutoplayStatusLabel(
  AutoplayState state, {
  required PlaybackViewStatus playbackStatus,
}) {
  if (state.transientMessage != null && state.transientMessage!.isNotEmpty) {
    return state.transientMessage;
  }
  if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
    return state.errorMessage;
  }

  switch (playbackStatus) {
    case PlaybackViewStatus.loading:
      if ((state.phase == AutoplayPhase.loading || state.isPreparing) &&
          state.position <= Duration.zero) {
        return 'Loading clip...';
      }
      return 'Loading...';
    case PlaybackViewStatus.buffering:
      return 'Buffering...';
    case PlaybackViewStatus.playing:
      return 'Now listening';
    case PlaybackViewStatus.paused:
      if (state.phase == AutoplayPhase.transitioning) {
        return 'Moving to next clip...';
      }
      return 'Paused';
    case PlaybackViewStatus.completed:
      return state.statusText ?? 'Completed';
    case PlaybackViewStatus.error:
      return state.errorMessage ?? state.statusText ?? 'Playback issue';
  }
}
