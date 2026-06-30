import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'camera_screen.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _ctrl = PageController();
  int _page = 0;

  static const int _total = 5;
  static const _kCyan = Color(0xFF00BCD4);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final box = await Hive.openBox<dynamic>('cam_ml_prefs');
    await box.put('tutorial_seen', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, _, _) => const CameraScreen(),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ));
  }

  void _next() {
    if (_page < _total - 1) {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1F),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CAM ML',
                    style: TextStyle(
                      color: _kCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 2,
                    ),
                  ),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('Skip',
                        style: TextStyle(color: Colors.white38, fontSize: 14)),
                  ),
                ],
              ),
            ),

            // ── Pages ─────────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _TutPage(
                    painter: _SpherePainter(),
                    title: 'Meet CAM ML',
                    body:
                        'Capture any object from every angle — the app guides you around a virtual sphere so no shot is missed.',
                  ),
                  _TutPage(
                    painter: _SetPointPainter(),
                    title: 'Point & Set',
                    body:
                        'Aim your camera at the object and tap Set Point. This anchors the centre of the capture sphere.',
                  ),
                  _TutPage(
                    painter: _ShootP1Painter(),
                    title: 'Shoot P1',
                    body:
                        'Walk up to the object and take the first photo. P1 sets the capture distance for all remaining shots.',
                  ),
                  _TutPage(
                    painter: _FollowDotsPainter(),
                    title: 'Follow the Dots',
                    body:
                        'Move to each floating ring. When bearing, pitch, and distance all turn green — the shot fires automatically.',
                  ),
                  _TutPage(
                    painter: _DonePainter(),
                    title: 'Review & Upload',
                    body:
                        'Tap Done when all shots are captured. Open Albums to review and upload your spherical capture.',
                  ),
                ],
              ),
            ),

            // ── Progress dots ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_total, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  width: i == _page ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? _kCyan : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // ── Next / Start button ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kCyan,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    _page == _total - 1 ? 'Start Capturing' : 'Next',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page wrapper ──────────────────────────────────────────────────────────────

class _TutPage extends StatelessWidget {
  const _TutPage(
      {required this.painter, required this.title, required this.body});
  final CustomPainter painter;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: CustomPaint(
                painter: painter,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: const TextStyle(
                color: Colors.white60, fontSize: 15, height: 1.55),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

// Page 1: Sphere wireframe (the app's core concept)
class _SpherePainter extends CustomPainter {
  const _SpherePainter();

  static const _cyan = Color(0xFF00BCD4);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(size.width, size.height) * 0.38;
    const pf = 0.30;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy),
      R + 14,
      Paint()
        ..color = _cyan.withValues(alpha: 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );

    // Sphere silhouette
    canvas.drawCircle(
        Offset(cx, cy),
        R,
        Paint()
          ..color = _cyan.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    // Secondary meridian
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy), width: R * 1.41, height: R * 2),
        Paint()
          ..color = _cyan.withValues(alpha: 0.38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);

    // Prime meridian
    canvas.drawCircle(
        Offset(cx, cy),
        R,
        Paint()
          ..color = _cyan.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Equator
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy), width: R * 2, height: R * 2 * pf),
        Paint()
          ..color = _cyan.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Plot-point dots
    void dot(double px, double py, {double r = 9.5}) {
      canvas.drawCircle(
          Offset(px, py), r + 3, Paint()..color = Colors.white.withValues(alpha: 0.85));
      canvas.drawCircle(Offset(px, py), r, Paint()..color = _cyan);
    }

    for (int i = 0; i < 4; i++) {
      final t = i * math.pi / 2;
      dot(cx + R * math.cos(t), cy + R * pf * math.sin(t));
    }
    dot(cx, cy - R);
    dot(cx, cy + R);

    // Centre object dot
    canvas.drawCircle(Offset(cx, cy), 8,
        Paint()..color = Colors.white.withValues(alpha: 0.15));
    canvas.drawCircle(Offset(cx, cy), 4,
        Paint()..color = Colors.white.withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(_) => false;
}

// Page 2: Camera viewfinder + crosshair + "Set Point" chip
class _SetPointPainter extends CustomPainter {
  const _SetPointPainter();

