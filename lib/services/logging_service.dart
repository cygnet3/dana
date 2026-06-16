import 'dart:async';

import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/logger.dart';

class LoggingService {
  late StreamSubscription logStreamSubscription;

  // private constructor
  LoggingService._();

  void _initialize() {
    logStreamSubscription =
        createLogStream(level: LogLevel.info, logDependencies: true)
            .listen((event) {
      // ignore: avoid_print
      print('${event.level} (${event.tag}): ${event.msg}');
    });
  }

  static LoggingService create() {
    final service = LoggingService._();
    service._initialize();
    return service;
  }
}
