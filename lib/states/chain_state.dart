import 'package:danawallet/data/models/recommended_fee_model.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/chain.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/services/chain_poller.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

/// Who may write the chain tip (single-producer rule, t_e67b63ae): exactly
/// one active backend session owns tip writes — the blindbit poller while
/// blindbit is the active backend, the frigate session (via the scan-
/// progress tip stream) while a frigate backend is active. There is no
/// fallback that substitutes another backend's value.
enum ChainTipProducer { blindbitPoller, frigateSession }

/// Blindbit chain height (`getChainHeight`). Injected so tests can serve a
/// local stub second backend without the rust library.
typedef ChainHeightFn = Future<int> Function({required String blindbitUrl});

/// Blindbit network check (`checkNetwork`).
typedef NetworkCheckFn = Future<bool> Function({
  required String blindbitUrl,
  required Network network,
});

class ChainState extends ChangeNotifier {
  ChainPoller? _foregroundChainPoller;

  // Indicates whether the chainstate is initialized.
  // Once initialized we can check for the availability.
  // We treat these as two separate states, because we want to allow
  // a case where the app is unable to sync the chain (e.g. when there is no internet).
  Network? _network;

  // indicates whether the chain is 'available'
  String? _blindbitUrl;
  int? _tip;

  /// The active tip producer (single-producer rule, t_e67b63ae). Defaults
  /// to the blindbit poller; the sync wiring re-classifies it from the
  /// backend resolution at startup and every wake cycle.
  ChainTipProducer _tipProducer = ChainTipProducer.blindbitPoller;

  final ChainHeightFn chainHeightFn;
  final NetworkCheckFn networkCheckFn;

  /// Whether the blindbit tip poller timer is currently running.
  @visibleForTesting
  bool get pollerRunning => _foregroundChainPoller?.running ?? false;

  ChainTipProducer get tipProducer => _tipProducer;

  bool get initiated => _network != null && _foregroundChainPoller != null;

  bool get available => initiated && _tip != null;

  ChainState({ChainHeightFn? chainHeightFn, NetworkCheckFn? networkCheckFn})
      : chainHeightFn = chainHeightFn ?? getChainHeight,
        networkCheckFn = networkCheckFn ?? checkNetwork;

  /// THE single tip-write chokepoint (single-producer rule, t_e67b63ae):
  /// every tip value entering this state passes through here, tagged with
  /// the producer it came from. A write from any producer other than the
  /// active one is rejected and logged — a second backend serving a foreign
  /// tip never moves the tip, and there is no fallback that substitutes
  /// another backend's value.
  void _writeTip(int? value, {required ChainTipProducer producer}) {
    if (producer != _tipProducer) {
      Logger().w(
          'Rejected chain tip $value from $producer: active tip producer is $_tipProducer (stored tip: $_tip)');
      return;
    }
    if (_tip == value) return;
    // Tip provenance (debug-level only): every accepted tip-update log
    // line names the backend that produced it.
    Logger().d('Chain tip update: $value from $producer (previous tip: $_tip)');
    _tip = value;
    notifyListeners();
  }

  /// Tip from the active frigate session (the scan-progress tip stream).
  /// The only way a session tip enters the chain state, and it is accepted
  /// only while the frigate session is the active tip producer.
  void applySessionTip(int height) =>
      _writeTip(height, producer: ChainTipProducer.frigateSession);

  /// Re-classifies the active tip producer from the backend resolution
  /// (single-producer rule, t_e67b63ae). Switching to the frigate session
  /// stops the blindbit poller and marks the tip stale until the session
  /// delivers one; switching back re-arms the poller (the caller starts it).
  void setTipProducer(ChainTipProducer producer) {
    if (producer == _tipProducer) return;
    Logger().i('Tip producer switching: $_tipProducer -> $producer');
    _tipProducer = producer;
    if (producer == ChainTipProducer.frigateSession) {
      // The blindbit url poller no longer runs for the tip in this mode.
      stopChainPoller();
      // No session tip yet: the tip goes unknown/stale — no fallback
      // substitutes another backend's value, and scanning pauses until the
      // session speaks.
      _writeTip(null, producer: ChainTipProducer.frigateSession);
    }
    notifyListeners();
  }

  void initialize(Network network) {
    Logger().i('Initializing chain state');
    Logger().i('Network: $network');
    // network is not yet verified in this state, it gets vetified in 'connect'
    _network = network;
    _foregroundChainPoller = ChainPoller(chainState: this);
  }

