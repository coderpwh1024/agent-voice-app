import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Directory('build/message-ui-verification');
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: (data) => writeResponseData(
    data == null
        ? null
        : (Map<String, dynamic>.from(data)..remove('screenshots')),
    destinationDirectory: 'build/message-ui-verification',
    testOutputFilename: 'result',
  ),
  writeResponseOnFailure: true,
);
