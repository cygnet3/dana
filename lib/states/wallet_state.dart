import 'dart:async';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/owned_output.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/unsigned_transaction.dart';
import 'package:danawallet/data/models/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/transactions_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/services/dana_address_service.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class WalletState extends ChangeNotifier {
  final walletRepository = WalletRepository.instance;
  final ownedOutputsRepository = OwnedOutputsRepository.instance;
  final transactionsRepository = TransactionsRepository.instance;

  // variables that never change (unless wallet is reset)
  late Network network;
  late String receivePaymentCode;
  late String changePaymentCode;
  DateTime? birthday; // birthday may not be known

  // variables that change
  late Amount amount;
  late Amount unconfirmedChange;
  late int? lastSync;

  // Cached data from SQLite (updated via _updateWalletState)
  late List<OwnedOutput> unspentOutputs;
  late List<OutPoint> outpointsToScan;
  late List<RecordedTransaction> transactions;

  // this variable may change in some exceptional cases
  Bip353Address? danaAddress;

  bool _initialized = false;

  Future<bool> initialize() async {
    _initialized = false;

    // we check if wallet data is present in database
    final wallet = await walletRepository.readWallet();

    // if not present, we have no wallet and return false
    if (wallet == null) {
      return false;
    }

    // since the wallet data is present, the following items must also be present
    network = await walletRepository.readNetwork();
    birthday = await _getBirthday();
    danaAddress = await walletRepository.readDanaAddress();

    // we calculate these based on our wallet data (scan key, spend key, network)
    receivePaymentCode = wallet.getReceivingAddress();
    changePaymentCode = wallet.getChangeAddress();

    await _updateWalletState();

    // All late fields are now populated; stream events can be processed safely.
    _initialized = true;

    return true;
  }

  Future<void> refreshAfterSync({bool lastSyncOnly = false}) async {
    if (!_initialized) return;
    await _updateWalletState(lastSyncOnly: lastSyncOnly);
    notifyListeners();
  }

  Future<void> reset() async {
    _initialized = false;
    danaAddress = null;
    await transactionsRepository.reset();
    // this is redudant, but we do it to be sure
    await ownedOutputsRepository.reset();
    await walletRepository.reset();
  }

  Future<void> restoreWallet(
      Network network, String mnemonic, DateTime? birthday) async {
    _initialized = false;
    final args = WalletSetupArgs(
        setupType: WalletSetupType.mnemonic(mnemonic), network: network);
    final setupResult = SpWallet.setupWallet(setupArgs: args);
    final wallet = await walletRepository.setupWallet(
        setupResult, network, birthday, null);

    // fill current state variables
    receivePaymentCode = wallet.getReceivingAddress();
    changePaymentCode = wallet.getChangeAddress();
    this.birthday = birthday;
    this.network = network;

    // lastSync will be initialized by chainState synchronization service
    lastSync = null;

    await _updateWalletState();
    _initialized = true;
  }

  Future<void> createNewWallet(Network network, int? currentTip) async {
    _initialized = false;
    final now = DateTime.now().toUtc();

    final args = WalletSetupArgs(
        setupType: const WalletSetupType.newWallet(), network: network);
    final setupResult = SpWallet.setupWallet(setupArgs: args);
    final wallet = await walletRepository.setupWallet(
        setupResult, network, now, currentTip);

    // fill current state variables
    receivePaymentCode = wallet.getReceivingAddress();
    changePaymentCode = wallet.getChangeAddress();
    birthday = now;
    this.network = network;
    lastSync = currentTip;

    await _updateWalletState();
    _initialized = true;
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

  Future<DateTime?> _getBirthday() async {
    final storedBirthday = await walletRepository.readBirthday();
    if (storedBirthday == null) {
      // birthday is unknown (not provided during wallet recovery)
      return null;
    }

    if (storedBirthday.isAfter(minimumAllowedBirthday)) {
      // This is a timestamp, we can use it directly
      return storedBirthday;
    } else {
      // if the birthday is older than the minimum allowed birthday,
      // this value must be from an earlier version where we stored the birthday as a block height.
      // to fix this, we convert the stored birthday back to an integer,
      // and fetch the date from that block
      final blockHeight = storedBirthday.toSeconds();
      try {
        final mempoolApi = MempoolApiRepository(network: network);
        final block = await mempoolApi.getBlockForHash(
            await mempoolApi.getBlockHashForHeight(blockHeight));
        final newBirthday = block.timestamp.toDate();
        Logger().i("Resolved block height $blockHeight to date $newBirthday");
        // store converted birthday in persistent storage before returning
        await walletRepository.saveBirthday(newBirthday);
        return newBirthday;
      } catch (e) {
        Logger()
            .w("Error resolving block height $blockHeight to timestamp: $e");
        return null;
      }
    }
  }

  Future<void> resetToBirthday() async {
    await transactionsRepository.reset();

    // owned outputs should be deleted automatically, but we do it explicitly to be sure
    await ownedOutputsRepository.reset();

    // the sync service will handle setting the lastSync to the birthday height
    await walletRepository.saveLastSync(null);

    await _updateWalletState();
    notifyListeners();
  }

  Future<void> resetToSyncHeight(int height) async {
    await transactionsRepository.deleteTransactionsAboveHeight(height);
    // note: owned outputs are deleted automatically when their corresponding transactions are dropped

    await walletRepository.saveLastSync(height);

    await _updateWalletState();
    notifyListeners();
  }

  Future<void> _updateWalletState({bool lastSyncOnly = false}) async {
    lastSync = await walletRepository.readLastSync();

    if (lastSyncOnly) {
      return;
    }

    // Get cached data from SQLite
    amount = await ownedOutputsRepository.getUnspentBalance();

    // fetch the unconfirmed change from the transaction history
    // in the future, we probably want to save change outputs in owned_outputs before they are confirmed
    // in that case, we can get the unconfirmed change from the owned outputs repository,
    // but for now we have to look at the transaction recipients
    unconfirmedChange = await transactionsRepository.getUnconfirmedChange(
        receivePaymentCode, changePaymentCode);

    // Cache outputs for spending and scanning
    unspentOutputs = await ownedOutputsRepository.getUnspentOutputs();
    final unspentOutpoints = await ownedOutputsRepository.getUnspentOutpoints();
    final unconfirmedSpentOutpoints =
        await transactionsRepository.getUnconfirmedSpentOutpoints();
    outpointsToScan = [...unspentOutpoints, ...unconfirmedSpentOutpoints];

    // Cache transactions for UI
    transactions = await transactionsRepository.getAllTransactions(
        receivePaymentCode, changePaymentCode);
  }

  Future<void> saveNote(int transactionId, String note) async {
    await transactionsRepository.saveNote(transactionId, note);
    await _updateWalletState();
    notifyListeners();
  }

  Future<SilentPaymentUnsignedTransaction> createUnsignedTxToThisRecipient(
      Recipient recipient, int feerate) async {
    final wallet = await getWalletFromSecureStorage();

    if (recipient.amount.field0 < amount.field0 - BigInt.from(546)) {
      return wallet.createNewTransaction(
          ownedOutputs: unspentOutputs,
          apiRecipients: [
            recipient,
          ],
          feerate: feerate.toDouble(),
          network: network);
    } else {
      return wallet.createDrainTransaction(
          ownedOutputs: unspentOutputs,
          wipeAddress: recipient.paymentCode,
          feerate: feerate.toDouble(),
          network: network);
    }
  }

  Future<String> signAndBroadcastUnsignedTx(
      SilentPaymentUnsignedTransaction unsignedTx) async {
    final selectedOutputs = unsignedTx.selectedUtxos;

    List<OutPoint> selectedOutpoints =
        selectedOutputs.map((tuple) => tuple.$1).toList();

    final recipients = unsignedTx.recipients;

    final finalizedTx =
        SpWallet.finalizeTransaction(unsignedTransaction: unsignedTx);

    final wallet = await getWalletFromSecureStorage();

    final signedTx = wallet.signTransaction(unsignedTransaction: finalizedTx);

    Logger().d("signed tx: $signedTx");

    String txid;
    try {
      switch (network) {
        case Network.mainnet:
          txid = await SpWallet.broadcastTx(tx: signedTx, network: network);
          break;
        case Network.signet:
          txid = await MempoolApiRepository(network: network)
              .postTransaction(signedTx);
          break;
        case Network.regtest:
          final blindbitUrl =
              await SettingsRepository.instance.getBlindbitUrl() ??
                  Network.regtest.defaultBlindbitUrl;
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

    await transactionsRepository.addOutgoingTransaction(
      txid: txid,
      spentOutpoints: selectedOutpoints,
      recipients: recipients,
    );

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
    if (network == Network.regtest) {
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
