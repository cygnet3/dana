import 'package:danawallet/models/fiat_currency.dart';
import 'package:flutter/services.dart';

// The default blindbit backend used
const String defaultMainnet = "https://silentpayments.dev/blindbit/mainnet";
const String defaultTestnet = "https://silentpayments.dev/blindbit/testnet";
const String defaultSignet = "https://silentpayments.dev/blindbit/signet";
const String defaultRegtest = "https://silentpayments.dev/blindbit/regtest";

// Default birthdays used in case we can't get the block height from blindbit
// These values are pretty arbitrary, they can be updated for newer heights later
const int defaultMainnetBirthday = 900000;
const int defaultTestnetBirthday = 2900000;
const int defaultSignetBirthday = 200000;
const int defaultRegtestBirthday = 80000;

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