  static const _cyan = Color(0xFF00BCD4);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final vw = size.width * 0.72;
    final vh = vw * 1.22;
    final vl = cx - vw / 2;
    final vt = cy - vh / 2;

    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(vl, vt, vw, vh), const Radius.circular(18));

    // Viewfinder background + border
    canvas.drawRRect(rrect,
        Paint()..color = Colors.white.withValues(alpha: 0.04));
    canvas.drawRRect(
        rrect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // Corner brackets
    const cLen = 22.0;
    final bp = Paint()
      ..color = _cyan
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final dx in [-1.0, 1.0]) {
      for (final dy in [-1.0, 1.0]) {
        final bx = dx < 0 ? vl : vl + vw;
        final by = dy < 0 ? vt : vt + vh;
        canvas.drawLine(Offset(bx, by), Offset(bx + cLen * dx, by), bp);
        canvas.drawLine(Offset(bx, by), Offset(bx, by + cLen * dy), bp);
      }
    }

    // Crosshair
    const gap = 20.0;
    const len = 26.0;
    final hp = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(cx - gap - len, cy), Offset(cx - gap, cy), hp);
    canvas.drawLine(Offset(cx + gap, cy), Offset(cx + gap + len, cy), hp);
    canvas.drawLine(Offset(cx, cy - gap - len), Offset(cx, cy - gap), hp);
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, cy + gap + len), hp);

    // Object dot at centre
    canvas.drawCircle(
        Offset(cx, cy),
        14,
        Paint()
          ..color = _cyan.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(
        Offset(cx, cy), 6, Paint()..color = _cyan.withValues(alpha: 0.9));
    canvas.drawCircle(
        Offset(cx, cy), 3, Paint()..color = Colors.white.withValues(alpha: 0.9));

    // "SET POINT" chip at bottom of viewfinder
    final chipY = vt + vh - 34;
    final chipW = 90.0;
    const chipH = 28.0;
    final cRRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, chipY), width: chipW, height: chipH),
        const Radius.circular(14));
    canvas.drawRRect(cRRect, Paint()..color = _cyan.withValues(alpha: 0.18));
    canvas.drawRRect(
        cRRect,
        Paint()
          ..color = _cyan.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    _text(canvas, 'SET POINT',
        TextStyle(
            color: _cyan.withValues(alpha: 0.95),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1),
        Offset(cx, chipY));
  }

  @override
  bool shouldRepaint(_) => false;
}

// Page 3: Top-down map view showing P1 + sphere ring
class _ShootP1Painter extends CustomPainter {
  const _ShootP1Painter();

  static const _cyan = Color(0xFF00BCD4);
  static const _green = Color(0xFF4CAF50);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(size.width, size.height) * 0.35;

