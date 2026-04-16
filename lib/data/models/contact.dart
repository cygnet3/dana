import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/contact_field.dart';
import 'package:flutter/material.dart';

class Contact {
  int? id;
  final String? name; // user defined user name
  final Bip353Address?
      bip353Address; // Eventually register more than one, for now keep it simple
  final String paymentCode; // silent payment address of the contact
  final List<ContactField>? customFields; // Optional custom fields

  Contact({
    this.id,
    this.name,
    this.bip353Address,
    required this.paymentCode,
    this.customFields,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'bip353Address': bip353Address?.toString(),
      'paymentCode': paymentCode,
    };
  }

  factory Contact.fromMap(Map<String, dynamic> map) {
    final String? bip353Address = map['bip353Address'];
    return Contact(
      id: map['id'],
      name: map['name'],
      bip353Address: bip353Address != null
          ? Bip353Address.fromString(bip353Address)
          : null,
      paymentCode: map['paymentCode'],
      customFields: null, // Custom fields loaded separately
    );
  }

  String? get displayName {
    return name ?? bip353Address?.toString();
  }

  String? get displayNameInitial {
    return displayName?[0].toUpperCase();
  }

  Color get avatarColor {
    // Generate a consistent color based on the static payment code
    final hash = paymentCode.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    // check equivalency based on ID only
    return other is Contact && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
