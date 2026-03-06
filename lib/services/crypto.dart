import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Backup encryption using PBKDF2-HMAC-SHA256 key derivation + AES-256-GCM
/// authenticated encryption.
///
/// Wire format (binary):
/// ```
///   version    1 byte  (currently 0x02)
///   salt      16 bytes (random, for PBKDF2)
///   nonce     12 bytes (random, for GCM)
///   ciphertext  variable
///   GCM tag   16 bytes
/// ```
///
/// Total overhead: 45 bytes.
class BackupCrypto {
  static const int _version = 2;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _pbkdf2Iterations = 100000;
  static const int _keyLengthBits = 256;

  static const int _headerLength = 1 + _saltLength + _nonceLength;
  static const int _minLength = _headerLength + _macLength;

  static final _aesGcm = AesGcm.with256bits();

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdf2Iterations,
    bits: _keyLengthBits,
  );

  /// Encrypt plaintext bytes with a password.
  ///
  /// Returns the full wire-format bytes.
  static Future<Uint8List> encrypt(
      Uint8List plaintext, String password) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = await _deriveKey(password, salt);

    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );

    final result = BytesBuilder(copy: false);
    result.addByte(_version);
    result.add(salt);
    result.add(nonce);
    result.add(secretBox.cipherText);
    result.add(secretBox.mac.bytes);
    return result.toBytes();
  }

  /// Decrypt wire-format bytes with a password.
  ///
  /// Throws [FormatException] for version mismatches or truncated data.
  /// Throws [SecretBoxAuthenticationError] if the password is wrong or data
  /// has been tampered with (GCM tag verification failure).
  static Future<Uint8List> decrypt(Uint8List data, String password) async {
    if (data.length < _minLength) {
      throw const FormatException('Backup data is too short');
    }

    final version = data[0];
    if (version != _version) {
      throw FormatException(
        'Unsupported backup encryption version: $version (expected $_version)',
      );
    }

    final salt = Uint8List.sublistView(data, 1, 1 + _saltLength);
    final nonce =
        Uint8List.sublistView(data, 1 + _saltLength, _headerLength);
    final cipherText =
        Uint8List.sublistView(data, _headerLength, data.length - _macLength);
    final mac = Mac(data.sublist(data.length - _macLength));

    final key = await _deriveKey(password, salt);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: mac,
    );

    final plaintext = await _aesGcm.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(plaintext);
  }

  /// PBKDF2-HMAC-SHA256 key derivation.
  static Future<SecretKey> _deriveKey(
      String password, List<int> salt) async {
    return _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  /// Generate cryptographically-secure random bytes.
  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }
}
