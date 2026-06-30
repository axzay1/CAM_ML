import 'captured_image.dart';
import 'plot_point.dart';

class Album {
  final String id;
  final String name;
  final double anchorLatitude;
  final double anchorLongitude;
  final double anchorBearing;
  final int pointsPerLayer;
  final int numberOfLayers;
  int currentPointIndex;
  List<PlotPoint> plotPoints;
  List<CapturedImage> images;

  Album({
    required this.id,
    required this.name,
    required this.anchorLatitude,
    required this.anchorLongitude,
    required this.anchorBearing,
    required this.pointsPerLayer,
    required this.numberOfLayers,
    this.currentPointIndex = 1,
    List<PlotPoint>? plotPoints,
    List<CapturedImage>? images,
  })  : plotPoints = plotPoints ?? [],
        images = images ?? [];

  int get totalPoints => pointsPerLayer * numberOfLayers;

  PlotPoint? get activePoint =>
      currentPointIndex < plotPoints.length
          ? plotPoints[currentPointIndex]
          : null;

  bool get isComplete =>
      plotPoints.isNotEmpty && plotPoints.every((p) => p.isCaptured);

  double? get sphereRadiusCm =>
      plotPoints.isEmpty ? null : plotPoints.first.distanceCm;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'anchorLatitude': anchorLatitude,
      'anchorLongitude': anchorLongitude,
      'anchorBearing': anchorBearing,
      'pointsPerLayer': pointsPerLayer,
      'numberOfLayers': numberOfLayers,
      'currentPointIndex': currentPointIndex,
      'plotPoints': plotPoints.map((p) => p.toMap()).toList(),
      'images': images.map((e) => e.toMap()).toList(),
    };
  }

  factory Album.fromMap(Map<dynamic, dynamic> map) {
    final dynamic rawPlotPoints = map['plotPoints'];
    final List<PlotPoint> plotPointList = <PlotPoint>[];
    if (rawPlotPoints is List) {
      for (final dynamic item in rawPlotPoints) {
        if (item is Map) {
          plotPointList.add(PlotPoint.fromMap(item));
        }
      }
    }

    final dynamic rawImages = map['images'];
    final List<CapturedImage> imageList = <CapturedImage>[];
    if (rawImages is List) {
      for (final dynamic item in rawImages) {
        if (item is Map) {
          imageList.add(CapturedImage.fromMap(item));
        }
      }
    }

    return Album(
      id: map['id'] as String,
      name: map['name'] as String,
      anchorLatitude: (map['anchorLatitude'] as num).toDouble(),
      anchorLongitude: (map['anchorLongitude'] as num).toDouble(),
      anchorBearing: (map['anchorBearing'] as num).toDouble(),
      pointsPerLayer: (map['pointsPerLayer'] as num? ?? 4).toInt(),
      numberOfLayers: (map['numberOfLayers'] as num? ?? 1).toInt(),
      currentPointIndex: (map['currentPointIndex'] as num? ?? 1).toInt(),
      plotPoints: plotPointList,
      images: imageList,
    );
  }
}
