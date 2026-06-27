import 'package:flutter/foundation.dart';

@immutable
class CapturedImage {
  final String path;
  final double latitude;
  final double longitude;
  final double distance;
  final double angle;
  final DateTime timestamp;
  final String albumId;
  final String albumName;

  const CapturedImage({
    required this.path,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.angle,
    required this.timestamp,
    this.albumId = '',
    this.albumName = 'General',
  });

  String get latitudeString => latitude.toStringAsFixed(5);
  String get longitudeString => longitude.toStringAsFixed(5);
  String get distanceString => '${distance.toStringAsFixed(1)} m';
  String get angleString => '${angle.toStringAsFixed(0)}°';
  String get timestampString => timestamp.toLocal().toString();
}
