import 'dart:async';

import 'package:agent_voice_app/core/location/device_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class FakeLocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Position? cached;
  Position? current;
  Object? currentError;
  int currentRequests = 0;
  LocationSettings? requestedSettings;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => cached;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    currentRequests++;
    requestedSettings = locationSettings;
    if (currentError != null) throw currentError!;
    return current!;
  }
}

Position positionAt(DateTime timestamp) => Position(
  longitude: 116.4,
  latitude: 39.9,
  timestamp: timestamp,
  accuracy: 12.5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late GeolocatorPlatform originalPlatform;
  late FakeLocationPlatform platform;

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
    platform = FakeLocationPlatform();
    GeolocatorPlatform.instance = platform;
  });

  tearDown(() => GeolocatorPlatform.instance = originalPlatform);

  test('uses a recent cached fix without waiting for GPS', () async {
    platform.cached = positionAt(
      DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
    );

    final result = await const GeolocatorDeviceLocationProvider()
        .currentLocation();

    expect(result.status, DeviceLocationStatus.ok);
    expect(result.location, isNotNull);
    expect(platform.currentRequests, 0);
  });

  test(
    'waits up to 25 seconds for a fresh fix when the cache is stale',
    () async {
      platform.cached = positionAt(
        DateTime.now().toUtc().subtract(const Duration(minutes: 6)),
      );
      platform.current = positionAt(DateTime.now().toUtc());

      final result = await const GeolocatorDeviceLocationProvider()
          .currentLocation();

      expect(result.status, DeviceLocationStatus.ok);
      expect(platform.currentRequests, 1);
      expect(requestedTimeLimit(platform), const Duration(seconds: 25));
    },
  );

  test('reports a GPS timeout without returning stale coordinates', () async {
    platform.cached = positionAt(
      DateTime.now().toUtc().subtract(const Duration(minutes: 6)),
    );
    platform.currentError = TimeoutException('no fix');

    final result = await const GeolocatorDeviceLocationProvider()
        .currentLocation();

    expect(result.status, DeviceLocationStatus.unavailable);
    expect(result.location, isNull);
    expect(result.failure, DeviceLocationFailure.timedOut);
    expect(result.notice, contains('定位超时'));
  });

  test(
    'does not query coordinates without permission or location service',
    () async {
      platform.permission = LocationPermission.denied;
      final denied = await const GeolocatorDeviceLocationProvider()
          .currentLocation();
      expect(denied.failure, DeviceLocationFailure.permissionDenied);
      expect(platform.currentRequests, 0);

      platform.enabled = false;
      final disabled = await const GeolocatorDeviceLocationProvider()
          .currentLocation();
      expect(disabled.failure, DeviceLocationFailure.serviceDisabled);
      expect(platform.currentRequests, 0);
    },
  );

  test('recognizes requests tied to the device position', () {
    for (final text in [
      '我现在在哪？',
      '告诉我当前位置',
      '附近有什么咖啡店',
      '请问附近有什么咖啡店',
      '我附近的地铁站',
      '给我推荐附近的地铁站',
      '我现在的位置在哪',
      '离我最近的便利店',
      '距离我最近的地铁站',
      '我身边有什么公园',
      '从我这里出发到故宫',
      '从当前位置出发去机场',
      'Where am I?',
      'Find restaurants near me',
    ]) {
      expect(requestsDeviceLocation(text), isTrue, reason: text);
    }
  });

  test('uses the position acquisition time in UTC', () {
    final location = DeviceLocation.fromPosition(
      Position(
        longitude: 116.4,
        latitude: 39.9,
        timestamp: DateTime.parse('2026-11-12T16:30:00+08:00'),
        accuracy: 12.5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
    expect(location.toJson(), {
      'latitude': 39.9,
      'longitude': 116.4,
      'accuracy_meters': 12.5,
      'captured_at': '2026-11-12T08:30:00.000Z',
    });
  });

  test('does not locate for ordinary or named-place questions', () {
    for (final text in [
      '你好',
      '介绍北京',
      '王府井附近的咖啡店',
      '从北京站出发到故宫',
      '解释一下“当前位置”是什么意思',
      '上海周边有哪些城市',
      '',
    ]) {
      expect(requestsDeviceLocation(text), isFalse, reason: text);
    }
  });
}

Duration? requestedTimeLimit(FakeLocationPlatform platform) =>
    platform.requestedSettings?.timeLimit;
