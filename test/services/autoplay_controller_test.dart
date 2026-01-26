import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:echo/models/voice_note.dart';
import 'package:echo/services/audio_playback_controller.dart';
import 'package:echo/services/audio_playback_state.dart';
import 'package:echo/services/autoplay_controller.dart';
import 'package:echo/services/autoplay_data_source.dart';

void main() {
  const hashtagId = 'focus';

  VoiceNote note(String id, {String hashtag = hashtagId, String? authorId}) {
    return VoiceNote(
      id: id,
      hashtagId: hashtag,
      hashtagLabel: '#$hashtag',
      createdAt: DateTime(2025, 1, 1).add(Duration(minutes: id.hashCode % 30)),
      duration: const Duration(seconds: 12),
      storagePath: 'storage/$id.m4a',
      allowReplies: true,
      expiresAt: null,
      authorId: authorId,
      transcriptPreview: 'clip $id',
      localPath: 'clip_$id.m4a',
    );
  }

  Future<void> settle([Duration duration = const Duration(milliseconds: 20)]) {
    return Future<void>.delayed(duration);
  }

  test('starts autoplay on attach and plays the first clip', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [note('a'), note('b')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();

    expect(audio.playHistory, isNotEmpty);
    expect(audio.playHistory.first, 'a');
    expect(controller.state.currentNote?.id, 'a');
    expect(controller.state.phase, AutoplayPhase.playing);
  });

  test('advances on completion without repeating until exhausted', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [note('a'), note('b'), note('c')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();
    expect(audio.playHistory, ['a']);

    audio.complete();
    await settle(const Duration(milliseconds: 360));
    expect(audio.playHistory, ['a', 'b']);

    audio.complete();
    await settle(const Duration(milliseconds: 360));
    expect(audio.playHistory, ['a', 'b', 'c']);
  });

  test('resumes after interruption only when user did not pause', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [note('a'), note('b')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();
    expect(controller.state.phase, AutoplayPhase.playing);

    audio.interruptBegin();
    await settle();
    expect(controller.state.phase, AutoplayPhase.interrupted);

    audio.interruptEnd();
    await settle();
    expect(audio.resumeCalls, 1);
  });

  test('does not auto-resume after user pause', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [note('a'), note('b')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();

    await controller.togglePlayPause();
    await settle();
    expect(controller.state.phase, AutoplayPhase.paused);

    audio.interruptBegin();
    await settle();
    audio.interruptEnd();
    await settle();

    expect(audio.resumeCalls, 0);
  });

  test('auto-skips when loading stalls', () {
    fakeAsync((async) {
      final dataSource = FakeAutoplayDataSource({
        hashtagId: [note('a'), note('b')],
      });
      final audio = FakeAudioPlaybackController(autoPlay: false);
      final controller = AutoplayController(dataSource: dataSource, audio: audio);

      controller.attach(hashtagId);
      async.elapse(const Duration(milliseconds: 60));

      expect(audio.playHistory, ['a']);

      async.elapse(const Duration(seconds: 12));
      async.elapse(const Duration(milliseconds: 400));

      expect(audio.playHistory.length, greaterThan(1));
    });
  });

  test('debounces skip quota consumption on rapid taps', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [note('a'), note('b')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();

    controller.skip();
    controller.skip();
    await settle(const Duration(milliseconds: 40));

    expect(dataSource.skipCalls, 1);
  });

  test('mute only affects the current clip', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [note('a'), note('b')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();

    await controller.toggleMute();
    await settle();

    expect(controller.state.isMuted, true);
    expect(audio.lastVolume, 0);

    await controller.togglePlayPause();
    await settle();
    await controller.togglePlayPause();
    await settle();

    expect(controller.state.isMuted, true);
    expect(audio.lastVolume, 0);

    await controller.skip();
    await settle(const Duration(milliseconds: 360));

    expect(controller.state.isMuted, false);
    expect(audio.lastVolume, closeTo(0.8, 0.001));
  });

  test('auto-skips dead clips without consuming skip quota', () async {
    final dataSource = FakeAutoplayDataSource(
      {
        hashtagId: [note('a'), note('b')],
      },
      failingNotes: {'a'},
    );
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle(const Duration(milliseconds: 900));

    expect(dataSource.skipCalls, 0);
    expect(audio.playHistory, ['b']);
    expect(controller.state.currentNote?.id, 'b');
  });

  test('suppresses the current clip without consuming skip quota', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [note('a'), note('b')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();
    expect(controller.state.currentNote?.id, 'a');

    await controller.suppressNote('a');
    await settle(const Duration(milliseconds: 360));

    expect(dataSource.skipCalls, 0);
    expect(controller.state.currentNote?.id, 'b');
    expect(
      controller.state.queue.any((note) => note.id == 'a'),
      isFalse,
    );
  });

  test('suppresses all clips from a blocked author', () async {
    final dataSource = FakeAutoplayDataSource({
      hashtagId: [
        note('a', authorId: 'user-1'),
        note('b', authorId: 'user-2'),
      ],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach(hashtagId);
    await settle();

    await controller.suppressAuthor('user-1');
    await settle(const Duration(milliseconds: 200));

    expect(
      controller.state.queue.any((note) => note.authorId == 'user-1'),
      isFalse,
    );
  });

  test('switching hashtags resets playback to the new queue', () async {
    final dataSource = FakeAutoplayDataSource({
      'alpha': [note('a1', hashtag: 'alpha')],
      'beta': [note('b1', hashtag: 'beta')],
    });
    final audio = FakeAudioPlaybackController();
    final controller = AutoplayController(dataSource: dataSource, audio: audio);

    controller.attach('alpha');
    await settle();
    expect(controller.state.currentNote?.hashtagId, 'alpha');

    controller.attach('beta');
    await settle();
    expect(controller.state.currentNote?.hashtagId, 'beta');
    expect(audio.playHistory.last, 'b1');
  });

  test('enters recoverable error after consecutive failures', () {
    fakeAsync((async) {
      final dataSource = FakeAutoplayDataSource(
        {
          hashtagId: [note('a'), note('b'), note('c')],
        },
        failingNotes: {'a', 'b', 'c'},
      );
      final audio = FakeAudioPlaybackController();
      final controller = AutoplayController(dataSource: dataSource, audio: audio);

      controller.attach(hashtagId);
      async.elapse(const Duration(seconds: 3));

      expect(controller.state.phase, AutoplayPhase.error);
      expect(controller.state.errorMessage, isNotNull);
      expect(audio.playHistory, isEmpty);
    });
  });
}

class FakeAutoplayDataSource extends ChangeNotifier
    implements AutoplayDataSource {
  FakeAutoplayDataSource(
    this._notesByHashtag, {
    Set<String> failingNotes = const {},
  }) : _failingNotes = failingNotes;

  final Map<String, List<VoiceNote>> _notesByHashtag;
  final Set<String> _failingNotes;
  final Map<String, bool> _loading = <String, bool>{};
  final Map<String, String?> _errors = <String, String?>{};
  int skipCalls = 0;
  bool allowSkips = true;

  @override
  List<VoiceNote> notesForHashtag(String hashtagId) {
    return List<VoiceNote>.from(_notesByHashtag[hashtagId] ?? const []);
  }

  @override
  bool isLoadingNotes(String hashtagId) => _loading[hashtagId] ?? false;

  @override
  String? notesError(String hashtagId) => _errors[hashtagId];

  @override
  Future<void> loadNotesForHashtag(
    String hashtagId, {
    bool force = false,
  }) async {
    _loading[hashtagId] = false;
    notifyListeners();
  }

  @override
  Future<String?> ensureLocalAudioPath(VoiceNote note) async {
    if (_failingNotes.contains(note.id)) {
      return null;
    }
    return note.localPath ?? 'clip_${note.id}.m4a';
  }

  @override
  Future<SkipQuotaResult> consumeSkip() async {
    skipCalls += 1;
    if (!allowSkips) {
      return const SkipQuotaResult(
        allowed: false,
        skipsLeft: 0,
        message: 'No skips left today.',
      );
    }
    return const SkipQuotaResult(allowed: true, skipsLeft: 2);
  }
}

class FakeAudioPlaybackController extends ChangeNotifier
    implements AudioPlaybackController {
  FakeAudioPlaybackController({this.autoPlay = true});

  final bool autoPlay;
  AudioPlaybackState _state = AudioPlaybackState.empty;
  final List<String> playHistory = <String>[];
  int resumeCalls = 0;
  double lastVolume = 0.8;

  @override
  AudioPlaybackState get state => _state;

  @override
  Future<void> play({
    required String sourceId,
    required String path,
    Duration? duration,
    String? title,
  }) async {
    playHistory.add(sourceId);
    final resolvedDuration = duration ?? const Duration(seconds: 12);
    _state = AudioPlaybackState(
      sourceId: sourceId,
      path: path,
      position: Duration.zero,
      duration: resolvedDuration,
      bufferedPosition: autoPlay ? resolvedDuration : Duration.zero,
      isPlaying: autoPlay,
      volume: _state.volume,
      phase: autoPlay
          ? AudioPlaybackPhase.playing
          : AudioPlaybackPhase.loading,
      interrupted: false,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _state = _state.copyWith(
      isPlaying: false,
      phase: AudioPlaybackPhase.paused,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    _state = _state.copyWith(
      isPlaying: true,
      phase: AudioPlaybackPhase.playing,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _state = AudioPlaybackState.empty.copyWith(volume: _state.volume);
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    _state = _state.copyWith(position: position);
    notifyListeners();
  }

  @override
  Future<void> setVolume(double volume) async {
    _state = _state.copyWith(volume: volume);
    lastVolume = volume;
    notifyListeners();
  }

  void complete() {
    _state = _state.copyWith(
      isPlaying: false,
      phase: AudioPlaybackPhase.completed,
    );
    notifyListeners();
  }

  void interruptBegin() {
    _state = _state.copyWith(
      isPlaying: false,
      phase: AudioPlaybackPhase.interrupted,
      interrupted: true,
    );
    notifyListeners();
  }

  void interruptEnd() {
    _state = _state.copyWith(
      isPlaying: false,
      phase: AudioPlaybackPhase.paused,
      interrupted: false,
    );
    notifyListeners();
  }
}
