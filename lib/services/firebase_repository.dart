import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/hashtag.dart';
import '../models/voice_note.dart';

class HashtagFeedPageResult {
  const HashtagFeedPageResult({
    required this.notes,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<VoiceNote> notes;
  final String? nextCursor;
  final bool hasMore;
}

class _HashtagFeedCursor {
  const _HashtagFeedCursor({
    required this.createdAtUtc,
    required this.noteId,
  });

  final DateTime createdAtUtc;
  final String noteId;

  String encode() {
    return '${createdAtUtc.millisecondsSinceEpoch}|$noteId';
  }

  static _HashtagFeedCursor? tryDecode(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    final separator = token.indexOf('|');
    if (separator <= 0 || separator >= token.length - 1) {
      return null;
    }
    final millis = int.tryParse(token.substring(0, separator));
    final noteId = token.substring(separator + 1);
    if (millis == null || noteId.isEmpty) {
      return null;
    }
    return _HashtagFeedCursor(
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      noteId: noteId,
    );
  }
}

class _CachedAudioUrl {
  const _CachedAudioUrl({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}

class _StationFeedEntry {
  const _StationFeedEntry({
    required this.clipId,
    this.inlineNote,
  });

  final String clipId;
  final VoiceNote? inlineNote;
}

class FirebaseRepository {
  FirebaseRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    String? storageCdnBaseUrl,
  }) : _firestore = firestore,
       _storage = storage,
       _storageCdnBaseUrl = _normalizeBaseUrl(storageCdnBaseUrl);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final String? _storageCdnBaseUrl;
  final Map<String, _CachedAudioUrl> _audioUrlCache = <String, _CachedAudioUrl>{};
  bool _stationFeedQueryEnabled = true;
  bool _legacyHashtagPagedQueryEnabled = true;
  static const _audioUrlCacheTtl = Duration(hours: 6);

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

  Future<HashtagFeedPageResult> fetchHashtagFeedPage({
    required String hashtagId,
    int limit = 40,
    String? cursor,
  }) async {
    final stationId = hashtagId.trim();
    if (stationId.isEmpty || limit <= 0) {
      return const HashtagFeedPageResult(
        notes: <VoiceNote>[],
        nextCursor: null,
        hasMore: false,
      );
    }
    final requested = limit.clamp(1, 100).toInt();
    HashtagFeedPageResult? stationFeed;
    if (_stationFeedQueryEnabled) {
      try {
        stationFeed = await _fetchStationFeedPage(
          stationId: stationId,
          limit: requested,
          cursor: cursor,
        );
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          _stationFeedQueryEnabled = false;
        }
        stationFeed = null;
      }
    }
    if (stationFeed != null && stationFeed.notes.isNotEmpty) {
      return stationFeed;
    }
    return _fetchLegacyHashtagFeedPage(
      hashtagId: stationId,
      limit: requested,
      cursor: cursor,
    );
  }

  Future<HashtagFeedPageResult?> _fetchStationFeedPage({
    required String stationId,
    required int limit,
    String? cursor,
  }) async {
    final now = DateTime.now().toUtc();
    final requested = limit.clamp(1, 100).toInt();
    final collected = <VoiceNote>[];
    var cursorValue = _HashtagFeedCursor.tryDecode(cursor);
    var hasMore = true;
    var loops = 0;
    var feedSeen = false;
    while (collected.length < requested && hasMore && loops < 8) {
      final fetchLimit = ((requested - collected.length) + 20)
          .clamp(10, 100)
          .toInt();
      Query<Map<String, dynamic>> query = _firestore
          .collection('stations')
          .doc(stationId)
          .collection('feed')
          .orderBy('created_at', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(fetchLimit);
      if (cursorValue != null) {
        query = query.startAfter(<Object>[
          Timestamp.fromDate(cursorValue.createdAtUtc),
          cursorValue.noteId,
        ]);
      }
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }
      feedSeen = true;
      final entries = <_StationFeedEntry>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final clipId = (data['clip_id'] as String?)?.trim() ?? doc.id;
        if (clipId.isEmpty) {
          continue;
        }
        final inlineNote = _noteFromStationFeedDoc(
          doc,
          stationId: stationId,
        );
        entries.add(
          _StationFeedEntry(
            clipId: clipId,
            inlineNote: inlineNote,
          ),
        );
      }
      final unresolvedClipIds = entries
          .where((entry) => entry.inlineNote == null)
          .map((entry) => entry.clipId)
          .toSet()
          .toList();
      final hydratedById = unresolvedClipIds.isEmpty
          ? <String, VoiceNote>{}
          : await _fetchClipMetadataByIds(
              clipIds: unresolvedClipIds,
              stationId: stationId,
            );
      for (final entry in entries) {
        final resolved = entry.inlineNote ?? hydratedById[entry.clipId];
        if (resolved == null) {
          continue;
        }
        final expiresAtUtc = resolved.expiresAt?.toUtc();
        final stillActive = expiresAtUtc == null || expiresAtUtc.isAfter(now);
        if (!stillActive) {
          continue;
        }
        collected.add(resolved);
        if (collected.length >= requested) {
          break;
        }
      }
      final lastDoc = snapshot.docs.last;
      final lastCreatedAt =
          _readTimestamp(lastDoc.data()['created_at'])?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      cursorValue = _HashtagFeedCursor(
        createdAtUtc: lastCreatedAt,
        noteId: lastDoc.id,
      );
      hasMore = snapshot.docs.length >= fetchLimit;
      loops += 1;
    }
    if (!feedSeen) {
      return null;
    }
    if (collected.length > requested) {
      collected.removeRange(requested, collected.length);
    }
    final nextCursor = hasMore && cursorValue != null
        ? cursorValue.encode()
        : null;
    return HashtagFeedPageResult(
      notes: collected,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Future<HashtagFeedPageResult> _fetchLegacyHashtagFeedPage({
    required String hashtagId,
    required int limit,
    String? cursor,
  }) async {
    final now = DateTime.now().toUtc();
    final requested = limit.clamp(1, 100).toInt();
    if (!_legacyHashtagPagedQueryEnabled) {
      if (cursor != null && cursor.isNotEmpty) {
        return const HashtagFeedPageResult(
          notes: <VoiceNote>[],
          nextCursor: null,
          hasMore: false,
        );
      }
      final fallback = await fetchNotes(hashtagId: hashtagId, limit: requested);
      final notes = List<VoiceNote>.from(fallback)
        ..sort((a, b) {
          final byCreated = b.createdAt.compareTo(a.createdAt);
          if (byCreated != 0) {
            return byCreated;
          }
          return b.id.compareTo(a.id);
        });
      if (notes.length > requested) {
        notes.removeRange(requested, notes.length);
      }
      return HashtagFeedPageResult(
        notes: notes,
        nextCursor: null,
        hasMore: false,
      );
    }
    final collected = <VoiceNote>[];
    var cursorValue = _HashtagFeedCursor.tryDecode(cursor);
    var hasMore = true;
    var loops = 0;
    while (collected.length < requested && hasMore && loops < 8) {
      final fetchLimit = ((requested - collected.length) + 20)
          .clamp(10, 100)
          .toInt();
      Query<Map<String, dynamic>> query = _firestore
          .collection('voice_notes')
          .where('status', isEqualTo: 'active')
          .where('hashtag_id', isEqualTo: hashtagId)
          .orderBy('created_at', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(fetchLimit);
      if (cursorValue != null) {
        query = query.startAfter(<Object>[
          Timestamp.fromDate(cursorValue.createdAtUtc),
          cursorValue.noteId,
        ]);
      }
      late final QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await query.get();
      } on FirebaseException catch (error) {
        final isMissingIndex =
            error.code == 'failed-precondition' &&
            (error.message?.toLowerCase().contains('requires an index') ??
                false);
        if (isMissingIndex && cursorValue == null) {
          _legacyHashtagPagedQueryEnabled = false;
          final fallback = await fetchNotes(
            hashtagId: hashtagId,
            limit: requested,
          );
          final notes = List<VoiceNote>.from(fallback)
            ..sort((a, b) {
              final byCreated = b.createdAt.compareTo(a.createdAt);
              if (byCreated != 0) {
                return byCreated;
              }
              return b.id.compareTo(a.id);
            });
          if (notes.length > requested) {
            notes.removeRange(requested, notes.length);
          }
          return HashtagFeedPageResult(
            notes: notes,
            nextCursor: null,
            hasMore: false,
          );
        }
        rethrow;
      }
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }
      for (final doc in snapshot.docs) {
        final note = _noteFromDoc(doc);
        final expiresAtUtc = note.expiresAt?.toUtc();
        final stillActive = expiresAtUtc == null || expiresAtUtc.isAfter(now);
        if (!stillActive) {
          continue;
        }
        collected.add(note);
        if (collected.length >= requested) {
          break;
        }
      }
      final lastDoc = snapshot.docs.last;
      final lastCreatedAt =
          _readTimestamp(lastDoc.data()['created_at'])?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      cursorValue = _HashtagFeedCursor(
        createdAtUtc: lastCreatedAt,
        noteId: lastDoc.id,
      );
      hasMore = snapshot.docs.length >= fetchLimit;
      loops += 1;
    }
    final notes = List<VoiceNote>.from(collected)
      ..sort((a, b) {
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) {
          return byCreated;
        }
        return b.id.compareTo(a.id);
      });
    if (notes.length > requested) {
      notes.removeRange(requested, notes.length);
    }
    final nextCursor = hasMore && cursorValue != null
        ? cursorValue.encode()
        : null;
    return HashtagFeedPageResult(
      notes: notes,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Future<Map<String, VoiceNote>> _fetchClipMetadataByIds({
    required List<String> clipIds,
    required String stationId,
  }) async {
    if (clipIds.isEmpty) {
      return const <String, VoiceNote>{};
    }
    final hydrated = <String, VoiceNote>{};
    for (final chunk in _chunkIds(clipIds, 30)) {
      if (chunk.isEmpty) {
        continue;
      }
      final clipsSnapshot = await _firestore
          .collection('clips')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in clipsSnapshot.docs) {
        final note = _noteFromClipDoc(doc, fallbackStationId: stationId);
        if (note == null) {
          continue;
        }
        hydrated[doc.id] = note;
      }
      final missing = chunk.where((id) => !hydrated.containsKey(id)).toList();
      if (missing.isEmpty) {
        continue;
      }
      final legacySnapshot = await _firestore
          .collection('voice_notes')
          .where(FieldPath.documentId, whereIn: missing)
          .get();
      for (final doc in legacySnapshot.docs) {
        final note = _noteFromClipDoc(doc, fallbackStationId: stationId);
        if (note == null) {
          continue;
        }
        hydrated[doc.id] = note;
      }
    }
    return hydrated;
  }

  Iterable<List<String>> _chunkIds(List<String> ids, int chunkSize) sync* {
    if (chunkSize <= 0) {
      yield ids;
      return;
    }
    for (var start = 0; start < ids.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, ids.length).toInt();
      yield ids.sublist(start, end);
    }
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
    final createdTimestamp = Timestamp.fromDate(createdAt);
    final expiresTimestamp = expiresAt == null
        ? null
        : Timestamp.fromDate(expiresAt.toUtc());
    final noteData = <String, dynamic>{
      'hashtag_id': hashtagId,
      'hashtag_label': hashtagLabel,
      'created_at': createdTimestamp,
      'duration_seconds': durationSeconds,
      'storage_path': storagePath,
      'allow_replies': allowReplies,
      'expires_at': expiresTimestamp,
      'caption': caption,
      'author_id': authorId,
      'status': 'active',
    };
    final clipData = <String, dynamic>{
      'station_id': hashtagId,
      'station_label': hashtagLabel,
      'created_at': createdTimestamp,
      'duration_seconds': durationSeconds,
      'storage_path': storagePath,
      'allow_replies': allowReplies,
      'expires_at': expiresTimestamp,
      'caption': caption,
      'author_id': authorId,
      'status': 'active',
    };
    final feedData = <String, dynamic>{
      'clip_id': id,
      'station_id': hashtagId,
      'created_at': createdTimestamp,
      'duration_seconds': durationSeconds,
      'storage_path': storagePath,
      'allow_replies': allowReplies,
      'expires_at': expiresTimestamp,
      'caption': caption,
      'author_id': authorId,
      'status': 'active',
    };
    final batch = _firestore.batch();
    final voiceNoteRef = _firestore.collection('voice_notes').doc(id);
    final clipRef = _firestore.collection('clips').doc(id);
    final feedRef = _firestore
        .collection('stations')
        .doc(hashtagId)
        .collection('feed')
        .doc(id);
    batch.set(voiceNoteRef, noteData, SetOptions(merge: true));
    batch.set(clipRef, clipData, SetOptions(merge: true));
    batch.set(feedRef, feedData, SetOptions(merge: true));
    try {
      await batch.commit();
    } catch (_) {
      // Backward-compatible fallback while feed-model rules/indexes roll out.
      await voiceNoteRef.set(noteData, SetOptions(merge: true));
    }

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
    final utcDate = _utcDateKey();
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('daily_skip_usage')
        .doc(utcDate);

    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final current = snapshot.data();
      final used = _parseInt(current?['skips_used']);
      if (used >= 3) {
        return {
          'ok': false,
          'skips_left': 0,
          'utc_date': utcDate,
        };
      }
      final next = used + 1;
      transaction.set(
        docRef,
        {
          'skips_used': next,
          'utc_date': utcDate,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return {
        'ok': true,
        'skips_left': 3 - next,
        'utc_date': utcDate,
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
    final normalizedPath = storagePath.trim();
    if (normalizedPath.isEmpty) {
      return '';
    }
    final cdnUrl = _buildCdnUrl(normalizedPath);
    if (cdnUrl != null) {
      return cdnUrl;
    }
    final now = DateTime.now().toUtc();
    final cached = _audioUrlCache[normalizedPath];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.url;
    }
    final ref = _storage.ref(normalizedPath);
    final url = await ref.getDownloadURL();
    _audioUrlCache[normalizedPath] = _CachedAudioUrl(
      url: url,
      expiresAt: now.add(_audioUrlCacheTtl),
    );
    return url;
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

  VoiceNote? _noteFromStationFeedDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String stationId,
  }) {
    final data = doc.data();
    return _noteFromMap(
      id: (data['clip_id'] as String?)?.trim() ?? doc.id,
      data: data,
      fallbackStationId: stationId,
    );
  }

  VoiceNote? _noteFromClipDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String fallbackStationId,
  }) {
    return _noteFromMap(
      id: doc.id,
      data: doc.data(),
      fallbackStationId: fallbackStationId,
    );
  }

  VoiceNote? _noteFromMap({
    required String id,
    required Map<String, dynamic> data,
    required String fallbackStationId,
  }) {
    final resolvedId = id.trim();
    if (resolvedId.isEmpty) {
      return null;
    }
    final status = (data['status'] as String?)?.trim();
    if (status != null && status.isNotEmpty && status != 'active') {
      return null;
    }
    final stationId =
        (data['station_id'] as String?)?.trim() ??
        (data['hashtag_id'] as String?)?.trim() ??
        fallbackStationId;
    final storagePath = (data['storage_path'] as String?)?.trim() ?? '';
    if (stationId.isEmpty || storagePath.isEmpty) {
      return null;
    }
    final createdAt =
        _readTimestamp(data['created_at'])?.toLocal() ?? DateTime.now();
    final expiresAt = _readTimestamp(data['expires_at'])?.toLocal();
    final label =
        (data['station_label'] as String?)?.trim() ??
        (data['hashtag_label'] as String?)?.trim() ??
        (data['hashtag_name'] as String?)?.trim() ??
        '#$stationId';
    return VoiceNote(
      id: resolvedId,
      hashtagId: stationId,
      hashtagLabel: label,
      createdAt: createdAt,
      duration: Duration(seconds: _parseInt(data['duration_seconds'])),
      storagePath: storagePath,
      allowReplies: data['allow_replies'] as bool? ?? false,
      expiresAt: expiresAt,
      authorId: data['author_id'] as String?,
      transcriptPreview: data['caption'] as String?,
    );
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

  String _utcDateKey() {
    final now = DateTime.now().toUtc();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String? _normalizeBaseUrl(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  String? _buildCdnUrl(String storagePath) {
    final base = _storageCdnBaseUrl;
    if (base == null || base.isEmpty) {
      return null;
    }
    final encodedPath = storagePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    if (encodedPath.isEmpty) {
      return null;
    }
    return '$base/$encodedPath';
  }
}
