import 'dart:convert';
import 'dart:typed_data';

/// Self-contained backup of all wallet data.
///
/// Captures everything from Secure Storage, SharedPreferences, and SQLite
/// into a single JSON-serializable structure. No Rust dependencies.
class DanaBackup {
  static const int currentVersion = 2;

  final int version;
  final WalletBackup wallet;
  final TransactionDataBackup data;
  final SettingsBackupData settings;

  DanaBackup({
    required this.wallet,
    required this.data,
    required this.settings,
    this.version = currentVersion,
  });

  String encode() => jsonEncode(toJson());

  static DanaBackup decode(String encoded) =>
      DanaBackup.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'version': version,
        'wallet': wallet.toJson(),
        'data': data.toJson(),
        'settings': settings.toJson(),
      };

  factory DanaBackup.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int;
    if (version != currentVersion) {
      throw FormatException(
        'Unsupported backup version: $version (expected $currentVersion)',
      );
    }
    return DanaBackup(
      version: version,
      wallet: WalletBackup.fromJson(
          json['wallet'] as Map<String, dynamic>),
      data: TransactionDataBackup.fromJson(
          json['data'] as Map<String, dynamic>),
      settings: SettingsBackupData.fromJson(
          json['settings'] as Map<String, dynamic>),
    );
  }
}

// ============================================
// WALLET
// Keys, seed, network — from Secure Storage & SharedPreferences
// ============================================

class WalletBackup {
  /// Encoded scan secret key (from Secure Storage)
  final String scanKey;

  /// Encoded spend key (from Secure Storage)
  final String spendKey;

  /// BIP39 seed phrase (from Secure Storage, optional for watch-only)
  final String? seedPhrase;

  /// Wallet birthday as unix timestamp in seconds
  final int? birthday;

  /// Network name (e.g. "mainnet", "signet", "regtest")
  final String network;

  /// Last scanned block height
  final int? lastScan;

  /// Dana address (BIP353)
  final String? danaAddress;

  WalletBackup({
    required this.scanKey,
    required this.spendKey,
    this.seedPhrase,
    this.birthday,
    required this.network,
    this.lastScan,
    this.danaAddress,
  });

  Map<String, dynamic> toJson() => {
        'scan_key': scanKey,
        'spend_key': spendKey,
        'seed_phrase': seedPhrase,
        'birthday': birthday,
        'network': network,
        'last_scan': lastScan,
        'dana_address': danaAddress,
      };

  factory WalletBackup.fromJson(Map<String, dynamic> json) {
    return WalletBackup(
      scanKey: json['scan_key'] as String,
      spendKey: json['spend_key'] as String,
      seedPhrase: json['seed_phrase'] as String?,
      birthday: json['birthday'] as int,
      network: json['network'] as String,
      lastScan: json['last_scan'] as int?,
      danaAddress: json['dana_address'] as String?,
    );
  }
}

// ============================================
// TRANSACTION DATA
// Owned outputs + transaction history — from SQLite
// ============================================

class TransactionDataBackup {
  final List<OwnedOutputBackup> ownedOutputs;
  final List<IncomingTxBackup> incomingTransactions;
  final List<OutgoingTxBackup> outgoingTransactions;

  TransactionDataBackup({
    required this.ownedOutputs,
    required this.incomingTransactions,
    required this.outgoingTransactions,
  });

  Map<String, dynamic> toJson() => {
        'owned_outputs': ownedOutputs.map((o) => o.toJson()).toList(),
        'incoming_transactions':
            incomingTransactions.map((t) => t.toJson()).toList(),
        'outgoing_transactions':
            outgoingTransactions.map((t) => t.toJson()).toList(),
      };

