import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/data/models/mempool_prices_response.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FiatExchangeRateState.withRateForTesting', () {
    test('rejects zero rate', () {
      expect(
        () => FiatExchangeRateState.withRateForTesting(
          rates: {FiatCurrency.usd: 0},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('FiatExchangeRateState.timeSinceLastExchangeRateUpdate', () {
    test('returns null when never updated', () {
      final state = FiatExchangeRateState();
      expect(state.timeSinceLastExchangeRateUpdate, isNull);
    });

    test('returns elapsed duration since last update', () {
      final lastUpdated =
          DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 50000},
        lastExchangeRateUpdateAt: lastUpdated,
      );

      final elapsed = state.timeSinceLastExchangeRateUpdate;
      expect(elapsed, isNotNull);
      expect(elapsed!, greaterThanOrEqualTo(const Duration(minutes: 5)));
      expect(elapsed, lessThan(const Duration(minutes: 6)));
    });
  });

  group('FiatExchangeRateState.updateExchangeRates', () {
    test('keeps last known-good cache on refresh failure', () async {
      final lastUpdated = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 50000},
        lastExchangeRateUpdateAt: lastUpdated,
      );
      state.repository = _ThrowingMempoolApiRepository();

      await state.updateExchangeRates();

      expect(state.exchangeRateFor(FiatCurrency.usd), 50000);
      expect(state.lastExchangeRateUpdateAt, lastUpdated);
    });

    test('skips refresh when last update was less than a minute ago', () async {
      final repository = _CountingMempoolApiRepository();
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 50000},
        lastExchangeRateUpdateAt:
            DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
      );
      state.repository = repository;

      await state.updateExchangeRates();

      expect(repository.callCount, 0);
      expect(state.exchangeRateFor(FiatCurrency.usd), 50000);
      expect(state.isUpdating, isFalse);
    });
  });
}

class _CountingMempoolApiRepository extends MempoolApiRepository {
  int callCount = 0;

  @override
  Future<MempoolPricesResponse> getExchangeRate() async {
    callCount++;
    return const MempoolPricesResponse(
      timestamp: 0,
      usd: 50000,
      eur: 45000,
      gbp: 40000,
      cad: 65000,
      chf: 45000,
      aud: 75000,
      jpy: 7000000,
    );
  }
}

class _ThrowingMempoolApiRepository extends MempoolApiRepository {
  @override
  Future<MempoolPricesResponse> getExchangeRate() async {
    throw Exception('network down');
  }
}
