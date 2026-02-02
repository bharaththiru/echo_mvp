import 'audio_playback_state.dart';

class AudioQueueItem {
  const AudioQueueItem({
    required this.sourceId,
    required this.path,
    this.duration,
    this.title,
  });

  final String sourceId;
  final String path;
  final Duration? duration;
  final String? title;
}

abstract class AudioPlaybackController {
  AudioPlaybackState get state;

  Future<void> play({
    required String sourceId,
    required String path,
    Duration? duration,
    String? title,
  });

  Future<void> playQueue({
    required List<AudioQueueItem> queue,
    int initialIndex = 0,
    Duration? startPosition,
  });

  Future<void> appendQueue(List<AudioQueueItem> queue);
  Future<void> seekToIndex(int index, {Duration? position});
  Future<void> skipToNext();
  Future<void> skipToPrevious();

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
