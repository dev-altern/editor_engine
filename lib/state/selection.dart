import 'package:meta/meta.dart';

import '../transform/step_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Selection — Represents the cursor position / selected range
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all selection types.
///
/// A selection has:
/// - [anchor]: where the selection started (fixed end)
/// - [head]: where the selection extends to (moving end / cursor)
/// - [from]: min(anchor, head)
/// - [to]: max(anchor, head)
@immutable
abstract class Selection {
  const Selection({required this.anchor, required this.head});

  /// Where the selection was anchored.
  final int anchor;

  /// Where the cursor/head is (the moving end).
  final int head;

  /// Start of the selection range.
  int get from => anchor < head ? anchor : head;

  /// End of the selection range.
  int get to => anchor > head ? anchor : head;

  /// Whether this is a collapsed selection (cursor with no range).
  bool get empty => from == to;

  /// Maps this selection through a [StepMap].
  Selection map(StepMap mapping);

  /// Maps this selection through a series of step maps sequentially.
  ///
  /// More accurate than composing all maps into one, as each map
  /// is applied in order to intermediate positions.
  Selection mapThrough(Mapping mapping) {
    var result = this;
    for (final m in mapping.maps) {
      result = result.map(m);
    }
    return result;
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson();

  /// Deserializes from JSON.
  static Selection fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'text':
        return TextSelection.fromJson(json);
      case 'node':
        return NodeSelection.fromJson(json);
      case 'multi':
        return MultiCursorSelection.fromJson(json);
      case 'all':
        return AllSelection.fromJson(json);
      default:
        return TextSelection.fromJson(json);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TextSelection — Standard text cursor / range selection
// ─────────────────────────────────────────────────────────────────────────────

/// A selection in text content — the most common selection type.
///
/// When collapsed (anchor == head), represents a blinking cursor.
/// When extended, represents a highlighted text range.
class TextSelection extends Selection {
  const TextSelection({required super.anchor, required super.head});

  /// Creates a collapsed cursor at [pos].
  const TextSelection.collapsed(int pos) : super(anchor: pos, head: pos);

  /// Creates a selection from [anchor] to [head].
  const TextSelection.range({required super.anchor, required super.head});

  @override
  Selection map(StepMap mapping) {
    if (empty) {
      // Collapsed cursor: both endpoints use same assoc so the cursor
      // moves together (e.g., to after an insertion at the cursor).
      final mapped = mapping.map(anchor, assoc: 1);
      return TextSelection.collapsed(mapped);
    }
    // The "from" side (leftmost) maps with assoc: 1 (stay right of insertions),
    // the "to" side (rightmost) maps with assoc: -1 (stay left of insertions).
    // Preserve direction by checking which side is anchor vs head.
    if (anchor <= head) {
      return TextSelection(
        anchor: mapping.map(anchor, assoc: 1),
        head: mapping.map(head, assoc: -1),
      );
    } else {
      return TextSelection(
        anchor: mapping.map(anchor, assoc: -1),
        head: mapping.map(head, assoc: 1),
      );
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'anchor': anchor,
    'head': head,
  };

  factory TextSelection.fromJson(Map<String, dynamic> json) =>
      TextSelection(anchor: json['anchor'] as int, head: json['head'] as int);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextSelection && anchor == other.anchor && head == other.head;

  @override
  int get hashCode => Object.hash(anchor, head);

  @override
  String toString() =>
      empty ? 'TextSelection.cursor($anchor)' : 'TextSelection($anchor→$head)';
}

// ─────────────────────────────────────────────────────────────────────────────
// NodeSelection — Selects an entire node (e.g., an image block)
// ─────────────────────────────────────────────────────────────────────────────

/// Selects an entire node, such as an image, divider, or embed block.
///
/// [from] and [to] bracket the node: from is before the node, to is after.
/// The [nodeSize] parameter specifies the size of the selected node
/// (defaults to 1 for leaf/atom nodes).
class NodeSelection extends Selection {
  const NodeSelection(int pos, [this.nodeSize = 1])
    : super(anchor: pos, head: pos + nodeSize);

  /// The size of the selected node.
  final int nodeSize;

  /// The position of the selected node.
  int get nodePos => anchor;

  @override
  bool get empty => false;

  @override
  Selection map(StepMap mapping) {
    final newPos = mapping.map(anchor);
    final newEnd = mapping.map(anchor + nodeSize);
    return NodeSelection(newPos, newEnd - newPos);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'node',
    'anchor': anchor,
    if (nodeSize != 1) 'nodeSize': nodeSize,
  };

  factory NodeSelection.fromJson(Map<String, dynamic> json) =>
      NodeSelection(json['anchor'] as int, json['nodeSize'] as int? ?? 1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeSelection &&
          anchor == other.anchor &&
          nodeSize == other.nodeSize;

  @override
  int get hashCode => Object.hash(anchor, nodeSize);

  @override
  String toString() => 'NodeSelection($anchor, size: $nodeSize)';
}

// ─────────────────────────────────────────────────────────────────────────────
// MultiCursorSelection — Multiple simultaneous cursors/ranges
// ─────────────────────────────────────────────────────────────────────────────

/// Multiple cursors or selection ranges active simultaneously.
///
/// Each range is an independent [TextSelection].
/// The primary cursor is the last one in the list.
///
/// Must contain at least one range.
class MultiCursorSelection extends Selection {
  MultiCursorSelection(this.ranges)
    : assert(
        ranges.isNotEmpty,
        'MultiCursorSelection requires at least one range',
      ),
      super(
        anchor: ranges.isNotEmpty ? ranges.last.anchor : 0,
        head: ranges.isNotEmpty ? ranges.last.head : 0,
      );

  /// All active selection ranges.
  final List<TextSelection> ranges;

  /// The primary (last) selection.
  TextSelection get primary => ranges.last;

  @override
  Selection map(StepMap mapping) => MultiCursorSelection(
    ranges.map((r) => r.map(mapping) as TextSelection).toList(),
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'multi',
    'ranges': ranges.map((r) => r.toJson()).toList(),
  };

  factory MultiCursorSelection.fromJson(Map<String, dynamic> json) =>
      MultiCursorSelection(
        (json['ranges'] as List<dynamic>)
            .map((r) => TextSelection.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MultiCursorSelection) return false;
    if (ranges.length != other.ranges.length) return false;
    for (var i = 0; i < ranges.length; i++) {
      if (ranges[i] != other.ranges[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ranges);

  @override
  String toString() => 'MultiCursor(${ranges.length} ranges)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AllSelection — Selects the entire document
// ─────────────────────────────────────────────────────────────────────────────

/// Selects the entire document content.
class AllSelection extends Selection {
  const AllSelection(int docSize) : super(anchor: 0, head: docSize);

  @override
  Selection map(StepMap mapping) => AllSelection(mapping.map(head));

  @override
  Map<String, dynamic> toJson() => {'type': 'all', 'size': head};

  factory AllSelection.fromJson(Map<String, dynamic> json) =>
      AllSelection(json['size'] as int);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AllSelection && head == other.head;

  @override
  int get hashCode => head.hashCode;

  @override
  String toString() => 'AllSelection(0→$head)';
}
