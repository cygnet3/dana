import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:flutter/material.dart';

class Bip353Address {
  String username;
  String domain;

  Bip353Address({required this.username, required this.domain});

  factory Bip353Address.fromString(String address) {
    if (address.isEmpty) {
      throw Exception("Address is empty");
    }

    if (!RegExp(r'^[a-z0-9]', caseSensitive: false).hasMatch(address[0])) {
      throw Exception(
          "Bip353 address does not start with a letter or digit: $address");
    }

    // Valid characters for dana address (username@domain format)
    final validAddressPattern =
        RegExp(r'^[a-z0-9._-]+@[a-z0-9.-]+\.[a-z]+$', caseSensitive: false);
    if (!validAddressPattern.hasMatch(address)) {
      throw Exception("Invalid bip353 address pattern: $address");
    }

    final parts = address.toLowerCase().split('@');
    if (parts.length != 2) {
      throw Exception("Invalid bip353 address pattern: $address");
    }

    // store everything in lower case
    final username = parts[0].toLowerCase();
    final domain = parts[1].toLowerCase();

    return Bip353Address(username: username, domain: domain);
  }

  @override
  String toString() {
    return "$username@$domain";
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is Bip353Address &&
        other.username == username &&
        other.domain == domain;
  }

  @override
  int get hashCode => Object.hash(username, domain);

  Widget asRichText(double? fontSize) {
    List<TextSpan> spans = [];

    // Add ₿ symbol at the beginning
    spans.add(TextSpan(
      text: '₿',
      style: BitcoinTextStyle.body5(Bitcoin.neutral6).copyWith(
        fontSize: fontSize,
        fontFamily: 'Inter',
        letterSpacing: 1,
        height: 1.5,
        fontWeight: FontWeight.w700,
      ),
    ));

    // Parse local part character by character to handle special characters
    String currentWord = '';
    bool inNumber = false;

    for (int i = 0; i < username.length; i++) {
      final char = username[i];

      // Check if character is a special separator (., -, _)
      if (char == '.' || char == '-' || char == '_') {
        // Add accumulated word first
        if (currentWord.isNotEmpty) {
          spans.add(TextSpan(
            text: currentWord,
            style: BitcoinTextStyle.body5(
                    inNumber ? Bitcoin.green : Bitcoin.blue)
                .copyWith(
              fontSize: fontSize,
              fontFamily: 'Inter',
              letterSpacing: 1,
              height: 1.5,
              fontWeight: inNumber ? FontWeight.w500 : FontWeight.w600,
            ),
          ));
          currentWord = '';
        }

        // Add special character in distinct grey color
        spans.add(TextSpan(
          text: char,
          style: BitcoinTextStyle.body5(Bitcoin.neutral6).copyWith(
            fontSize: fontSize,
            fontFamily: 'Inter',
            letterSpacing: 1,
            height: 1.5,
            fontWeight: FontWeight.w400,
          ),
        ));

        // Reset number flag after special character
        inNumber = false;
      } else {
        // Check if we're transitioning to numbers
        final isDigit = char.contains(RegExp(r'[0-9]'));
        if (isDigit && !inNumber) {
          // Add accumulated text part if any
          if (currentWord.isNotEmpty) {
            spans.add(TextSpan(
              text: currentWord,
              style: BitcoinTextStyle.body5(Bitcoin.blue).copyWith(
                fontSize: fontSize,
                fontFamily: 'Inter',
                letterSpacing: 1,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ));
            currentWord = '';
          }
          inNumber = true;
        }
        currentWord += char;
      }
    }

    // Add remaining local part
    if (currentWord.isNotEmpty) {
      spans.add(TextSpan(
        text: currentWord,
        style:
            BitcoinTextStyle.body5(inNumber ? Bitcoin.green : Bitcoin.blue)
                .copyWith(
          fontSize: fontSize,
          fontFamily: 'Inter',
          letterSpacing: 1,
          height: 1.5,
          fontWeight: inNumber ? FontWeight.w500 : FontWeight.w600,
        ),
      ));
    }

    // Add @ symbol - Grey
    spans.add(TextSpan(
      text: '@',
      style: BitcoinTextStyle.body5(Bitcoin.neutral6).copyWith(
        fontSize: fontSize,
        fontFamily: 'Inter',
        letterSpacing: 1,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
    ));

    // Parse domain part character by character to handle special characters
    currentWord = '';
    for (int i = 0; i < domain.length; i++) {
      final char = domain[i];

      // Check if character is a special separator (., -, _)
      if (char == '.' || char == '-' || char == '_') {
        // Add accumulated word first
        if (currentWord.isNotEmpty) {
          spans.add(TextSpan(
            text: currentWord,
            style: BitcoinTextStyle.body5(Bitcoin.purple).copyWith(
              fontSize: fontSize,
              fontFamily: 'Inter',
              letterSpacing: 1,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ));
          currentWord = '';
        }

        // Add special character in distinct grey color
        spans.add(TextSpan(
          text: char,
          style: BitcoinTextStyle.body5(Bitcoin.neutral6).copyWith(
            fontSize: fontSize,
            fontFamily: 'Inter',
            letterSpacing: 1,
            height: 1.5,
            fontWeight: FontWeight.w400,
          ),
        ));
      } else {
        currentWord += char;
      }
    }

    // Add remaining domain part
    if (currentWord.isNotEmpty) {
      spans.add(TextSpan(
        text: currentWord,
        style: BitcoinTextStyle.body5(Bitcoin.purple).copyWith(
          fontSize: fontSize,
          fontFamily: 'Inter',
          letterSpacing: 1,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ));
    }

    return SizedBox(
      child: AutoSizeText.rich(
        TextSpan(children: spans),
        textAlign: TextAlign.center,
        minFontSize: 10,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
