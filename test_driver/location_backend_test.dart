import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) => writeResponseData(
    data,
    destinationDirectory: 'build/location-backend-verification',
    testOutputFilename: 'device-result',
  ),
  writeResponseOnFailure: true,
);
