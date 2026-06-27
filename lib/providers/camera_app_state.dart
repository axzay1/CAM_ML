import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../models/captured_image.dart';
import '../services/location_service.dart';

class PinAlbum {
  PinAlbum({required this.id, required this.name});

  final String id;
  String name;
  final List<CapturedImage> captures = [];
  double? baselineHeight;
  double? baselineAngle;
}

enum PinWorkflowState { normal, setup, running }

class CameraAppState extends ChangeNotifier {
  CameraAppState(this.cameras) {
    albums.add(PinAlbum(id: _createAlbumId(), name: 'Quick captures'));
    activeAlbumId = albums.first.id;
  }

  final List<CameraDescription> cameras;
  final List<CapturedImage> captures = [];
  final List<PinAlbum> albums = [];

  double targetDistanceCm = 150.0;
  double currentDistance = 0.0;
  double currentHeading = 0.0;
  double currentAltitude = 0.0;
  double? pinnedAltitude;
  bool permissionsGranted = false;
  final List<double> _distanceSamples = <double>[];
  String statusMessage = 'Requesting permissions...';
  double currentLatitude = 0.0;
  double currentLongitude = 0.0;
  double currentAccuracy = 0.0;
  double? pinnedLatitude;
  double? pinnedLongitude;
  DateTime? pinCreatedAt;
  DateTime? pinExpiresAt;
  String? activeAlbumId;
  bool autoCapturePending = false;
  bool needsNewPin = false;
  String? pinWarningMessage;
  PinWorkflowState workflowState = PinWorkflowState.normal;
  bool sensorStableForPinPlacement = true;
  bool hasSensorReading = false;
  vm.Vector3? arPinPosition;
  vm.Vector3? arCurrentPosition;
  double? arPinYawDeg;
  double currentApproachYawDeg = 0.0;

  bool get hasPinnedTarget => pinnedLatitude != null && pinnedLongitude != null;

  bool get hasArPin => arPinPosition != null;

  bool get isInitialState => workflowState == PinWorkflowState.normal;

  bool get isCaptureState => workflowState == PinWorkflowState.running;

  bool get isPinExpired =>
      hasPinnedTarget && pinExpiresAt != null && DateTime.now().isAfter(pinExpiresAt!);

  bool get isPinTooFar => hasPinnedTarget && currentDistance > 20.0;

  bool get shouldDiscardPin => hasPinnedTarget && (isPinExpired || isPinTooFar);

  bool get isPinActive => hasPinnedTarget && !shouldDiscardPin;

  double get verticalOffsetMeters => hasPinnedTarget && pinnedAltitude != null ? currentAltitude - pinnedAltitude! : 0.0;

  double get verticalOffsetCm => verticalOffsetMeters * 100.0;

  double get currentDistance3dMeters {
    if (hasArPin) {
      return currentDistance;
    }
    return math.sqrt(currentDistance * currentDistance + verticalOffsetMeters * verticalOffsetMeters);
  }

  double get currentDistance3dCm => currentDistance3dMeters * 100.0;

  bool get isAwaitingTargetDistance => workflowState == PinWorkflowState.setup || (hasPinnedTarget && workflowState == PinWorkflowState.normal);

  bool get canFinishAlbum => activeAlbum != null && activeAlbum!.captures.length >= 4;

  bool get isWithinTolerance {
    if (!isPinActive || targetDistanceCm <= 0) {
      return false;
    }
    return isDistanceReady;
  }

  double get currentDistanceCm => currentDistance * 100.0;

  double get targetDistanceMeters => targetDistanceCm / 100.0;

  double get distanceToleranceCm => targetDistanceCm > 0 ? targetDistanceCm * 0.1 : 0.0;

  double get distanceToleranceMeters => distanceToleranceCm / 100.0;

  bool get isDistanceReady {
    if (!isPinActive || targetDistanceCm <= 0 || _distanceSamples.length < 3) {
      return false;
    }

    final averageDistance = _distanceSamples.reduce((a, b) => a + b) / _distanceSamples.length;
    final variance = _distanceSamples.fold<double>(0.0, (sum, value) {
      final diff = value - averageDistance;
      return sum + diff * diff;
    }) / _distanceSamples.length;
    final inRange = (averageDistance - targetDistanceMeters).abs() <= distanceToleranceMeters;
    final steady = variance <= math.max(0.5, distanceToleranceMeters * 0.25);
    return inRange && steady;
  }

  bool get canCaptureNow {
    if (!isPinActive || workflowState != PinWorkflowState.running || !isDistanceReady) {
      return false;
    }

    if (!hasCaptureBaseline) {
      return true;
    }

    final heightOk = (currentAltitude - activeAlbum!.baselineHeight!).abs() <= 0.5;
    final angleOk = _angleDifference(currentHeading, activeAlbum!.baselineAngle!) <= 10.0;
    return heightOk && angleOk;
  }

