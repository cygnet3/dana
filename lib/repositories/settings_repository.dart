import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyBlindbitUrl = "blindbiturl";
const String _keyFrigateUrl = "frigateurl";

/// Declared visibility of the current frigate URL ("public" | "private"),
/// D5. Unset defaults to private.
const String _keyFrigateVisibility = "frigateurlvisibility";

/// Explicit sync backend selection ("blindbit" | "frigate"), D9.
/// Unset defaults to blindbit.
const String _keyFrigateBackend = "frigatebackend";
const String _keyDustLimit = "dustlimit";
const String _keyFiatCurrency = "fiatcurrency";
const String _keyBlockExplorerUrl = "blockexplorerurl";
const String _keyAmountDisplayUnit = "amountdisplayunit";

/// Backend values for the D9 selector.
const String frigateBackendBlindbit = "blindbit";
const String frigateBackendFrigate = "frigate";

/// Visibility values for the D5 picker.
const String frigateVisibilityPublic = "public";
const String frigateVisibilityPrivate = "private";

/// Storage surface [SyncEngine] reads from [SettingsRepository]; lets tests
/// substitute an in-memory store.
abstract class SettingsStore {
  Future<String?> getBlindbitUrl();
  Future<String?> getFrigateUrl();
  Future<String?> getFrigateBackend();
  Future<String?> getFrigateVisibility();
  Future<int?> getDustLimit();
}

class SettingsRepository implements SettingsStore {
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();

  // private constructor
  SettingsRepository._();

  // singleton instance
  static final instance = SettingsRepository._();

  Future<void> resetAll() async {
    await prefs.clear(allowList: {
      _keyBlindbitUrl,
      _keyFrigateUrl,
      _keyFrigateVisibility,
      _keyFrigateBackend,
      _keyDustLimit,
      _keyFiatCurrency,
      _keyBlockExplorerUrl,
      _keyAmountDisplayUnit,
    });
  }

  Future<void> setBlindbitUrl(String? url) async {
    if (url != null) {
      return await prefs.setString(_keyBlindbitUrl, url);
    } else {
      return await prefs.remove(_keyBlindbitUrl);
    }
  }

  @override
  Future<String?> getBlindbitUrl() async {
    return await prefs.getString(_keyBlindbitUrl);
  }

  /// Frigate scanner URL for the optional frigate sync backend.
  /// Unset or empty means the feature is off and blindbit is used.
  Future<void> setFrigateUrl(String? url) async {
    if (url != null) {
      return await prefs.setString(_keyFrigateUrl, url);
    } else {
      return await prefs.remove(_keyFrigateUrl);
    }
  }

  @override
  Future<String?> getFrigateUrl() async {
    return await prefs.getString(_keyFrigateUrl);
  }

  /// Declared visibility of the current frigate URL (D5). Unset defaults
  /// to private.
  Future<void> setFrigateVisibility(String? visibility) async {
    if (visibility != null) {
      return await prefs.setString(_keyFrigateVisibility, visibility);
    } else {
      return await prefs.remove(_keyFrigateVisibility);
    }
  }

  @override
  Future<String?> getFrigateVisibility() async {
    return await prefs.getString(_keyFrigateVisibility);
  }

  /// Explicit backend selection (D9). Unset defaults to blindbit.
  Future<void> setFrigateBackend(String? backend) async {
    if (backend != null) {
      return await prefs.setString(_keyFrigateBackend, backend);
    } else {
      return await prefs.remove(_keyFrigateBackend);
    }
  }

  @override
  Future<String?> getFrigateBackend() async {
    return await prefs.getString(_keyFrigateBackend);
  }

  Future<void> setBlockExplorerUrl(String? url) async {
    if (url != null) {
      return await prefs.setString(_keyBlockExplorerUrl, url);
    } else {
      return await prefs.remove(_keyBlockExplorerUrl);
    }
  }

  Future<String?> getBlockExplorerUrl() async {
    return await prefs.getString(_keyBlockExplorerUrl);
  }

  Future<void> setDustLimit(int? value) async {
    if (value != null) {
      return await prefs.setInt(_keyDustLimit, value);
    } else {
      return await prefs.remove(_keyDustLimit);
    }
  }

  @override
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

  Future<void> setAmountDisplayUnit(AmountDisplayUnit? unit) async {
    if (unit != null) {
      return await prefs.setString(_keyAmountDisplayUnit, unit.name);
    } else {
      return await prefs.remove(_keyAmountDisplayUnit);
    }
  }

  Future<AmountDisplayUnit?> getAmountDisplayUnit() async {
    final unit = await prefs.getString(_keyAmountDisplayUnit);

    return unit != null ? AmountDisplayUnit.values.byName(unit) : null;
  }
}
