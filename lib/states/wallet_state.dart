import 'dart:async';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/recipient_form_filled.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/extensions/outpoint.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/outpoint.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/structs/unsigned_transaction.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:danawallet/generated/rust/stream.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/tx_history_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:danawallet/services/bip353_resolver.dart';
import 'package:danawallet/services/dana_address_service.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class WalletState extends ChangeNotifier {
  final walletRepository = WalletRepository.instance;
  final ownedOutputsRepository = OwnedOutputsRepository.instance;
  final txHistoryRepository = TxHistoryRepository.instance;

  // variables that never change (unless wallet is reset)
  late ApiNetwork network;
  late String receivePaymentCode;
  late String changePaymentCode;
  DateTime? birthday; // birthday may not be known

  // variables that change
  late ApiAmount amount;
  late ApiAmount unconfirmedChange;
  late int? lastSync;

  // Cached data from SQLite (updated via _updateWalletState)
  late List<OwnedOutput> unspentOutputs;
  late List<String> outpointsToScan;
  late List<RecordedTransaction> transactions;

  // this variable may change in some exceptional cases
  Bip353Address? danaAddress;

  // stream to receive updates while scanning
  late StreamSubscription syncResultSubscription;

  // private constructor
  WalletState._();

  static Future<WalletState> create() async {
    final instance = WalletState._();
    await instance._initStreams();
    return instance;
  }

  Future<void> _initStreams() async {
    syncResultSubscription = createSyncResultStream().listen(((event) async {
      lastSync = event.blkheight;

      // Process found outputs (new UTXOs we own)
      for (final found in event.foundOutputs) {
        // Insert output into database
        await ownedOutputsRepository.insertOutput(output: found);

        // Check if this is a self-send (skip change outputs)
        final isOwnTx = await txHistoryRepository.isOwnOutgoingTx(found.txid);
        if (!isOwnTx || found.label == null) {
          // Add incoming transaction
          await txHistoryRepository.addIncomingTransaction(
            txid: found.txid,
            amountSat: found.amount,
            confirmationHeight: event.blkheight,
            confirmationBlockhash: event.blkhash,
          );
        }
      }

      // Process found inputs (our UTXOs being spent)
      for (final outpoint in event.foundInputs) {
        // Try to confirm an outgoing transaction
        final confirmed = await txHistoryRepository.confirmOutgoingTransaction(
          spentOutpointTxid: outpoint.txid,
          spentOutpointVout: outpoint.vout,
          confirmationHeight: event.blkheight,
          confirmationBlockhash: event.blkhash,
        );

        // This should never happen, it means user is using the same wallet on multiple devices
        if (!confirmed) {
          try {
            // For unknown outgoing transactions we don't know the spending txid.
            // We store `tx_outgoing.txid = NULL` and link the outpoints via `tx_outgoing.id`.
            final spentAmountSat = await ownedOutputsRepository.getOutputAmount(
              outpoint.txid,
              outpoint.vout,
            );
            await txHistoryRepository.addOutgoingTransaction(
              spentOutpoints: [outpoint],
              recipients: [],
              changeSat: null, // unknown for externally-created spend
              feeSat: null, // unknown for externally-created spend
              txid: null,
              amountSpentSat: spentAmountSat ?? 0,
            );
            final confirmed =
                await txHistoryRepository.confirmOutgoingTransaction(
              spentOutpointTxid: outpoint.txid,
              spentOutpointVout: outpoint.vout,
              confirmationHeight: event.blkheight,
              confirmationBlockhash: event.blkhash,
            );
            if (!confirmed) {
              throw Exception(
                  "Failed to confirm unknown outgoing transaction for ${outpoint.toDisplayString()}");
            }
          } catch (e) {
            Logger().e("Failed to add unknown outgoing transaction: $e");
          }
        }
      }

      await walletRepository.saveLastSync(lastSync!);

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
    birthday = await _getBirthday();
    danaAddress = await walletRepository.readDanaAddress();

    // we calculate these based on our wallet data (scan key, spend key, network)
    receivePaymentCode = wallet.getReceivingAddress();
    changePaymentCode = wallet.getChangeAddress();

    await _updateWalletState();

    return true;
  }

  @override
  void dispose() {
    syncResultSubscription.cancel();
    super.dispose();
  }

  Future<void> reset() async {
    danaAddress = null;
    await ownedOutputsRepository.reset();
    await txHistoryRepository.reset();
    await walletRepository.reset();
  }

  Future<void> restoreWallet(
      ApiNetwork network, String mnemonic, DateTime? birthday) async {
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
  }

  Future<void> createNewWallet(ApiNetwork network, int? currentTip) async {
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
    await ownedOutputsRepository.reset();
    await txHistoryRepository.reset();

    // the sync service will handle setting the lastSync to the birthday height
    await walletRepository.saveLastSync(null);

    await _updateWalletState();
    notifyListeners();
  }

  Future<void> resetToSyncHeight(int height) async {
    // note: this feature is not stable, as it does not take output spent status into account
    await ownedOutputsRepository.reset();
    await txHistoryRepository.reset();

    await walletRepository.resetToHeight(height);

    await _updateWalletState();
    notifyListeners();
  }

  Future<void> _updateWalletState() async {
    lastSync = await walletRepository.readLastSync();

    // Get cached data from SQLite
    amount = await ownedOutputsRepository.getUnspentBalance();

    unconfirmedChange = await txHistoryRepository.getUnconfirmedChange();

    // Cache outputs for spending and scanning
    unspentOutputs = await ownedOutputsRepository.getUnspentOutputs();
    final unspentOutpoints = await ownedOutputsRepository.getUnspentOutpoints();
    final unconfirmedSpentOutpoints =
        await txHistoryRepository.getUnconfirmedSpentOutpoints();
    outpointsToScan = [...unspentOutpoints, ...unconfirmedSpentOutpoints];

    // Cache transactions for UI
    transactions = await txHistoryRepository.getAllTransactions();
  }

  Future<ApiSilentPaymentUnsignedTransaction> createUnsignedTxToThisRecipient(
      RecipientFormFilled form) async {
    final wallet = await getWalletFromSecureStorage();

    if (form.amount.field0 < amount.field0 - BigInt.from(546)) {
      return wallet.createNewTransaction(
          ownedOutputs: unspentOutputs,
          apiRecipients: [
            ApiRecipient(
                paymentCode: form.recipient.paymentCode, amount: form.amount)
          ],
          feerate: form.feerate.toDouble(),
          network: network);
    } else {
      return wallet.createDrainTransaction(
          ownedOutputs: unspentOutputs,
          wipeAddress: form.recipient.paymentCode,
          feerate: form.feerate.toDouble(),
          network: network);
    }
  }

  Future<String> signAndBroadcastUnsignedTx(
      ApiSilentPaymentUnsignedTransaction unsignedTx) async {
    final selectedOutputs = unsignedTx.selectedUtxos;

    List<OutPoint> selectedOutpoints =
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

    await txHistoryRepository.addOutgoingTransaction(
      txid: txid,
      spentOutpoints: selectedOutpoints,
      recipients: recipients,
      changeSat: changeValue.field0.toInt(),
      feeSat: feeAmount.field0.toInt(),
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
