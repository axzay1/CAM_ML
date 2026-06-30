import '../models/plot_point.dart';

class PlotService {
  /// Returns elevation offsets (degrees) for each layer relative to
  /// p1ElevationDeg.  P1 always sits on the equator layer (offset 0).
  List<double> _layerElevationOffsets(int numberOfLayers) {
    switch (numberOfLayers) {
      case 1:
        return [0];
      case 2:
        return [0, 40];
      case 3:
        return [-40, 0, 40];
      case 4:
        return [-60, -20, 20, 60];
      default:
        return [0];
    }
  }

  List<PlotPoint> generatePoints({
    required int pointsPerLayer,
    required int numberOfLayers,
    required double p1AzimuthDeg,
    required double p1ElevationDeg,
    required double p1DistanceCm,
  }) {
    final List<PlotPoint> points = [];
    final double azStep = 360.0 / pointsPerLayer;
    final List<double> elevOffsets = _layerElevationOffsets(numberOfLayers);
    int globalIndex = 0;

    for (int li = 0; li < elevOffsets.length; li++) {
      final bool isEquator = elevOffsets[li] == 0;
      final double layerElev =
          (p1ElevationDeg + elevOffsets[li]).clamp(-80.0, 80.0);

      // Equator layer starts at P1 azimuth (no offset).
      // Non-equator layers are offset by half azStep for better sphere
      // coverage when viewed from above.
      final double azOffset = isEquator ? 0 : azStep * 0.5;

      for (int pi = 0; pi < pointsPerLayer; pi++) {
        final double az =
            (p1AzimuthDeg + azOffset + pi * azStep) % 360; 

        final bool isP1 = isEquator && pi == 0;

        points.add(PlotPoint(
          index: globalIndex,
          label: 'P${globalIndex + 1}',
          layerIndex: li,
          pointInLayer: pi,
          azimuthDeg: az,
          elevationDeg: layerElev,
          distanceCm: p1DistanceCm,
          isCaptured: isP1,
        ));

        globalIndex++;
      }
    }

    return points;
  }
}
