import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:flutter/material.dart';

/// User-facing display and personalisation choices (fiat currency, amount
/// unit, and eventually locale).
class DisplayPreferencesState extends ChangeNotifier {
  late FiatCurrency fiatCurrency;
  late AmountDisplayUnit amountDisplayUnit;

  DisplayPreferencesState._();

  static Future<DisplayPreferencesState> create() async {
    final instance = DisplayPreferencesState._();
    final settings = SettingsRepository.instance;
    instance.fiatCurrency = await settings.getFiatCurrency() ?? defaultCurrency;
    instance.amountDisplayUnit =
        await settings.getAmountDisplayUnit() ?? defaultAmountDisplayUnit;
    return instance;
  }

  Future<void> updateFiatCurrency(FiatCurrency currency) async {
    await SettingsRepository.instance.setFiatCurrency(currency);
    fiatCurrency = currency;
    notifyListeners();
  }

  Future<void> updateAmountDisplayUnit(AmountDisplayUnit unit) async {
    await SettingsRepository.instance.setAmountDisplayUnit(unit);
    amountDisplayUnit = unit;
    notifyListeners();
  }
}
