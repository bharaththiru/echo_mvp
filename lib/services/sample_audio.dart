import 'sample_audio_stub.dart'
    if (dart.library.io) 'sample_audio_io.dart'
    if (dart.library.html) 'sample_audio_web.dart';

class SampleAudio {
  static Future<String> ensureSampleAudio() {
    return SampleAudioPlatform.ensureSampleAudio();
  }
}