  bool get hasCaptureBaseline => activeAlbum != null && activeAlbum!.baselineHeight != null && activeAlbum!.baselineAngle != null;

  bool get isCaptureCriteriaMet {
    if (!isPinActive || !hasCaptureBaseline || activeAlbum == null || workflowState != PinWorkflowState.running) {
      return false;
    }

    final distanceTolerance = distanceToleranceMeters;
    final heightTolerance = 0.5;
    final angleTolerance = 10.0;
    final distanceOk = (currentDistance - targetDistanceMeters).abs() <= distanceTolerance;
    final heightOk = (currentAltitude - activeAlbum!.baselineHeight!).abs() <= heightTolerance;
    final angleOk = _angleDifference(currentHeading, activeAlbum!.baselineAngle!) <= angleTolerance;
    return distanceOk && heightOk && angleOk;
  }

  double _angleDifference(double a, double b) {
    final difference = (a - b).abs();
    return difference > 180 ? 360 - difference : difference;
  }

  String get pinStatusLabel {
    if (!hasPinnedTarget) {
      return 'No pin';
    }
    if (isPinExpired) {
      return 'Expired';
    }
    if (isPinTooFar) {
      return 'Too far';
    }
    return 'Active 5 min';
  }

  PinAlbum? get activeAlbum {
    if (activeAlbumId == null) {
      return null;
    }
    for (final album in albums) {
      if (album.id == activeAlbumId) {
        return album;
      }
    }
    return null;
  }

  void updatePermissions(bool granted) {
    permissionsGranted = granted;
    statusMessage = granted ? 'Permissions granted' : 'Permissions required';
    notifyListeners();
  }

  void setStatusMessage(String message) {
    statusMessage = message;
    notifyListeners();
  }

  void setTargetDistance(double value) {
    targetDistanceCm = value;
    notifyListeners();
  }

  void updateArPose(vm.Matrix4 pose) {
    final position = pose.getTranslation();
    arCurrentPosition = position;

    currentApproachYawDeg = _extractYawDegrees(pose);
    currentHeading = currentApproachYawDeg;
    currentAltitude = position.y;

    if (arPinPosition != null) {
      final delta = position - arPinPosition!;
      final rawDistance = delta.length;
      _distanceSamples.add(rawDistance);
      if (_distanceSamples.length > 5) {
        _distanceSamples.removeAt(0);
      }
      currentDistance = _distanceSamples.reduce((a, b) => a + b) / _distanceSamples.length;

      if (isDistanceReady && !autoCapturePending) {
        autoCapturePending = true;
      }
    }

    if (workflowState == PinWorkflowState.running && !autoCapturePending && canCaptureNow) {
      autoCapturePending = true;
    }

    notifyListeners();
  }

  double _extractYawDegrees(vm.Matrix4 pose) {
    final fwd = vm.Vector3(pose.entry(0, 2), pose.entry(1, 2), pose.entry(2, 2));
    final yawRadians = math.atan2(fwd.x, fwd.z);
    var yaw = yawRadians * 180.0 / math.pi;
    if (yaw < 0) {
      yaw += 360.0;
    }
    return yaw;
  }

  void updatePosition(double latitude, double longitude, {double? altitude, double? accuracy}) {
    currentLatitude = latitude;
    currentLongitude = longitude;
    if (accuracy != null) {
      currentAccuracy = accuracy;
    }
    if (altitude != null) {
      currentAltitude = altitude;
    }

    if (hasPinnedTarget && !hasArPin) {
      final rawDistance = LocationService.calculateDistanceHaversine(
        currentLatitude,
        currentLongitude,
        pinnedLatitude!,
        pinnedLongitude!,
      );
      _distanceSamples.add(rawDistance);
      if (_distanceSamples.length > 5) {
        _distanceSamples.removeAt(0);
      }
      currentDistance = _distanceSamples.reduce((a, b) => a + b) / _distanceSamples.length;

      if (shouldDiscardPin) {
        invalidatePinnedTarget('Pin moved too far away. Please create a new pin.');
        return;
      }

      if (isDistanceReady && !autoCapturePending) {
        autoCapturePending = true;
      }
    }

    if (workflowState == PinWorkflowState.running && !autoCapturePending && canCaptureNow) {
      autoCapturePending = true;
    }

    notifyListeners();
  }

  void updateHeading(double heading) {
    currentHeading = heading;
    notifyListeners();
  }

  void consumeAutoCapture() {
    autoCapturePending = false;
    notifyListeners();
  }

  void clearPinWarning() {
    needsNewPin = false;
    pinWarningMessage = null;
    notifyListeners();
  }

