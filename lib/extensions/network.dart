import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/global_functions.dart';
import 'package:flutter/services.dart';

extension NetworkExtension on ApiNetwork {
  String get defaultBlindbitUrl {
    switch (this) {
      case ApiNetwork.mainnet:
        if (isDevEnv && const String.fromEnvironment("MAINNET_URL") != "") {
          return const String.fromEnvironment("MAINNET_URL");
        } else {
          return defaultMainnet;
        }
      case ApiNetwork.testnet3:
      case ApiNetwork.testnet4:
        if (isDevEnv && const String.fromEnvironment("TESTNET_URL") != "") {
          return const String.fromEnvironment("TESTNET_URL");
        } else {
          return defaultTestnet;
        }
      case ApiNetwork.signet:
        if (isDevEnv && const String.fromEnvironment("SIGNET_URL") != "") {
          return const String.fromEnvironment("SIGNET_URL");
        } else {
          return defaultSignet;
        }
      case ApiNetwork.regtest:
        if (isDevEnv && const String.fromEnvironment("REGTEST_URL") != "") {
          return const String.fromEnvironment("REGTEST_URL");
        } else {
          return defaultRegtest;
        }
    }
  }

  Color get toColor {
    switch (this) {
      case ApiNetwork.mainnet:
        return Bitcoin.orange;
      case ApiNetwork.testnet3:
      case ApiNetwork.testnet4:
        return Bitcoin.green;
      case ApiNetwork.signet:
        return Bitcoin.purple;
      case ApiNetwork.regtest:
        return Bitcoin.blue;
    }
  }

  int get defaultBirthday {
    switch (this) {
      case ApiNetwork.mainnet:
        return defaultMainnetBirthday;
      case ApiNetwork.testnet3:
      case ApiNetwork.testnet4:
        return defaultTestnetBirthday;
      case ApiNetwork.signet:
        return defaultSignetBirthday;
      case ApiNetwork.regtest:
        return defaultRegtestBirthday;
    }
  }
}
