import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/album.dart';
import '../models/captured_image.dart';
import '../services/album_service.dart';
import '../services/drive_service.dart';
import '../services/spatial_service.dart';

enum AppState { initial, capture }

class CameraProvider extends ChangeNotifier {
  CameraProvider({
    SpatialService? spatialService,
    AlbumService? albumService,
    DriveService? driveService,
  })  : _spatialService = spatialService ?? SpatialService(),
        _albumService = albumService ?? AlbumService(),
        _driveService = driveService ?? DriveService() {
    _initialize();
  }

  final SpatialService _spatialService;
  final AlbumService _albumService;
  final DriveService _driveService;

  StreamSubscription<Position>? _positionSubscription;

  AppState appState = AppState.initial;
  Album? currentAlbum;
  List<Album> albums = <Album>[];

  double currentDistanceCm = 0.0;
  double currentBearing = 0.0;
  double currentHeightDelta = 0.0;
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

  bool get isInPosition {
    if (currentAlbum == null) {
      return false;
    }
    return _spatialService.isInPosition(
      currentDistanceCm: currentDistanceCm,
      targetDistanceCm: targetDistanceCm,
      currentBearing: currentBearing,
      anchorBearing: currentAlbum!.anchorBearing,
      currentHeightDelta: currentHeightDelta,
    );
  }

  bool get canUpload => currentAlbum?.isComplete == true;

  bool get isCalibrating => _spatialService.isCalibrating;

  bool get shouldShowDriftWarning => appState == AppState.capture && _spatialService.shouldRecommendReset;

  bool isAlbumUploaded(String albumId) => _uploadedAlbumIds.contains(albumId);

  double get bearingDelta {
    if (currentAlbum == null) {
      return 0.0;
    }
    return _spatialService.bearingDelta(currentBearing, currentAlbum!.anchorBearing);
  }

  double get distanceDelta => currentDistanceCm - targetDistanceCm;

  Future<void> _initialize() async {
    _spatialService.start();
    _spatialService.addListener(_onSpatialChange);

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
      notifyListeners();
    });

    _initialized = true;
    notifyListeners();
  }

  void _onSpatialChange() {
    currentBearing = _spatialService.currentBearing;
    _recomputeSpatialValues();
  }

  void _recomputeSpatialValues() {
    if (currentAlbum != null) {
      currentDistanceCm = _spatialService.distanceCm;
      currentHeightDelta = _spatialService.heightDeltaCm;
    } else {
      currentDistanceCm = 0.0;
      currentHeightDelta = 0.0;
    }
    notifyListeners();
  }

  Future<void> setPoint(double lat, double lng, double bearing) async {
    await _spatialService.calibrateAtSetPoint();

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

    albums.insert(0, album);
    await _albumService.saveAlbum(album);
    _recomputeSpatialValues();
  }

  Future<void> captureImage(CameraController controller) async {
    if (!isInPosition) {
      lastError = 'You are not in position yet. Align distance, bearing, and height.';
      notifyListeners();
      throw Exception(lastError);
    }

    if (currentAlbum == null) {
      lastError = 'No active album. Set point first.';
      notifyListeners();
      throw Exception(lastError);
    }

    final XFile image = await controller.takePicture();

    final CapturedImage captured = CapturedImage(
      imagePath: image.path,
      latitude: currentLatitude,
      longitude: currentLongitude,
      distanceCm: currentDistanceCm,
      bearingAngle: currentBearing,
      heightDelta: currentHeightDelta,
      timestamp: DateTime.now(),
    );

    currentAlbum!.images.add(captured);
    await _albumService.saveAlbum(currentAlbum!);
    lastError = null;
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();

    try {
      final List<File> files = target.images.map((e) => File(e.imagePath)).toList();
      final String link = await _driveService.uploadImages(
        files: files,
        onProgress: (double p) {
          uploadProgress = p;
          notifyListeners();
        },
      );
      _uploadedAlbumIds.add(target.id);
      lastDriveLink = link;
      notifyListeners();
      return link;
    } finally {
      isUploading = false;
      notifyListeners();
    }
  }

  Future<void> deleteAlbum(String id) async {
    await _albumService.deleteAlbum(id);
    albums.removeWhere((album) => album.id == id);
    _uploadedAlbumIds.remove(id);
    if (currentAlbum?.id == id) {
      resetToInitial();
    }
    notifyListeners();
  }

  void resetPosition() {
    _spatialService.resetPosition();
    _recomputeSpatialValues();
  }

  void resetToInitial() {
    currentAlbum = null;
    appState = AppState.initial;
    currentDistanceCm = 0.0;
    currentHeightDelta = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _spatialService.removeListener(_onSpatialChange);
    _spatialService.dispose();
    super.dispose();
  }
}
