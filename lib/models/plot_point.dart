class PlotPoint {
  final int index;
  final String label;
  final int layerIndex;
  final int pointInLayer;
  final double azimuthDeg;
  final double elevationDeg;
  final double distanceCm;
  bool isCaptured;

  PlotPoint({
    required this.index,
    required this.label,
    required this.layerIndex,
    required this.pointInLayer,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.distanceCm,
    this.isCaptured = false,
  });

  /// Bearing the camera must face — toward the anchor object.
  double get requiredBearing => azimuthDeg;

  Map<String, dynamic> toMap() => {
        'index': index,
        'label': label,
        'layerIndex': layerIndex,
        'pointInLayer': pointInLayer,
        'azimuthDeg': azimuthDeg,
        'elevationDeg': elevationDeg,
        'distanceCm': distanceCm,
        'isCaptured': isCaptured,
      };

  factory PlotPoint.fromMap(Map<dynamic, dynamic> map) => PlotPoint(
        index: (map['index'] as num).toInt(),
        label: map['label'] as String,
        layerIndex: (map['layerIndex'] as num).toInt(),
        pointInLayer: (map['pointInLayer'] as num).toInt(),
        azimuthDeg: (map['azimuthDeg'] as num).toDouble(),
        elevationDeg: (map['elevationDeg'] as num).toDouble(),
        distanceCm: (map['distanceCm'] as num).toDouble(),
        isCaptured: map['isCaptured'] as bool? ?? false,
      );
}