  void startChainPoller(bool immediate,
      {Future<void> Function()? onTipUpdated,
      bool Function()? shouldSkipTick}) {
    if (_tipProducer == ChainTipProducer.frigateSession) {
      // Single-producer rule: the frigate session owns the tip; the
      // blindbit url poller no longer runs for the tip in that mode.
      Logger()
          .i('Frigate session owns the chain tip; blindbit poller not started');
      return;
    }
    if (_foregroundChainPoller != null) {
      _foregroundChainPoller!.onTipUpdated = onTipUpdated;
      _foregroundChainPoller!.shouldSkipTick = shouldSkipTick;
      _foregroundChainPoller!.start();
      if (immediate) {
        _foregroundChainPoller!.triggerImmediateUpdate();
      }
    } else {
      throw Exception(
          'Attempted to start chain poller, but chain state is not initialized');
    }
  }

  /// Try connecting to blindbit service
  Future<bool> connect(String blindbitUrl) async {
    if (!initiated) {
      return false;
    }

    Logger().i('Connecting to blindbit: $blindbitUrl');
    try {
      final correctNetwork =
          await networkCheckFn(blindbitUrl: blindbitUrl, network: _network!);

      if (correctNetwork) {
        Logger().i('Network correct');
        final tip = await chainHeightFn(blindbitUrl: blindbitUrl);

        Logger().i('Successfully connected to blindbit, current tip: $tip');
        _blindbitUrl = blindbitUrl;
        // Blindbit-sourced tip: the chokepoint rejects it while the frigate
        // session is the active producer (single-producer rule).
        _writeTip(tip, producer: ChainTipProducer.blindbitPoller);
        notifyListeners();
        return true;
      } else {
        Logger().w('Wrong network');
        return false;
      }
    } catch (e) {
      Logger().w('Connection to blindbit failed: $e');
      return false;
    }
  }

  Future<bool> reconnect() async {
    if (_blindbitUrl != null) {
      return await connect(_blindbitUrl!);
    } else {
      Logger().w("Attempted to reconnect, but no blindbit url is known");
      return false;
    }
  }

  void stopChainPoller() {
    _foregroundChainPoller?.stop();
  }

  void reset() {
    _foregroundChainPoller?.stop();
    _foregroundChainPoller = null;
    _tipProducer = ChainTipProducer.blindbitPoller;
    _writeTip(null, producer: ChainTipProducer.blindbitPoller);
    _blindbitUrl = null;
    _network = null;
  }

  int get tip {
    if (available) {
      return _tip!;
    } else {
      throw Exception('Attempted to get chain tip, but chain is unavailable');
    }
  }

  Network get network {
    if (initiated) {
      return _network!;
    } else {
      throw Exception('Attempted to get current network without initializing');
    }
  }

  Future<bool> updateChainTip() async {
    if (!available) {
      Logger().w('Cannot update chain tip: chain state not available');
      return false;
    }

    try {
      final height = await chainHeightFn(blindbitUrl: _blindbitUrl!);
      _writeTip(height, producer: ChainTipProducer.blindbitPoller);
      Logger().i('updating tip: $_tip from ${ChainTipProducer.blindbitPoller}');
      notifyListeners();
      return true;
    } catch (e) {
      Logger().e('Failed to update chain tip: $e');
      // Blindbit-sourced staleness: rejected while the frigate session is
      // the active producer — a blindbit failure must never stale the
      // session's tip.
      _writeTip(null, producer: ChainTipProducer.blindbitPoller);
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetBlindbitUrl() async {
    Logger().i('Resetting blindbit url');
    _blindbitUrl = network.defaultBlindbitUrl;
    return await reconnect();
  }

  Future<bool> updateBlindbitUrl(String newUrl) async {
    Logger().i('Updating blindbit url');
    Logger().i('Old blindbit url: $_blindbitUrl');
    Logger().i('New blindbit url: $newUrl');
    return await connect(newUrl);
  }

  Future<RecommendedFeeResponse> getCurrentFeeRates() async {
    if (network == Network.regtest) {
      // for regtest, we always return 1 sat/vb
      return RecommendedFeeResponse(
          nextBlockFee: 1, halfHourFee: 1, hourFee: 1, dayFee: 1);
    } else {
      final mempoolApiRepository = MempoolApiRepository(network: network);
      final response = await mempoolApiRepository.getCurrentFeeRate();
      return response;
    }
  }

  Future<int> getBlockHeightFromDate(DateTime date) async {
    final mempoolApiRepository = MempoolApiRepository(network: network);
    final block =
        await mempoolApiRepository.getBlockFromTimestamp(date.toSeconds());
    return block.height;
  }
}
