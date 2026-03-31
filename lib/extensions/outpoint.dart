import 'package:danawallet/generated/rust/api/structs/outpoint.dart';

extension OutpointExtension on OutPoint {
  String toDisplayString() {
    return '$txid:$vout';
  }
}

extension OutpointListExtension on List<OutPoint> {
  String toDisplayString() {
    return '[${map((e) => "\"${e.toDisplayString()}\"").join(', ')}]';
  }
}
