import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

/// TICKET 3 (t_bea7f1b9): tip provenance logging.
///
/// Every tip value entering the chain state through the single tip-write
/// chokepoint (_writeTip, t_e67b63ae) — and every rejection — must be
/// greppable to its source backend:
/// - accepted updates log the producing backend (debug level, no UI);
/// - rejections log the source backend AND both heights (offered vs stored).
/// The stub second backend is the injected chainHeightFn (local, no
/// network; the public blindbit instance never appears here).
void main() {
  final memoryOutput = MemoryOutput();

  setUp(() {
    // The production code logs through default-constructed Loggers, so the
    // logger's static defaults are redirected at the output seam for each
    // test: every Logger() call lands in this capture buffer.
    Logger.defaultOutput = () => memoryOutput;
    Logger.defaultPrinter = () => SimplePrinter(colors: false);
  });

  tearDown(() {
    Logger.defaultOutput = () => ConsoleOutput();
    Logger.defaultPrinter = () => PrettyPrinter();
    memoryOutput.buffer.clear();
  });

  List<String> lines() =>
      memoryOutput.buffer.expand((event) => event.lines).toList();

  String lineWith(String needle) =>
      lines().firstWhere((line) => line.contains(needle),
          orElse: () => '<no log line matching "$needle">');

  // Local stub second backend: whatever url it is asked about, it serves
  // the foreign tip 523.
  ChainState stubChain({int stubTip = 523}) => ChainState(
        chainHeightFn: ({required blindbitUrl}) async => stubTip,
        networkCheckFn: ({required blindbitUrl, required network}) async =>
            true,
      );

  group('accepted tip updates name the producing backend', () {
    test('frigate session tip: debug line names frigateSession', () {
      final chain = stubChain()..initialize(Network.regtest);
      chain.setTipProducer(ChainTipProducer.frigateSession);
      memoryOutput.buffer.clear();

      chain.applySessionTip(522);

      final line = lineWith('Chain tip update');
      expect(line, contains('522'));
      expect(line, contains('frigateSession'));
      // Debug-level only: the provenance line must not escalate.
      final event = memoryOutput.buffer.firstWhere(
          (e) => e.lines.any((l) => l.contains('Chain tip update')));
      expect(event.level, Level.debug);
    });

    test('blindbit poller tip: debug line names blindbitPoller', () async {
      final chain = stubChain()..initialize(Network.regtest);
      memoryOutput.buffer.clear();

      await chain.connect('http://stub-blindbit.invalid');

      final line = lineWith('Chain tip update');
      expect(line, contains('523'));
      expect(line, contains('blindbitPoller'));
    });
  });

  group('rejected tips log source backend and both heights', () {
    test('foreign tip with a stored tip: offered vs stored logged', () async {
      final chain = stubChain()..initialize(Network.regtest);
      chain.setTipProducer(ChainTipProducer.frigateSession);
      chain.applySessionTip(522);
      memoryOutput.buffer.clear();

      await chain.connect('http://stub-blindbit.invalid');

      final line = lineWith('Rejected chain tip');
      expect(line, contains('blindbitPoller')); // source backend
      expect(line, contains('523')); // offered height
      expect(line, contains('522')); // stored height
    });

    test('foreign tip before any stored tip: stored height logged as null', () {
      final chain = stubChain()..initialize(Network.regtest);
      memoryOutput.buffer.clear();

      // The frigate session offers a tip while the blindbit poller is
      // still the active producer, and nothing is stored yet.
      chain.applySessionTip(522);

      final line = lineWith('Rejected chain tip');
      expect(line, contains('frigateSession')); // source backend
      expect(line, contains('522')); // offered height
      expect(line, contains('null')); // nothing stored yet
    });
  });
}
