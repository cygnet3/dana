import 'package:danawallet/generated/rust/api/structs/outpoint.dart';

extension OutpointExtension on OutPoint {
  String toDisplayString() {
    return '$txid:$vout';
  }
}
