import 'package:meta/meta.dart';

import '../transform/step_map.dart';
import '../transform/transaction.dart';
import '../model/node.dart';
import 'editor_state.dart';
import 'selection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DecorationSpec — Metadata about a decoration type
// ─────────────────────────────────────────────────────────────────────────────

/// Metadata describing the type and purpose of a decoration.
///
/// A spec gives decorations a semantic identity beyond their position and
/// attributes — useful for filtering, styling, and debugging.
///
/// ```dart
/// final spec = DecorationSpec(type: 'search-highlight', attrs: {'index': 3});
/// ```
@immutable
class DecorationSpec {
  /// Creates a decoration spec.
  const DecorationSpec({required this.type, this.attrs = const {}});

  /// The decoration type name (e.g., "search-highlight", "lint-warning").
  final String type;

  /// Additional attributes for this decoration type.
  final Map<String, Object?> attrs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecorationSpec &&
          type == other.type &&
          _mapsEqual(attrs, other.attrs);

  @override
  int get hashCode => Object.hash(type, _mapHash(attrs));

  @override
  String toString() {
    final attrStr = attrs.isEmpty ? '' : ', attrs: $attrs';
    return 'DecorationSpec($type$attrStr)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoration — Base class for visual annotations
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for visual annotations that don't affect document content.
///
/// Decorations are used to add visual styling, widgets, or metadata to
/// the editor view without modifying the underlying document model.
/// They are managed separately from the document and mapped through
/// edits to stay in sync.
///
/// Three types of decorations are supported:
/// - [InlineDecoration] — range-based (highlights, underlines, syntax coloring)
/// - [NodeDecoration] — targets an entire node (selected block, drag target)
/// - [WidgetDecoration] — inserts a widget at a position (line numbers, fold markers)
@immutable
sealed class Decoration {
  const Decoration();

  /// Maps this decoration through a [Mapping], returning the updated
  /// decoration or `null` if it was deleted by the edit.
  Decoration? mapThrough(Mapping mapping);
}

// ─────────────────────────────────────────────────────────────────────────────
// InlineDecoration — Range-based decoration (highlights, underlines, etc.)
// ─────────────────────────────────────────────────────────────────────────────

/// A decoration that spans a range of the document.
///
/// Inline decorations are used for highlighting, syntax coloring, underlines,
/// search matches, spell-check errors, and any styling that covers a
/// contiguous range of text or inline content.
///
/// When mapped through edits:
/// - If the entire range is deleted, the decoration is removed.
/// - Otherwise, [from] and [to] are mapped to stay around the surviving content.
///
/// ```dart
/// final highlight = InlineDecoration(
///   5, 15,
///   {'class': 'search-match'},
///   spec: DecorationSpec(type: 'search', attrs: {'index': 0}),
/// );
/// ```
@immutable
class InlineDecoration extends Decoration {
  /// Creates an inline decoration spanning [from]..[to].
  const InlineDecoration(this.from, this.to, this.attrs, {this.spec});

  /// The start position of the decorated range (inclusive).
  final int from;

  /// The end position of the decorated range (exclusive).
  final int to;

  /// Visual attributes for this decoration (e.g., CSS classes, colors).
  final Map<String, Object?> attrs;

  /// Optional metadata about the decoration type.
  final DecorationSpec? spec;

  @override
  Decoration? mapThrough(Mapping mapping) {
    // Map from to the right (assoc: 1) so the start doesn't expand outward.
    // Map to to the left (assoc: -1) so the end doesn't expand outward.
    final newFrom = mapping.map(from, assoc: 1);
    final newTo = mapping.map(to, assoc: -1);

    // If the range collapsed or inverted, the content was fully deleted.
    if (newFrom >= newTo) return null;

    return InlineDecoration(newFrom, newTo, attrs, spec: spec);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineDecoration &&
          from == other.from &&
          to == other.to &&
          spec == other.spec &&
          _mapsEqual(attrs, other.attrs);

  @override
  int get hashCode => Object.hash(from, to, spec, _mapHash(attrs));

  @override
  String toString() {
    final specStr = spec != null ? ', spec: $spec' : '';
    return 'InlineDecoration($from, $to, $attrs$specStr)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NodeDecoration — Decoration on an entire node
// ─────────────────────────────────────────────────────────────────────────────

/// A decoration that targets an entire node at a given position.
///
/// Node decorations are used for block-level styling: selected blocks,
/// drag targets, collapsible section headers, etc.
///
/// [pos] should point to the start of the node (the position just before
/// the node's opening token).
///
/// When mapped through edits, the position moves with the node.
///
/// ```dart
/// final selected = NodeDecoration(0, {'class': 'selected-block'});
/// ```
@immutable
class NodeDecoration extends Decoration {
  /// Creates a node decoration at [pos].
  const NodeDecoration(this.pos, this.attrs);

  /// The position of the decorated node.
  final int pos;

  /// Visual attributes for this decoration.
  final Map<String, Object?> attrs;

  @override
  Decoration? mapThrough(Mapping mapping) {
    final newPos = mapping.mapOrNull(pos, assoc: 1);
    if (newPos == null) return null;
    return NodeDecoration(newPos, attrs);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeDecoration &&
          pos == other.pos &&
          _mapsEqual(attrs, other.attrs);

  @override
  int get hashCode => Object.hash(pos, _mapHash(attrs));

  @override
  String toString() => 'NodeDecoration($pos, $attrs)';
}

// ─────────────────────────────────────────────────────────────────────────────
// WidgetDecoration — Widget inserted at a position
// ─────────────────────────────────────────────────────────────────────────────

/// A decoration that inserts a widget at a specific position.
///
/// Widget decorations are used for line numbers, fold markers, breakpoints,
/// inline buttons, and any UI element that lives at a point in the document
/// without occupying document space.
///
/// [side] controls whether the widget appears before (`false`) or after
/// (`true`) the content at [pos]. This matters when multiple widgets are
/// placed at the same position.
///
/// When mapped through edits, the position moves with the surrounding content.
///
/// ```dart
/// final lineNumber = WidgetDecoration(0, attrs: {'line': 1});
/// final foldMarker = WidgetDecoration(0, side: true, attrs: {'folded': false});
/// ```
@immutable
class WidgetDecoration extends Decoration {
  /// Creates a widget decoration at [pos].
  const WidgetDecoration(this.pos, {this.side = false, this.attrs = const {}});

  /// The position where the widget is inserted.
  final int pos;

  /// Whether the widget appears after (`true`) or before (`false`) the
  /// content at [pos].
  final bool side;

  /// Visual attributes for this widget decoration.
  final Map<String, Object?> attrs;

  @override
  Decoration? mapThrough(Mapping mapping) {
    // Use assoc based on side: widgets after content map right (+1),
    // widgets before content map left (-1).
    final assoc = side ? 1 : -1;
    final newPos = mapping.mapOrNull(pos, assoc: assoc);
    if (newPos == null) return null;
    return WidgetDecoration(newPos, side: side, attrs: attrs);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetDecoration &&
          pos == other.pos &&
          side == other.side &&
          _mapsEqual(attrs, other.attrs);

  @override
  int get hashCode => Object.hash(pos, side, _mapHash(attrs));

  @override
  String toString() {
    final sideStr = side ? ', side: true' : '';
    return 'WidgetDecoration($pos$sideStr, $attrs)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DecorationSet — Efficient collection of decorations
// ─────────────────────────────────────────────────────────────────────────────

/// An immutable, efficient collection of decorations.
///
/// A DecorationSet holds all decorations for a given editor state and
/// provides methods to query, add, remove, and map them through edits.
///
/// Decorations in the set are stored in a flat list. For large numbers of
/// decorations, consider partitioning into multiple sets by type.
///
/// ```dart
/// var decos = DecorationSet.empty;
/// decos = decos.add(InlineDecoration(5, 15, {'class': 'highlight'}));
/// decos = decos.add(NodeDecoration(0, {'class': 'selected'}));
///
/// // After an edit, map through the transaction's mapping:
/// decos = decos.map(tr.mapping);
/// ```
@immutable
class DecorationSet {
  /// Creates a decoration set from a list of decorations.
  DecorationSet(List<Decoration> decorations)
    : _decorations = List.unmodifiable(decorations);

  /// An empty decoration set.
  static final DecorationSet empty = DecorationSet(const []);

  final List<Decoration> _decorations;

  late final List<InlineDecoration> _inlines = _decorations
      .whereType<InlineDecoration>()
      .toList(growable: false);
  late final List<NodeDecoration> _nodes = _decorations
      .whereType<NodeDecoration>()
      .toList(growable: false);
  late final List<WidgetDecoration> _widgets = _decorations
      .whereType<WidgetDecoration>()
      .toList(growable: false);

  // ── Size ────────────────────────────────────────────────────────────

  /// The number of decorations in this set.
  int get length => _decorations.length;

  /// Whether this set contains no decorations.
  bool get isEmpty => _decorations.isEmpty;

  /// Whether this set contains at least one decoration.
  bool get isNotEmpty => _decorations.isNotEmpty;

  /// An iterable of all decorations in this set.
  Iterable<Decoration> get decorations => _decorations;

  // ── Modification ───────────────────────────────────────────────────

  /// Returns a new set with [decoration] added.
  DecorationSet add(Decoration decoration) {
    return DecorationSet([..._decorations, decoration]);
  }

  /// Returns a new set with [decoration] removed.
  ///
  /// If the decoration is not found, returns this set unchanged.
  DecorationSet remove(Decoration decoration) {
    final index = _decorations.indexOf(decoration);
    if (index < 0) return this;
    final newList = List<Decoration>.of(_decorations)..removeAt(index);
    return DecorationSet(newList);
  }

  // ── Querying ───────────────────────────────────────────────────────

  /// Finds all decorations matching the given criteria.
  ///
  /// [from] and [to] filter by position range (inclusive). The semantics
  /// depend on decoration type:
  /// - InlineDecoration: overlaps the range [from]..[to]
  /// - NodeDecoration: [pos] is within [from]..[to]
  /// - WidgetDecoration: [pos] is within [from]..[to]
  ///
  /// [type] filters by [DecorationSpec.type] (only applies to decorations
  /// that have a spec, currently [InlineDecoration]).
  List<Decoration> find({int? from, int? to, String? type}) {
    // Type filter — only InlineDecorations have specs
    if (type != null) {
      final source = _inlines.where((d) => d.spec?.type == type);
      if (from == null && to == null) return source.toList();
      final rangeFrom = from ?? 0;
      final rangeTo = to ?? _maxInt;
      return source.where((d) => d.from < rangeTo && d.to > rangeFrom).toList();
    }

    if (from == null && to == null) return List.of(_decorations);

    final rangeFrom = from ?? 0;
    final rangeTo = to ?? _maxInt;
    return _decorations.where((d) {
      switch (d) {
        case InlineDecoration(:final from, :final to):
          if (from >= rangeTo || to <= rangeFrom) return false;
        case NodeDecoration(:final pos):
          if (pos < rangeFrom || pos >= rangeTo) return false;
        case WidgetDecoration(:final pos):
          if (pos < rangeFrom || pos >= rangeTo) return false;
      }
      return true;
    }).toList();
  }

  /// Finds all inline decorations that overlap the range [from]..[to].
  List<InlineDecoration> findInline(int from, int to) {
    return _inlines.where((d) => d.from < to && d.to > from).toList();
  }

  /// Finds all node decorations at [pos].
  List<NodeDecoration> findNode(int pos) {
    return _nodes.where((d) => d.pos == pos).toList();
  }

  /// Finds all widget decorations at [pos].
  List<WidgetDecoration> findWidget(int pos) {
    return _widgets.where((d) => d.pos == pos).toList();
  }

  // ── Mapping ────────────────────────────────────────────────────────

  /// Maps all decorations through a [Mapping], returning a new set.
  ///
  /// Decorations that are fully deleted by the mapping are removed.
  /// Surviving decorations have their positions updated to reflect
  /// the new document.
  DecorationSet map(Mapping mapping) {
    if (_decorations.isEmpty || mapping.length == 0) return this;

    final mapped = <Decoration>[];
    for (final d in _decorations) {
      final result = d.mapThrough(mapping);
      if (result != null) {
        mapped.add(result);
      }
    }

    return DecorationSet(mapped);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecorationSet && _listsEqual(_decorations, other._decorations);

  @override
  int get hashCode => Object.hashAll(_decorations);

  @override
  String toString() {
    if (_decorations.isEmpty) return 'DecorationSet.empty';
    return 'DecorationSet(${_decorations.length} decorations)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DecorationPlugin — Plugin that manages decorations in editor state
// ─────────────────────────────────────────────────────────────────────────────

/// A plugin that manages a [DecorationSet] as part of editor state.
///
/// When a transaction is applied, the plugin maps all decorations through
/// the transaction's mapping so that they stay in sync with document edits.
///
/// ```dart
/// final state = EditorState.create(
///   schema: schema,
///   plugins: [DecorationPlugin()],
/// );
///
/// // Access decorations:
/// final decos = state.pluginState<DecorationSet>('decorations');
/// ```
class DecorationPlugin extends Plugin {
  @override
  String get key => 'decorations';

  @override
  Object init(DocNode doc, Selection selection) => DecorationSet.empty;

  @override
  Object apply(Transaction tr, Object? state, {Selection? selectionBefore}) {
    final decoSet = state as DecorationSet? ?? DecorationSet.empty;

    // If the transaction has steps, map decorations through the mapping.
    if (tr.hasSteps) {
      return decoSet.map(tr.mapping);
    }

    return decoSet;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Largest SMI (Small Integer) on 64-bit Dart VM.
const int _maxInt = 0x3FFFFFFFFFFFFFFF;

/// Deep-equality check for `Map<String, Object?>` without pulling in
/// `package:collection`.
bool _mapsEqual(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Order-independent hash for `Map<String, Object?>`.
/// Uses XOR so iteration order does not affect the result.
int _mapHash(Map<String, Object?> m) {
  var h = 0;
  for (final entry in m.entries) {
    h ^= Object.hash(entry.key, entry.value);
  }
  return h;
}

/// Equality check for `List<Decoration>`.
bool _listsEqual(List<Decoration> a, List<Decoration> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