  void invalidatePinnedTarget(String message) {
    pinnedLatitude = null;
    pinnedLongitude = null;
    pinnedAltitude = null;
    pinCreatedAt = null;
    pinExpiresAt = null;
    needsNewPin = true;
    pinWarningMessage = message;
    statusMessage = message;
    notifyListeners();
  }

  void enterSetupState() {
    workflowState = PinWorkflowState.setup;
    notifyListeners();
  }

  void enterRunningState() {
    workflowState = PinWorkflowState.running;
    notifyListeners();
  }

  void resetWorkflowState() {
    workflowState = PinWorkflowState.normal;
    pinnedLatitude = null;
    pinnedLongitude = null;
    pinnedAltitude = null;
    pinCreatedAt = null;
    pinExpiresAt = null;
    autoCapturePending = false;
    needsNewPin = false;
    pinWarningMessage = null;
    currentDistance = 0.0;
    _distanceSamples.clear();
    arPinPosition = null;
    arCurrentPosition = null;
    arPinYawDeg = null;
    currentApproachYawDeg = 0.0;
    sensorStableForPinPlacement = true;
    hasSensorReading = false;
    statusMessage = 'Ready to start a new pin.';
    notifyListeners();
  }

  bool get canSetPinWithCurrentSensorState => !hasSensorReading || sensorStableForPinPlacement;

  void updateSensorStability(double accelerationMagnitude) {
    hasSensorReading = true;
    sensorStableForPinPlacement = LocationService.isSensorStable(accelerationMagnitude);
    if (!sensorStableForPinPlacement && workflowState == PinWorkflowState.normal) {
      statusMessage = 'Hold still to set a pin';
    }
    notifyListeners();
  }

  void pinTargetLocation() {
    if (!canSetPinWithCurrentSensorState && hasSensorReading) {
      statusMessage = 'Hold still for a moment before setting the pin.';
    }

    if (!LocationService.hasReliableGps(accuracy: currentAccuracy)) {
      statusMessage = 'GPS accuracy is poor. Pin set with a weaker fix.';
    }

    pinnedLatitude = currentLatitude;
    pinnedLongitude = currentLongitude;
    pinnedAltitude = currentAltitude;
    pinCreatedAt = DateTime.now();
    pinExpiresAt = pinCreatedAt!.add(const Duration(minutes: 5));
    needsNewPin = false;
    pinWarningMessage = null;
    autoCapturePending = false;
    workflowState = PinWorkflowState.running;

    final newAlbum = PinAlbum(
      id: _createAlbumId(),
      name: 'Pin ${albums.length + 1}',
    );
    albums.insert(0, newAlbum);
    activeAlbumId = newAlbum.id;

    final rawDistance = LocationService.calculateDistanceHaversine(
      currentLatitude,
      currentLongitude,
      pinnedLatitude!,
      pinnedLongitude!,
    );
    _distanceSamples.clear();
    _distanceSamples.add(rawDistance);
    currentDistance = rawDistance;
    statusMessage = 'Pin created. Keep it within 20 m for 5 minutes.';
    notifyListeners();
  }

  void createPinAndEnterSetup() {
    if (!canSetPinWithCurrentSensorState && hasSensorReading) {
      statusMessage = 'Hold still for a moment before setting the pin.';
    }

    if (!LocationService.hasReliableGps(accuracy: currentAccuracy)) {
      statusMessage = 'GPS accuracy is poor. Pin set with a weaker fix.';
    }

    pinnedLatitude = currentLatitude;
    pinnedLongitude = currentLongitude;
    pinnedAltitude = currentAltitude;
    pinCreatedAt = DateTime.now();
    pinExpiresAt = pinCreatedAt!.add(const Duration(minutes: 5));
    needsNewPin = false;
    pinWarningMessage = null;
    autoCapturePending = false;
    workflowState = PinWorkflowState.setup;

    final newAlbum = PinAlbum(
      id: _createAlbumId(),
      name: 'Pin ${albums.length + 1}',
    );
    albums.insert(0, newAlbum);
    activeAlbumId = newAlbum.id;

    final rawDistance = LocationService.calculateDistanceHaversine(
      currentLatitude,
      currentLongitude,
      pinnedLatitude!,
      pinnedLongitude!,
    );
    _distanceSamples.clear();
    _distanceSamples.add(rawDistance);
    currentDistance = rawDistance;
    statusMessage = 'Pin set. Choose the target distance.';
    notifyListeners();
  }

