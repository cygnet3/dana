import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

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

  int get defaultBirthday {
    switch (this) {
      case Network.mainnet:
        return defaultMainnetBirthday;
      case Network.testnet3:
      case Network.testnet4:
        return defaultTestnetBirthday;
      case Network.signet:
        return defaultSignetBirthday;
      case Network.regtest:
        return defaultRegtestBirthday;
    }
  }
}

Network get getNetworkForFlavor {
  switch (appFlavor) {
    // only live flavor uses mainnet
    case 'live':
      return Network.mainnet;
    // all other flavors use signet by default
    case 'signet':
    case 'dev':
    case 'local':
      return Network.signet;
    default:
      Logger().w("Unknown Flavor; defaulting to signet");
      return Network.signet;
  }
}
