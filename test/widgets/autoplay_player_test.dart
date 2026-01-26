import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echo/app/app_scope.dart';
import 'package:echo/app/app_state.dart';
import 'package:echo/app/theme.dart';
import 'package:echo/models/hashtag.dart';
import 'package:echo/models/voice_note.dart';
import 'package:echo/screens/autoplay_player.dart';
import 'package:echo/services/audio_controller.dart';
import 'package:echo/services/audio_engine.dart';
import 'package:echo/services/echo_audio_handler.dart';

void main() {
  const hashtagId = 'focus';

  VoiceNote note(String id) {
    return VoiceNote(
      id: id,
      hashtagId: hashtagId,
      hashtagLabel: '#focus',
      createdAt: DateTime(2025, 1, 1).add(Duration(minutes: id.hashCode % 45)),
      duration: const Duration(seconds: 12),
      storagePath: 'storage/$id.m4a',
      allowReplies: true,
      expiresAt: null,
      authorId: null,
      transcriptPreview: 'clip $id',
      localPath: 'clip_$id.m4a',
    );
  }

  Hashtag buildHashtag() {
    return const Hashtag(
      id: hashtagId,
      name: '#focus',
      description: 'Quiet concentration',
      icon: Icons.self_improvement,
      gradient: [EchoColors.surface, EchoColors.muted],
      noteCount: 2,
    );
  }

  Future<_Harness> buildHarness(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final engine = FakeAudioEngine();
    final audio = await AudioController.create(engine: engine);
    final notes = <String, List<VoiceNote>>{
      hashtagId: [note('a'), note('b')],
    };
    final appState = await AppState.forTest(
      audio: audio,
      hashtags: [buildHashtag()],
      notesByHashtag: notes,
    );

    await tester.pumpWidget(
      AppScope(
        state: appState,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AutoplayPlayer(hashtagId: hashtagId),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
    return _Harness(appState: appState, audio: audio, engine: engine);
  }

  testWidgets('play/pause button reflects playback state', (tester) async {
    final harness = await buildHarness(tester);

    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
    harness.appState.dispose();
  });

  testWidgets('buffering status is shown calmly when buffering', (
    tester,
  ) async {
    final harness = await buildHarness(tester);

    harness.engine.setBuffering();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.textContaining('Buffering'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
    harness.appState.dispose();
  });
}

class _Harness {
  const _Harness({
    required this.appState,
    required this.audio,
    required this.engine,
  });

  final AppState appState;
  final AudioController audio;
  final FakeAudioEngine engine;
}

class FakeAudioEngine implements AudioEngine {
  AudioEngineSnapshot _snapshot = AudioEngineSnapshot.empty;
  final _snapshotController = StreamController<AudioEngineSnapshot>.broadcast();
  final _eventController = StreamController<EchoAudioEvent>.broadcast();

  @override
  AudioEngineSnapshot get snapshot => _snapshot;

  @override
  Stream<AudioEngineSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<EchoAudioEvent> get events => _eventController.stream;

  @override
  Future<void> setSource({
    required String sourceId,
    required String path,
    String? title,
    Duration? duration,
  }) async {
    _snapshot = AudioEngineSnapshot.empty.copyWith(
      sourceId: sourceId,
      path: path,
      duration: duration ?? const Duration(seconds: 12),
      bufferedPosition: duration ?? const Duration(seconds: 12),
      phase: AudioEnginePhase.loading,
      volume: _snapshot.volume,
      errorMessage: null,
    );
    _emit();
  }

  @override
  Future<void> play() async {
    _snapshot = _snapshot.copyWith(
      isPlaying: true,
      phase: AudioEnginePhase.ready,
      errorMessage: null,
    );
    _emit();
  }

  @override
  Future<void> pause() async {
    _snapshot = _snapshot.copyWith(
      isPlaying: false,
      phase: AudioEnginePhase.ready,
    );
    _emit();
  }

  @override
  Future<void> stop() async {
    _snapshot = AudioEngineSnapshot.empty.copyWith(volume: _snapshot.volume);
    _emit();
  }

  @override
  Future<void> seek(Duration position) async {
    _snapshot = _snapshot.copyWith(position: position);
    _emit();
  }

  @override
  Future<void> setVolume(double volume) async {
    _snapshot = _snapshot.copyWith(volume: volume);
    _emit();
  }

  void setBuffering() {
    _snapshot = _snapshot.copyWith(
      isPlaying: true,
      phase: AudioEnginePhase.buffering,
    );
    _emit();
  }

  void complete() {
    _snapshot = _snapshot.copyWith(
      isPlaying: false,
      phase: AudioEnginePhase.completed,
    );
    _emit();
  }

  void interruptBegin() {
    _eventController.add(
      const EchoAudioEvent(EchoAudioEventType.interruptionBegan),
    );
  }

  void interruptEnd() {
    _eventController.add(
      const EchoAudioEvent(EchoAudioEventType.interruptionEnded),
    );
  }

  void error([String message = 'Playback error']) {
    _eventController.add(
      EchoAudioEvent(EchoAudioEventType.error, message: message),
    );
    _snapshot = _snapshot.copyWith(
      phase: AudioEnginePhase.error,
      errorMessage: message,
    );
    _emit();
  }

  void _emit() {
    if (_snapshotController.isClosed) {
      return;
    }
    _snapshotController.add(_snapshot);
  }

  @override
  Future<void> dispose() async {
    await _snapshotController.close();
    await _eventController.close();
  }
}
