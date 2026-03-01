import 'package:meta/meta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IntervalEntry — A positioned entry in the interval tree
// ─────────────────────────────────────────────────────────────────────────────

/// An entry in an [IntervalTree] representing a range with associated data.
@immutable
class IntervalEntry<T> {
  /// Creates an interval entry.
  const IntervalEntry({
    required this.id,
    required this.from,
    required this.to,
    required this.data,
  });

  /// Unique identifier for this entry.
  final Object id;

  /// Start position (inclusive).
  final int from;

  /// End position (exclusive).
  final int to;

  /// The data associated with this interval.
  final T data;

  /// Whether this interval overlaps with the range [qFrom]..[qTo].
  bool overlaps(int qFrom, int qTo) => from < qTo && to > qFrom;

  /// Whether this interval contains [pos].
  bool contains(int pos) => from <= pos && to > pos;

  /// Returns a copy with updated positions.
  IntervalEntry<T> copyWith({int? from, int? to}) => IntervalEntry(
    id: id,
    from: from ?? this.from,
    to: to ?? this.to,
    data: data,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntervalEntry<T> &&
          id == other.id &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => Object.hash(id, from, to);

  @override
  String toString() => 'IntervalEntry($id, $from..$to)';
}

// ─────────────────────────────────────────────────────────────────────────────
// IntervalTree — Immutable sorted-list interval tree
// ─────────────────────────────────────────────────────────────────────────────

/// An immutable interval tree for efficient range overlap queries.
///
/// Backed by a sorted list of [IntervalEntry] objects, sorted by `from`
/// position. Provides O(log n + k) range queries where k is the number
/// of results, and O(n) add/remove operations (acceptable for typical
/// document marker counts < 1000).
///
/// All mutation operations return new trees — the original is unchanged.
@immutable
class IntervalTree<T> {
  /// Creates an interval tree from a list of entries.
  ///
  /// The entries are sorted by `from` position internally.
  factory IntervalTree(List<IntervalEntry<T>> entries) {
    if (entries.isEmpty) return IntervalTree<T>._(const [], 0, const []);
    final sorted = List<IntervalEntry<T>>.of(entries)
      ..sort((a, b) {
        final cmp = a.from.compareTo(b.from);
        return cmp != 0 ? cmp : a.to.compareTo(b.to);
      });
    // Compute max endpoint for early termination in queries.
    var maxTo = 0;
    for (final e in sorted) {
      if (e.to > maxTo) maxTo = e.to;
    }
    final maxToPrefix = _buildMaxToPrefix(sorted);
    return IntervalTree._(List.unmodifiable(sorted), maxTo, maxToPrefix);
  }

  const IntervalTree._(this._entries, this._maxTo, this._maxToPrefix);

  /// An empty interval tree.
  static IntervalTree<T> empty<T>() => IntervalTree<T>._(const [], 0, const []);

  final List<IntervalEntry<T>> _entries;
  final int _maxTo;

  /// `_maxToPrefix[i]` = max `to` value among entries `[0..i]`.
  /// Used to early-terminate the backward scan in [query].
  final List<int> _maxToPrefix;

  /// The number of entries.
  int get length => _entries.length;

  /// Whether this tree is empty.
  bool get isEmpty => _entries.isEmpty;

  /// Whether this tree is not empty.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// All entries (sorted by `from`).
  List<IntervalEntry<T>> get entries => _entries;

  /// Returns all entries whose ranges overlap with [from]..[to].
  ///
  /// An entry overlaps if `entry.from < to && entry.to > from`.
  List<IntervalEntry<T>> query(int from, int to) {
    if (_entries.isEmpty || from >= _maxTo) return const [];

    final result = <IntervalEntry<T>>[];

    // Binary search: find first entry where entry.from >= from.
    var lo = 0;
    var hi = _entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_entries[mid].from < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    // Scan backwards from lo to catch entries that start before `from`
    // but extend into the query range. Use _maxToPrefix to stop early:
    // if _maxToPrefix[i] <= from, no entry at i or before can overlap.
    for (var i = lo - 1; i >= 0; i--) {
      if (_maxToPrefix[i] <= from) break;
      final entry = _entries[i];
      if (entry.to > from) {
        result.add(entry);
      }
    }

    // Scan forward from lo for entries starting within the query range.
    for (var i = lo; i < _entries.length; i++) {
      final entry = _entries[i];
      if (entry.from >= to) break; // All remaining start after query range.
      if (entry.to > from) {
        result.add(entry);
      }
    }

    return result;
  }

  /// Returns all entries containing [pos].
  List<IntervalEntry<T>> queryPoint(int pos) => query(pos, pos + 1);

  /// Returns a new tree with [entry] added.
  ///
  /// Uses binary search insertion to maintain sort order in O(n) time
  /// (single list copy) instead of O(n log n) full re-sort.
  IntervalTree<T> add(IntervalEntry<T> entry) {
    // Binary search for insertion point.
    var lo = 0;
    var hi = _entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final cmp = _entries[mid].from.compareTo(entry.from);
      if (cmp < 0 || (cmp == 0 && _entries[mid].to.compareTo(entry.to) < 0)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final newEntries = List<IntervalEntry<T>>.of(_entries)..insert(lo, entry);
    final newMaxTo = entry.to > _maxTo ? entry.to : _maxTo;
    final newMaxToPrefix = _buildMaxToPrefix(newEntries);
    return IntervalTree._(
      List.unmodifiable(newEntries),
      newMaxTo,
      newMaxToPrefix,
    );
  }

  /// Returns a new tree with the entry matching [id] removed.
  IntervalTree<T> remove(Object id) {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx == -1) return this; // not found
    final newEntries = List<IntervalEntry<T>>.of(_entries)..removeAt(idx);
    if (newEntries.isEmpty) return IntervalTree<T>._(const [], 0, const []);
    var newMaxTo = 0;
    for (final e in newEntries) {
      if (e.to > newMaxTo) newMaxTo = e.to;
    }
    final newMaxToPrefix = _buildMaxToPrefix(newEntries);
    return IntervalTree._(
      List.unmodifiable(newEntries),
      newMaxTo,
      newMaxToPrefix,
    );
  }

  /// Returns a new tree with all entries transformed by [transform].
  ///
  /// Entries for which [transform] returns `null` are removed.
  IntervalTree<T> map(IntervalEntry<T>? Function(IntervalEntry<T>) transform) {
    final result = <IntervalEntry<T>>[];
    for (final entry in _entries) {
      final mapped = transform(entry);
      if (mapped != null && mapped.from < mapped.to) {
        result.add(mapped);
      }
    }
    if (result.length == _entries.length) {
      // Check if anything actually changed.
      var changed = false;
      for (var i = 0; i < result.length; i++) {
        if (result[i] != _entries[i]) {
          changed = true;
          break;
        }
      }
      if (!changed) return this;
    }
    return IntervalTree<T>(result);
  }

  /// Builds a prefix-max array where `result[i]` = max `to` for entries [0..i].
  static List<int> _buildMaxToPrefix<T>(List<IntervalEntry<T>> entries) {
    if (entries.isEmpty) return const [];
    final result = List<int>.filled(entries.length, 0);
    result[0] = entries[0].to;
    for (var i = 1; i < entries.length; i++) {
      result[i] = entries[i].to > result[i - 1] ? entries[i].to : result[i - 1];
    }
    return result;
  }

  @override
  String toString() => 'IntervalTree(${_entries.length} entries)';
}
