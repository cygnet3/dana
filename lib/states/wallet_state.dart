import 'dart:async';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/recipient_form_filled.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/history.dart';
import 'package:danawallet/generated/rust/api/outputs.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/unsigned_transaction.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/services/dana_address_service.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class WalletState extends ChangeNotifier {
  final walletRepository = WalletRepository.instance;

  // variables that never change (unless wallet is reset)
  late ApiNetwork network;
  late String receivePaymentCode;
  late String changePaymentCode;
  DateTime? birthday;

  // variables that change
  late ApiAmount amount;
  late ApiAmount unconfirmedChange;
  late int lastScan;
  late TxHistory txHistory;
  late OwnedOutputs ownedOutputs;

  // this variable may change in some exceptional cases
  Bip353Address? danaAddress;

  // stream to receive updates while scanning
  late StreamSubscription scanResultSubscription;

  // private constructor
  WalletState._();

  static Future<WalletState> create() async {
    final instance = WalletState._();
    await instance._initStreams();
    return instance;
  }

  Future<void> _initStreams() async {
    scanResultSubscription = createScanResultStream().listen(((event) async {
      // process update
      lastScan = event.getHeight();
      txHistory.processStateUpdate(update: event, ownedOutputs: ownedOutputs);
      ownedOutputs.processStateUpdate(update: event);

      // save updates to storage
      await walletRepository.saveHistory(txHistory);
      await walletRepository.saveOwnedOutputs(ownedOutputs);
      await walletRepository.saveLastScan(lastScan);

      // update UI
      await _updateWalletState();
      notifyListeners();
    }));
  }

  Future<bool> initialize() async {
    // we check if wallet data is present in database
    final wallet = await walletRepository.readWallet();

    // if not present, we have no wallet and return false
    if (wallet == null) {
      return false;
    }

    // since the wallet data is present, the following items must also be present
    network = await walletRepository.readNetwork();
    await setBirthday();
    danaAddress = await walletRepository.readDanaAddress();

    // we calculate these based on our wallet data (scan key, spend key, network)
    receivePaymentCode = wallet.getReceivingAddress();
    changePaymentCode = wallet.getChangeAddress();

    await _updateWalletState();

    return true;
  }

  @override
  void dispose() {
    scanResultSubscription.cancel();
    super.dispose();
  }

  Future<void> reset() async {
    danaAddress = null;
    await walletRepository.reset();
  }

  Future<void> restoreWallet(ApiNetwork network, String mnemonic, DateTime birthday) async {
    final args = WalletSetupArgs(
        setupType: WalletSetupType.mnemonic(mnemonic), network: network);
    final setupResult = SpWallet.setupWallet(setupArgs: args);
    final wallet =
        await walletRepository.setupWallet(setupResult, network, birthday);

    // fill current state variables
    receivePaymentCode = wallet.getReceivingAddress();
    changePaymentCode = wallet.getChangeAddress();
    this.birthday = birthday;
    this.network = network;
    await _updateWalletState();
  }

  Future<void> createNewWallet(ApiNetwork network) async {
    final now = DateTime.now().toUtc();

    final args = WalletSetupArgs(
        setupType: const WalletSetupType.newWallet(), network: network);
    final setupResult = SpWallet.setupWallet(setupArgs: args);
    final wallet =
        await walletRepository.setupWallet(setupResult, network, now);

    // fill current state variables
    receivePaymentCode = wallet.getReceivingAddress();
    changePaymentCode = wallet.getChangeAddress();
    birthday = now;
    this.network = network;
    await _updateWalletState();
  }

  Future<SpWallet> getWalletFromSecureStorage() async {
    final wallet = await walletRepository.readWallet();
    if (wallet != null) {
      return wallet;
    } else {
      throw Exception("No wallet in storage");
    }
  }

  Future<String?> getSeedPhraseFromSecureStorage() async {
    return await walletRepository.readSeedPhrase();
  }

  // Older wallets may have birthday as a block height, we apply the same check than core
  Future<void> setBirthday() async {
    final storedBirthday = await walletRepository.readBirthday();
    if (storedBirthday.isAfter(defaultBirthday)) {
      // This is a timestamp, we can use it directly
      birthday = storedBirthday;
    } else {
      // This is a block height, we need to convert it to a timestamp
      // That unfortunately requires a network call that may fail
      try {
        final mempoolApi = MempoolApiRepository(network: network);
        final block = await mempoolApi.getBlockForHash(await mempoolApi.getBlockHashForHeight(storedBirthday.toSeconds()));
        final newBirthday = block.timestamp.toDate();
        Logger().i("Resolved block height $storedBirthday to date $newBirthday");
        // Update the birthday value to an epoch time
        await walletRepository.saveBirthday(newBirthday);
        birthday = newBirthday;
      } catch (e) {
        Logger().e("Error resolving block height $storedBirthday to timestamp: $e");
        birthday = null;
      }
    }

  }

  Future<void> resetToScanHeight(int height) async {
    lastScan = height;

    ownedOutputs.resetToHeight(height: height);
    txHistory.resetToHeight(height: height);

    await walletRepository.saveLastScan(height);
    await walletRepository.saveHistory(txHistory);
    await walletRepository.saveOwnedOutputs(ownedOutputs);

    await _updateWalletState();
    notifyListeners();
  }

  Future<void> _updateWalletState() async {
    txHistory = await walletRepository.readHistory();
    ownedOutputs = await walletRepository.readOwnedOutputs();
    lastScan = await walletRepository.readLastScan();

    amount = ownedOutputs.getUnspentAmount();
    unconfirmedChange = txHistory.getUnconfirmedChange();
  }

  Future<ApiSilentPaymentUnsignedTransaction> createUnsignedTxToThisRecipient(
      RecipientFormFilled form) async {
    final wallet = await getWalletFromSecureStorage();

    final unspentOutputs = ownedOutputs.getUnspentOutputs();
    if (form.amount.field0 < amount.field0 - BigInt.from(546)) {
      return wallet.createNewTransaction(
          apiOutputs: unspentOutputs,
          apiRecipients: [
            ApiRecipient(
                address: form.recipient.paymentCode, amount: form.amount)
          ],
          feerate: form.feerate.toDouble(),
          network: network);
    } else {
      return wallet.createDrainTransaction(
          apiOutputs: unspentOutputs,
          wipeAddress: form.recipient.paymentCode,
          feerate: form.feerate.toDouble(),
          network: network);
    }
  }

  Future<String> signAndBroadcastUnsignedTx(
      ApiSilentPaymentUnsignedTransaction unsignedTx) async {
    final selectedOutputs = unsignedTx.selectedUtxos;

    List<String> selectedOutpoints =
        selectedOutputs.map((tuple) => tuple.$1).toList();

    final changeValue =
        unsignedTx.getChangeAmount(changeAddress: changePaymentCode);

    final feeAmount = unsignedTx.getFeeAmount();

    final recipients =
        unsignedTx.getRecipients(changeAddress: changePaymentCode);

    final finalizedTx =
        SpWallet.finalizeTransaction(unsignedTransaction: unsignedTx);

    final wallet = await getWalletFromSecureStorage();

    final signedTx = wallet.signTransaction(unsignedTransaction: finalizedTx);

    Logger().d("signed tx: $signedTx");

    String txid;
    try {
      switch (network) {
        case ApiNetwork.mainnet:
          txid = await SpWallet.broadcastTx(tx: signedTx, network: network);
          break;
        case ApiNetwork.signet:
          txid = await MempoolApiRepository(network: network)
              .postTransaction(signedTx);
          break;
        case ApiNetwork.regtest:
          final blindbitUrl =
              await SettingsRepository.instance.getBlindbitUrl() ??
                  ApiNetwork.regtest.defaultBlindbitUrl;
          txid = await SpWallet.broadcastUsingBlindbit(
              blindbitUrl: blindbitUrl, tx: signedTx);
          break;
        default:
          throw Exception("Unsupported network");
      }
    } catch (e) {
      Logger().e('Failed to broadcast transaction: $e');
      throw Exception(
          'Unable to broadcast transaction. Please check your connection and try again.');
    }

    ownedOutputs.markOutpointsSpent(spentBy: txid, spent: selectedOutpoints);

    txHistory.addOutgoingTxToHistory(
        txid: txid,
        spentOutpoints: selectedOutpoints,
        recipients: recipients,
        change: changeValue,
        fee: feeAmount);

    // save the updated wallet
    await walletRepository.saveOwnedOutputs(ownedOutputs);
    await walletRepository.saveHistory(txHistory);

    // refresh variables and notify listeners
    await _updateWalletState();
    notifyListeners();

    return txid;
  }

  Future<String?> createSuggestedUsername() async {
    // Generate an available dana address (without registering yet)
    return await DanaAddressService(network: network)
        .generateAvailableDanaAddress(
      paymentCode: receivePaymentCode,
      maxRetries: 5,
    );
  }

  Future<void> registerDanaAddress(String username) async {
    if (danaAddress != null) {
      throw Exception("Dana address already known");
    }

    Logger().i('Registering dana address with username: $username');
    final registeredAddress = await DanaAddressService(network: network)
        .registerUser(username: username, paymentCode: receivePaymentCode);

    // Registration successful
    Logger().i('Registration successful: $registeredAddress');

    // store registed address
    danaAddress = registeredAddress;

    // Persist the dana address to storage
    await walletRepository.saveDanaAddress(registeredAddress);
  }

  // Return value indicates whether the caller should be directed to the dana registration screen
  Future<bool> checkDanaAddressRegistrationNeeded() async {
    // regtest networks have no dana address support
    if (network == ApiNetwork.regtest) {
      danaAddress = null;
      return false;
    }

    // load dana address from storage
    danaAddress = await walletRepository.readDanaAddress();

    // if a stored dana address was present, verify if it's still valid
    if (danaAddress != null) {
      try {
        final verified = await Bip353Resolver.verifyPaymentCode(
            danaAddress!, receivePaymentCode, network);

        if (verified) {
          // we have a stored address and it's valid, no need to register
          Logger().i("Stored dana address is valid");
          return false;
        } else {
          Logger()
              .w("Dana address is not pointing to our sp address, removing");
          danaAddress = null;
          // note: because we haven't found a valid address in memory, we don't return here
        }
      } catch (e) {
        // If we encounter an error while verifying the address,
        // we probably don't have a working internet connection.
        // We just assume the stored address is valid for now.
        Logger().w("Received an error while verifying dana address: $e");
        return false;
      }
    }

    // no address present in storage, this may indicate we need to register a new address
    // but first, we check if the name server already has an address for us
    Logger().i("Attempting to look up dana address");
    try {
      final lookupResult = await DanaAddressService(network: network)
          .lookupDanaAddress(receivePaymentCode);
      if (lookupResult != null) {
        Logger().i("Found dana address: $lookupResult");
        danaAddress = lookupResult;
        await walletRepository.saveDanaAddress(lookupResult);
        return false;
      } else {
        Logger().i("Did not find dana address");
        return true;
      }
    } catch (e) {
      // If we encounter an error while looking up the dana address,
      // either we don't have a working internet connection,
      // or the DNS record changed and the name server is unaware.
      // For now, we assume that the stored address is valid.
      Logger().w("Received error while looking up dana address: $e");
      return false;
    }
  }
}
