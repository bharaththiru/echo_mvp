import 'audio_playback_state.dart';

abstract class AudioPlaybackController {
  AudioPlaybackState get state;

  Future<void> play({
    required String sourceId,
    required String path,
    Duration? duration,
    String? title,
  });

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
