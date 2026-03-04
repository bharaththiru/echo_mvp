import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'audio_playback_controller.dart';

class PlaybackPerfMonitor {
  PlaybackPerfMonitor({required AudioPlaybackController audio}) : _audio = audio;

  final AudioPlaybackController _audio;
  StreamSubscription<PlaybackMetrics>? _metricsSub;
  TimingsCallback? _timingsCallback;
  Timer? _flushTimer;

  int _frames = 0;
  int _jankFrames = 0;
  int _worstBuildMs = 0;
  int _worstRasterMs = 0;

  int _metricsEvents = 0;
  int _statusEvents = 0;
  int _trackEvents = 0;
  String? _lastSourceId;
  PlaybackProcessingState _lastState = PlaybackProcessingState.idle;

  void start() {
    if (!(kDebugMode || kProfileMode)) {
      return;
    }
    _timingsCallback = (timings) {
      for (final timing in timings) {
        _frames++;
        final buildMs = timing.buildDuration.inMilliseconds;
        final rasterMs = timing.rasterDuration.inMilliseconds;
        if (buildMs > _worstBuildMs) {
          _worstBuildMs = buildMs;
        }
        if (rasterMs > _worstRasterMs) {
          _worstRasterMs = rasterMs;
        }
        if (buildMs > 16 || rasterMs > 16) {
          _jankFrames++;
        }
      }
    };
    WidgetsBinding.instance.addTimingsCallback(_timingsCallback!);

    _metricsSub = _audio.playbackMetrics.listen((metrics) {
      _metricsEvents++;
      if (_lastState != metrics.processingState) {
        _statusEvents++;
        _lastState = metrics.processingState;
      }
      if (_lastSourceId != metrics.sourceId) {
        _trackEvents++;
        _lastSourceId = metrics.sourceId;
      }
    });

    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final metricsPerSecond = _metricsEvents / 5;
      debugPrint(
        '[PlaybackPerf] frames=$_frames jank=$_jankFrames worstBuild=${_worstBuildMs}ms '
        'worstRaster=${_worstRasterMs}ms metricsHz=${metricsPerSecond.toStringAsFixed(1)} '
        'stateChanges=$_statusEvents trackChanges=$_trackEvents',
      );
      _frames = 0;
      _jankFrames = 0;
      _worstBuildMs = 0;
      _worstRasterMs = 0;
      _metricsEvents = 0;
      _statusEvents = 0;
      _trackEvents = 0;
    });
  }

  Future<void> dispose() async {
    if (_timingsCallback != null) {
      WidgetsBinding.instance.removeTimingsCallback(_timingsCallback!);
    }
    _flushTimer?.cancel();
    await _metricsSub?.cancel();
  }
}
