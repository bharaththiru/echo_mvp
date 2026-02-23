import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeAudioService {
  static const MethodChannel _channel = MethodChannel('echo.audio/methods');

  Future<bool> requestMicrophonePermission() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestMicrophonePermission',
      );
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> startRecording(String path) async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('startRecording', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopRecording() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('stopRecording');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> startPlayback(String path) async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('startPlayback', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> pausePlayback() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('pausePlayback');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> resumePlayback() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('resumePlayback');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopPlayback() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('stopPlayback');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isPlaying() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('isPlaying');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<Duration> getPlaybackPosition() async {
    if (kIsWeb) {
      return Duration.zero;
    }
    try {
      final millis = await _channel.invokeMethod<int>('getPlaybackPosition');
      return Duration(milliseconds: millis ?? 0);
    } on PlatformException {
      return Duration.zero;
    }
  }

  Future<Duration> getPlaybackDuration() async {
    if (kIsWeb) {
      return Duration.zero;
    }
    try {
      final millis = await _channel.invokeMethod<int>('getPlaybackDuration');
      return Duration(milliseconds: millis ?? 0);
    } on PlatformException {
      return Duration.zero;
    }
  }

  Future<bool> seekTo(Duration position) async {
    if (kIsWeb) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('seekTo', {
        'positionMs': position.inMilliseconds,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setPlaybackVolume(double value) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setPlaybackVolume', {'volume': value});
    } on PlatformException {
      return;
    }
  }

  Future<Duration> getAudioDuration(String path) async {
    if (kIsWeb) {
      return Duration.zero;
    }
    try {
      final millis = await _channel.invokeMethod<int>('getAudioDuration', {
        'path': path,
      });
      return Duration(milliseconds: millis ?? 0);
    } on PlatformException {
      return Duration.zero;
    }
  }
}
