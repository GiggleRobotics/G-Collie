import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/read_budget.dart';

void main() {
  test('simultaneous reads coalesce, success clears budget', () async {
    final gate = ReadBudget();
    final done = Completer<int>();
    var calls = 0;
    Future<int> read() {
      calls++;
      return done.future;
    }

    final a = gate.run('x', read), b = gate.run('x', read);
    expect(calls, 1);
    done.complete(7);
    expect(await a, 7);
    expect(await b, 7);
    expect(gate.pending, isEmpty);
  });
  test('Retry-After and exponential budget do not replay requests', () {
    var time = DateTime.utc(2026);
    final gate = ReadBudget(clock: () => time);
    gate.failed('x', retryAfter: const Duration(seconds: 20));
    expect(gate.remaining('x').inSeconds, 20);
    time = time.add(const Duration(seconds: 21));
    expect(gate.remaining('x'), Duration.zero);
    gate.failed('x');
    expect(gate.remaining('x').inMilliseconds, greaterThanOrEqualTo(4000));
  });
}
