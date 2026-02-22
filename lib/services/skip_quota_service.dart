import 'package:shared_preferences/shared_preferences.dart';

import 'autoplay_data_source.dart';
import 'firebase_repository.dart';

/// Manages the user's daily skip quota, backed by a remote endpoint with a
/// local SharedPreferences cache for offline fallback.
class SkipQuotaService {
  SkipQuotaService({
    required SharedPreferences prefs,
    required FirebaseRepository repository,
    required String? Function() userId,
    required bool Function() isDevUnauthed,
  })  : _prefs = prefs,
        _repository = repository,
        _userId = userId,
        _isDevUnauthed = isDevUnauthed;

  static const _skipQuotaDateKey = 'skip_quota_date';
  static const _skipQuotaRemainingKey = 'skip_quota_remaining';

  final SharedPreferences _prefs;
  final FirebaseRepository _repository;
  final String? Function() _userId;
  final bool Function() _isDevUnauthed;

  Future<SkipQuotaResult> consumeSkip() async {
    if (_isDevUnauthed()) {
      return _consumeSkipLocal(scope: 'dev');
    }
    final currentUser = _userId();
    if (currentUser == null) {
      return _consumeSkipLocal(scope: 'anon');
    }
    try {
      final response = await _repository.consumeSkip(userId: currentUser);
      final ok = response['ok'] == true;
      final skipsLeft = _parseInt(response['skips_left']);
      final date = response['utc_date']?.toString() ?? _utcDateKey();
      _writeSkipCache(scope: currentUser, date: date, remaining: skipsLeft);
      return SkipQuotaResult(
        allowed: ok,
        skipsLeft: skipsLeft,
        message: ok ? null : 'No skips left today.',
      );
    } catch (_) {
      return _consumeSkipFromCache(scope: currentUser);
    }
  }

  SkipQuotaResult _consumeSkipLocal({required String scope}) {
    final today = _utcDateKey();
    final cached = _readSkipCache(scope: scope);
    final remaining =
        cached != null && cached.date == today ? cached.remaining : 3;
    if (remaining <= 0) {
      _writeSkipCache(scope: scope, date: today, remaining: 0);
      return const SkipQuotaResult(
        allowed: false,
        skipsLeft: 0,
        message: 'No skips left today.',
      );
    }
    final nextRemaining = remaining - 1;
    _writeSkipCache(scope: scope, date: today, remaining: nextRemaining);
    return SkipQuotaResult(allowed: true, skipsLeft: nextRemaining);
  }

  SkipQuotaResult _consumeSkipFromCache({required String scope}) {
    final cached = _readSkipCache(scope: scope);
    if (cached == null) {
      return const SkipQuotaResult(
        allowed: false,
        skipsLeft: 0,
        message: 'Skip unavailable offline. Reconnect to refresh your quota.',
      );
    }
    final today = _utcDateKey();
    if (cached.date != today) {
      return SkipQuotaResult(
        allowed: false,
        skipsLeft: cached.remaining,
        message: 'Skip unavailable offline. Reconnect to refresh your quota.',
      );
    }
    if (cached.remaining <= 0) {
      return const SkipQuotaResult(
        allowed: false,
        skipsLeft: 0,
        message: 'No skips left today.',
      );
    }
    final nextRemaining = cached.remaining - 1;
    _writeSkipCache(scope: scope, date: cached.date, remaining: nextRemaining);
    return SkipQuotaResult(allowed: true, skipsLeft: nextRemaining);
  }

  void _writeSkipCache({
    required String scope,
    required String date,
    required int remaining,
  }) {
    _prefs.setString(_skipCacheKey(scope, _skipQuotaDateKey), date);
    _prefs.setInt(_skipCacheKey(scope, _skipQuotaRemainingKey), remaining);
  }

  _SkipQuotaCache? _readSkipCache({required String scope}) {
    final date = _prefs.getString(_skipCacheKey(scope, _skipQuotaDateKey));
    final remaining =
        _prefs.getInt(_skipCacheKey(scope, _skipQuotaRemainingKey));
    if (date == null || remaining == null) return null;
    return _SkipQuotaCache(date: date, remaining: remaining);
  }

  String _skipCacheKey(String scope, String key) => '$key:$scope';

  String _utcDateKey() {
    final now = DateTime.now().toUtc();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class _SkipQuotaCache {
  const _SkipQuotaCache({required this.date, required this.remaining});

  final String date;
  final int remaining;
}
