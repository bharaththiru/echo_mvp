import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../services/audio_controller.dart';

class RecordTab extends StatefulWidget {
  const RecordTab({super.key});

  @override
  State<RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends State<RecordTab> with WidgetsBindingObserver {
  static const int _maxSeconds = 12;

  final Random _random = Random();
  AudioController? _audio;
  Timer? _countdownTimer;
  Timer? _waveTimer;
  int _remainingSeconds = _maxSeconds;
  bool _isRecording = false;
  bool _hasRecording = false;
  bool _finalizingRecording = false;
  bool _permissionRequestInFlight = false;
  int _permissionDeniedCount = 0;
  DateTime? _lastPermissionDeniedAt;
  bool _restoredDraft = false;
  String? _recordingPath;
  List<double> _waveHeights = List<double>.filled(12, 0.2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audio ??= AppScope.of(context).audio;
    _restorePendingRecording();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _waveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_isRecording) {
      unawaited(_stopRecording(interrupted: true, silent: true));
    } else {
      _audio?.stopRecording();
    }
    _audio?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isRecording) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stopRecording(interrupted: true));
    }
  }

  Future<void> _startRecording() async {
    final appState = AppScope.of(context);
    appState.audio.stop();
    if (_permissionRequestInFlight || _isRecording || _finalizingRecording) {
      return;
    }
    final now = DateTime.now();
    if (_permissionDeniedCount >= 2 &&
        _lastPermissionDeniedAt != null &&
        now.difference(_lastPermissionDeniedAt!) < const Duration(seconds: 30)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone permission denied. Enable it in Settings to record.',
          ),
        ),
      );
      return;
    }
    _permissionRequestInFlight = true;
    final granted = await appState.audio.requestMicrophonePermission();
    _permissionRequestInFlight = false;
    if (!mounted) {
      return;
    }
    if (!granted) {
      _permissionDeniedCount += 1;
      _lastPermissionDeniedAt = DateTime.now();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _permissionDeniedCount >= 2
                ? 'Microphone permission denied. Enable it in Settings.'
                : 'Microphone permission is required to record.',
          ),
        ),
      );
      return;
    }
    _permissionDeniedCount = 0;
    _lastPermissionDeniedAt = null;
    appState.clearPendingPostDraft();
    appState.clearPendingRecording();

    final path = appState.createRecordingPath();
    final started = await appState.audio.startRecording(path);
    if (!started) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start recording.')),
      );
      return;
    }

    setState(() {
      _recordingPath = path;
      _isRecording = true;
      _hasRecording = false;
      _remainingSeconds = _maxSeconds;
    });

    _startCountdown();
    _startWaveform();
  }

  Future<void> _stopRecording({
    bool interrupted = false,
    bool silent = false,
  }) async {
    if (_finalizingRecording) {
      return;
    }
    _finalizingRecording = true;
    final appState = AppScope.of(context);
    try {
      await appState.audio.stopRecording();
      _countdownTimer?.cancel();
      _waveTimer?.cancel();
      final path = _recordingPath;
      var hasRecording = false;
      if (path != null && path.isNotEmpty) {
        hasRecording = await _isValidRecordingFile(path);
      }
      if (hasRecording && path != null) {
        appState.setPendingRecordingPath(path);
      } else {
        if (path != null &&
            appState.pendingPostDraft?.recordingPath == path) {
          appState.clearPendingPostDraft();
        }
        appState.clearPendingRecording();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
        _hasRecording = hasRecording;
        if (!hasRecording) {
          _recordingPath = null;
          _remainingSeconds = _maxSeconds;
        }
      });
      if (!silent) {
        if (!hasRecording) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording not saved. Please try again.'),
            ),
          );
        } else if (interrupted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording stopped due to an interruption.'),
            ),
          );
        }
      }
    } finally {
      _finalizingRecording = false;
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        _stopRecording();
      } else {
        setState(() => _remainingSeconds -= 1);
      }
    });
  }

  void _startWaveform() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      setState(() {
        _waveHeights = _waveHeights
            .map((_) => 0.2 + _random.nextDouble() * 0.8)
            .toList();
      });
    });
  }

  Future<bool> _isValidRecordingFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }
      final size = await file.length();
      return size > 0;
    } catch (_) {
      return false;
    }
  }

  void _restorePendingRecording() {
    if (_restoredDraft || _isRecording || _hasRecording) {
      return;
    }
    final appState = AppScope.of(context);
    final pending = appState.pendingRecordingPath;
    if (pending == null || pending.isEmpty) {
      _restoredDraft = true;
      return;
    }
    final file = File(pending);
    try {
      if (!file.existsSync() || file.lengthSync() <= 0) {
        appState.clearPendingPostDraft();
        appState.clearPendingRecording();
        _restoredDraft = true;
        return;
      }
      setState(() {
        _recordingPath = pending;
        _hasRecording = true;
        _remainingSeconds = _maxSeconds;
        _waveHeights = List<double>.filled(12, 0.2);
        _restoredDraft = true;
      });
    } catch (_) {
      appState.clearPendingPostDraft();
      appState.clearPendingRecording();
      _restoredDraft = true;
    }
  }

  void _reRecord() {
    final appState = AppScope.of(context);
    appState.audio.stop();
    appState.clearPendingPostDraft();
    appState.clearPendingRecording();
    setState(() {
      _hasRecording = false;
      _recordingPath = null;
      _remainingSeconds = _maxSeconds;
      _waveHeights = List<double>.filled(12, 0.2);
    });
  }

  Future<void> _continue() async {
    final appState = AppScope.of(context);
    final path = _recordingPath;
    if (path == null) {
      return;
    }
    final valid = await _isValidRecordingFile(path);
    if (!valid) {
      appState.clearPendingPostDraft();
      appState.clearPendingRecording();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording not found. Please record again.'),
        ),
      );
      setState(() {
        _hasRecording = false;
        _recordingPath = null;
      });
      return;
    }
    appState.setPendingRecordingPath(path);
    context.go('/post-options');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = AppScope.of(context);
    final reduceMotion = appState.settings.reduceMotion;

    return AnimatedBuilder(
      animation: appState.audio,
      builder: (context, _) {
        final audioState = appState.audio.state;
        final isPlaying =
            audioState.sourceId == 'recording_preview' && audioState.isPlaying;
        final ringColor = _isRecording ? EchoColors.action : EchoColors.accent;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Record', style: theme.textTheme.displaySmall),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 240,
                        width: 240,
                        child: CircularProgressIndicator(
                          value: _isRecording
                              ? 1 - (_remainingSeconds / _maxSeconds)
                              : 0,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          backgroundColor: EchoColors.muted,
                          valueColor: AlwaysStoppedAnimation(ringColor),
                        ),
                      ),
                      SizedBox(
                        height: 160,
                        width: 160,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            backgroundColor: _isRecording
                                ? EchoColors.action
                                : EchoColors.accent,
                            foregroundColor: EchoColors.background,
                          ),
                          onPressed: _isRecording
                              ? _stopRecording
                              : _hasRecording
                              ? () async {
                                  final path = _recordingPath;
                                  if (path == null) {
                                    return;
                                  }
                                  final valid = await _isValidRecordingFile(
                                    path,
                                  );
                                  if (!valid) {
                                    appState.clearPendingPostDraft();
                                    appState.clearPendingRecording();
                                    if (!mounted) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Recording not found. Please record again.',
                                        ),
                                      ),
                                    );
                                    setState(() {
                                      _hasRecording = false;
                                      _recordingPath = null;
                                    });
                                    return;
                                  }
                                  appState.audio.toggle(
                                    sourceId: 'recording_preview',
                                    path: path,
                                  );
                                }
                              : _startRecording,
                          child: Icon(
                            _isRecording
                                ? Icons.close
                                : _hasRecording
                                ? (isPlaying ? Icons.pause : Icons.play_arrow)
                                : Icons.mic,
                            size: 46,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isRecording) ...[
                    Text(
                      '$_remainingSeconds',
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'seconds remaining',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: EchoColors.textSecondary,
                      ),
                    ),
                  ] else if (_hasRecording) ...[
                    Text('Your recording', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to preview',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: EchoColors.textSecondary,
                      ),
                    ),
                  ] else ...[
                    Text('Tap to record', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      '12 seconds max',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: EchoColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_isRecording)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _waveHeights
                          .map(
                            (height) => AnimatedContainer(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: 6,
                              height: 20 + 60 * height,
                              decoration: BoxDecoration(
                                color: ringColor.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
            if (_hasRecording)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _continue,
                        child: const Text('Continue'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _reRecord,
                        icon: const Icon(Icons.replay),
                        label: const Text('Re-record'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
