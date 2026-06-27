class CapturedImage {
  const CapturedImage({
    required this.imagePath,
    required this.latitude,
    required this.longitude,
    required this.distanceCm,
    required this.bearingAngle,
    required this.heightDelta,
    required this.timestamp,
  });

  final String imagePath;
  final double latitude;
  final double longitude;
  final double distanceCm;
  final double bearingAngle;
  final double heightDelta;
  final DateTime timestamp;

  Map<String, dynamic> toMap() {
    return {
      'imagePath': imagePath,
      'latitude': latitude,
      'longitude': longitude,
      'distanceCm': distanceCm,
      'bearingAngle': bearingAngle,
      'heightDelta': heightDelta,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory CapturedImage.fromMap(Map<dynamic, dynamic> map) {
    return CapturedImage(
      imagePath: map['imagePath'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      distanceCm: (map['distanceCm'] as num).toDouble(),
      bearingAngle: (map['bearingAngle'] as num).toDouble(),
      heightDelta: (map['heightDelta'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
