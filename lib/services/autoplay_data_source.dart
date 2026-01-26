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
  List<VoiceNote> notesForHashtag(String hashtagId);
  bool isLoadingNotes(String hashtagId);
  String? notesError(String hashtagId);
  Future<void> loadNotesForHashtag(String hashtagId, {bool force});
  Future<String?> ensureLocalAudioPath(VoiceNote note);
  Future<SkipQuotaResult> consumeSkip();
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
