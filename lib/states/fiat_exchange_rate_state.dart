import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/fiat_currency.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class FiatExchangeRateState extends ChangeNotifier {
  MempoolApiRepository repository = MempoolApiRepository();

  late FiatCurrency currency;
  double? _cachedRate; // Make nullable to represent "no data available"

  // private constructor, create class using static async 'create' instead
  FiatExchangeRateState._();

  static Future<FiatExchangeRateState> create() async {
    final instance = FiatExchangeRateState._();
    final currency =
        await SettingsRepository.instance.getFiatCurrency() ?? defaultCurrency;
    instance.currency = currency;

    try {
      final rate = await instance._fetchExchangeRate(currency);
      instance._cachedRate = rate;
    } catch (e) {
      Logger().w('Failed to fetch exchange rate: $e');
      instance._cachedRate = null;
    }

    return instance;
  }

  double? get exchangeRate {
    return _cachedRate; // Can be null if no data available
  }

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
      notifyListeners();
    } catch (e) {
      Logger().w('Failed to update exchange rate: $e');
      // Keep current state (which might be null), don't crash
      // UI will show unavailable indicator
    }
  }

  Future<double> _fetchExchangeRate(FiatCurrency currency) async {
    final rates = await repository.getExchangeRate();

    switch (currency) {
      case FiatCurrency.eur:
        return rates.eur.toDouble();
      case FiatCurrency.usd:
        return rates.usd.toDouble();
      case FiatCurrency.gbp:
        return rates.gbp.toDouble();
      case FiatCurrency.cad:
        return rates.cad.toDouble();
      case FiatCurrency.chf:
        return rates.chf.toDouble();
      case FiatCurrency.aud:
        return rates.aud.toDouble();
      case FiatCurrency.jpy:
        return rates.jpy.toDouble();
    }
  }

  String displayFiat(ApiAmount amount) {
    final symbol = currency.symbol();
    final minorUnits = currency.minorUnits();
    if (_cachedRate != null) {
      final btcAmount = amount.field0.toDouble() / bitcoinUnits.toDouble();
      final fiatAmount = btcAmount * _cachedRate!;
      return "$symbol ${fiatAmount.toStringAsFixed(minorUnits)}";
    } else {
      return "$symbol ---";
    }
  }
}
