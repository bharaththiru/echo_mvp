import 'dart:async';

import 'package:echo/services/audio_controller.dart';
import 'package:echo/services/audio_engine.dart';
import 'package:echo/services/audio_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playbackUiMetrics samples high-frequency engine snapshots', () async {
    final engine = _BurstAudioEngine();
    final audio = await AudioController.create(engine: engine);
    final events = <PlaybackMetrics>[];
    final sub = audio.playbackUiMetrics.listen(events.add);

    engine.emitBurst(count: 20, step: const Duration(milliseconds: 25));
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(events.length, lessThan(10));

    await sub.cancel();
    audio.dispose();
  });
}

class _BurstAudioEngine implements AudioEngine {
  AudioEngineSnapshot _snapshot = AudioEngineSnapshot.empty;
  final _snapshots = StreamController<AudioEngineSnapshot>.broadcast();
  final _events = StreamController<EchoAudioEvent>.broadcast();

  @override
  AudioEngineSnapshot get snapshot => _snapshot;

  @override
  Stream<AudioEngineSnapshot> get snapshots => _snapshots.stream;

  @override
  Stream<EchoAudioEvent> get events => _events.stream;

  void emitBurst({required int count, required Duration step}) {
    for (var i = 0; i < count; i++) {
      Future<void>.delayed(step * i, () {
        _snapshot = _snapshot.copyWith(
          sourceId: 'note-1',
          path: '/tmp/note-1.m4a',
          queueIndex: 0,
          duration: const Duration(seconds: 12),
          bufferedPosition: const Duration(seconds: 12),
          position: Duration(milliseconds: i * 25),
          isPlaying: true,
          phase: AudioEnginePhase.ready,
        );
        _snapshots.add(_snapshot);
      });
    }
  }

  @override
  Future<void> appendQueue(List<AudioQueueItem> queue) async {}

  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _events.close();
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> seekToIndex(int index, {Duration? position}) async {}

  @override
  Future<void> setQueue({
    required List<AudioQueueItem> queue,
    int initialIndex = 0,
    Duration? startPosition,
  }) async {}

  @override
  Future<void> setSource({
    required String sourceId,
    required String path,
    String? title,
    Duration? duration,
  }) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> stop() async {}
}
