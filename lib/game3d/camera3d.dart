import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Orbit camera over the game world for the 3D view.
///
/// Game coordinates are kept as they are (x east, y south, 1 unit ~ 1 m in Tashkent); z is height in metres.
/// Internally the camera works in a right-handed frame W = (x, -y, z) (east, north, up).
class OrbitCamera {
  /// Ground point the camera looks at, in game units.
  double targetX, targetY;

  /// Distance from the eye to [targetX]/[targetY] in metres.
  double distance;

  /// Heading: 0 looks north; positive turns towards east (the 2D map rotation is `yaw = -rot`).
  double yaw;

  /// Elevation of the eye above the horizon, radians.
  double pitch;

  final double fovY;
  static const double near = 1.0;
  static const double minPitch = 0.22, maxPitch = 1.45;
  static const double minDistance = 60, maxDistance = 2600;

  OrbitCamera({
    this.targetX = 3200,
    this.targetY = 3200,
    this.distance = 700,
    this.yaw = 0,
    this.pitch = 0.75,
    this.fovY = 50 * math.pi / 180,
  });

  // derived (update)
  double ex = 0, ey = 0, ez = 0; // eye in W
  double rx = 1, ry = 0; // right (rz = 0)
  double ux = 0, uy = 0, uz = 1; // up
  double fx = 0, fy = 1, fz = 0; // forward
  double focal = 1, cx = 0, cy = 0;
  Size viewport = Size.zero;

  /// Recomputes the view basis; call once per frame before [toCamera]/[project].
  void update(Size size) {
    pitch = pitch.clamp(minPitch, maxPitch).toDouble();
    distance = distance.clamp(minDistance, maxDistance).toDouble();
    viewport = size;
    final cp = math.cos(pitch), sp = math.sin(pitch), cyw = math.cos(yaw), syw = math.sin(yaw);
    fx = cp * syw;
    fy = cp * cyw;
    fz = -sp;
    ex = targetX - distance * fx;
    ey = -targetY - distance * fy;
    ez = -distance * fz;
    rx = cyw;
    ry = -syw;
    // u = r x f
    ux = ry * fz;
    uy = -rx * fz;
    uz = rx * fy - ry * fx;
    focal = (size.height / 2) / math.tan(fovY / 2);
    cx = size.width / 2;
    cy = size.height / 2;
  }

  /// Eye position in game coordinates (x, y) and height.
  Offset get eyeGame => Offset(ex, -ey);
  double get eyeHeight => ez;

  /// Game point -> camera space (x right, y up, z depth along the view direction) into [out] (3 values).
  void toCamera(double gx, double gy, double z, Float64List out) {
    final dx = gx - ex, dy = -gy - ey, dz = z - ez;
    out[0] = dx * rx + dy * ry;
    out[1] = dx * ux + dy * uy + dz * uz;
    out[2] = dx * fx + dy * fy + dz * fz;
  }

  /// Depth (distance along the view direction) of a game point.
  double depthOf(double gx, double gy, double z) => (gx - ex) * fx + (-gy - ey) * fy + (z - ez) * fz;

  /// Camera space -> screen pixels. Only valid for z >= [near].
  Offset screenOf(double xc, double yc, double zc) => Offset(cx + xc / zc * focal, cy - yc / zc * focal);

  /// Game point -> screen into [out] (x, y, depth); false when the point is behind the near plane.
  bool project(double gx, double gy, double z, Float64List out) {
    toCamera(gx, gy, z, out);
    final zc = out[2];
    if (zc < near) return false;
    final x = out[0], y = out[1];
    out[0] = cx + x / zc * focal;
    out[1] = cy - y / zc * focal;
    out[2] = zc;
    return true;
  }

  /// Ground point (game coordinates) under a screen position, or null when the ray does not hit the ground.
  Offset? groundAt(Offset screen) {
    final a = (screen.dx - cx) / focal, b = -(screen.dy - cy) / focal;
    final dx = rx * a + ux * b + fx, dy = ry * a + uy * b + fy, dz = ux * 0 + uz * b + fz;
    if (dz >= -1e-6) return null;
    final t = -ez / dz;
    return Offset(ex + dx * t, -(ey + dy * t));
  }

  /// Screen y of the horizon (clamped to the viewport by the caller).
  double get horizonY => cy - math.tan(pitch) * focal;
}
