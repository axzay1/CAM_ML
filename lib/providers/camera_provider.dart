import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/album.dart';
import '../models/captured_image.dart';
import '../models/plot_point.dart';
import '../services/album_service.dart';
import '../services/depth_service.dart';
import '../services/drive_service.dart';
import '../services/location_service.dart';
import '../services/plot_service.dart';
import '../services/position_check_service.dart';

enum AppState { initial, p1, capture }

class CameraProvider extends ChangeNotifier {
  CameraProvider({
    DepthService? depthService,
    AlbumService? albumService,
    DriveService? driveService,
    LocationService? locationService,
  })  : depthService = depthService ?? DepthService(),
        albumService = albumService ?? AlbumService(),
        driveService = driveService ?? DriveService(),
        locationService = locationService ?? LocationService() {
    _initialize();
  }

  // ── Services ──────────────────────────────────────────────────────────────
  final DepthService depthService;
  final LocationService locationService;
  final AlbumService albumService;
  final DriveService driveService;
  final PlotService _plotService = PlotService();
  final PositionCheckService _positionCheck = PositionCheckService();

  // ── Sensor subscriptions ──────────────────────────────────────────────────
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _positionSub;

  // ── App state ─────────────────────────────────────────────────────────────
  AppState _appState = AppState.initial;
  AppState get appState => _appState;

  // ── User inputs ───────────────────────────────────────────────────────────
  int _pointsPerLayer = 4;
  int _numberOfLayers = 1;
  int get pointsPerLayer => _pointsPerLayer;
  int get numberOfLayers => _numberOfLayers;
  int get totalPoints => _pointsPerLayer * _numberOfLayers;

  void setPointsPerLayer(int v) {
    assert(v == 4 || v == 8 || v == 12);
    _pointsPerLayer = v;
    _scheduleNotify();
  }

  void setNumberOfLayers(int v) {
    assert(v >= 1 && v <= 4);
    _numberOfLayers = v;
    _scheduleNotify();
  }

  // ── Anchor ────────────────────────────────────────────────────────────────
  double _anchorLat = 0;
  double _anchorLng = 0;
  double _anchorBearing = 0;

  // ── P1 sphere definition (null until P1 is shot) ──────────────────────────
  double? _p1DistanceCm;
  double? _p1AzimuthDeg;
  double? _p1ElevationDeg;
  double? get sphereRadiusCm => _p1DistanceCm;

  // ── Current album ─────────────────────────────────────────────────────────
  Album? _currentAlbum;
  Album? get currentAlbum => _currentAlbum;

  // ── Albums list (for AlbumScreen) ─────────────────────────────────────────
  List<Album> albums = <Album>[];

  // ── Live sensor readings ──────────────────────────────────────────────────
  double _currentBearing = 0.0;
  double _currentPitch = 0.0;
  double _currentLatitude = 0.0;
  double _currentLongitude = 0.0;

  double get currentBearing => _currentBearing;
  double get currentPitch => _currentPitch;
  double get currentLatitude => _currentLatitude;
  double get currentLongitude => _currentLongitude;

  // ── Init flag ─────────────────────────────────────────────────────────────
  bool _initialized = false;
  bool get initialized => _initialized;

  // ── Upload state (used by AlbumScreen) ───────────────────────────────────
  bool isUploading = false;
  double uploadProgress = 0.0;
  String? lastDriveLink;
  final Set<String> _uploadedAlbumIds = <String>{};

  // ── UI notify throttle ────────────────────────────────────────────────────
  static const Duration _minUiNotifyInterval = Duration(milliseconds: 66);
  DateTime _lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _notifyTimer;

  // ── Plot points ───────────────────────────────────────────────────────────
  List<PlotPoint> get plotPoints =>
      _currentAlbum?.plotPoints ?? <PlotPoint>[];

  PlotPoint? get activePlotPoint => _currentAlbum?.activePoint;

