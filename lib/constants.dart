import 'package:danawallet/data/enums/fiat_currency.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
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

// colors
const Color danaBlue = Color.fromARGB(255, 10, 109, 214);

// example address, used in onboarding flow
const String exampleAddress =
    "sp1qq0cygnetgn3rz2kla5cp05nj5uetlsrzez0l4p8g7wehf7ldr93lcqadw65upymwzvp5ed38l8ur2rznd6934xh95msevwrdwtrpk372hyz4vr6g";

// example mnemonic
const String exampleMnemonic =
    "gloom police month stamp viable claim hospital heart alcohol off ocean ghost";

// number of satoshis in 1 btc
const int bitcoinUnits = 100000000;
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

// if the change is below this amount, suggest we donate
final Amount donateBelow = Amount(field0: BigInt.from(5000));
// signet faucet address
const String donatePaymentCode =
    "tsp1qqtp5ql6htn4jz4feslzspyel2n3dzmr5fxjrc69yge2w72hnh2jzzqh6g9zjzkwzzv3m79y84dwusw3sdw2akyzvxm8l2x4gagzxjlrvf5njz0j6";
