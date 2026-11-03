import 'dart:async';
import 'dart:math';

/// Coalesces reads only. Writes never enter this gate and are never replayed.
class ReadBudget {
  final Map<String, Future<dynamic>> pending = {};
  final Map<String, DateTime> until = {};
  final Map<String, int> failures = {};
  final DateTime Function() now;
  ReadBudget({DateTime Function()? clock}) : now = clock ?? DateTime.now;
  Duration remaining(String key) {
    final value = until[key]?.difference(now()) ?? Duration.zero;
    return value.isNegative ? Duration.zero : value;
  }

  void failed(String key, {Duration? retryAfter}) {
    final n = min(6, (failures[key] ?? 0) + 1);
    failures[key] = n;
    until[key] = now().add(
      retryAfter ??
          Duration(
            milliseconds: min(60000, 1000 * (1 << n)) + Random().nextInt(500),
          ),
    );
  }

  Future<dynamic> run(String key, Future<dynamic> Function() read) {
    if (pending.containsKey(key)) return pending[key]!;
    final future = Future<dynamic>.sync(read)
        .then((value) {
          failures.remove(key);
          until.remove(key);
          return value;
        })
        .whenComplete(() {
          pending.remove(key);
        });
    pending[key] = future;
    return future;
  }
}
