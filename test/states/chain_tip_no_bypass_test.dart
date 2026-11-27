import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TICKET 1 (t_e67b63ae) no-bypass check: exactly one writer of the chain
/// tip exists in the code. The `_tip` field of ChainState is private, and
/// every write to it must live inside the single chokepoint `_writeTip` in
/// lib/states/chain_state.dart — any other assignment site in lib/ (outside
/// the generated bridge code, which cannot reach a private field of another
/// library) is a bypass.
void main() {
  test('no-bypass: the chain tip is written at exactly one site (the chokepoint)',
      () {
    final offenders = <String>[];
    var writeSites = 0;

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()) {
      final normalized = file.path.replaceAll('\\', '/');
      if (!normalized.endsWith('.dart') || normalized.startsWith('lib/generated/')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'_tip\s*=[^=]').hasMatch(lines[i])) {
          if (normalized == 'lib/states/chain_state.dart') {
            writeSites++;
          } else {
            offenders.add('$normalized:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'chain tip written outside lib/states/chain_state.dart');
    expect(writeSites, 1,
        reason: 'the tip must be written only inside the single _writeTip '
            'chokepoint in lib/states/chain_state.dart');
  });
}
