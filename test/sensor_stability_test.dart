import 'package:cam_ml/providers/camera_app_state.dart';
import 'package:cam_ml/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocationService sensor stability', () {
    test('treats low acceleration as stable for pin placement', () {
      expect(LocationService.isSensorStable(0.4), isTrue);
    });

    test('treats high acceleration as unstable for pin placement', () {
      expect(LocationService.isSensorStable(2.3), isFalse);
    });
  });

  group('CameraAppState pin workflow', () {
    test('allows entering setup before any sensor update arrives', () {
      final state = CameraAppState(const []);
      state.updatePosition(12.34, 56.78);

      state.createPinAndEnterSetup();

      expect(state.workflowState, PinWorkflowState.setup);
    });

    test('still allows setup when the sensor reports motion', () {
      final state = CameraAppState(const []);
      state.updateSensorStability(3.0);
      state.updatePosition(12.34, 56.78, accuracy: 10.0);

      state.createPinAndEnterSetup();

      expect(state.workflowState, PinWorkflowState.setup);
    });

    test('still allows pin setup when GPS accuracy is too poor', () {
      final state = CameraAppState(const []);
      state.updatePosition(12.34, 56.78, altitude: 20.0, accuracy: 60.0);

      state.createPinAndEnterSetup();

      expect(state.workflowState, PinWorkflowState.setup);
    });

    test('stores target distance in centimeters', () {
      final state = CameraAppState(const []);

      state.setTargetDistance(250);

      expect(state.targetDistanceCm, 250);
      expect(state.targetDistanceMeters, closeTo(2.5, 0.0001));
    });

    test('tracks pin altitude and z offset for 3d guidance', () {
      final state = CameraAppState(const []);
      state.updatePosition(12.34, 56.78, altitude: 20.0, accuracy: 10.0);

      state.createPinAndEnterSetup();
      state.updatePosition(12.34, 56.78, altitude: 21.0, accuracy: 10.0);

      expect(state.pinnedAltitude, 20.0);
      expect(state.verticalOffsetMeters, closeTo(1.0, 0.0001));
      expect(state.currentDistance3dMeters, closeTo(1.0, 0.0001));
    });
  });
}
