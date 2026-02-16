import 'package:danawallet/generated/rust/api/backup.dart';
import 'package:danawallet/models/fiat_currency.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyBlindbitUrl = "blindbiturl";
const String _keyDustLimit = "dustlimit";
const String _keyFiatCurrency = "fiatcurrency";

class SettingsRepository {
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();

  // private constructor
  SettingsRepository._();

  // singleton instance
  static final instance = SettingsRepository._();

  Future<void> resetAll() async {
    await prefs
        .clear(allowList: {_keyBlindbitUrl, _keyDustLimit, _keyFiatCurrency});
  }

  Future<void> setBlindbitUrl(String? url) async {
    if (url != null) {
      return await prefs.setString(_keyBlindbitUrl, url);
    } else {
      return await prefs.remove(_keyBlindbitUrl);
    }
  }

  Future<String?> getBlindbitUrl() async {
    return await prefs.getString(_keyBlindbitUrl);
  }

  Future<void> setDustLimit(int? value) async {
    if (value != null) {
      return await prefs.setInt(_keyDustLimit, value);
    } else {
      return await prefs.remove(_keyDustLimit);
    }
  }

  Future<int?> getDustLimit() async {
    return await prefs.getInt(_keyDustLimit);
  }

  Future<void> setFiatCurrency(FiatCurrency? currency) async {
    if (currency != null) {
      return await prefs.setString(_keyFiatCurrency, currency.name);
    } else {
      return await prefs.remove(_keyFiatCurrency);
    }
  }

  Future<FiatCurrency?> getFiatCurrency() async {
    final currency = await prefs.getString(_keyFiatCurrency);

    return currency != null ? FiatCurrency.values.byName(currency) : null;
  }

  Future<SettingsBackup> createSettingsBackup() async {
    final blindbitUrl = await getBlindbitUrl();
    final dustLimit = await getDustLimit();

    return SettingsBackup(blindbitUrl: blindbitUrl, dustLimit: dustLimit);
  }

  Future<void> restoreSettingsBackup(SettingsBackup backup) async {
    await resetAll();
    if (backup.blindbitUrl != null) {
      await setBlindbitUrl(backup.blindbitUrl!);
    }
    if (backup.dustLimit != null) {
      await setDustLimit(backup.dustLimit!);
    }
  }
}
