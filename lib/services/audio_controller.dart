import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_engine.dart';
import 'audio_playback_controller.dart';
import 'audio_playback_state.dart';
import 'echo_audio_handler.dart';
import 'native_audio_service.dart';

export 'audio_playback_state.dart';

class AudioController extends ChangeNotifier
    implements AudioPlaybackController {
  AudioController._({
    required AudioEngine engine,
    NativeAudioService? recordingService,
  }) : _engine = engine,
       _recordingService = recordingService ?? NativeAudioService() {
    _bindEngine();
  }

  final AudioEngine _engine;
  final NativeAudioService _recordingService;
  AudioPlaybackState _state = AudioPlaybackState.empty;
  int _operationToken = 0;
  bool _isDisposed = false;

  StreamSubscription<AudioEngineSnapshot>? _engineSub;
  StreamSubscription<EchoAudioEvent>? _engineEventSub;

  static Future<AudioController> create({AudioEngine? engine}) async {
    if (engine != null) {
      return AudioController._(engine: engine);
    }
    try {
      final resolvedEngine = await AudioServiceEngine.create();
      return AudioController._(engine: resolvedEngine);
    } catch (error, stackTrace) {
      debugPrint(
        'AudioServiceEngine init failed, using native fallback: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      final fallbackEngine = NativeAudioEngine();
      return AudioController._(engine: fallbackEngine);
    }
  }

  @override
  AudioPlaybackState get state => _state;

  Future<bool> requestMicrophonePermission() {
    return _recordingService.requestMicrophonePermission();
  }

  Future<bool> startRecording(String path) {
    return _recordingService.startRecording(path);
  }

  Future<bool> stopRecording() {
    return _recordingService.stopRecording();
  }

  void _bindEngine() {
    _engineSub = _engine.snapshots.listen(_handleEngineSnapshot);
    _engineEventSub = _engine.events.listen(_handleEngineEvent);
  }

  void _handleEngineSnapshot(AudioEngineSnapshot snapshot) {
    if (_isDisposed) {
      return;
    }
    final nextPhase = _mapPhase(snapshot);
    _state = _state.copyWith(
      sourceId: snapshot.sourceId,
      path: snapshot.path,
      position: snapshot.position,
      duration: snapshot.duration,
      bufferedPosition: snapshot.bufferedPosition,
      isPlaying: snapshot.isPlaying,
      volume: snapshot.volume,
      phase: nextPhase,
      interrupted: snapshot.interrupted,
      errorMessage: snapshot.errorMessage,
    );
    notifyListeners();
  }

  void _handleEngineEvent(EchoAudioEvent event) {
    if (_isDisposed) {
      return;
    }
    switch (event.type) {
      case EchoAudioEventType.interruptionBegan:
        _state = _state.copyWith(
          isPlaying: false,
          phase: AudioPlaybackPhase.interrupted,
          interrupted: true,
          errorMessage: null,
        );
        notifyListeners();
        break;
      case EchoAudioEventType.interruptionEnded:
        _state = _state.copyWith(
          interrupted: false,
          phase: _state.isPlaying
              ? AudioPlaybackPhase.playing
              : AudioPlaybackPhase.paused,
          errorMessage: null,
        );
        notifyListeners();
        break;
      case EchoAudioEventType.error:
        _state = _state.copyWith(
          isPlaying: false,
          phase: AudioPlaybackPhase.error,
          errorMessage: event.message ?? 'Playback error.',
        );
        notifyListeners();
        break;
    }
  }

  AudioPlaybackPhase _mapPhase(AudioEngineSnapshot snapshot) {
    if (snapshot.interrupted) {
      return AudioPlaybackPhase.interrupted;
    }
    switch (snapshot.phase) {
      case AudioEnginePhase.idle:
        return AudioPlaybackPhase.idle;
      case AudioEnginePhase.loading:
        return AudioPlaybackPhase.loading;
      case AudioEnginePhase.buffering:
        return AudioPlaybackPhase.buffering;
      case AudioEnginePhase.ready:
        return snapshot.isPlaying
            ? AudioPlaybackPhase.playing
            : AudioPlaybackPhase.paused;
      case AudioEnginePhase.completed:
        return AudioPlaybackPhase.completed;
      case AudioEnginePhase.error:
        return AudioPlaybackPhase.error;
    }
  }

  @override
  Future<void> play({
    required String sourceId,
    required String path,
    Duration? duration,
    String? title,
  }) async {
    final token = ++_operationToken;
    _state = _state.copyWith(
      sourceId: sourceId,
      path: path,
      position: Duration.zero,
      duration: duration ?? _state.duration,
      bufferedPosition: Duration.zero,
      isPlaying: false,
      phase: AudioPlaybackPhase.loading,
      interrupted: false,
      errorMessage: null,
    );
    notifyListeners();
    try {
      await _engine.stop();
      await _engine.setSource(
        sourceId: sourceId,
        path: path,
        title: title,
        duration: duration,
      );
      if (token != _operationToken || _isDisposed) {
        return;
      }
      await _engine.setVolume(_state.volume);
      if (token != _operationToken || _isDisposed) {
        return;
      }
      await _engine.play();
    } catch (_) {
      if (token != _operationToken || _isDisposed) {
        return;
      }
      _state = _state.copyWith(
        isPlaying: false,
        phase: AudioPlaybackPhase.error,
        errorMessage: 'Unable to play this clip.',
      );
      notifyListeners();
      return;
    }
  }

  @override
  Future<void> pause() async {
    _operationToken++;
    await _engine.pause();
    _state = _state.copyWith(
      isPlaying: false,
      phase: AudioPlaybackPhase.paused,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    _operationToken++;
    final isReady = _state.isActive;
    if (!isReady) {
      return;
    }
    await _engine.play();
    _state = _state.copyWith(
      isPlaying: true,
      phase: AudioPlaybackPhase.playing,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _operationToken++;
    await _engine.stop();
    _state = _state.copyWith(
      isPlaying: false,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      phase: AudioPlaybackPhase.idle,
      interrupted: false,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_state.isActive) {
      return;
    }
    await _engine.seek(position);
    _state = _state.copyWith(position: position);
    notifyListeners();
  }

  Future<void> toggle({required String sourceId, required String path}) async {
    if (_state.sourceId == sourceId && _state.path == path) {
      if (_state.isPlaying) {
        await pause();
      } else {
        await resume();
      }
      return;
    }
    await play(sourceId: sourceId, path: path);
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    _state = _state.copyWith(volume: clamped);
    await _engine.setVolume(clamped);
    notifyListeners();
  }

  Future<Duration> getAudioDuration(String path) async {
    return _recordingService.getAudioDuration(path);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _operationToken++;
    _engineSub?.cancel();
    _engineEventSub?.cancel();
    _engine.dispose();
    super.dispose();
  }
}
