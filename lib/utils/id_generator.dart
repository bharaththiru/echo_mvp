import 'dart:math';

class IdGenerator {
  IdGenerator() : _random = Random();

  final Random _random;

  String next() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entropy = _random.nextInt(1 << 32);
    return '$now-$entropy';
  }
}
