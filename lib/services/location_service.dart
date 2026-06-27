import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static const double sensorStabilityThreshold = 1.0;
  static const double minimumGpsAccuracyMeters = 20.0;

  static bool isSensorStable(double accelerationMagnitude) {
    return accelerationMagnitude <= sensorStabilityThreshold;
  }

  static bool hasReliableGps({required double accuracy}) {
    return accuracy <= minimumGpsAccuracyMeters;
  }

  static Future<bool> requestPermission() async {
    final cameraPermission = await Permission.camera.request();
    final locationPermission = await Permission.locationWhenInUse.request();

    final granted = cameraPermission.isGranted && locationPermission.isGranted;
    if (!granted) {
      return false;
    }

    final geolocatorPermission = await Geolocator.requestPermission();
    return geolocatorPermission == LocationPermission.always ||
        geolocatorPermission == LocationPermission.whileInUse;
  }

  static Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
  }

  static double calculateDistanceHaversine(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadius = 6371000.0;
    final lat1 = _degreesToRadians(startLatitude);
    final lon1 = _degreesToRadians(startLongitude);
    final lat2 = _degreesToRadians(endLatitude);
    final lon2 = _degreesToRadians(endLongitude);

    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) => degrees * pi / 180.0;
}
