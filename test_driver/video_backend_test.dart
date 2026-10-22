import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final directory = Directory('build/video-verification');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: (data) => writeResponseData(
    data,
    destinationDirectory: 'build/video-verification',
    testOutputFilename: 'backend-result',
  ),
  writeResponseOnFailure: true,
);