  void setArPointAndStartAlbum() {
    if (arCurrentPosition == null) {
      statusMessage = 'Move device to initialize AR tracking, then set point.';
      notifyListeners();
      return;
    }

    pinnedLatitude = currentLatitude;
    pinnedLongitude = currentLongitude;
    pinnedAltitude = arCurrentPosition!.y;
    arPinPosition = vm.Vector3.copy(arCurrentPosition!);
    arPinYawDeg = currentApproachYawDeg;
    pinCreatedAt = DateTime.now();
    pinExpiresAt = pinCreatedAt!.add(const Duration(minutes: 5));
    needsNewPin = false;
    pinWarningMessage = null;
    autoCapturePending = false;
    workflowState = PinWorkflowState.running;

    final newAlbum = PinAlbum(
      id: _createAlbumId(),
      name: 'Album ${albums.length + 1}',
    );
    albums.insert(0, newAlbum);
    activeAlbumId = newAlbum.id;

    _distanceSamples.clear();
    currentDistance = 0.0;
    statusMessage = 'AR point set. Move to target distance and capture 4+ images.';
    notifyListeners();
  }

  Future<void> finishActiveAlbum() async {
    if (activeAlbum == null || !canFinishAlbum) {
      return;
    }

    final albumDirectory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory('${albumDirectory.path}/CAM_ML_exports/${activeAlbum!.id}');
    if (!await exportDirectory.exists()) {
      await exportDirectory.create(recursive: true);
    }

    for (final capture in activeAlbum!.captures) {
      final sourceFile = File(capture.path);
      if (await sourceFile.exists()) {
        await sourceFile.copy('${exportDirectory.path}/${sourceFile.uri.pathSegments.last}');
      }
    }

    final archive = Archive();
    final files = exportDirectory.listSync(recursive: true).whereType<File>();
    for (final file in files) {
      final relativePath = file.path.replaceFirst('${exportDirectory.path}/', '');
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
    }

    final archiveBytes = ZipEncoder().encode(archive);

    final archivePath = '${albumDirectory.path}/CAM_ML_exports/${activeAlbum!.id}.zip';
    final archiveFile = File(archivePath);
    await archiveFile.writeAsBytes(archiveBytes);

    const sharedDriveOwner = 'akshayscamml@gmail.com';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(archivePath)],
        subject: 'CAM_ML album: ${activeAlbum!.name}',
        text: 'Album exported from CAM_ML for $sharedDriveOwner. Please place this archive in the shared Google Drive for $sharedDriveOwner.',
      ),
    );

    workflowState = PinWorkflowState.normal;
    statusMessage = 'Album exported for $sharedDriveOwner.';
    notifyListeners();
  }

  void renameAlbum(String albumId, String newName) {
    for (final album in albums) {
      if (album.id == albumId) {
        album.name = newName.trim().isEmpty ? album.name : newName.trim();
        notifyListeners();
        return;
      }
    }
  }

  Future<void> addCapture(String sourcePath) async {
    if (!permissionsGranted) {
      return;
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    final imagesDirectory = Directory('${appDocDir.path}/CAM_ML_captures');
    if (!await imagesDirectory.exists()) {
      await imagesDirectory.create(recursive: true);
    }

    final newPath = '${imagesDirectory.path}/capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final originalFile = File(sourcePath);
    final bytes = await originalFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);

    if (decodedImage != null) {
      final cropSize = decodedImage.width < decodedImage.height ? decodedImage.width : decodedImage.height;
      final x = (decodedImage.width - cropSize) ~/ 2;
      final y = (decodedImage.height - cropSize) ~/ 2;
      final squareImage = img.copyCrop(decodedImage, x: x, y: y, width: cropSize, height: cropSize);
      final encodedBytes = img.JpegEncoder(quality: 90).encode(squareImage);
      await File(newPath).writeAsBytes(encodedBytes);
    } else {
      await originalFile.copy(newPath);
    }

    final metadataPath = '$newPath.json';
    final metadata = {
      'latitude': currentLatitude,
      'longitude': currentLongitude,
      'height': currentAltitude,
      'pinLatitude': pinnedLatitude,
      'pinLongitude': pinnedLongitude,
      'pinHeight': pinnedAltitude,
      'zOffset': verticalOffsetMeters,
      'distance': currentDistance,
      'distance3d': currentDistance3dMeters,
      'approachYaw': currentApproachYawDeg,
      'angle': currentHeading,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    await File(metadataPath).writeAsString(jsonEncode(metadata));

    final album = activeAlbum ?? albums.first;
    if (album.captures.isEmpty) {
      album.baselineHeight = currentAltitude;
      album.baselineAngle = currentApproachYawDeg;
    }

    final capture = CapturedImage(
      path: newPath,
      latitude: currentLatitude,
      longitude: currentLongitude,
      distance: currentDistance,
      angle: currentApproachYawDeg,
      timestamp: DateTime.now(),
      albumId: album.id,
      albumName: album.name,
    );

    captures.insert(0, capture);
    album.captures.insert(0, capture);
    notifyListeners();
  }

  String _createAlbumId() => 'album_${DateTime.now().microsecondsSinceEpoch}';
}
