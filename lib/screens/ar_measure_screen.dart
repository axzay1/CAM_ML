import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class ArMeasureResult {
  const ArMeasureResult({required this.distanceCm, required this.zOffsetCm});

  final double distanceCm;
  final double zOffsetCm;
}

class ArMeasureScreen extends StatefulWidget {
  const ArMeasureScreen({super.key});

  @override
  State<ArMeasureScreen> createState() => _ArMeasureScreenState();
}

class _ArMeasureScreenState extends State<ArMeasureScreen> {
  ARSessionManager? _arSessionManager;
  vector.Vector3? _pinPoint;
  double? _distanceCm;
  double? _zOffsetCm;
  String _status = 'Tap a detected plane to set AR pin';
  bool _isSupported = true;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      _isSupported = false;
      _status = 'AR measurement is not supported on this platform.';
    }
  }

  void _onArViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;

    arSessionManager.onInitialize(
      showAnimatedGuide: true,
      showFeaturePoints: true,
      showPlanes: true,
      handleTaps: true,
    );
    arObjectManager.onInitialize();
    arSessionManager.onPlaneOrPointTap = _handlePlaneTap;
  }

  Future<void> _handlePlaneTap(List<ARHitTestResult> hits) async {
    if (hits.isEmpty) {
      return;
    }

    final tappedPoint = hits.first.worldTransform.getTranslation();
    if (_pinPoint == null) {
      _pinPoint = tappedPoint;
      setState(() {
        _status = 'Pin set. Move and tap again at capture position.';
      });
      return;
    }

    final dx = tappedPoint.x - _pinPoint!.x;
    final dy = tappedPoint.y - _pinPoint!.y;
    final dz = tappedPoint.z - _pinPoint!.z;
    final distance = math.sqrt(dx * dx + dy * dy + dz * dz);

    setState(() {
      _distanceCm = distance * 100.0;
      _zOffsetCm = dy * 100.0;
      _status = 'Measurement updated. Tap Use measurement to apply.';
    });
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceText = _distanceCm == null
        ? '--'
        : _distanceCm!.toStringAsFixed(0);
    final zText = _zOffsetCm == null
        ? '--'
        : _zOffsetCm!.toStringAsFixed(0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AR Measure'),
        actions: [
          TextButton(
            onPressed: _distanceCm == null
                ? null
                : () {
                    Navigator.of(context).pop(
                      ArMeasureResult(
                        distanceCm: _distanceCm!,
                        zOffsetCm: _zOffsetCm ?? 0.0,
                      ),
                    );
                  },
            child: const Text('Use measurement'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isSupported
                ? ARView(
                    onARViewCreated: _onArViewCreated,
                    planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            color: const Color(0xFF111827),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _status,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  '3D distance: $distanceText cm   Z offset: $zText cm',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
