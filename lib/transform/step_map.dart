import 'package:meta/meta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StepMap — Maps positions through an editing operation
// ─────────────────────────────────────────────────────────────────────────────

/// Maps document positions through an editing operation.
///
/// When text is inserted or deleted, positions after the edit shift.
/// A StepMap records these shifts so that selections, markers,
/// and other position-dependent data can be updated correctly.
///
/// StepMaps compose: applying map A then map B is equivalent to
/// applying the composed map A·B.
@immutable
class StepMap {
  /// Creates a step map from a list of ranges.
  ///
  /// Ranges are triples: (position, oldSize, newSize).
  /// They must be sorted and non-overlapping.
  StepMap(List<int> ranges) : ranges = List.unmodifiable(ranges);

  /// An identity map (no position changes).
  static final StepMap identity = StepMap(const []);

  /// The mapping ranges as flat triples: [pos, oldSize, newSize, ...]
  final List<int> ranges;

  /// Creates a simple step map for a single replacement.
  ///
  /// [pos] — position of the edit
  /// [oldSize] — number of characters deleted
  /// [newSize] — number of characters inserted
  factory StepMap.simple(int pos, int oldSize, int newSize) =>
      StepMap([pos, oldSize, newSize]);

  /// Maps a [pos]ition through this step map.
  ///
  /// [assoc] determines how positions at edit boundaries are mapped:
  /// - negative: map to the left (before the edit)
  /// - positive: map to the right (after the edit)
  /// - zero: map to the closest side
  int map(int pos, {int assoc = 1}) {
    final len = ranges.length;
    if (len == 0) return pos;

    // Fast path: pos before first range
    if (pos < ranges[0]) return pos;

    // Fast path: pos after last range
    final lastIdx = len - 3;
    final lastEnd = ranges[lastIdx] + ranges[lastIdx + 1];
    if (pos > lastEnd || (pos == lastEnd && lastEnd > ranges[lastIdx])) {
      var diff = 0;
      for (var i = 0; i < len; i += 3) {
        diff += ranges[i + 2] - ranges[i + 1];
      }
      return pos + diff;
    }

    var diff = 0;
    for (var i = 0; i < len; i += 3) {
      final start = ranges[i];
      final oldSize = ranges[i + 1];
      final newSize = ranges[i + 2];

      final end = start + oldSize;

      if (pos < start) {
        return pos + diff;
      }

      if (pos > end || (pos == end && end > start)) {
        diff += newSize - oldSize;
        continue;
      }

      // Position is inside the edited range (or at a pure insertion point)
      if (assoc < 0) {
        return start + diff;
      } else {
        return start + newSize + diff;
      }
    }

    return pos + diff;
  }

  /// Maps a position, returning null if the position was deleted.
  int? mapOrNull(int pos, {int assoc = 1}) {
    final len = ranges.length;
    if (len == 0) return pos;

    // Fast path: pos before first range
    if (pos < ranges[0]) return pos;

    var diff = 0;
    for (var i = 0; i < len; i += 3) {
      final start = ranges[i];
      final oldSize = ranges[i + 1];
      final newSize = ranges[i + 2];
      final end = start + oldSize;

      if (pos < start) return pos + diff;

      if (pos > end || (pos == end && end > start)) {
        diff += newSize - oldSize;
        continue;
      }

      // Position was deleted
      if (oldSize > 0 && newSize == 0) return null;
      if (assoc < 0) return start + diff;
      return start + newSize + diff;
    }
    return pos + diff;
  }

  /// Composes this map with [other] (apply this first, then other).
  ///
  /// The composed map produces the same result as applying this map
  /// then [other] sequentially.
  StepMap compose(StepMap other) {
    if (ranges.isEmpty) return other;
    if (other.ranges.isEmpty) return this;
    return Mapping.from([this, other]).composed;
  }

  /// Returns the inverse of this map (cached).
  late final StepMap inverse = _computeInverse();

  StepMap _computeInverse() {
    if (ranges.isEmpty) return this;
    final result = <int>[];
    var diff = 0;
    for (var i = 0; i < ranges.length; i += 3) {
      final pos = ranges[i] + diff;
      final oldSize = ranges[i + 1];
      final newSize = ranges[i + 2];
      result.addAll([pos, newSize, oldSize]);
      diff += newSize - oldSize;
    }
    return StepMap(result);
  }

