import 'package:flutter_test/flutter_test.dart';
import 'package:cam_ml/models/captured_image.dart';

void main() {
  test('CapturedImage map conversion is stable', () {
    final original = CapturedImage(
      imagePath: '/tmp/a.jpg',
      latitude: 1.23,
      longitude: 4.56,
      distanceCm: 150.0,
      bearingAngle: 90.0,
      heightDelta: 8.0,
      timestamp: DateTime.parse('2026-01-01T00:00:00.000Z'),
    );

    final restored = CapturedImage.fromMap(original.toMap());

    expect(restored.imagePath, original.imagePath);
    expect(restored.latitude, original.latitude);
    expect(restored.longitude, original.longitude);
    expect(restored.distanceCm, original.distanceCm);
    expect(restored.bearingAngle, original.bearingAngle);
    expect(restored.heightDelta, original.heightDelta);
  });
}
