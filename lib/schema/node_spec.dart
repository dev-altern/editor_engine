import 'package:meta/meta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AttrSpec — Attribute specification
// ─────────────────────────────────────────────────────────────────────────────

/// Specifies a single attribute for a node or mark type.
@immutable
class AttrSpec {
  /// Creates an attribute spec.
  ///
  /// If [defaultValue] is provided, the attribute is optional.
  /// If null and [required] is true, nodes must always specify this attr.
  const AttrSpec({
    this.defaultValue,
    this.required = false,
  });

  /// The default value. If null and not required, the attribute is optional.
  final Object? defaultValue;

  /// Whether this attribute must be explicitly provided.
  final bool required;

  /// Whether this attribute has a default value.
  bool get hasDefault => defaultValue != null || !required;
}

// ─────────────────────────────────────────────────────────────────────────────
// NodeSpec — Node type specification
// ─────────────────────────────────────────────────────────────────────────────

/// Defines a node type within a schema.
///
/// A NodeSpec describes:
/// - What content the node can contain ([content] expression)
/// - What marks are allowed on its inline content ([marks])
/// - What attributes it has ([attrs])
/// - Behavioral flags (leaf, atom, inline, etc.)
///
/// Content expressions follow ProseMirror's grammar:
/// - `"block+"` — one or more block nodes
/// - `"inline*"` — zero or more inline nodes
/// - `"paragraph block*"` — a paragraph followed by any blocks
/// - `""` — no content (leaf node)
@immutable
class NodeSpec {
  const NodeSpec({
    required this.name,
    this.group,
    this.content = '',
    this.marks = '_',
    this.attrs = const {},
    this.inline = false,
    this.atom = false,
    this.selectable = true,
    this.draggable = false,
    this.isolating = false,
    this.defining = false,
  });

  /// The type name (e.g., "paragraph", "heading", "image").
  final String name;

  /// The group this node belongs to (e.g., "block", "inline", "list_item").
  final String? group;

  /// Content expression defining allowed children.
  ///
  /// Examples:
  /// - `"block+"` — one or more block nodes
  /// - `"inline*"` — zero or more inline nodes
  /// - `""` — no content (leaf)
  /// - `"paragraph heading*"` — a paragraph then optional headings
  final String content;

  /// Which marks are allowed on inline content within this node.
  ///
  /// - `"_"` — all marks allowed (default)
  /// - `""` — no marks allowed
  /// - `"bold italic"` — only bold and italic
  final String marks;

  /// Attribute definitions for this node type.
  final Map<String, AttrSpec> attrs;

  /// Whether this is an inline node (participates in text flow).
  final bool inline;

  /// Whether this node is treated as a single unit for selection/editing.
  final bool atom;

  /// Whether this node can be selected as a node selection.
  final bool selectable;

  /// Whether this node can be dragged to reorder.
  final bool draggable;

  /// Whether selection can cross into/out of this node.
  final bool isolating;

  /// Whether this node defines its type (content replacement preserves type).
  final bool defining;

  /// Whether this is a leaf node (no content allowed).
  bool get isLeaf => content.isEmpty;

  /// Whether this node has inline content.
  bool get hasInlineContent =>
      content.contains('inline') || content.contains('text');
}

// ─────────────────────────────────────────────────────────────────────────────
// MarkSpec — Mark type specification
// ─────────────────────────────────────────────────────────────────────────────

/// Defines a mark type within a schema.
@immutable
class MarkSpec {
  const MarkSpec({
    required this.name,
    this.attrs = const {},
    this.inclusive = true,
    this.excludes,
    this.group,
    this.spanning = true,
  });

  /// The mark type name (e.g., "bold", "italic", "link").
  final String name;

  /// Attribute definitions for this mark type.
  final Map<String, AttrSpec> attrs;

  /// Whether this mark is inclusive (applies to text inserted at edges).
  ///
  /// True for bold/italic, false for links.
  final bool inclusive;

  /// Mark types that this mark excludes (can't coexist with).
  ///
  /// Space-separated type names. `"_"` excludes all other marks.
  final String? excludes;

  /// The group this mark belongs to.
  final String? group;

  /// Whether this mark can span across multiple nodes.
  final bool spanning;
}