  @override
  String toString() {
    if (ranges.isEmpty) return 'StepMap.identity';
    final parts = <String>[];
    for (var i = 0; i < ranges.length; i += 3) {
      parts.add('${ranges[i]}:${ranges[i + 1]}→${ranges[i + 2]}');
    }
    return 'StepMap(${parts.join(', ')})';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mapping — Composed chain of step maps
// ─────────────────────────────────────────────────────────────────────────────

/// A chain of step maps that can map positions through a series of edits.
///
/// Built from a transaction's sequence of steps. Each step adds its map
/// to the chain.
class Mapping {
  /// Creates an empty mapping.
  Mapping() : _maps = [];

  /// Creates a mapping from existing step maps.
  Mapping.from(List<StepMap> maps) : _maps = List.of(maps);

  final List<StepMap> _maps;

  /// The number of step maps in this mapping.
  int get length => _maps.length;

  /// An unmodifiable view of the step maps in this mapping.
  List<StepMap> get maps => List.unmodifiable(_maps);

  /// Adds a step map to the chain.
  void appendMap(StepMap map) => _maps.add(map);

  /// Maps a position through all step maps in sequence.
  int map(int pos, {int assoc = 1}) {
    for (final m in _maps) {
      pos = m.map(pos, assoc: assoc);
    }
    return pos;
  }

  /// Maps a position, returning null if it was deleted by any step.
  int? mapOrNull(int pos, {int assoc = 1}) {
    for (final m in _maps) {
      final mapped = m.mapOrNull(pos, assoc: assoc);
      if (mapped == null) return null;
      pos = mapped;
    }
    return pos;
  }

  /// Composes all maps into a single StepMap.
  ///
  /// The composed map produces the same result as sequential application
  /// via [map], but as a single StepMap.
  StepMap get composed {
    if (_maps.isEmpty) return StepMap.identity;
    if (_maps.length == 1) return _maps.first;

    // Collect boundary positions in D0 (original document) space.
    // For the first map, boundaries come directly from its ranges.
    // For subsequent maps, boundaries are mapped back to D0 via inverse
    // of all preceding maps.
    final d0Points = <int>{};

    for (var mapIdx = 0; mapIdx < _maps.length; mapIdx++) {
      final m = _maps[mapIdx];
      for (var j = 0; j < m.ranges.length; j += 3) {
        var startPos = m.ranges[j];
        var endPos = startPos + m.ranges[j + 1];

        // Map back through inverse of preceding maps (in reverse order).
        // Each inverse is cached via late final, so repeated access is O(1).
        for (var k = mapIdx - 1; k >= 0; k--) {
          final inv = _maps[k].inverse;
          startPos = inv.map(startPos, assoc: -1);
          endPos = inv.map(endPos, assoc: 1);
        }

        d0Points.add(startPos);
        d0Points.add(endPos);
      }
    }

    if (d0Points.isEmpty) return StepMap.identity;

    final sorted = d0Points.toList()..sort();
    final result = <int>[];

    void emit(int pos, int oldSize, int newSize) {
      if (oldSize == 0 && newSize == 0) return;
      // Merge with previous range if adjacent.
      if (result.isNotEmpty &&
          result[result.length - 3] + result[result.length - 2] == pos) {
        result[result.length - 2] += oldSize;
        result[result.length - 1] += newSize;
      } else {
        result.addAll([pos, oldSize, newSize]);
      }
    }

    for (var i = 0; i < sorted.length; i++) {
      final d0Pos = sorted[i];

      // 1) Check for net insertion at this D0 point.
      var lo = d0Pos, hi = d0Pos;
      for (final m in _maps) {
        lo = m.map(lo, assoc: -1);
        hi = m.map(hi, assoc: 1);
      }
      if (lo < hi) {
        emit(d0Pos, 0, hi - lo);
      }

      // 2) Process the segment from this point to the next.
      if (i + 1 >= sorted.length) continue;
      final d0Next = sorted[i + 1];
      final segOld = d0Next - d0Pos;

      // Use assoc:1 for lo (skip past insertions at start boundary)
      // and assoc:-1 for hi (stop before insertions at end boundary).
      lo = d0Pos;
      hi = d0Next;
      for (final m in _maps) {
        lo = m.map(lo, assoc: 1);
        hi = m.map(hi, assoc: -1);
      }
      final segNew = hi - lo;

      if (segOld != segNew) {
        emit(d0Pos, segOld, segNew);
      }
    }

    return StepMap(result);
  }

  /// Returns a new mapping that is the inverse of this one.
  Mapping get inverse {
    final inverted = _maps.reversed.map((m) => m.inverse).toList();
    return Mapping.from(inverted);
  }
}