    // Sphere top-down circle
    canvas.drawCircle(Offset(cx, cy), R,
        Paint()..color = _cyan.withValues(alpha: 0.08));
    canvas.drawCircle(
        Offset(cx, cy),
        R,
        Paint()
          ..color = _cyan.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // P2, P3, P4 — empty position rings
    for (final deg in [90.0, 180.0, 270.0]) {
      final rad = deg * math.pi / 180;
      final px = cx + R * math.cos(rad);
      final py = cy + R * math.sin(rad);
      canvas.drawCircle(
          Offset(px, py),
          10,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    // P1 at 0° — green, filled
    final p1x = cx + R;
    final p1y = cy;

    // Distance line
    canvas.drawLine(
        Offset(cx, cy),
        Offset(p1x, p1y),
        Paint()
          ..color = _green.withValues(alpha: 0.55)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);

    // "capture distance" label
    _text(
        canvas,
        'capture distance',
        TextStyle(color: _green.withValues(alpha: 0.7), fontSize: 10),
        Offset(cx + R * 0.5, cy - 14));

    // Object at centre
    canvas.drawCircle(
        Offset(cx, cy),
        18,
        Paint()
          ..color = _cyan.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(
        Offset(cx, cy), 9, Paint()..color = _cyan.withValues(alpha: 0.85));
    canvas.drawCircle(Offset(cx, cy), 4.5,
        Paint()..color = Colors.white.withValues(alpha: 0.9));

    // P1 dot
    canvas.drawCircle(Offset(p1x, p1y), 17,
        Paint()..color = _green.withValues(alpha: 0.18));
    canvas.drawCircle(
        Offset(p1x, p1y),
        17,
        Paint()
          ..color = _green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
    canvas.drawCircle(
        Offset(p1x, p1y), 7, Paint()..color = _green.withValues(alpha: 0.9));

    // "P1" label
    _text(
        canvas,
        'P1',
        const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        Offset(p1x + 24, p1y));
  }

  @override
  bool shouldRepaint(_) => false;
}

// Page 4: Floating ring targets and auto-capture chips
class _FollowDotsPainter extends CustomPainter {
  const _FollowDotsPainter();

  static const _cyan = Color(0xFF00BCD4);
  static const _green = Color(0xFF4CAF50);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(size.width, size.height) * 0.30;

    // Background sphere arc (minimal)
    canvas.drawCircle(
        Offset(cx, cy),
        R,
        Paint()
          ..color = _cyan.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // Captured dots (greyed)
    for (final deg in [0.0, 90.0, 180.0]) {
      final rad = deg * math.pi / 180;
      canvas.drawCircle(
          Offset(cx + R * math.cos(rad), cy + R * math.sin(rad)),
          8,
          Paint()..color = _green.withValues(alpha: 0.5));
    }

    // Active floating ring (270° position) — highlighted with glow
    final tx = cx;
    final ty = cy - R;
    canvas.drawCircle(
        Offset(tx, ty),
        26,
        Paint()
          ..color = _cyan.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawCircle(Offset(tx, ty), 19,
        Paint()..color = _cyan.withValues(alpha: 0.15));
    canvas.drawCircle(
        Offset(tx, ty),
        19,
        Paint()
          ..color = _cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8);
    canvas.drawCircle(Offset(tx, ty), 3.5,
        Paint()..color = Colors.white.withValues(alpha: 0.85));

    // Arrow pointing toward active ring
    const arrowH = 28.0;
    final arrowTip = Offset(cx, ty + 28);
    final arrowBase = Offset(cx, ty + 28 + arrowH);
    canvas.drawLine(
        arrowBase,
        arrowTip,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);
    // Arrowhead
    final arrowP = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(arrowTip, arrowTip + const Offset(-6, 8), arrowP);
    canvas.drawLine(arrowTip, arrowTip + const Offset(6, 8), arrowP);

    // Status chips — all green
    final chipsY = cy + R * 1.45;
    const labels = ['🧭 Bearing', '↗ Pitch', '↕ Distance'];
    const chipW = 80.0;
    const chipH = 24.0;
    const gap = 6.0;
    var chipX = cx - (chipW * 3 + gap * 2) / 2;
    for (final label in labels) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(chipX, chipsY, chipW, chipH), const Radius.circular(12));
      canvas.drawRRect(r, Paint()..color = _green.withValues(alpha: 0.18));
      canvas.drawRRect(
          r,
          Paint()
            ..color = _green.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      _text(
          canvas,
          label,
          TextStyle(
              color: _green, fontSize: 9.5, fontWeight: FontWeight.w600),
          Offset(chipX + chipW / 2, chipsY + chipH / 2));
      chipX += chipW + gap;
    }

    // "Auto-capture!" hint
    _text(
        canvas,
        '↑  auto-captures when all green',
        TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
        Offset(cx, chipsY + chipH + 14));
  }

  @override
  bool shouldRepaint(_) => false;
}

// Page 5: Completed photo grid + done chip + upload hint
class _DonePainter extends CustomPainter {
  const _DonePainter();

  static const _cyan = Color(0xFF00BCD4);
  static const _green = Color(0xFF4CAF50);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 2 × 2 photo grid
    const cols = 2;
    const rows = 2;
    const ps = 76.0; // photo size
    const gap = 8.0;
    const gridW = cols * ps + (cols - 1) * gap;
    const gridH = rows * ps + (rows - 1) * gap;
    final gl = cx - gridW / 2;
    final gt = cy - gridH / 2 - 24;

    const bgColors = [
      Color(0xFF0E2030),
      Color(0xFF0E3020),
      Color(0xFF20103A),
      Color(0xFF1A2E12),
    ];

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final x = gl + c * (ps + gap);
        final y = gt + r * (ps + gap);
        final rr = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, ps, ps), const Radius.circular(12));
        canvas.drawRRect(rr, Paint()..color = bgColors[r * cols + c]);
        canvas.drawRRect(
            rr,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.1)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);

        // Checkmark
        final checkX = x + ps / 2;
        final checkY = y + ps / 2;
        final cp = Paint()
          ..color = _green.withValues(alpha: 0.85)
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        canvas.drawPath(
            Path()
              ..moveTo(checkX - 12, checkY)
              ..lineTo(checkX - 4, checkY + 8)
              ..lineTo(checkX + 12, checkY - 8),
            cp);
      }
    }

    // DONE chip
    final doneY = gt + gridH + 22;
    final dr = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, doneY + 14), width: 86, height: 30),
        const Radius.circular(15));
    canvas.drawRRect(dr, Paint()..color = _cyan.withValues(alpha: 0.15));
    canvas.drawRRect(
        dr,
        Paint()
          ..color = _cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3);
    _text(
        canvas,
        'DONE',
        TextStyle(
            color: _cyan,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5),
        Offset(cx, doneY + 14));

    // Upload arrow
    final ay = doneY + 58;
    final ap = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, ay), Offset(cx, ay - 20), ap);
    canvas.drawLine(Offset(cx, ay - 20), Offset(cx - 8, ay - 10), ap);
    canvas.drawLine(Offset(cx, ay - 20), Offset(cx + 8, ay - 10), ap);

    _text(
        canvas,
        'Upload to Google Drive',
        TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
        Offset(cx, ay + 8));
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Utility ───────────────────────────────────────────────────────────────────

void _text(Canvas canvas, String t, TextStyle style, Offset centre) {
  final tp = TextPainter(
    text: TextSpan(text: t, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
}
