import 'dart:async';
import 'dart:typed_data';
import 'package:danawallet/constants.dart';
import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/recipient_form_filled.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/discovered_output.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
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
  DateTime? birthday; // birthday may not be known

  // variables that change
  late ApiAmount amount;
  late ApiAmount unconfirmedChange;
  late int? lastScan;

  // Cached data from SQLite (updated via _updateWalletState)
  late Map<String, ApiDiscoveredOutput> unspentOutputs;
  late List<String> outpointsToScan;
  late List<ApiRecordedTransaction> transactions;

  // this variable may change in some exceptional cases
  Bip353Address? danaAddress;

  // stream to receive updates while scanning
  late StreamSubscription scanResultSubscription;

  // callback when outputs are found during scan
  void Function(int count)? onOutputsFound;

  // private constructor
  WalletState._();

  static Future<WalletState> create() async {
    final instance = WalletState._();
    await instance._initStreams();
    return instance;
  }

  Future<void> _initStreams() async {
    scanResultSubscription = createScanResultStream().listen(((event) async {
      lastScan = event.blkheight;

      if (onOutputsFound != null) {
        onOutputsFound!(event.foundOutputs.length);
      }

      // Process found outputs (new UTXOs we own)
      for (final found in event.foundOutputs) {
        final outpoint = found.outpoint.split(':');
        final txid = outpoint[0];
        final vout = int.parse(outpoint[1]);
        final output = found.output;

        // Insert output into database
        await walletRepository.insertOutput(
          txid: txid,
          vout: vout,
          blockheight: event.blkheight,
          tweak: Uint8List.fromList(output.tweak),
          amountSat: output.value.field0.toInt(),
          script: output.scriptPubkey,
          label: output.label,
        );

        // Check if this is a self-send (skip change outputs)
        final isOwnTx = await walletRepository.isOwnOutgoingTx(txid);
        if (!isOwnTx || output.label == null) {
          // Add incoming transaction
          await walletRepository.addIncomingTransaction(
            txid: txid,
            amountSat: output.value.field0.toInt(),
            confirmationHeight: event.blkheight,
            confirmationBlockhash: event.blkhash,
          );
        }
      }

      // Process found inputs (our UTXOs being spent)
      for (final outpointStr in event.foundInputs) {
        final outpoint = outpointStr.split(':');
        final spentTxid = outpoint[0];
        final spentVout = int.parse(outpoint[1]);

        // Try to confirm an outgoing transaction
        final confirmed = await walletRepository.confirmOutgoingTransaction(
          spentOutpointTxid: spentTxid,
          spentOutpointVout: spentVout,
          confirmationHeight: event.blkheight,
          confirmationBlockhash: event.blkhash,
        );

        if (!confirmed) {
          // Unknown spend - mark output as spent without history entry
          await walletRepository.markOutputsSpentUnknown(
            spentOutpoints: [(spentTxid, spentVout, 0)],
            minedInBlock: event.blkhash,
          );
        }
      }

      await walletRepository.saveLastScan(lastScan!);

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
    scanResultSubscription.cancel();
    super.dispose();
  }

  Future<void> reset() async {
    danaAddress = null;
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

    // lastScan will be initialized by chainState synchronization service
    lastScan = null;

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
    lastScan = currentTip;
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

  Future<void> resetToScanHeight(int height) async {
    lastScan = height;

    await walletRepository.resetToHeight(height);

    await _updateWalletState();
    notifyListeners();
  }

  Future<void> _updateWalletState() async {
    lastScan = await walletRepository.readLastScan();

    // Get cached data from SQLite
    final balanceSat = await walletRepository.getUnspentBalance();
    amount = ApiAmount(field0: BigInt.from(balanceSat));

    final unconfirmedChangeSat = await walletRepository.getUnconfirmedChange();
    unconfirmedChange = ApiAmount(field0: BigInt.from(unconfirmedChangeSat));

    // Cache outputs for spending and scanning
    unspentOutputs = await walletRepository.getUnspentOutputs();
    outpointsToScan = await walletRepository.getNotMinedOutpoints();

    // Cache transactions for UI
    transactions = await walletRepository.getAllTransactions();
  }

  Future<ApiSilentPaymentUnsignedTransaction> createUnsignedTxToThisRecipient(
      RecipientFormFilled form) async {
    final wallet = await getWalletFromSecureStorage();

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

    // Mark outputs as spent in SQLite
    for (final outpointStr in selectedOutpoints) {
      final parts = outpointStr.split(':');
      final outTxid = parts[0];
      final outVout = int.parse(parts[1]);
      await walletRepository.markOutputSpent(outTxid, outVout, txid);
    }

    // Add outgoing transaction to SQLite
    final spentOutpointsWithAmount = <(String, int, int)>[];
    for (final outpointStr in selectedOutpoints) {
      final parts = outpointStr.split(':');
      final outTxid = parts[0];
      final outVout = int.parse(parts[1]);
      final outputAmount = unspentOutputs[outpointStr]?.value.field0.toInt() ?? 0;
      spentOutpointsWithAmount.add((outTxid, outVout, outputAmount));
    }

    await walletRepository.addOutgoingTransaction(
      txid: txid,
      spentOutpoints: spentOutpointsWithAmount,
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
