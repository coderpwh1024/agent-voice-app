import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum DeviceLocationStatus { ok, denied, unavailable }

enum DeviceLocationFailure {
  permissionDenied,
  serviceDisabled,
  timedOut,
  unavailable,
}

class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  factory DeviceLocation.fromPosition(Position position) => DeviceLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
    capturedAt: position.timestamp,
  );

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;

  Map<String, Object> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_meters': accuracyMeters,
    'captured_at': capturedAt.toUtc().toIso8601String(),
  };
}

class DeviceLocationResult {
  const DeviceLocationResult(this.status, [this.location, this.failure]);

  final DeviceLocationStatus status;
  final DeviceLocation? location;
  final DeviceLocationFailure? failure;

  String? get notice => switch (failure) {
    DeviceLocationFailure.permissionDenied => '未取得当前位置：请允许位置权限，或直接说明地点。',
    DeviceLocationFailure.serviceDisabled => '未取得当前位置：请开启系统定位服务，或直接说明地点。',
    DeviceLocationFailure.timedOut => '未取得当前位置：定位超时，请重试或直接说明地点。',
    DeviceLocationFailure.unavailable => '未取得当前位置：定位暂不可用，请重试或直接说明地点。',
    null => status == DeviceLocationStatus.ok ? null : '未取得当前位置：请重试或直接说明地点。',
  };
}

abstract interface class DeviceLocationProvider {
  Future<DeviceLocationResult> currentLocation();
}

class GeolocatorDeviceLocationProvider implements DeviceLocationProvider {
  const GeolocatorDeviceLocationProvider();

  static const maxCachedAge = Duration(minutes: 5);

  static bool _isFresh(Position position) {
    final age = DateTime.now().toUtc().difference(position.timestamp.toUtc());
    return !age.isNegative && age < maxCachedAge;
  }

  @override
  Future<DeviceLocationResult> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DeviceLocationResult(
          DeviceLocationStatus.unavailable,
          null,
          DeviceLocationFailure.serviceDisabled,
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return const DeviceLocationResult(
          DeviceLocationStatus.denied,
          null,
          DeviceLocationFailure.permissionDenied,
        );
      }
      Position? cached;
      try {
        cached = await Geolocator.getLastKnownPosition();
      } on PermissionDeniedException {
        return const DeviceLocationResult(
          DeviceLocationStatus.denied,
          null,
          DeviceLocationFailure.permissionDenied,
        );
      } on LocationServiceDisabledException {
        return const DeviceLocationResult(
          DeviceLocationStatus.unavailable,
          null,
          DeviceLocationFailure.serviceDisabled,
        );
      } on Exception {
        cached = null;
      }
      if (cached != null && _isFresh(cached)) {
        return DeviceLocationResult(
          DeviceLocationStatus.ok,
          DeviceLocation.fromPosition(cached),
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (!_isFresh(position)) {
        return const DeviceLocationResult(
          DeviceLocationStatus.unavailable,
          null,
          DeviceLocationFailure.unavailable,
        );
      }
      return DeviceLocationResult(
        DeviceLocationStatus.ok,
        DeviceLocation.fromPosition(position),
      );
    } on TimeoutException {
      return const DeviceLocationResult(
        DeviceLocationStatus.unavailable,
        null,
        DeviceLocationFailure.timedOut,
      );
    } on PermissionDeniedException {
      return const DeviceLocationResult(
        DeviceLocationStatus.denied,
        null,
        DeviceLocationFailure.permissionDenied,
      );
    } on LocationServiceDisabledException {
      return const DeviceLocationResult(
        DeviceLocationStatus.unavailable,
        null,
        DeviceLocationFailure.serviceDisabled,
      );
    } on Exception {
      return const DeviceLocationResult(
        DeviceLocationStatus.unavailable,
        null,
        DeviceLocationFailure.unavailable,
      );
    }
  }
}

bool requestsDeviceLocation(String text) {
  final normalized = text.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (RegExp(r'什么意思|什么含义|怎么翻译|解释一下').hasMatch(normalized)) {
    return false;
  }
  return RegExp(r'当前位置|我的位置|我现在的位置|我现在在哪|我在哪[里儿]?|我在什么地方|我所处的位置|我所在的位置|定位我')
          .hasMatch(normalized) ||
      RegExp(r'(我|咱们|我们|这里|这儿|此处).{0,4}(附近|周边|周围|身边)').hasMatch(normalized) ||
      RegExp(r'离我(最近|近)|距我|距离我').hasMatch(normalized) ||
      RegExp(r'^(请问|请|帮我|帮忙|查找|查一下|看看|找|搜|搜索|推荐|给我|现在|目前|在)?[，,\s]*(附近|周边|周围)')
          .hasMatch(normalized) ||
      RegExp(r'(推荐|搜索|找|看看|查找|查询|查一下)附近').hasMatch(normalized) ||
      RegExp(r'(从|以)(我这里|我这儿|我现在的位置|当前位置|我的位置|这里|这儿|此处)(出发|为起点|到)')
          .hasMatch(normalized) ||
      RegExp(
        r'\b(where am i|near me|around me|my current location|from my location)\b',
      ).hasMatch(normalized);
}
