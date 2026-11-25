// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

enum SearchArea {
  devices('Devices'),
  alerts('Alerts'),
  drones('Drones'),
  nodes('Nodes'),
  wardrive('Wardrive');

  const SearchArea(this.label);
  final String label;
}

const searchPerAreaLimit = 50;

String searchHaystack(Iterable<Object?> parts) {
  final text = parts
      .where((p) => p != null)
      .map((p) => p.toString())
      .where((s) => s.isNotEmpty)
      .join(' ')
      .toLowerCase();
  return '$text ${text.replaceAll(':', '').replaceAll('-', '')}';
}

bool searchHits(String haystack, String query) {
  final hay = haystack.toLowerCase();
  for (final word in query.toLowerCase().split(RegExp(r'\s+'))) {
    if (word.isEmpty || hay.contains(word)) continue;
    if (hay.contains(word.replaceAll(':', '').replaceAll('-', ''))) continue;
    return false;
  }
  return true;
}

class SearchEntry {
  SearchEntry({
    required this.area,
    required this.title,
    required this.subtitle,
    required Iterable<Object?> haystack,
    this.payload,
    this.atMs = 0,
  }) : hay = searchHaystack(haystack);

  final SearchArea area;
  final String title;
  final String subtitle;
  final String hay;
  final Object? payload;
  final int atMs;
}

class SearchResults {
  const SearchResults(this.query, this.byArea, this.totals);

  static const empty = SearchResults('', {}, {});

  final String query;
  final Map<SearchArea, List<SearchEntry>> byArea;
  final Map<SearchArea, int> totals;

  int get total => totals.values.fold(0, (a, b) => a + b);

  List<SearchArea> get areas => [for (final a in SearchArea.values) if ((totals[a] ?? 0) > 0) a];
}

SearchResults searchEntries(String query, Iterable<SearchEntry> entries, {int limit = searchPerAreaLimit}) {
  final q = query.trim();
  if (q.isEmpty) return SearchResults.empty;
  final byArea = <SearchArea, List<SearchEntry>>{};
  final totals = <SearchArea, int>{};
  for (final e in entries) {
    if (!searchHits(e.hay, q)) continue;
    totals[e.area] = (totals[e.area] ?? 0) + 1;
    (byArea[e.area] ??= []).add(e);
  }
  for (final list in byArea.values) {
    list.sort((a, b) => b.atMs.compareTo(a.atMs));
    if (list.length > limit) list.removeRange(limit, list.length);
  }
  return SearchResults(q, byArea, totals);
}
