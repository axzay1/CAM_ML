// dart run tool/gen_icon.dart
// Generates assets/icon/icon.png — source for flutter_launcher_icons.
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  const int S = 1024;
  const double cx = S / 2.0;
  const double cy = S / 2.0;
  const double R = 290.0; // sphere radius in pixels

  final image = img.Image(width: S, height: S);

  // ── Background: dark navy with radial gradient ────────────────────────────
  for (int y = 0; y < S; y++) {
    for (int x = 0; x < S; x++) {
      final double d =
          math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2)) / (S * 0.7);
      final double t = d.clamp(0.0, 1.0);
      image.setPixel(x, y,
          img.ColorRgba8(_li(0x0B, 0x04, t), _li(0x0F, 0x06, t), _li(0x1F, 0x0C, t), 255));
    }
  }

  // ── Sphere outer glow ─────────────────────────────────────────────────────
  _ellipse(image, cx, cy, R + 18, R + 18, img.ColorRgba8(0, 188, 212, 18), 18);
  _ellipse(image, cx, cy, R + 6, R + 6, img.ColorRgba8(0, 188, 212, 40), 6);

  // ── Secondary meridian (tilted 45° around Y — appears as narrow ellipse) ─
  _ellipse(image, cx, cy, R * 0.707, R, img.ColorRgba8(0, 188, 212, 80), 2.5);

  // ── Prime meridian (vertical full circle) ─────────────────────────────────
  _ellipse(image, cx, cy, R, R, img.ColorRgba8(0, 188, 212, 190), 3.0);

  // ── Equator (horizontal, foreshortened perspective) ───────────────────────
  const double pf = 0.30;
  _ellipse(image, cx, cy, R, R * pf, img.ColorRgba8(0, 188, 212, 190), 3.0);

  // ── Dots at 4 equator cardinal positions ──────────────────────────────────
  for (int i = 0; i < 4; i++) {
    final double t = i * math.pi / 2;
    _dot(image, cx + R * math.cos(t), cy + R * pf * math.sin(t));
  }

  // ── Dots at north and south poles ────────────────────────────────────────
  _dot(image, cx, cy - R);
  _dot(image, cx, cy + R);

  // ── Center object ─────────────────────────────────────────────────────────
  _disk(image, cx, cy, 9, img.ColorRgba8(255, 255, 255, 40));
  _disk(image, cx, cy, 4, img.ColorRgba8(255, 255, 255, 180));

  // ── Write ─────────────────────────────────────────────────────────────────
  Directory('assets/icon').createSync(recursive: true);
  final File out = File('assets/icon/icon.png');
  out.writeAsBytesSync(img.encodePng(image));
  // ignore: avoid_print
  print('Icon written → ${out.path}');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

int _li(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);

/// Draw a dot: white outer ring + cyan fill.
void _dot(img.Image image, double cx, double cy) {
  _disk(image, cx, cy, 14, img.ColorRgba8(255, 255, 255, 200));
  _disk(image, cx, cy, 9, img.ColorRgba8(0, 188, 212, 255));
}

/// Draw an ellipse by filling small disks along the parametric curve.
void _ellipse(
    img.Image image, double cx, double cy, double rx, double ry, img.ColorRgba8 color, double thickness) {
  final int steps = (2 * math.pi * math.max(rx, ry)).ceil().clamp(600, 4000);
  for (int i = 0; i < steps; i++) {
    final double t = 2 * math.pi * i / steps;
    _disk(image, cx + rx * math.cos(t), cy + ry * math.sin(t), thickness / 2, color);
  }
}

/// Fill a disk at (cx,cy) with radius r, blending color's alpha into existing pixels.
void _disk(img.Image image, double cx, double cy, double r, img.ColorRgba8 color) {
  final double alpha = color.a / 255.0;
  if (alpha <= 0) return;
  final int x0 = (cx - r - 1).floor().clamp(0, image.width - 1);
  final int x1 = (cx + r + 1).ceil().clamp(0, image.width - 1);
  final int y0 = (cy - r - 1).floor().clamp(0, image.height - 1);
  final int y1 = (cy + r + 1).ceil().clamp(0, image.height - 1);
  final double r2 = r * r;
  for (int x = x0; x <= x1; x++) {
    for (int y = y0; y <= y1; y++) {
      final double dx = x - cx;
      final double dy = y - cy;
      if (dx * dx + dy * dy <= r2) {
        final p = image.getPixel(x, y);
        image.setPixel(
          x, y,
          img.ColorRgba8(
            (p.r * (1 - alpha) + color.r * alpha).round().clamp(0, 255),
            (p.g * (1 - alpha) + color.g * alpha).round().clamp(0, 255),
            (p.b * (1 - alpha) + color.b * alpha).round().clamp(0, 255),
            255,
          ),
        );
      }
    }
  }
}
