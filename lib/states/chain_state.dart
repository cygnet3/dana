import 'package:danawallet/data/models/recommended_fee_model.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/chain.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/services/synchronization_service.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class ChainState extends ChangeNotifier {
  late SynchronizationService _synchronizationService;

  // Indicates whether the chainstate is initialized.
  // Once initialized we can check for the availability.
  // We treat these as two separate states, because we want to allow
  // a case where the app is unable to sync the chain (e.g. when there is no internet).
  Network? _network;

  // indicates whether the chain is 'available'
  String? _blindbitUrl;
  int? _tip;

  bool get initiated => _network != null;

  bool get available => initiated && _blindbitUrl != null && _tip != null;

  ChainState();

  void initialize(Network network) {
    Logger().i('Initializing chain state');
    Logger().i('Network: $network');
    // network is not yet verified in this state, it gets vetified in 'connect'
    _network = network;
  }

  void startSyncService(WalletState walletState,
      ScanProgressNotifier scanProgress, bool immediate) {
    // start sync service & timer
    _synchronizationService = SynchronizationService(
        chainState: this, walletState: walletState, scanProgress: scanProgress);
    _synchronizationService.startSyncTimer(immediate);
  }

  /// Try connecting to blindbit service
  Future<bool> connect(String blindbitUrl) async {
    if (!initiated) {
      return false;
    }

    Logger().i('Connecting to blindbit: $blindbitUrl');
    try {
      final correctNetwork =
          await checkNetwork(blindbitUrl: blindbitUrl, network: _network!);

      if (correctNetwork) {
        Logger().i('Network correct');
        final tip = await getChainHeight(blindbitUrl: blindbitUrl);

        Logger().i('Successfully connected to blindbit, current tip: $tip');
        _blindbitUrl = blindbitUrl;
        _tip = tip;
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

  void reset() {
    _synchronizationService.stopSyncTimer();
    _tip = null;
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
      _tip = await getChainHeight(blindbitUrl: _blindbitUrl!);
      Logger().i('updating tip: $_tip');
      notifyListeners();
      return true;
    } catch (e) {
      Logger().e('Failed to update chain tip: $e');
      _tip = null;
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
}
