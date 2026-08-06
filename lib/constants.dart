import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:flutter/services.dart';

// The default blindbit backend used
const String defaultMainnet = "https://silentpayments.dev/blindbit/mainnet";
const String defaultTestnet = "https://silentpayments.dev/blindbit/testnet";
const String defaultSignet = "https://silentpayments.dev/blindbit/signet";
const String defaultRegtest = "https://silentpayments.dev/blindbit/regtest";

// The default block explorer base URL per network (null for regtest)
const String defaultBlockExplorerMainnet = "https://mempool.space";
const String defaultBlockExplorerTestnet = "https://mempool.space/testnet";
const String defaultBlockExplorerSignet = "https://mempool.space/signet";

// Default birthday, this value is based on the first Dana release
final DateTime defaultBirthday = DateTime.utc(2025, 6, 1);

// minimum birthday allowed during recovery. This value is set to the moment BIP352 got merged,
// see: https://github.com/bitcoin/bips/pull/1458
final DateTime minimumAllowedBirthday = DateTime.utc(2024, 5, 8);

// default dust limit. this is used in syncing, as well as sending
// for syncing, amounts < dust limit will be ignored
// for sending, the user needs to send a minimum of >= dust
const int defaultDustLimit = 600;

// default fiat currency
const FiatCurrency defaultCurrency = FiatCurrency.usd;

// Exchange rate older than this is considered stale in the spend flow.
const Duration staleExchangeRateThreshold = Duration(hours: 1);

// colors
const Color danaBlue = Color.fromARGB(255, 10, 109, 214);

// number of decimals in 1 btc
const int bitcoinUnits = 8;
// String that displays when amount is hidden
const String hideAmountFormat = "*****";

// the in-production name server, only used on live flavors with mainnet
const String nameServerLive = "https://nameserver.danawallet.app/v1";
// name server for other flavors that use mainnet
const String nameServerDevMainnet =
    "https://main.dev.nameserver.danawallet.app/v1";
// name server for other flavors that user testnet/signet
const String nameServerDevTestnet =
    "https://test.dev.nameserver.danawallet.app/v1";

// Message keys sent to the main isolate from the foreground sync service.
const String bgKeyStartHeight = 'startHeight';
const String bgKeyEndHeight = 'endHeight';
const String bgKeyComplete = 'complete';
const String bgKeyRefresh = 'refresh';
const String bgKeyInterrupt = 'interrupt';
const String bgKeyFatalError = 'fatalError';

// Message keys sent to the background sync service from the main isolate.
const String bgKeySync = 'sync';

// Enforce english convention for amounts inputs
const String decimalSeparator = '.';
const String groupSeparator = ',';

// Amount display symbols
// ₿ is U+20BF, a standard Unicode character — no custom font needed
const String btcSymbol = '₿';
// Satoshi symbol glyphs live in the SatoshiSymbol font (Private Use Area)
// U+E007 = satoshisymbol-solid, U+E000 = satoshisymbol-outline
const String satSymbol = '\uE007';
const String satSymbolOutline = '\uE000';
const String satFontFamily = 'SatoshiSymbol';

const AmountDisplayUnit defaultAmountDisplayUnit = AmountDisplayUnit.btc;
