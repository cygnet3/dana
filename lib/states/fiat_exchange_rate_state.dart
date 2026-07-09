import 'dart:math';

import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/mempool_prices_response.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class FiatExchangeRateState extends ChangeNotifier {
  static const _minRefreshInterval = Duration(minutes: 1);

  MempoolApiRepository repository = MempoolApiRepository();

  Map<FiatCurrency, int> _cachedRates = const {};
  DateTime? _lastExchangeRateUpdateAt;
  bool _isUpdating = false;

  FiatExchangeRateState();

  /// Visible for tests only.
  static FiatExchangeRateState withRateForTesting({
    required Map<FiatCurrency, int> rates,
    DateTime? lastExchangeRateUpdateAt,
  }) {
    for (final entry in rates.entries) {
      if (entry.value <= 0) {
        throw ArgumentError.value(
          entry.value,
          'rates[${entry.key.name}]',
          'must be a positive number',
        );
      }
    }
    final instance = FiatExchangeRateState();
    instance._cachedRates = Map<FiatCurrency, int>.from(rates);
    instance._lastExchangeRateUpdateAt = lastExchangeRateUpdateAt;
    return instance;
  }

  Map<FiatCurrency, int> get exchangeRates => Map.unmodifiable(_cachedRates);
  int? exchangeRateFor(FiatCurrency currency) => _cachedRates[currency];
  DateTime? get lastExchangeRateUpdateAt => _lastExchangeRateUpdateAt;

  /// Elapsed time since the last successful rate update, or `null` if never updated.
  Duration? get timeSinceLastExchangeRateUpdate {
    final lastUpdate = _lastExchangeRateUpdateAt;
    if (lastUpdate == null) return null;
    return DateTime.now().toUtc().difference(lastUpdate);
  }

  bool get isUpdating => _isUpdating;

  Future<void> updateExchangeRates() async {
    if (_isUpdating) return;

    final lastUpdate = _lastExchangeRateUpdateAt;
    if (lastUpdate != null &&
        DateTime.now().toUtc().difference(lastUpdate) < _minRefreshInterval) {
      return;
    }

    _isUpdating = true;
    notifyListeners();

    try {
      Logger().i('Updating exchange rates for all currencies');
      _cachedRates = await _fetchExchangeRates();
      _lastExchangeRateUpdateAt = DateTime.now().toUtc();
    } catch (e) {
      Logger().e('Failed to update exchange rate: $e');
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
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
        BigInt.from(pow(10, bitcoinUnits));
  }

  /// Converts [amount] to fiat minor units (e.g. cents for USD) using the
  /// cached rate. Uses integer floor division, symmetric with [fiatToSat].
  BigInt satsAmountToFiat(Amount amount, FiatCurrency currency) {
    final rate = exchangeRateFor(currency);
    if (rate == null) throw StateError('Exchange rate not available');
    return _satsToFiatMinor(amount, rate, currency);
  }

  /// Converts fiat minor units to satoshis using the cached rate.
  /// Rounds down so the send amount never exceeds the entered fiat value.
  Amount fiatToSat(BigInt fiatAmount, FiatCurrency currency) {
    if (fiatAmount == BigInt.zero) {
      return Amount(field0: BigInt.zero);
    } else if (fiatAmount.isNegative) {
      throw ArgumentError.value(fiatAmount, 'fiatAmount', 'must be positive');
    }

    final rate = exchangeRateFor(currency);
    if (rate == null) {
      throw StateError('Exchange rate not available');
    }

    final scale = pow(10, currency.minorUnits()).toInt();
    final sats = fiatAmount *
        BigInt.from(pow(10, bitcoinUnits)) ~/
        (BigInt.from(rate) * BigInt.from(scale));
    return Amount(field0: sats);
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
