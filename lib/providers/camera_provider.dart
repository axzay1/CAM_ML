import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/album.dart';
import '../models/captured_image.dart';
import '../services/album_service.dart';
import '../services/depth_service.dart';
import '../services/drive_service.dart';
import '../services/spatial_service.dart';

enum AppState { initial, capture }

class CameraProvider extends ChangeNotifier {
  CameraProvider({
    SpatialService? spatialService,
    AlbumService? albumService,
    DriveService? driveService,
    DepthService? depthService,
  })  : _spatialService = spatialService ?? SpatialService(),
        _albumService = albumService ?? AlbumService(),
        _driveService = driveService ?? DriveService(),
        _depthService = depthService ?? DepthService() {
    _initialize();
  }

  final SpatialService _spatialService;
  final AlbumService _albumService;
  final DriveService _driveService;
  final DepthService _depthService;

  StreamSubscription<Position>? _positionSubscription;

  AppState appState = AppState.initial;
  Album? currentAlbum;
  List<Album> albums = <Album>[];

  double currentDistanceCm = 0.0;
  double currentBearing = 0.0;
  double currentPitch = 0.0;
  double targetDistanceCm = 150.0;

  double currentLatitude = 0.0;
  double currentLongitude = 0.0;

  bool _initialized = false;
  bool get initialized => _initialized;

  String? lastError;
  bool isUploading = false;
  double uploadProgress = 0.0;
  String? lastDriveLink;

  final Set<String> _uploadedAlbumIds = <String>{};

  static const Duration _minUiNotifyInterval = Duration(milliseconds: 66);
  DateTime _lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _notifyTimer;

  double? _referenceScale;
  double? _referenceBearing;
  double? _referencePitch;

  bool get isInPosition {
    if (currentAlbum == null) {
      return false;
    }

    if (currentAlbum!.images.isEmpty) {
      return (currentDistanceCm - targetDistanceCm).abs() <= 10.0;
    }

    if (_referenceScale == null || _referenceBearing == null || _referencePitch == null) {
      return false;
    }

    final bool scaleOk = ((_depthService.currentScale - _referenceScale!).abs() / _referenceScale!) <= 0.08;
    final bool bearingOk = _spatialService.withinBearingTolerance(currentBearing, _referenceBearing!, tolerance: 3.0);
    final bool pitchOk = _spatialService.withinPitchTolerance(currentPitch, _referencePitch!, tolerance: 3.0);
    return scaleOk && bearingOk && pitchOk;
  }

  bool get canUpload => currentAlbum?.isComplete == true;

  bool get hasAnchor => _depthService.hasAnchor;

  bool get hasDepthFrame => _depthService.hasFrame;

  double get currentScale => _depthService.currentScale;

  String? get trackingWarning => _depthService.warningMessage;

  bool get isUsingFallbackTracking => _depthService.isUsingFallback;

  bool get showAngleHeightGuides => currentAlbum != null && currentAlbum!.images.isNotEmpty;

  bool isAlbumUploaded(String albumId) => _uploadedAlbumIds.contains(albumId);

  double get bearingDelta {
    if (currentAlbum == null) {
      return 0.0;
    }
    return _spatialService.bearingDelta(currentBearing, currentAlbum!.anchorBearing);
  }

  double get distanceDelta => currentDistanceCm - targetDistanceCm;

  double get pitchDelta => (_referencePitch == null) ? 0.0 : (currentPitch - _referencePitch!);

  double get scaleDeltaPercent {
    if (_referenceScale == null || _referenceScale == 0) {
      return 0.0;
    }
    return ((_depthService.currentScale - _referenceScale!) / _referenceScale!) * 100.0;
  }

  double get scaleBarNormalized {
    final double delta = (currentDistanceCm - targetDistanceCm) / 200.0;
    return (0.5 + delta).clamp(0.0, 1.0);
  }

  void processCameraFrame(CameraImage image, int sensorOrientation) {
    _depthService.onCameraImage(
      image,
      sensorOrientation: sensorOrientation,
    );
  }

  Future<void> waitForFirstDepthFrame() {
    return _depthService.waitForFirstFrame();
  }

  Future<bool> setDepthPoint() {
    return _depthService.setPoint(targetDistanceCm: targetDistanceCm);
  }

