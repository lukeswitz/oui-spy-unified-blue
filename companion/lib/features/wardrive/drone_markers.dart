import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/models/detection.dart';

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

class PilotPin extends StatelessWidget {
  const PilotPin({
    super.key,
    required this.color,
    required this.size,
  });
  final Color color;
  final double size;

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
            child: SvgPicture.asset(
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
