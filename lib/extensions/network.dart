import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:flutter/services.dart';

extension NetworkExtension on Network {
  String get defaultBlindbitUrl {
    switch (this) {
      case Network.mainnet:
        if (isDevEnv && const String.fromEnvironment("MAINNET_URL") != "") {
          return const String.fromEnvironment("MAINNET_URL");
        } else {
          return defaultMainnet;
        }
      case Network.testnet3:
      case Network.testnet4:
        if (isDevEnv && const String.fromEnvironment("TESTNET_URL") != "") {
          return const String.fromEnvironment("TESTNET_URL");
        } else {
          return defaultTestnet;
        }
      case Network.signet:
        if (isDevEnv && const String.fromEnvironment("SIGNET_URL") != "") {
          return const String.fromEnvironment("SIGNET_URL");
        } else {
          return defaultSignet;
        }
      case Network.regtest:
        if (isDevEnv && const String.fromEnvironment("REGTEST_URL") != "") {
          return const String.fromEnvironment("REGTEST_URL");
        } else {
          return defaultRegtest;
        }
    }
  }

  /// Returns null for regtest, which has no public block explorer.
  String? get defaultBlockExplorerUrl {
    switch (this) {
      case Network.mainnet:
        return defaultBlockExplorerMainnet;
      case Network.testnet3:
      case Network.testnet4:
        return defaultBlockExplorerTestnet;
      case Network.signet:
        return defaultBlockExplorerSignet;
      case Network.regtest:
        return null;
    }
  }

  Color get toColor {
    switch (this) {
      case Network.mainnet:
        return Bitcoin.orange;
      case Network.testnet3:
      case Network.testnet4:
        return Bitcoin.green;
      case Network.signet:
        return Bitcoin.purple;
      case Network.regtest:
        return Bitcoin.blue;
    }
  }
}
