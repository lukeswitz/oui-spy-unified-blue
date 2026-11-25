// Copyright (c) 2026 Luke Switzer
import 'dart:math' as math;

enum PresenceCategory {
  stationary('Stationary'),
  frequentFlier('Frequent-Flier'),
  visitor('Visitor'),
  newcomer('New'),
  transient('Transient');

  const PresenceCategory(this.label);
  final String label;
}

class PresenceParams {
  final int windowMs;
  final int gapMs;
  final int frequentFlierVisits;
  final int visitorAbsenceMs;
  final double stationaryPresencePct;
  const PresenceParams({
    this.windowMs = 7 * 24 * 3600 * 1000,
    this.gapMs = 10 * 60 * 1000,
    this.frequentFlierVisits = 5,
    this.visitorAbsenceMs = 60 * 60 * 1000,
    this.stationaryPresencePct = 60,
  });
}

class PresenceStats {
  final int firstSeen;
  final int lastSeen;
  final int visitsInWindow;
  final int presenceMsInWindow;
  const PresenceStats(this.firstSeen, this.lastSeen, this.visitsInWindow, this.presenceMsInWindow);

  static PresenceStats? fromSightings(List<int> tsMs, int now, PresenceParams p, {int? baselineStart}) {
    if (tsMs.isEmpty) return null;
    final ts = [...tsMs]..sort();
    final windowStart = _windowStart(now, p, baselineStart);
    var visits = 0;
    var presence = 0;
    int? runStart;
    int? prev;
    void close() {
      final rs = runStart, pv = prev;
      if (rs != null && pv != null && pv >= windowStart) {
        visits++;
        presence += pv - math.max(rs, windowStart);
      }
    }

    for (final t in ts) {
      if (prev == null || t - prev > p.gapMs) {
        close();
        runStart = t;
      }
      prev = t;
    }
    close();
    return PresenceStats(ts.first, ts.last, visits, presence);
  }
}

int _windowStart(int now, PresenceParams p, int? baselineStart) {
  final rolling = now - p.windowMs;
  return baselineStart != null ? math.max(baselineStart, rolling) : rolling;
}

PresenceCategory classifyPresence(PresenceStats s, int now, PresenceParams p, {int? baselineStart}) {
  final windowLen = math.max(0, now - _windowStart(now, p, baselineStart));
  final presencePct = windowLen > 0
      ? s.presenceMsInWindow / windowLen * 100
      : (s.presenceMsInWindow > 0 ? 100 : 0);
  final currentlyPresent = now - s.lastSeen <= p.gapMs;
  final isPostBaseline = baselineStart != null && s.firstSeen >= baselineStart;
  final absence = now - s.lastSeen;

  if (s.visitsInWindow >= p.frequentFlierVisits) return PresenceCategory.frequentFlier;
  if (presencePct >= p.stationaryPresencePct) return PresenceCategory.stationary;
  if (isPostBaseline && !currentlyPresent && absence >= p.visitorAbsenceMs) return PresenceCategory.visitor;
  if (isPostBaseline && currentlyPresent) return PresenceCategory.newcomer;
  return PresenceCategory.transient;
}
