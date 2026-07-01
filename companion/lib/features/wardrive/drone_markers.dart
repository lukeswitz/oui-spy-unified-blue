import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

class FanGeometry {
  const FanGeometry(this.angle, this.length);
  final double angle;
  final double length;
}

/// Rounded key identifying co-located markers (same plotted point).
String plotKey(Detection d) {
  final rid = d.engine == Engine.skySpy ? droneRidPoint(d) : null;
  final lat = rid?.latitude ?? d.latitude;
  final lon = rid?.longitude ?? d.longitude;
  if (lat == null || lon == null) return '';
  return '${(lat * 1e5).round()},${(lon * 1e5).round()}';
}

FanGeometry fanGeometry(int index, int count, {double baseAngle = -pi / 2}) {
  if (count <= 1) return FanGeometry(baseAngle, 23);
  final angle = (index / count) * 2 * pi + baseAngle;
  final length = count <= 4 ? 19.0 : 16.0 + count * 1.0;
  return FanGeometry(angle, length);
}

class FannedPin extends StatelessWidget {
  const FannedPin({
    super.key,
    required this.geo,
    required this.head,
    required this.lineColor,
    this.headExtent = 40.0,
  });
  final FanGeometry geo;
  final Widget head;
  final Color lineColor;
  final double headExtent;

  @override
  Widget build(BuildContext context) {
    final box = (geo.length + headExtent) * 2;
    final dx = geo.length * cos(geo.angle);
    final dy = geo.length * sin(geo.angle);
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size(box, box),
            painter: _LeaderPainter(dx: dx, dy: dy, color: lineColor),
          ),
          Transform.translate(offset: Offset(dx, dy), child: head),
        ],
      ),
    );
  }
}

class _LeaderPainter extends CustomPainter {
  _LeaderPainter({required this.dx, required this.dy, required this.color});
  final double dx;
  final double dy;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final line = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(c, c + Offset(dx, dy), line);
    canvas.drawCircle(c, 3.0, Paint()..color = color);
    canvas.drawCircle(
        c,
        3.0,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_LeaderPainter old) =>
      old.dx != dx || old.dy != dy || old.color != color;
}

const String kDroneSvgAsset = 'assets/icons/drone.svg';
const String kPilotSvgAsset = 'assets/icons/pilot.svg';
const Color kDroneFreshRing = Color(0xFF7CFF4F);

LatLng? droneRidPoint(Detection d) {
  final o = d.odid;
  if (o == null) return null;
  return _validPoint(o.droneLat, o.droneLon);
}

LatLng? pilotRidPoint(Detection d) {
  final o = d.odid;
  if (o == null) return null;
  return _validPoint(o.pilotLat, o.pilotLon);
}

LatLng? _validPoint(double? lat, double? lon) {
  if (lat == null || lon == null) return null;
  if (lat == 0 && lon == 0) return null;
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  if (lat.isNaN || lon.isNaN) return null;
  return LatLng(lat, lon);
}

bool droneIsFresh(Detection d,
    {Duration window = const Duration(seconds: 5)}) {
  return DateTime.now().difference(d.appTimestamp) <= window;
}

Color droneColorForMac(String mac) {
  var hash = 0;
  for (var i = 0; i < mac.length; i++) {
    hash = mac.codeUnitAt(i) + ((hash << 5) - hash);
  }
  final hue = (hash.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.75, 0.6).toColor();
}

class DronePin extends StatelessWidget {
  const DronePin({
    super.key,
    required this.color,
    required this.size,
    this.fresh = false,
  });
  final Color color;
  final double size;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size + 16,
        height: size + 16,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (fresh)
                Container(
                  width: size + 12,
                  height: size + 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kDroneFreshRing, width: 2.2),
                  ),
                ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.8),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: fresh ? 0.85 : 0.5),
                      blurRadius: fresh ? 16 : 9,
                      spreadRadius: fresh ? 2 : 1,
                    ),
                    const BoxShadow(
                      color: Color(0x77000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  kDroneSvgAsset,
                  width: size * 0.62,
                  height: size * 0.62,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DroneRangePin extends StatelessWidget {
  const DroneRangePin({
    super.key,
    required this.color,
    required this.label,
    this.fresh = false,
  });
  final Color color;
  final String label;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.95),
              border: Border.all(
                color: fresh ? kDroneFreshRing : Colors.white,
                width: 2.4,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xCC000000),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              kDroneSvgAsset,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xE6000000),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: 1),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PilotPin extends StatelessWidget {
  const PilotPin({
    super.key,
    required this.color,
    required this.size,
    this.isTakeoff = false,
  });
  final Color color;
  final double size;

  final bool isTakeoff;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size + 14,
        height: size + 14,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.85),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.8),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 7,
                  spreadRadius: 0.5,
                ),
                const BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 3,
                  offset: Offset(0, 1.5),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: isTakeoff
                ? Icon(
                    Icons.flight_takeoff,
                    size: size * 0.62,
                    color: Colors.white,
                  )
                : SvgPicture.asset(
                    kPilotSvgAsset,
                    width: size * 0.6,
                    height: size * 0.6,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
          ),
        ),
      ),
    );
  }
}
