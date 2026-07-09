import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/data/models/mempool_prices_response.dart';
import 'package:danawallet/extensions/api_amount.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/states/fiat_exchange_rate_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FiatExchangeRateState.satsAmountToFiat', () {
    test('converts sats to fiat minor units', () {
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 100000},
      );

      // 50000 sats at $100,000/BTC = $50.00 = 5000 cents
      final fiat = state.satsAmountToFiat(
          Amount(field0: BigInt.from(50000)), FiatCurrency.usd);

      expect(fiat, BigInt.from(5000));
    });

    test('floors when sats do not divide evenly into fiat minor units', () {
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 97531},
      );

      // 1 sat at $97531/BTC = $0.00097531 → 0 cents (floored)
      final fiat =
          state.satsAmountToFiat(Amount(field0: BigInt.one), FiatCurrency.usd);

      expect(fiat, BigInt.zero);
    });

    test('throws when exchange rate is unavailable', () {
      final state = FiatExchangeRateState();

      expect(
        () => state.satsAmountToFiat(
            Amount(field0: BigInt.from(50000)), FiatCurrency.usd),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FiatExchangeRateState.fiatToSat', () {
    test('converts fiat minor units to sats rounding down', () {
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 50000},
      );

      // $100.00 = 10000 cents
      final amount = state.fiatToSat(BigInt.from(10000), FiatCurrency.usd);

      expect(amount.field0, BigInt.from(200000));
    });

    test('returns zero amount for zero fiat', () {
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 50000},
      );

      final amount = state.fiatToSat(BigInt.zero, FiatCurrency.usd);

      expect(amount.field0, BigInt.zero);
    });

    test('rejects negative fiat amounts', () {
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 50000},
      );

      expect(
        () => state.fiatToSat(BigInt.from(-1), FiatCurrency.usd),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when exchange rate is unavailable', () {
      final state = FiatExchangeRateState();

      expect(
        () => state.fiatToSat(BigInt.from(100), FiatCurrency.usd),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('fiat input to sats flow', () {
    test('converts parsed fiat minor units through fiatToSat', () {
      final state = FiatExchangeRateState.withRateForTesting(
        rates: {FiatCurrency.usd: 50000},
      );
      final fiatMinor = AmountExtension.parseFiatInput(
        '100',
        FiatCurrency.usd.minorUnits(),
      );

      final amount = state.fiatToSat(fiatMinor, FiatCurrency.usd);

      expect(amount.field0, BigInt.from(200000));
    });
  });

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
