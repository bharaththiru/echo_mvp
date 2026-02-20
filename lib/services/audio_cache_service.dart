import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/voice_note.dart';
import 'firebase_repository.dart';

/// Resolves a [VoiceNote] to a playable local path (or remote URL fallback),
/// managing an in-memory path cache and an on-disk LRU audio cache.
class AudioCacheService {
  AudioCacheService._({
    required FirebaseRepository repository,
    required String cacheDirectory,
  })  : _repository = repository,
        _cacheDirectory = cacheDirectory;

  /// Creates a real instance by preparing the on-disk cache directory.
  static Future<AudioCacheService> create({
    required FirebaseRepository repository,
  }) async {
    final dir = await _prepareDirectory();
    return AudioCacheService._(repository: repository, cacheDirectory: dir);
  }

  /// Creates a test instance with an explicit [cacheDirectory] path.
  static AudioCacheService forTest({
    required FirebaseRepository repository,
    required String cacheDirectory,
  }) =>
      AudioCacheService._(
        repository: repository,
        cacheDirectory: cacheDirectory,
      );

  static const _maxEntries = 300;

  final FirebaseRepository _repository;
  final String _cacheDirectory;
  final Map<String, String> _pathCache = {};

  /// Returns a local file path or remote URL suitable for playback.
  Future<String?> ensureLocalAudioPath(VoiceNote note) async {
    if (note.localPath != null && await File(note.localPath!).exists()) {
      await _touchCachedFile(File(note.localPath!));
      return note.localPath;
    }
    final cachedPath = _pathCache[note.id];
    if (cachedPath != null && cachedPath.isNotEmpty) {
      if (_isRemotePath(cachedPath)) {
        return cachedPath;
      }
      final cachedFile = File(cachedPath);
      if (await cachedFile.exists()) {
        final size = await cachedFile.length();
        if (size > 0) {
          await _touchCachedFile(cachedFile);
          return cachedPath;
        }
      }
      _pathCache.remove(note.id);
    }
    if (note.storagePath.isEmpty) {
      return note.localPath;
    }
    final diskPath = await _ensureAudioDownloadedToDisk(note);
    if (diskPath != null && diskPath.isNotEmpty) {
      _pathCache[note.id] = diskPath;
      return diskPath;
    }
    try {
      final url = await _repository.fetchAudioUrl(note.storagePath);
      _pathCache[note.id] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Prunes the on-disk cache to [_maxEntries] by deleting the oldest files.
  Future<void> prune() async {
    final dir = Directory(_cacheDirectory);
    if (!await dir.exists()) return;
    final entities = await dir.list(followLinks: false).toList();
    final files = <_CachedDiskFile>[];
    for (final entity in entities) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        files.add(_CachedDiskFile(file: entity, modified: stat.modified));
      } catch (_) {
        // Skip files that cannot be inspected.
      }
    }
    if (files.length <= _maxEntries) return;
    files.sort((a, b) => a.modified.compareTo(b.modified));
    final toDelete = files.length - _maxEntries;
    for (var i = 0; i < toDelete; i++) {
      final path = files[i].file.path;
      try {
        await files[i].file.delete();
      } catch (_) {
        // Skip files that cannot be deleted.
      }
      _pathCache.removeWhere((_, value) => value == path);
    }
  }

  bool _isRemotePath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  String _cachePathForStorage(String storagePath) {
    final digest = sha1.convert(utf8.encode(storagePath)).toString();
    final ext = _extensionForStoragePath(storagePath);
    return '$_cacheDirectory${Platform.pathSeparator}$digest$ext';
  }

  String _extensionForStoragePath(String storagePath) {
    final dot = storagePath.lastIndexOf('.');
    if (dot < 0 || dot >= storagePath.length - 1) return '.m4a';
    final ext = storagePath.substring(dot);
    if (ext.length > 8 || ext.contains('/') || ext.contains('\\')) return '.m4a';
    return ext;
  }

  Future<String?> _ensureAudioDownloadedToDisk(VoiceNote note) async {
    if (note.storagePath.isEmpty) return null;
    final cachePath = _cachePathForStorage(note.storagePath);
    final file = File(cachePath);
    if (await file.exists()) {
      try {
        final size = await file.length();
        if (size > 0) {
          await _touchCachedFile(file);
          return file.path;
        }
        await file.delete();
      } catch (_) {
        // Attempt fresh download when cached file is invalid.
      }
    }
    try {
      final bytes = await _repository.downloadAudio(note.storagePath);
      if (bytes.isEmpty) return null;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await _touchCachedFile(file);
      _pathCache[note.id] = file.path;
      unawaited(prune());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _touchCachedFile(File file) async {
    try {
      await file.setLastModified(DateTime.now().toUtc());
    } catch (_) {
      // Ignore file timestamp updates.
    }
  }

  static Future<String> _prepareDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final cache = Directory('${directory.path}/audio_cache');
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    return cache.path;
  }
}

class _CachedDiskFile {
  const _CachedDiskFile({required this.file, required this.modified});

  final File file;
  final DateTime modified;
}