  int get capturedCount => plotPoints.where((p) => p.isCaptured).length;

  bool get albumComplete => _currentAlbum?.isComplete ?? false;

  // ── Position check ────────────────────────────────────────────────────────
  PositionStatus? get positionStatus {
    if (_appState != AppState.capture) return null;
    final PlotPoint? target = activePlotPoint;
    if (target == null) return null;
    return _positionCheck.check(
      target: target,
      currentDistanceCm: depthService.currentDistanceCm,
      currentBearingDeg: _currentBearing,
      currentPitchDeg: _currentPitch,
    );
  }

  bool get isInPosition {
    if (_appState == AppState.p1) return true;
    return positionStatus?.allOK ?? false;
  }

  // ── Depth frame passthrough ───────────────────────────────────────────────
  bool get hasDepthFrame => depthService.hasFrame;
  bool get hasAnchor => depthService.hasAnchor;
  String? get trackingWarning => depthService.warningMessage;
  bool get isUsingFallbackTracking => depthService.isUsingFallback;
  double get currentDistanceCm => depthService.currentDistanceCm;

  bool isAlbumUploaded(String albumId) => _uploadedAlbumIds.contains(albumId);

  void processCameraFrame(CameraImage image, int sensorOrientation) {
    depthService.onCameraImage(image, sensorOrientation: sensorOrientation);
  }

  Future<void> waitForFirstDepthFrame() => depthService.waitForFirstFrame();

