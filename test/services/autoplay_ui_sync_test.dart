import 'package:flutter_test/flutter_test.dart';

import 'package:echo/services/audio_playback_controller.dart';
import 'package:echo/services/autoplay_controller.dart';
import 'package:echo/services/autoplay_ui_sync.dart';

void main() {
  const noteId = 'note-1';

  test('resolves loading status before playback starts', () {
    final state = AutoplayState.empty.copyWith(
      phase: AutoplayPhase.loading,
      isPreparing: true,
    );
    const metrics = PlaybackMetrics(
      sourceId: noteId,
      queueIndex: 0,
      position: Duration.zero,
      duration: Duration(seconds: 12),
      bufferedPosition: Duration.zero,
      playing: false,
      processingState: PlaybackProcessingState.loading,
      isPositionAdvancing: false,
    );

    final ui = resolveAutoplayUiSnapshot(
      state: state,
      metrics: metrics,
      currentNoteId: noteId,
    );

    expect(ui.isUiLoading, isTrue);
    expect(ui.showSpinner, isTrue);
    expect(ui.statusLabel, 'Loading clip...');
  });

  test('returns buffering label when engine reports buffering', () {
    final state = AutoplayState.empty.copyWith(phase: AutoplayPhase.playing);
    const metrics = PlaybackMetrics(
      sourceId: noteId,
      queueIndex: 0,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 12),
      bufferedPosition: Duration(seconds: 3),
      playing: false,
      processingState: PlaybackProcessingState.buffering,
      isPositionAdvancing: false,
    );

    final ui = resolveAutoplayUiSnapshot(
      state: state,
      metrics: metrics,
      currentNoteId: noteId,
    );

    expect(ui.isEngineBuffering, isTrue);
    expect(ui.statusLabel, 'Buffering...');
  });

  test('prefers transient message over computed status', () {
    final state = AutoplayState.empty.copyWith(
      phase: AutoplayPhase.playing,
      transientMessage: 'Skip unavailable right now.',
    );
    const metrics = PlaybackMetrics(
      sourceId: noteId,
      queueIndex: 0,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 12),
      bufferedPosition: Duration(seconds: 8),
      playing: true,
      processingState: PlaybackProcessingState.ready,
      isPositionAdvancing: true,
    );

    final ui = resolveAutoplayUiSnapshot(
      state: state,
      metrics: metrics,
      currentNoteId: noteId,
    );

    expect(ui.statusLabel, 'Skip unavailable right now.');
  });
}
