import 'dart:math';

import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/mempool_prices_response.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class FiatExchangeRateState extends ChangeNotifier {
  MempoolApiRepository repository = MempoolApiRepository();

  Map<FiatCurrency, int> _cachedRates = const {};

  FiatExchangeRateState._();

  static Future<FiatExchangeRateState> create() async {
    return FiatExchangeRateState._();
  }

  Map<FiatCurrency, int> get exchangeRates => Map.unmodifiable(_cachedRates);
  int? exchangeRateFor(FiatCurrency currency) => _cachedRates[currency];

  Future<void> updateExchangeRate() async {
    try {
      Logger().i('Updating exchange rates for all currencies');
      _cachedRates = await _fetchExchangeRates();
    } catch (e) {
      Logger().w('Failed to update exchange rate: $e');
    }
    notifyListeners();
  }

  Future<Map<FiatCurrency, int>> _fetchExchangeRates() async {
    final rates = await repository.getExchangeRate();
    final mappedRates = _mapRatesByCurrency(rates);
    for (final entry in mappedRates.entries) {
      if (entry.value <= 0) {
        throw Exception('invalid rate for ${entry.key.name}: ${entry.value}');
      }
    }
    return mappedRates;
  }

  Map<FiatCurrency, int> _mapRatesByCurrency(MempoolPricesResponse rates) {
    return {
      FiatCurrency.usd: rates.usd,
      FiatCurrency.eur: rates.eur,
      FiatCurrency.gbp: rates.gbp,
      FiatCurrency.cad: rates.cad,
      FiatCurrency.chf: rates.chf,
      FiatCurrency.aud: rates.aud,
      FiatCurrency.jpy: rates.jpy,
    };
  }

  BigInt _satsToFiatMinor(Amount amount, int rate, FiatCurrency currency) {
    final scale = pow(10, currency.minorUnits()).toInt();
    return amount.field0 *
        BigInt.from(rate) *
        BigInt.from(scale) ~/
        BigInt.from(bitcoinUnits);
  }

  String displayFiat(Amount amount, FiatCurrency currency) {
    final rate = exchangeRateFor(currency);
    if (rate == null) return '${currency.symbol()} ---';

    final minor = _satsToFiatMinor(amount, rate, currency);
    final minorUnits = currency.minorUnits();
    if (minorUnits == 0) {
      return '${currency.symbol()} $minor';
    }
    final scale = BigInt.from(pow(10, minorUnits));
    final whole = minor ~/ scale;
    final fraction = (minor % scale).toString().padLeft(minorUnits, '0');
    return '${currency.symbol()} $whole.$fraction';
  }
}
