import 'dart:math';

import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class FiatExchangeRateState extends ChangeNotifier {
  MempoolApiRepository repository = MempoolApiRepository();

  late FiatCurrency currency;
  int? _cachedRate;

  // private constructor, create class using static async 'create' instead
  FiatExchangeRateState._();

  static Future<FiatExchangeRateState> create() async {
    final instance = FiatExchangeRateState._();
    final currency =
        await SettingsRepository.instance.getFiatCurrency() ?? defaultCurrency;
    instance.currency = currency;

    return instance;
  }

  int? get exchangeRate => _cachedRate;

  Future<void> updateCurrency(FiatCurrency currency) async {
    await SettingsRepository.instance.setFiatCurrency(currency);
    this.currency = currency;

    // Reset exchange rate when currency changes
    _cachedRate = null;
    notifyListeners();

    // Try to fetch fresh data for new currency
    return await updateExchangeRate();
  }

  Future<void> updateExchangeRate() async {
    try {
      Logger().i("Updating exchange rate: ${currency.displayName()}");
      final rate = await _fetchExchangeRate(currency);
      _cachedRate = rate;
    } catch (e) {
      Logger().w('Failed to update exchange rate: $e');
      _cachedRate = null;
    }
    notifyListeners();
  }

  Future<int> _fetchExchangeRate(FiatCurrency currency) async {
    final rates = await repository.getExchangeRate();

    switch (currency) {
      case FiatCurrency.eur:
        return rates.eur;
      case FiatCurrency.usd:
        return rates.usd;
      case FiatCurrency.gbp:
        return rates.gbp;
      case FiatCurrency.cad:
        return rates.cad;
      case FiatCurrency.chf:
        return rates.chf;
      case FiatCurrency.aud:
        return rates.aud;
      case FiatCurrency.jpy:
        return rates.jpy;
    }
  }

  BigInt _satsToFiatMinor(Amount amount, int rate) {
    final scale = pow(10, currency.minorUnits()).toInt();
    return amount.field0 *
        BigInt.from(rate) *
        BigInt.from(scale) ~/
        BigInt.from(bitcoinUnits);
  }

  String displayFiat(Amount amount) {
    final symbol = currency.symbol();
    final minorUnits = currency.minorUnits();
    final rate = _cachedRate;
    if (rate == null) {
      return '$symbol ---';
    }

    final minor = _satsToFiatMinor(amount, rate);
    if (minorUnits == 0) {
      return '$symbol $minor';
    }
    final scale = BigInt.from(pow(10, minorUnits));
    final whole = minor ~/ scale;
    final fraction = (minor % scale).toString().padLeft(minorUnits, '0');
    return '$symbol $whole.$fraction';
  }
}
