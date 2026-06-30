import '../models/plot_point.dart';

class PositionStatus {
  final bool distanceOK;
  final bool bearingOK;
  final bool pitchOK;
  final double distanceDelta; // cm,  positive = too far
  final double bearingDelta;  // deg, positive = turn right
  final double pitchDelta;    // deg, positive = tilt up more

  const PositionStatus({
    required this.distanceOK,
    required this.bearingOK,
    required this.pitchOK,
    required this.distanceDelta,
    required this.bearingDelta,
    required this.pitchDelta,
  });

  bool get allOK => distanceOK && bearingOK && pitchOK;
}

class PositionCheckService {
  static const double kDistanceTolerance = 45.0; // cm — loosened: depth estimate is noisy
  static const double kBearingTolerance = 8.0;   // degrees
  static const double kPitchTolerance = 8.0;     // degrees — loosened: match bearing tolerance

  PositionStatus check({
    required PlotPoint target,
    required double currentDistanceCm,
    required double currentBearingDeg,
    required double currentPitchDeg,
  }) {
    final double dDelta = currentDistanceCm - target.distanceCm;

    // Signed wraparound diff: positive = user needs to turn right.
    final double bDelta =
        _signedAngleDiff(currentBearingDeg, target.requiredBearing);

    final double pDelta = currentPitchDeg - target.elevationDeg;

    return PositionStatus(
      distanceOK: dDelta.abs() <= kDistanceTolerance,
      bearingOK: bDelta.abs() <= kBearingTolerance,
      pitchOK: pDelta.abs() <= kPitchTolerance,
      distanceDelta: dDelta,
      bearingDelta: bDelta,
      pitchDelta: pDelta,
    );
  }

  double _signedAngleDiff(double current, double target) {
    return (current - target + 540) % 360 - 180;
  }
}