  Future<void> _initialize() async {
    _spatialService.start();
    _spatialService.addListener(_onSpatialChange);
    _depthService.addListener(_onDepthChange);

    await _albumService.init();
    albums = _albumService.getAllAlbums();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      currentLatitude = position.latitude;
      currentLongitude = position.longitude;
      _scheduleNotify();
    });

    _initialized = true;
    _scheduleNotify(immediate: true);
  }

  void _onSpatialChange() {
    currentBearing = _spatialService.currentBearing;
    currentPitch = _spatialService.currentPitch;
    _recomputeSpatialValues();
  }

  void _onDepthChange() {
    _recomputeSpatialValues();
  }

  void _recomputeSpatialValues() {
    if (currentAlbum != null) {
      currentDistanceCm = _depthService.currentDistanceCm;
    } else {
      currentDistanceCm = 0.0;
    }
    _scheduleNotify();
  }

  void _scheduleNotify({bool immediate = false}) {
    if (immediate) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      _lastNotifyAt = DateTime.now();
      notifyListeners();
      return;
    }

    final DateTime now = DateTime.now();
    final Duration elapsed = now.difference(_lastNotifyAt);
    if (elapsed >= _minUiNotifyInterval) {
      _lastNotifyAt = now;
      notifyListeners();
      return;
    }

    if (_notifyTimer != null) {
      return;
    }

    _notifyTimer = Timer(_minUiNotifyInterval - elapsed, () {
      _notifyTimer = null;
      _lastNotifyAt = DateTime.now();
      notifyListeners();
    });
  }

  Future<bool> setPoint(double lat, double lng, double bearing) async {
    final bool anchorReady = await setDepthPoint();
    if (!anchorReady) {
      lastError = _depthService.warningMessage ?? 'No center object detected.';
      _scheduleNotify(immediate: true);
      return false;
    }

    await switchToCaptureState(lat, lng, bearing);
    return true;
  }

  Future<void> switchToCaptureState(double lat, double lng, double bearing) async {

    final Album album = Album(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: 'Album ${albums.length + 1}',
      anchorLat: lat,
      anchorLng: lng,
      anchorBearing: bearing,
      targetDistanceCm: targetDistanceCm,
      images: <CapturedImage>[],
    );

    currentAlbum = album;
    appState = AppState.capture;
    _referenceScale = null;
    _referenceBearing = null;
    _referencePitch = null;

    albums.insert(0, album);
    await _albumService.saveAlbum(album);
    _recomputeSpatialValues();
    _scheduleNotify(immediate: true);
  }

  Future<void> captureImage(CameraController controller) async {
    if (!isInPosition) {
      lastError = 'You are not in position yet. Align distance, bearing, and height.';
      _scheduleNotify(immediate: true);
      throw Exception(lastError);
    }

    if (currentAlbum == null) {
      lastError = 'No active album. Set point first.';
      _scheduleNotify(immediate: true);
      throw Exception(lastError);
    }

    final XFile image = await controller.takePicture();

    final CapturedImage captured = CapturedImage(
      imagePath: image.path,
      latitude: currentLatitude,
      longitude: currentLongitude,
      distanceCm: currentDistanceCm,
      bearingAngle: currentBearing,
      heightDelta: currentPitch,
      timestamp: DateTime.now(),
    );

    if (currentAlbum!.images.isEmpty) {
      _referenceScale = _depthService.currentScale;
      _referenceBearing = currentBearing;
      _referencePitch = currentPitch;
    }

    currentAlbum!.images.add(captured);
    await _albumService.saveAlbum(currentAlbum!);
    lastError = null;
    _scheduleNotify(immediate: true);
  }

  void setTargetDistance(double cm) {
    targetDistanceCm = cm;
    if (currentAlbum != null) {
      currentAlbum = Album(
        id: currentAlbum!.id,
        name: currentAlbum!.name,
        anchorLat: currentAlbum!.anchorLat,
        anchorLng: currentAlbum!.anchorLng,
        anchorBearing: currentAlbum!.anchorBearing,
        targetDistanceCm: cm,
        images: currentAlbum!.images,
      );
      final int index = albums.indexWhere((a) => a.id == currentAlbum!.id);
      if (index != -1) {
        albums[index] = currentAlbum!;
      }
      _albumService.saveAlbum(currentAlbum!);
    }
    _scheduleNotify(immediate: true);
  }

  Future<String> uploadAlbum([Album? album]) async {
    final Album? target = album ?? currentAlbum;
    if (target == null) {
      throw Exception('No album selected.');
    }
    if (!target.isComplete) {
      throw Exception('Album needs at least 4 images before upload.');
    }

    isUploading = true;
    uploadProgress = 0.0;
    lastDriveLink = null;
    _scheduleNotify(immediate: true);

    try {
      final List<File> files = target.images.map((e) => File(e.imagePath)).toList();
      final String link = await _driveService.uploadImages(
        files: files,
        onProgress: (double p) {
          uploadProgress = p;
          _scheduleNotify();
        },
      );
      _uploadedAlbumIds.add(target.id);
      lastDriveLink = link;
      _scheduleNotify(immediate: true);
      return link;
    } finally {
      isUploading = false;
      _scheduleNotify(immediate: true);
    }
  }

  Future<void> deleteAlbum(String id) async {
    await _albumService.deleteAlbum(id);
    albums.removeWhere((album) => album.id == id);
    _uploadedAlbumIds.remove(id);
    if (currentAlbum?.id == id) {
      resetToInitial();
    }
    _scheduleNotify(immediate: true);
  }

  void resetPosition() {
    _depthService.clearAnchor();
    _recomputeSpatialValues();
  }

  void resetToInitial() {
    currentAlbum = null;
    appState = AppState.initial;
    currentDistanceCm = 0.0;
    currentPitch = 0.0;
    _referenceScale = null;
    _referenceBearing = null;
    _referencePitch = null;
    _depthService.clearAnchor();
    _scheduleNotify(immediate: true);
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _positionSubscription?.cancel();
    _spatialService.removeListener(_onSpatialChange);
    _depthService.removeListener(_onDepthChange);
    _spatialService.dispose();
    _depthService.dispose();
    super.dispose();
  }
}
