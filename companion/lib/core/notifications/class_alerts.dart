import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/detector_signatures.dart';

final alertableClasses = [
  for (final c in SignatureClass.values)
    if (c != SignatureClass.bodyworn) c,
];

const defaultAlertClasses = {
  SignatureClass.drone,
  SignatureClass.lawEnforcement,
  SignatureClass.glasses,
};

const _guessBuckets = {
  'camera': SignatureClass.camera,
  'drone': SignatureClass.drone,
  'glasses': SignatureClass.glasses,
  'tag': SignatureClass.finder,
  'radio': SignatureClass.lawEnforcement,
  'law-enforcement': SignatureClass.lawEnforcement,
  'bodyworn': SignatureClass.lawEnforcement,
};

const flockFleetIds = {
  'fleet-flock-cameras',
  'fleet-fs-ext-battery',
  'fleet-penguin',
  'fleet-pigvision',
  'fleet-raven',
};

bool isFlockSignature(Signature s) => flockFleetIds.contains(s.id);

class ClassAlert {
  const ClassAlert(this.kind, this.label, this.matches);
  ClassAlert.ofClass(SignatureClass c) : this(c.name, c.label, (s) => s.kind.folded == c);
  static const flock = ClassAlert('flock', 'Flock', isFlockSignature);
  final String kind;
  final String label;
  final bool Function(Signature) matches;
}

const _detectorBitClass = {
  sigCamera: SignatureClass.camera,
  sigTracker: SignatureClass.finder,
  sigGlasses: SignatureClass.glasses,
  sigFlipper: SignatureClass.hacking,
  sigPwnagotchi: SignatureClass.hacking,
  sigAxon: SignatureClass.lawEnforcement,
};

final detectorMethodClass = {
  for (final e in detectorMethodsByBit.entries)
    if (_detectorBitClass[e.key] case final c?)
      for (final m in e.value) m: c,
};

ClassAlert? classAlertOf(ClassifiedDevice d, Set<SignatureClass> enabled, {required bool flock}) {
  final board = detectorMethodClass[d.obs.detectorMethod];
  if (d.signatures.any(isFlockSignature)) {
    if (flock) return ClassAlert.flock;
    return board == null ? null : ClassAlert.ofClass(board);
  }
  final c = alertClassOf(d, enabled) ?? board;
  return c == null ? null : ClassAlert.ofClass(c);
}

SignatureClass? alertClassOf(ClassifiedDevice d, Set<SignatureClass> enabled) {
  for (final s in d.signatures) {
    if (isFlockSignature(s)) continue;
    if (enabled.contains(s.kind.folded)) return s.kind.folded;
  }
  if (d.signatures.isNotEmpty) return null;
  final g = d.guess;
  if (g.confidence == Confidence.low) return null;
  final c = _guessBuckets[g.bucket];
  return c != null && enabled.contains(c) ? c : null;
}
