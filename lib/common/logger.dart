import 'package:flutter/material.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'extensions.dart';

class CustomLog extends FlutterTalkerLog {
  CustomLog(String message) : super(message);

  @override
  AnsiPen get pen => AnsiPen()..xterm(49);

  @override
  Color get color => Colors.teal;

  @override
  String generateTextMessage() {
    return '| Custom leading | $message';
  }
}

enum TalkerType { fine, info, verbose, warning, logTyped, log }

void logTalker({
  required String classFileName,
  required TalkerType logType,
  required String message,
}) {
  if (true) {
    var talker = Talker(
      /// Your own observers to handle errors's exception's and log's
      /// like Crashlytics or Sentry observer
      observers: [],
      settings: TalkerSettings(
        /// You can enable/disable all talker processes with this field
        enabled: true,

        /// You can enable/disable saving logs data in history
        useHistory: true,

        /// Length of history that saving logs data
        maxHistoryItems: 100,

        /// You can enable/disable console logs
        useConsoleLogs: true,
      ),

      /// Setup your implementation of logger
      logger: TalkerLogger(
        output: (message) {
          '⏰⏰⏰ $classFileName 🌷🌷🌷 $message'.log();
        },
      ),

      ///etc...
    );

    switch (logType) {
      case TalkerType.fine:
        talker.fine(message);
        break;
      case TalkerType.info:
        talker.info(message);
        break;
      case TalkerType.verbose:
        talker.verbose(message);
        break;
      case TalkerType.warning:
        talker.warning(message);
        break;
      case TalkerType.logTyped:
        talker.log(CustomLog(message));
        break;
      case TalkerType.log:
        talker.log(CustomLog(message));
        break;
    }
  }
}
