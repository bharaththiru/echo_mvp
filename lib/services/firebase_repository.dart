import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/hashtag.dart';
import '../models/voice_note.dart';

class FirebaseRepository {
  FirebaseRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  }) : _firestore = firestore,
       _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Future<List<Hashtag>> fetchHashtags() async {
    final snapshot = await _firestore
        .collection('hashtags')
        .where('is_active', isEqualTo: true)
        .orderBy('name')
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      final noteCount = _parseInt(data['note_count']);
      final isActive = data['is_active'];
      if (isActive is bool && !isActive) {
        return null;
      }
      return Hashtag.fromRow({
        'id': doc.id,
        'name': data['name'],
        'description': data['description'],
        'note_count': noteCount,
      });
    }).whereType<Hashtag>().toList();
  }

  Future<List<VoiceNote>> fetchNotes({
    String? hashtagId,
    String? authorId,
    int limit = 40,
  }) async {
    final now = Timestamp.fromDate(DateTime.now().toUtc());
    Query<Map<String, dynamic>> base = _firestore
        .collection('voice_notes')
        .where('status', isEqualTo: 'active');

    if (hashtagId != null) {
      base = base.where('hashtag_id', isEqualTo: hashtagId);
    }
    if (authorId != null) {
      base = base.where('author_id', isEqualTo: authorId);
    }

    final nonExpiring = base
        .where('expires_at', isNull: true)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    final expiring = base
        .where('expires_at', isGreaterThan: now)
        .orderBy('expires_at')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();

    final results = await Future.wait([nonExpiring, expiring]);
    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in results) {
      for (final doc in snapshot.docs) {
        merged[doc.id] = doc;
      }
    }
    final notes =
        merged.values.map(_noteFromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (notes.length > limit) {
      return notes.sublist(0, limit);
    }
    return notes;
  }

  Future<VoiceNote> createNote({
    required String id,
    required String hashtagId,
    required String hashtagLabel,
    required int durationSeconds,
    required String storagePath,
    required bool allowReplies,
    required DateTime? expiresAt,
    required String? caption,
    required String authorId,
  }) async {
    final createdAt = DateTime.now().toUtc();
    final docRef = _firestore.collection('voice_notes').doc(id);
    await docRef.set({
      'hashtag_id': hashtagId,
      'hashtag_label': hashtagLabel,
      'created_at': Timestamp.fromDate(createdAt),
      'duration_seconds': durationSeconds,
      'storage_path': storagePath,
      'allow_replies': allowReplies,
      'expires_at': expiresAt == null
          ? null
          : Timestamp.fromDate(expiresAt.toUtc()),
      'caption': caption,
      'author_id': authorId,
      'status': 'active',
    }, SetOptions(merge: true));

    return VoiceNote(
      id: id,
      hashtagId: hashtagId,
      hashtagLabel: hashtagLabel,
      createdAt: createdAt.toLocal(),
      duration: Duration(seconds: durationSeconds),
      storagePath: storagePath,
      allowReplies: allowReplies,
      expiresAt: expiresAt?.toLocal(),
      authorId: authorId,
      transcriptPreview: caption,
    );
  }

  Future<Map<String, dynamic>> consumeSkip({required String userId}) async {
    final localDate = _localDateKey();
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('daily_skip_usage')
        .doc(localDate);

    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final current = snapshot.data();
      final used = _parseInt(current?['skips_used']);
      if (used >= 3) {
        return {
          'ok': false,
          'skips_left': 0,
          'local_date': localDate,
        };
      }
      final next = used + 1;
      transaction.set(
        docRef,
        {
          'skips_used': next,
          'local_date': localDate,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return {
        'ok': true,
        'skips_left': 3 - next,
        'local_date': localDate,
      };
    });
  }

  Future<void> reportClip({
    required String reporterUserId,
    required String clipId,
    required String reason,
    String? details,
  }) async {
    await _firestore.collection('reports').add({
      'reporter_user_id': reporterUserId,
      'clip_id': clipId,
      'reason': reason,
      if (details != null && details.isNotEmpty) 'details': details,
      'created_at': FieldValue.serverTimestamp(),
      'status': 'open',
    });
  }

  Future<void> blockUser({
    required String blockerUserId,
    required String blockedUserId,
  }) async {
    await _firestore
        .collection('users')
        .doc(blockerUserId)
        .collection('blocks')
        .doc(blockedUserId)
        .set({
          'blocked_user_id': blockedUserId,
          'created_at': FieldValue.serverTimestamp(),
        });
  }

  Future<String> uploadAudio({
    required String userId,
    required String noteId,
    required String filePath,
  }) async {
    final storagePath = '$userId/$noteId.m4a';
    final ref = _storage.ref().child(storagePath);
    await ref.putFile(
      File(filePath),
      SettableMetadata(contentType: 'audio/m4a'),
    );
    return storagePath;
  }

  Future<String> fetchAudioUrl(String storagePath) async {
    final ref = _storage.ref(storagePath);
    return ref.getDownloadURL();
  }

  Future<List<int>> downloadAudio(String storagePath) async {
    final ref = _storage.ref(storagePath);
    const maxSizeBytes = 20 * 1024 * 1024;
    final data = await ref.getData(maxSizeBytes);
    if (data == null) {
      return const <int>[];
    }
    return data;
  }

  VoiceNote _noteFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = _readTimestamp(data['created_at'])?.toLocal() ??
        DateTime.now();
    final expiresAt = _readTimestamp(data['expires_at'])?.toLocal();
    final hashtagId = data['hashtag_id'] as String? ?? '';
    final hashtagLabel =
        data['hashtag_label'] as String? ??
        data['hashtag_name'] as String? ??
        (hashtagId.isEmpty ? '' : '#$hashtagId');
    return VoiceNote(
      id: doc.id,
      hashtagId: hashtagId,
      hashtagLabel: hashtagLabel,
      createdAt: createdAt,
      duration: Duration(seconds: _parseInt(data['duration_seconds'])),
      storagePath: data['storage_path'] as String? ?? '',
      allowReplies: data['allow_replies'] as bool? ?? false,
      expiresAt: expiresAt,
      authorId: data['author_id'] as String?,
      transcriptPreview: data['caption'] as String?,
    );
  }

  DateTime? _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  String _localDateKey() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
