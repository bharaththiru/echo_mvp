import '../models/voice_note.dart';

class SkipQuotaResult {
  const SkipQuotaResult({
    required this.allowed,
    required this.skipsLeft,
    this.message,
  });

  final bool allowed;
  final int skipsLeft;
  final String? message;
}

abstract class AutoplayDataSource {
  Future<String?> ensureLocalAudioPath(VoiceNote note);
  Future<SkipQuotaResult> consumeSkip();
}
