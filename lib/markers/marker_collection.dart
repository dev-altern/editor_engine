import 'package:meta/meta.dart';

import '../model/node.dart';
import '../state/editor_state.dart';
import '../state/selection.dart';
import '../transform/step_map.dart';
import '../transform/transaction.dart';
import 'interval_tree.dart';
import 'marker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MarkerCollection — Immutable collection of markers with range queries
// ─────────────────────────────────────────────────────────────────────────────

/// An immutable collection of [Marker]s with efficient range queries.
///
/// Backed by an [IntervalTree] for O(log n + k) overlap queries.
/// All mutation operations return new collections.
///
/// Access from editor state via:
/// ```dart
/// final markers = state.pluginState<MarkerCollection>('markers');
/// final overlapping = markers?.findOverlapping(10, 20) ?? [];
/// ```
@immutable
class MarkerCollection {
  /// Creates a collection from a list of markers.
  factory MarkerCollection(List<Marker> markers) {
    if (markers.isEmpty) return MarkerCollection.empty;
    final entries = markers
        .map(
          (m) =>
              IntervalEntry<Marker>(id: m.id, from: m.from, to: m.to, data: m),
        )
        .toList();
    return MarkerCollection._(IntervalTree(entries));
  }

  const MarkerCollection._(this._tree);

  /// An empty marker collection.
  static final MarkerCollection empty = MarkerCollection._(
    IntervalTree.empty<Marker>(),
  );

  final IntervalTree<Marker> _tree;

  /// The number of markers.
  int get length => _tree.length;

  /// Whether this collection is empty.
  bool get isEmpty => _tree.isEmpty;

  /// Whether this collection is not empty.
  bool get isNotEmpty => _tree.isNotEmpty;

  /// All markers in this collection.
  Iterable<Marker> get markers => _tree.entries.map((e) => e.data);

  /// Returns markers whose ranges overlap with [from]..[to].
  List<Marker> findOverlapping(int from, int to) =>
      _tree.query(from, to).map((e) => e.data).toList();

  /// Returns markers containing [pos].
  List<Marker> findAt(int pos) =>
      _tree.queryPoint(pos).map((e) => e.data).toList();

  /// Returns markers of the given [type].
  List<Marker> findByType(String type) => _tree.entries
      .where((e) => e.data.type == type)
      .map((e) => e.data)
      .toList();

  /// Finds a specific marker by [id].
  Marker? findById(String id) {
    for (final entry in _tree.entries) {
      if (entry.id == id) return entry.data;
    }
    return null;
  }

  /// Returns a new collection with [marker] added.
  MarkerCollection add(Marker marker) {
    final entry = IntervalEntry<Marker>(
      id: marker.id,
      from: marker.from,
      to: marker.to,
      data: marker,
    );
    return MarkerCollection._(_tree.add(entry));
  }

  /// Returns a new collection with the marker of [id] removed.
  MarkerCollection remove(String id) {
    final newTree = _tree.remove(id);
    if (identical(newTree, _tree)) return this;
    return MarkerCollection._(newTree);
  }

  /// Returns a new collection with the marker of [id] updated.
  MarkerCollection update(String id, Marker Function(Marker) updater) {
    final existing = findById(id);
    if (existing == null) return this;
    final updated = updater(existing);
    return remove(id).add(updated);
  }

  /// Maps all markers through a [Mapping], removing collapsed markers.
  MarkerCollection mapThrough(Mapping mapping) {
    final newTree = _tree.map((entry) {
      final mapped = entry.data.mapThrough(mapping);
      if (mapped == null) return null;
      return IntervalEntry<Marker>(
        id: mapped.id,
        from: mapped.from,
        to: mapped.to,
        data: mapped,
      );
    });
    if (identical(newTree, _tree)) return this;
    return MarkerCollection._(newTree);
  }

  /// Serializes to JSON.
  List<Map<String, dynamic>> toJson() =>
      _tree.entries.map((e) => e.data.toJson()).toList();

  /// Deserializes from JSON.
  factory MarkerCollection.fromJson(List<dynamic> json) => MarkerCollection(
    json.cast<Map<String, dynamic>>().map((m) => Marker.fromJson(m)).toList(),
  );

  @override
  String toString() => 'MarkerCollection(${_tree.length} markers)';
}

// ─────────────────────────────────────────────────────────────────────────────
// MarkerPlugin — Plugin that manages markers in editor state
// ─────────────────────────────────────────────────────────────────────────────

/// Plugin that manages [MarkerCollection] as part of [EditorState].
///
/// Access markers via:
/// ```dart
/// final markers = state.pluginState<MarkerCollection>('markers');
/// ```
///
/// Modify markers via transaction metadata:
/// ```dart
/// final tr = Transaction(state.doc)
///   ..insertText(5, 'hello')
///   ..setMeta('addMarker', Marker(id: 'm1', from: 5, to: 10, type: 'comment'));
///
/// // Or remove:
/// final tr = Transaction(state.doc)
///   ..setMeta('removeMarker', 'marker-id');
///
/// // Or update attrs:
/// final tr = Transaction(state.doc)
///   ..setMeta('updateMarker', {'id': 'marker-id', 'attrs': {'resolved': true}});
/// ```
class MarkerPlugin extends Plugin {
  @override
  String get key => 'markers';

  @override
  Object init(DocNode doc, Selection selection) => MarkerCollection.empty;

  @override
  Object apply(Transaction tr, Object? state, {Selection? selectionBefore}) {
    var markers = state as MarkerCollection? ?? MarkerCollection.empty;

    // Map through steps first.
    if (tr.hasSteps) {
      markers = markers.mapThrough(tr.mapping);
    }

    // Process marker operations from metadata.
    final addMarker = tr.getMeta('addMarker');
    if (addMarker is Marker) {
      markers = markers.add(addMarker);
    }

    final removeMarkerId = tr.getMeta('removeMarker');
    if (removeMarkerId is String) {
      markers = markers.remove(removeMarkerId);
    }

    final updateMarker = tr.getMeta('updateMarker');
    if (updateMarker is Map) {
      final id = updateMarker['id'] as String?;
      final attrs = updateMarker['attrs'] as Map<String, Object?>?;
      if (id != null && attrs != null) {
        markers = markers.update(id, (m) => m.copyWith(attrs: attrs));
      }
    }

    return markers;
  }
}
