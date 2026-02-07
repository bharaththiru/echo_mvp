import '../models/voice_note.dart';

class AutoplayFeedPage {
  const AutoplayFeedPage({
    required this.stationId,
    required this.notes,
    required this.nextCursor,
    required this.hasMore,
  });

  final String stationId;
  final List<VoiceNote> notes;
  final String? nextCursor;
  final bool hasMore;
}

abstract class AutoplayFeedQueueBuilder {
  Future<AutoplayFeedPage> loadPage({
    required String stationId,
    required int limit,
    String? cursor,
  });

  Future<List<String>> fallbackStationIds({
    required String currentStationId,
    int limit = 6,
  });
}