  // ── Initialization ────────────────────────────────────────────────────────
  Future<void> _initialize() async {
    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      final double? heading = event.heading;
      if (heading == null) return;
      final double next = _normalizeDegrees(heading);
      if ((_currentBearing - next).abs() < 0.5) return;
      _currentBearing = next;
      _scheduleNotify();
    });

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((AccelerometerEvent event) {
      final double next =
          math.atan2(event.y, event.z) * 180 / math.pi;
      if ((_currentPitch - next).abs() < 0.25) return;
      _currentPitch = next;
      _scheduleNotify();
    });

    depthService.addListener(_onDepthChange);

    await albumService.init();
    albums = albumService.getAllAlbums();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      _currentLatitude = position.latitude;
      _currentLongitude = position.longitude;
      _scheduleNotify();
    });

    _initialized = true;
    _scheduleNotify(immediate: true);
  }

  void _onDepthChange() {
    _scheduleNotify();
  }

  // ── SET POINT ─────────────────────────────────────────────────────────────
  Future<bool> setPoint() async {
    if (!depthService.hasFrame) return false;

    _anchorLat = _currentLatitude;
    _anchorLng = _currentLongitude;
    _anchorBearing = _currentBearing;

    // 150 cm is the tracking reference; actual sphere radius comes from P1.
    final bool ok = await depthService.setPoint(targetDistanceCm: 150);
    if (!ok) return false;

    _p1DistanceCm = null;
    _p1AzimuthDeg = null;
    _p1ElevationDeg = null;

    _currentAlbum = Album(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Album ${DateTime.now().toIso8601String()}',
      anchorLatitude: _anchorLat,
      anchorLongitude: _anchorLng,
      anchorBearing: _anchorBearing,
      pointsPerLayer: _pointsPerLayer,
      numberOfLayers: _numberOfLayers,
    );

    albums.insert(0, _currentAlbum!);

    _appState = AppState.p1;
    _scheduleNotify(immediate: true);
    return true;
  }

  // ── CAPTURE IMAGE ─────────────────────────────────────────────────────────
  Future<void> captureImage(CameraController ctrl) async {
    if (_appState == AppState.p1) {
      // P1: no position check — shoot freely.
      final XFile file = await ctrl.takePicture();

      _p1DistanceCm = depthService.currentDistanceCm;
      _p1AzimuthDeg = _currentBearing;
      _p1ElevationDeg = _currentPitch;

      final CapturedImage img = CapturedImage(
        imagePath: file.path,
        latitude: _currentLatitude,
        longitude: _currentLongitude,
        distanceCm: _p1DistanceCm!,
        bearingAngle: _p1AzimuthDeg!,
        heightDelta: _p1ElevationDeg!,
        timestamp: DateTime.now(),
      );
      _currentAlbum!.images.add(img);

      // Generate all sphere points from P1.
      _currentAlbum!.plotPoints = _plotService.generatePoints(
        pointsPerLayer: _pointsPerLayer,
        numberOfLayers: _numberOfLayers,
        p1AzimuthDeg: _p1AzimuthDeg!,
        p1ElevationDeg: _p1ElevationDeg!,
        p1DistanceCm: _p1DistanceCm!,
      );

      // P1 is index 0, already marked captured; next active = index 1.
      _currentAlbum!.currentPointIndex = 1;

      await albumService.saveAlbum(_currentAlbum!);
      _appState = AppState.capture;
      _scheduleNotify(immediate: true);
      return;
    }

    if (_appState == AppState.capture) {
      // P2+: position check required.
      final PositionStatus? status = positionStatus;
      if (status == null || !status.allOK) {
        throw Exception('Not in position');
      }

      final XFile file = await ctrl.takePicture();
      final CapturedImage img = CapturedImage(
        imagePath: file.path,
        latitude: _currentLatitude,
        longitude: _currentLongitude,
        distanceCm: depthService.currentDistanceCm,
        bearingAngle: _currentBearing,
        heightDelta: _currentPitch,
        timestamp: DateTime.now(),
      );
      _currentAlbum!.images.add(img);

      final int idx = _currentAlbum!.currentPointIndex;
      _currentAlbum!.plotPoints[idx].isCaptured = true;

      // Advance to next uncaptured point.
      final int next = _currentAlbum!.plotPoints
          .indexWhere((p) => !p.isCaptured, idx + 1);
      if (next != -1) {
        _currentAlbum!.currentPointIndex = next;
      }

      await albumService.saveAlbum(_currentAlbum!);
      _scheduleNotify(immediate: true);
    }
  }

  // ── UPLOAD ────────────────────────────────────────────────────────────────
  Future<String> uploadAlbum([Album? album]) async {
    final Album? target = album ?? _currentAlbum;
    if (target == null) throw Exception('No album selected.');
    if (!target.isComplete) throw Exception('Album is not complete.');

    isUploading = true;
    uploadProgress = 0.0;
    lastDriveLink = null;
    _scheduleNotify(immediate: true);

    try {
      final List<File> files =
          target.images.map((e) => File(e.imagePath)).toList();
      final String link = await driveService.uploadImages(
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

  // ── DELETE ALBUM ──────────────────────────────────────────────────────────
  Future<void> deleteAlbum(String id) async {
    await albumService.deleteAlbum(id);
    albums.removeWhere((a) => a.id == id);
    _uploadedAlbumIds.remove(id);
    if (_currentAlbum?.id == id) {
      resetToInitial();
    }
    _scheduleNotify(immediate: true);
  }

  // ── RESET ─────────────────────────────────────────────────────────────────
  void resetToInitial() {
    _appState = AppState.initial;
    _currentAlbum = null;
    _p1DistanceCm = null;
    _p1AzimuthDeg = null;
    _p1ElevationDeg = null;
    depthService.clearAnchor();
    _scheduleNotify(immediate: true);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
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

    if (_notifyTimer != null) return;

    _notifyTimer = Timer(_minUiNotifyInterval - elapsed, () {
      _notifyTimer = null;
      _lastNotifyAt = DateTime.now();
      notifyListeners();
    });
  }

  double _normalizeDegrees(double angle) {
    final double normalized = angle % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _positionSub?.cancel();
    depthService.removeListener(_onDepthChange);
    depthService.dispose();
    super.dispose();
  }
}