  factory TransactionDataBackup.fromJson(Map<String, dynamic> json) {
    return TransactionDataBackup(
      ownedOutputs: (json['owned_outputs'] as List)
          .map((o) => OwnedOutputBackup.fromJson(o as Map<String, dynamic>))
          .toList(),
      incomingTransactions: (json['incoming_transactions'] as List)
          .map((t) => IncomingTxBackup.fromJson(t as Map<String, dynamic>))
          .toList(),
      outgoingTransactions: (json['outgoing_transactions'] as List)
          .map((t) => OutgoingTxBackup.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OwnedOutputBackup {
  final String txid;
  final int vout;
  final int blockheight;

  /// 32-byte tweak, hex-encoded
  final String tweakHex;
  final int amountSat;
  final String script;
  final String? label;
  final String? spendingTxid;
  final String? minedInBlock;

  OwnedOutputBackup({
    required this.txid,
    required this.vout,
    required this.blockheight,
    required this.tweakHex,
    required this.amountSat,
    required this.script,
    this.label,
    this.spendingTxid,
    this.minedInBlock,
  });

  /// Create from a SQLite row map.
  factory OwnedOutputBackup.fromRow(Map<String, Object?> row) {
    return OwnedOutputBackup(
      txid: row['txid'] as String,
      vout: row['vout'] as int,
      blockheight: row['blockheight'] as int,
      tweakHex: _bytesToHex(row['tweak'] as Uint8List),
      amountSat: row['amount_sat'] as int,
      script: row['script'] as String,
      label: row['label'] as String?,
      spendingTxid: row['spending_txid'] as String?,
      minedInBlock: row['mined_in_block'] as String?,
    );
  }

  /// Convert back to a SQLite row map for insertion.
  Map<String, Object?> toRow() => {
        'txid': txid,
        'vout': vout,
        'blockheight': blockheight,
        'tweak': _hexToBytes(tweakHex),
        'amount_sat': amountSat,
        'script': script,
        'label': label,
        'spending_txid': spendingTxid,
        'mined_in_block': minedInBlock,
      };

  Map<String, dynamic> toJson() => {
        'txid': txid,
        'vout': vout,
        'blockheight': blockheight,
        'tweak': tweakHex,
        'amount_sat': amountSat,
        'script': script,
        'label': label,
        'spending_txid': spendingTxid,
        'mined_in_block': minedInBlock,
      };

  factory OwnedOutputBackup.fromJson(Map<String, dynamic> json) {
    return OwnedOutputBackup(
      txid: json['txid'] as String,
      vout: json['vout'] as int,
      blockheight: json['blockheight'] as int,
      tweakHex: json['tweak'] as String,
      amountSat: json['amount_sat'] as int,
      script: json['script'] as String,
      label: json['label'] as String?,
      spendingTxid: json['spending_txid'] as String?,
      minedInBlock: json['mined_in_block'] as String?,
    );
  }
}

class IncomingTxBackup {
  final String txid;
  final int amountReceivedSat;
  final int? confirmationHeight;
  final String? confirmationBlockhash;
  final String? userNote;

  IncomingTxBackup({
    required this.txid,
    required this.amountReceivedSat,
    this.confirmationHeight,
    this.confirmationBlockhash,
    this.userNote,
  });

  /// Create from a SQLite row map.
  factory IncomingTxBackup.fromRow(Map<String, Object?> row) {
    return IncomingTxBackup(
      txid: row['txid'] as String,
      amountReceivedSat: row['amount_received_sat'] as int,
      confirmationHeight: row['confirmation_height'] as int?,
      confirmationBlockhash: row['confirmation_blockhash'] as String?,
      userNote: row['user_note'] as String?,
    );
  }

  /// Convert back to a SQLite row map for insertion.
  Map<String, Object?> toRow() => {
        'txid': txid,
        'amount_received_sat': amountReceivedSat,
        'confirmation_height': confirmationHeight,
        'confirmation_blockhash': confirmationBlockhash,
        'user_note': userNote,
      };

  Map<String, dynamic> toJson() => {
        'txid': txid,
        'amount_received_sat': amountReceivedSat,
        'confirmation_height': confirmationHeight,
        'confirmation_blockhash': confirmationBlockhash,
        'user_note': userNote,
      };

  factory IncomingTxBackup.fromJson(Map<String, dynamic> json) {
    return IncomingTxBackup(
      txid: json['txid'] as String,
      amountReceivedSat: json['amount_received_sat'] as int,
      confirmationHeight: json['confirmation_height'] as int?,
      confirmationBlockhash: json['confirmation_blockhash'] as String?,
      userNote: json['user_note'] as String?,
    );
  }
}

class OutgoingTxBackup {
  final String txid;
  final int amountSpentSat;
  final int changeSat;
  final int feeSat;
  final int? confirmationHeight;
  final String? confirmationBlockhash;
  final String? userNote;

  /// Outpoints consumed by this transaction: ["txid:vout", ...]
  final List<String> spentOutpoints;

  /// Recipients: [{address, amount_sat}, ...]
  final List<RecipientBackup> recipients;

  OutgoingTxBackup({
    required this.txid,
    required this.amountSpentSat,
    required this.changeSat,
    required this.feeSat,
    this.confirmationHeight,
    this.confirmationBlockhash,
    this.userNote,
    required this.spentOutpoints,
    required this.recipients,
  });

  Map<String, dynamic> toJson() => {
        'txid': txid,
        'amount_spent_sat': amountSpentSat,
        'change_sat': changeSat,
        'fee_sat': feeSat,
        'confirmation_height': confirmationHeight,
        'confirmation_blockhash': confirmationBlockhash,
        'user_note': userNote,
        'spent_outpoints': spentOutpoints,
        'recipients': recipients.map((r) => r.toJson()).toList(),
      };

  factory OutgoingTxBackup.fromJson(Map<String, dynamic> json) {
    return OutgoingTxBackup(
      txid: json['txid'] as String,
      amountSpentSat: json['amount_spent_sat'] as int,
      changeSat: json['change_sat'] as int,
      feeSat: json['fee_sat'] as int,
      confirmationHeight: json['confirmation_height'] as int?,
      confirmationBlockhash: json['confirmation_blockhash'] as String?,
      userNote: json['user_note'] as String?,
      spentOutpoints: (json['spent_outpoints'] as List).cast<String>(),
      recipients: (json['recipients'] as List)
          .map((r) => RecipientBackup.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RecipientBackup {
  final String address;
  final int amountSat;

  RecipientBackup({
    required this.address,
    required this.amountSat,
  });

  Map<String, dynamic> toJson() => {
        'address': address,
        'amount_sat': amountSat,
      };

  factory RecipientBackup.fromJson(Map<String, dynamic> json) {
    return RecipientBackup(
      address: json['address'] as String,
      amountSat: json['amount_sat'] as int,
    );
  }
}

// ============================================
// SETTINGS
// From SharedPreferences
// ============================================

class SettingsBackupData {
  final String? blindbitUrl;
  final int? dustLimit;

  SettingsBackupData({
    this.blindbitUrl,
    this.dustLimit,
  });

  Map<String, dynamic> toJson() => {
        'blindbit_url': blindbitUrl,
        'dust_limit': dustLimit,
      };

  factory SettingsBackupData.fromJson(Map<String, dynamic> json) {
    return SettingsBackupData(
      blindbitUrl: json['blindbit_url'] as String?,
      dustLimit: json['dust_limit'] as int?,
    );
  }
}

// ============================================
// HEX HELPERS
// ============================================

String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
