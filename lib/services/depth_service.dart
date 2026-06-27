import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class DepthService extends ChangeNotifier {
  DepthService()
      : _detector = ObjectDetector(
          options: ObjectDetectorOptions(
            mode: DetectionMode.stream,
            classifyObjects: false,
            multipleObjects: false,
          ),
        );

  static const Duration _minProcessInterval = Duration(milliseconds: 66);
  static const Duration _fallbackDelay = Duration(seconds: 1);
  static const int _fallbackPatchSize = 32;

  final ObjectDetector _detector;

  CameraImage? _latestFrame;
  int _latestSensorOrientation = 0;

  bool _isCalibrated = false;
  bool _isProcessing = false;

  double _currentDistanceCm = 0.0;
  double _targetDistanceCm = 150.0;
  double _scale = 1.0;

  double _anchorBoundingBoxArea = 0.0;
  double _anchorFrameArea = 0.0;

  Uint8List? _fallbackAnchorPatch;

  String? _warningMessage;
  bool _isUsingFallback = false;

  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCenterObjectAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasAnchor => _isCalibrated;
  bool get isCalibrated => _isCalibrated;
  double get currentDistanceCm => _currentDistanceCm;
  double get currentScale => _scale;
  String? get warningMessage => _warningMessage;
  bool get isUsingFallback => _isUsingFallback;

  void updateLatestFrame(
    CameraImage image, {
    required int sensorOrientation,
  }) {
    _latestFrame = image;
    _latestSensorOrientation = sensorOrientation;

    if (!_isCalibrated || _isProcessing) {
      return;
    }

    final DateTime now = DateTime.now();
    if (now.difference(_lastProcessedAt) < _minProcessInterval) {
      return;
    }

    _isProcessing = true;
    unawaited(_processLatestFrame(now));
  }

  Future<bool> calibrateAtSetPoint({required double targetDistanceCm}) async {
    final CameraImage? frame = _latestFrame;
    if (frame == null) {
      _warningMessage = 'No camera frame available yet.';
      notifyListeners();
      return false;
    }

    final InputImage? inputImage = _toInputImage(frame, _latestSensorOrientation);
    if (inputImage == null) {
      _warningMessage = 'Camera format not supported for ML detection.';
      notifyListeners();
      return false;
    }

    final List<DetectedObject> objects = await _detector.processImage(inputImage);
    final DetectedObject? centerObject = _findCenterObject(objects, frame.width, frame.height);
    if (centerObject == null) {
      _warningMessage = 'Keep object in crosshair';
      notifyListeners();
      return false;
    }

    final Rect box = centerObject.boundingBox;
    _anchorBoundingBoxArea = box.width * box.height;
    _anchorFrameArea = (frame.width * frame.height).toDouble();
    _fallbackAnchorPatch = _extractCenterPatch(frame, _fallbackPatchSize);

    _targetDistanceCm = targetDistanceCm;
    _isCalibrated = true;
    _scale = 1.0;
    _currentDistanceCm = targetDistanceCm;
    _warningMessage = null;
    _isUsingFallback = false;
    _lastCenterObjectAt = DateTime.now();
    _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    return true;
  }

  void clearAnchor() {
    _isCalibrated = false;
    _isProcessing = false;
    _anchorBoundingBoxArea = 0.0;
    _anchorFrameArea = 0.0;
    _fallbackAnchorPatch = null;
    _currentDistanceCm = 0.0;
    _scale = 1.0;
    _warningMessage = null;
    _isUsingFallback = false;
    _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastCenterObjectAt = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
  }

  Future<void> _processLatestFrame(DateTime now) async {
    try {
      final CameraImage? frame = _latestFrame;
      if (frame == null || !_isCalibrated) {
        return;
      }

      final InputImage? inputImage = _toInputImage(frame, _latestSensorOrientation);
      if (inputImage == null) {
        return;
      }

      final List<DetectedObject> objects = await _detector.processImage(inputImage);
      final DetectedObject? centerObject = _findCenterObject(objects, frame.width, frame.height);

      if (centerObject != null && _anchorBoundingBoxArea > 0 && _anchorFrameArea > 0) {
        final Rect box = centerObject.boundingBox;
        final double currentArea = box.width * box.height;
        final double currentFrameArea = (frame.width * frame.height).toDouble();

        final double normalizedCurrent = currentArea / currentFrameArea;
        final double normalizedAnchor = _anchorBoundingBoxArea / _anchorFrameArea;
        _scale = (normalizedCurrent / normalizedAnchor).clamp(0.1, 10.0);
        _currentDistanceCm = _targetDistanceCm / _scale;
        _warningMessage = null;
        _isUsingFallback = false;
        _lastCenterObjectAt = now;
      } else {
        final bool shouldFallback = now.difference(_lastCenterObjectAt) > _fallbackDelay;
        if (shouldFallback && _fallbackAnchorPatch != null) {
          final Uint8List? currentPatch = _extractCenterPatch(frame, _fallbackPatchSize);
          if (currentPatch != null) {
            final double fallbackScale = await compute<Map<String, Uint8List>, double>(
              _scaleWorker,
              <String, Uint8List>{
                'anchor': _fallbackAnchorPatch!,
                'current': currentPatch,
              },
            );
            if (fallbackScale > 0) {
              _scale = fallbackScale.clamp(0.1, 10.0);
              _currentDistanceCm = _targetDistanceCm / _scale;
            }
          }
          _warningMessage = 'Keep object in crosshair';
          _isUsingFallback = true;
        } else {
          _warningMessage = 'Keep object in crosshair';
          _isUsingFallback = false;
        }
      }

      notifyListeners();
    } finally {
      _lastProcessedAt = now;
      _isProcessing = false;
    }
  }

  InputImage? _toInputImage(CameraImage image, int sensorOrientation) {
    final InputImageRotation rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final InputImageFormat? format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      return null;
    }

    final Uint8List bytes = _cameraImageBytes(image);

    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Uint8List _cameraImageBytes(CameraImage image) {
    if (image.planes.length == 1) {
      return image.planes.first.bytes;
    }

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  DetectedObject? _findCenterObject(
    List<DetectedObject> objects,
    int frameWidth,
    int frameHeight,
  ) {
    if (objects.isEmpty) {
      return null;
    }

    final Offset center = Offset(frameWidth / 2, frameHeight / 2);

    for (final DetectedObject object in objects) {
      if (object.boundingBox.contains(center)) {
        return object;
      }
    }

    return null;
  }

  Uint8List? _extractCenterPatch(CameraImage image, int patchSize) {
    if (image.planes.isEmpty) {
      return null;
    }

    final Plane plane = image.planes.first;
    final Uint8List bytes = plane.bytes;
    final int rowStride = plane.bytesPerRow;
    final int width = image.width;
    final int height = image.height;

    final int half = patchSize ~/ 2;
    final int centerX = width ~/ 2;
    final int centerY = height ~/ 2;
    final int left = centerX - half;
    final int top = centerY - half;

    if (left < 0 || top < 0 || left + patchSize > width || top + patchSize > height) {
      return null;
    }

    final Uint8List patch = Uint8List(patchSize * patchSize);
    int index = 0;
    for (int y = 0; y < patchSize; y++) {
      final int srcY = top + y;
      for (int x = 0; x < patchSize; x++) {
        final int srcX = left + x;
        patch[index++] = bytes[srcY * rowStride + srcX];
      }
    }
    return patch;
  }

  @override
  void dispose() {
    _detector.close();
    super.dispose();
  }
}

double _scaleWorker(Map<String, Uint8List> payload) {
  final Uint8List anchor = payload['anchor'] ?? Uint8List(0);
  final Uint8List current = payload['current'] ?? Uint8List(0);
  if (anchor.isEmpty || current.isEmpty) {
    return 1.0;
  }

  final double anchorEnergy = _patchEnergy(anchor);
  final double currentEnergy = _patchEnergy(current);
  if (anchorEnergy <= 0 || currentEnergy <= 0) {
    return 1.0;
  }

  return (currentEnergy / anchorEnergy).clamp(0.1, 10.0);
}

double _patchEnergy(Uint8List patch) {
  if (patch.length < 64) {
    return 1.0;
  }

  final int side = 32;
  double total = 0.0;
  for (int y = 1; y < side; y++) {
    for (int x = 1; x < side; x++) {
      final int i = y * side + x;
      final int dx = (patch[i] - patch[i - 1]).abs();
      final int dy = (patch[i] - patch[i - side]).abs();
      total += dx + dy;
    }
  }

  return total / ((side - 1) * (side - 1));
}
