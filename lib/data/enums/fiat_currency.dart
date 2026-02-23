enum FiatCurrency {
  eur,
  usd,
  gbp,
  cad,
  chf,
  aud,
  jpy;

  String symbol() {
    switch (this) {
      case FiatCurrency.eur:
        return '€';
      case FiatCurrency.usd:
        return r'$';
      case FiatCurrency.gbp:
        return '£';
      case FiatCurrency.cad:
        return r'$';
      case FiatCurrency.chf:
        return 'Fr.';
      case FiatCurrency.aud:
        return 'AU\$';
      case FiatCurrency.jpy:
        return '¥';
    }
  }

  String displayName() {
    switch (this) {
      case FiatCurrency.eur:
        return 'Euro';
      case FiatCurrency.usd:
        return 'US Dollar';
      case FiatCurrency.gbp:
        return 'Pound Sterling';
      case FiatCurrency.cad:
        return 'Canadian Dollar';
      case FiatCurrency.chf:
        return 'Swiss Franc';
      case FiatCurrency.aud:
        return 'Australian Dollar';
      case FiatCurrency.jpy:
        return 'Japanese Yen';
    }
  }

  int minorUnits() {
    switch (this) {
      case FiatCurrency.jpy:
        return 0;
      case FiatCurrency.eur:
      case FiatCurrency.usd:
      case FiatCurrency.gbp:
      case FiatCurrency.cad:
      case FiatCurrency.chf:
      case FiatCurrency.aud:
        return 2;
    }
  }
}

