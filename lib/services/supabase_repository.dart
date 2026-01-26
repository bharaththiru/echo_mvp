import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/supabase_config.dart';
import '../models/hashtag.dart';
import '../models/voice_note.dart';

class SupabaseRepository {
  SupabaseRepository(this._client);

  final SupabaseClient _client;

  Future<List<Hashtag>> fetchHashtags() async {
    final response = await _client
        .from('hashtags')
        .select()
        .order('name', ascending: true);
    final rows = List<Map<String, dynamic>>.from(response);
    return rows.map(Hashtag.fromRow).toList();
  }

  Future<List<VoiceNote>> fetchNotes({
    String? hashtagId,
    String? authorId,
    int limit = 40,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    var query = _client
        .from('voice_notes')
        .select(
          'id,hashtag_id,created_at,duration_seconds,storage_path,allow_replies,expires_at,caption,author_id,hashtags(name)',
        )
        .eq('status', 'active')
        .or('expires_at.is.null,expires_at.gt.$now');

    if (hashtagId != null) {
      query = query.eq('hashtag_id', hashtagId);
    }
    if (authorId != null) {
      query = query.eq('author_id', authorId);
    }

    final response = await query
        .order('created_at', ascending: false)
        .limit(limit);
    final rows = List<Map<String, dynamic>>.from(response);
    return rows.map(_noteFromRow).toList();
  }

  Future<VoiceNote> createNote({
    required String id,
    required String hashtagId,
    required int durationSeconds,
    required String storagePath,
    required bool allowReplies,
    required DateTime? expiresAt,
    required String? caption,
    required String authorId,
  }) async {
    final response = await _client
        .from('voice_notes')
        .upsert(
          {
            'id': id,
            'hashtag_id': hashtagId,
            'duration_seconds': durationSeconds,
            'storage_path': storagePath,
            'allow_replies': allowReplies,
            'expires_at': expiresAt?.toUtc().toIso8601String(),
            'caption': caption,
            'author_id': authorId,
          },
          onConflict: 'id',
        )
        .select(
          'id,hashtag_id,created_at,duration_seconds,storage_path,allow_replies,expires_at,caption,author_id,hashtags(name)',
        );

    if (response == null) {
      throw StateError('Empty response from createNote');
    }
    if (response is List && response.isEmpty) {
      throw StateError('Empty response from createNote');
    }
    final row = response is List
        ? Map<String, dynamic>.from(response.first as Map)
        : Map<String, dynamic>.from(response as Map);
    return _noteFromRow(row);
  }

  Future<Map<String, dynamic>> consumeSkip() async {
    final response = await _client.rpc('consume_skip');
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw StateError('Unexpected skip response');
  }

  Future<void> reportClip({
    required String clipId,
    required String reason,
    String? details,
  }) async {
    final reporterId = _client.auth.currentUser?.id;
    if (reporterId == null || reporterId.isEmpty) {
      throw StateError('Missing reporter id');
    }
    await _client.from('reports').insert({
      'reporter_user_id': reporterId,
      'clip_id': clipId,
      'reason': reason,
      if (details != null && details.isNotEmpty) 'details': details,
    });
  }

  Future<void> blockUser({
    required String blockerUserId,
    required String blockedUserId,
  }) async {
    await _client
        .from('blocks')
        .upsert(
          {
            'blocker_user_id': blockerUserId,
            'blocked_user_id': blockedUserId,
          },
          onConflict: 'blocker_user_id,blocked_user_id',
        );
  }

  Future<String> uploadAudio({
    required String userId,
    required String noteId,
    required String filePath,
  }) async {
    final storagePath = '$userId/$noteId.m4a';
    await _client.storage
        .from(SupabaseConfig.storageBucket)
        .upload(
          storagePath,
          File(filePath),
          fileOptions: const FileOptions(upsert: true),
        );
    return storagePath;
  }

  Future<List<int>> downloadAudio(String storagePath) async {
    final response = await _client.storage
        .from(SupabaseConfig.storageBucket)
        .download(storagePath);
    return response;
  }

  VoiceNote _noteFromRow(Map<String, dynamic> row) {
    final hashtag = row['hashtags'] as Map<String, dynamic>?;
    return VoiceNote(
      id: row['id'] as String,
      hashtagId: row['hashtag_id'] as String,
      hashtagLabel: hashtag?['name'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      duration: Duration(seconds: row['duration_seconds'] as int? ?? 0),
      storagePath: row['storage_path'] as String,
      allowReplies: row['allow_replies'] as bool? ?? false,
      expiresAt: row['expires_at'] == null
          ? null
          : DateTime.parse(row['expires_at'] as String).toLocal(),
      authorId: row['author_id'] as String?,
      transcriptPreview: row['caption'] as String?,
    );
  }
}
