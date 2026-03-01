import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'fragment.dart';
import 'mark.dart';
import 'resolved_pos.dart';

export 'resolved_pos.dart';
export 'slice.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Node — The base class for all document nodes
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all nodes in the document tree.
///
/// A document is a tree of nodes. Each node has a [type], optional [attrs],
/// and [content] (child nodes). Inline nodes also carry [marks] (formatting).
///
/// ## Position model
///
/// The document uses an integer-based position system (from ProseMirror):
/// - Each character in a text node counts as 1
/// - Each leaf node (image, divider, inline widget) counts as 1
/// - Each non-leaf node contributes 2 (open + close) plus its content size
///
/// Example:
/// ```
///     0   1    2   3   4    5   6   7   8   9
///     <p> "H"  "i" </p> <img/> <p> "B"  "y" </p>
/// ```
@immutable
abstract class Node {
  /// Creates a node with the given properties.
  const Node({
    required this.type,
    this.attrs = const {},
    this.content = Fragment.empty,
    this.marks = const [],
  });

  /// The node type name (e.g., "paragraph", "heading", "text").
  final String type;

  /// Node-specific attributes (e.g., level for headings, src for images).
  final Map<String, Object?> attrs;

  /// Child nodes. Empty for leaf nodes (text, images, etc.).
  final Fragment content;

  /// Marks applied to this node (only meaningful for inline nodes).
  final List<Mark> marks;

  /// A unique ID for this node, useful for tracking across edits.
  /// Override in subclasses that need stable identity.
  String? get id => attrs['id'] as String?;

  // ── Size calculations ───────────────────────────────────────────────

  /// The size this node occupies in the document's position space.
  int get nodeSize;

  /// The size of this node's content only (excluding open/close tokens).
  int get contentSize => content.size;

  /// The number of direct child nodes.
  int get childCount => content.childCount;

  // ── Type checks ─────────────────────────────────────────────────────

  /// Whether this is a text node.
  bool get isText => false;

  /// Whether this is a block node (not inline).
  bool get isBlock => !isInline;

  /// Whether this is an inline node (text, inline widget).
  bool get isInline => false;

  /// Whether this is a leaf node (no content allowed).
  bool get isLeaf => false;

  /// Whether this node has inline content.
  bool get inlineContent => false;

  /// Whether this is an "atom" — treated as a single unit for selection.
  bool get isAtom => isLeaf;

  /// Whether this is a text block (block with inline content).
  bool get isTextblock => isBlock && inlineContent;

  // ── Tree operations ─────────────────────────────────────────────────

  /// Returns a copy of this node with different content.
  Node copy(Fragment newContent);

  /// Returns a copy with updated attributes.
  Node withAttrs(Map<String, Object?> newAttrs);

  /// Returns the child node at [index].
  Node child(int index) => content.child(index);

  /// Returns the child at [index], or null if out of bounds.
  Node? maybeChild(int index) => content.maybeChild(index);

  /// Iterates over direct children.
  void forEach(void Function(Node node, int offset, int index) callback) =>
      content.forEach(callback);

  /// Returns the text content of this node and all descendants.
  String get textContent {
    final buffer = StringBuffer();
    _collectText(buffer);
    return buffer.toString();
  }

  void _collectText(StringBuffer buffer) {
    content.forEach((node, _, _) => node._collectText(buffer));
  }

  /// Returns all descendant text nodes in document order.
  Iterable<TextNode> get textNodes sync* {
    if (isText) {
      yield this as TextNode;
    } else {
      for (var i = 0; i < content.childCount; i++) {
        yield* content.child(i).textNodes;
      }
    }
  }

  // ── Descendant walking ──────────────────────────────────────────────

  /// Walks all descendant nodes depth-first.
  ///
  /// The callback receives the node, its absolute position in the parent,
  /// and its parent node. Return `false` to stop early.
  void descendants(bool Function(Node node, int pos, Node? parent) callback) {
    _walkDescendants(callback, 0, null);
  }

  int _walkDescendants(
    bool Function(Node node, int pos, Node? parent) callback,
    int pos,
    Node? parent,
  ) {
    for (var i = 0; i < content.childCount; i++) {
      final child = content.child(i);
      final before = pos;
      if (!child.isLeaf) {
        // Non-leaf: skip open token
        if (!callback(child, before, this)) return -1;
        final result = child._walkDescendants(callback, pos + 1, child);
        if (result < 0) return -1;
        pos = result;
        pos++; // close token
      } else {
        if (!callback(child, before, this)) return -1;
        pos += child.nodeSize;
      }
    }
    return pos;
  }

  // ── Resolve position ────────────────────────────────────────────────

  /// Resolves an integer [pos] into a [ResolvedPos] within this node.
  ResolvedPos resolve(int pos) {
    return ResolvedPos.resolve(this, pos);
  }

  // ── Serialization ───────────────────────────────────────────────────

  /// Serializes this node to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes a node from a JSON-compatible map.
  ///
  /// Uses a registry pattern — callers should register node types
  /// or use the default set.
  static Node nodeFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'text':
        return TextNode.fromJson(json);
      case 'doc':
        return DocNode.fromJson(json);
      case 'inline_widget':
        return InlineWidgetNode.fromJson(json);
      default:
        return BlockNode.fromJson(json);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Node || type != other.type) return false;
    if (!const DeepCollectionEquality().equals(attrs, other.attrs)) {
      return false;
    }
    if (!const ListEquality<Mark>().equals(marks, other.marks)) return false;
    return content == other.content;
  }

  @override
  int get hashCode => Object.hash(
    type,
    const DeepCollectionEquality().hash(attrs),
    const ListEquality<Mark>().hash(marks),
    content,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TextNode — Leaf node containing text with marks
// ─────────────────────────────────────────────────────────────────────────────

/// A leaf node containing text content with optional inline marks.
///
/// Text nodes are always inline and always leaves (no children).
/// Adjacent text nodes with identical mark sets are merged automatically
/// when constructing fragments.
class TextNode extends Node {
  /// Creates a text node with the given [text] and optional [marks].
  const TextNode(this.text, {super.marks = const []})
    : super(type: 'text', content: Fragment.empty);

  /// The text content.
  final String text;

  @override
  bool get isText => true;

  @override
  bool get isInline => true;

  @override
  bool get isLeaf => true;

  @override
  int get nodeSize => text.length;

  @override
  int get contentSize => 0;

  @override
  void _collectText(StringBuffer buffer) => buffer.write(text);

  /// Returns a new text node with a substring of this text.
  TextNode cut(int from, [int? to]) {
    final end = to ?? text.length;
    if (from == 0 && end == text.length) return this;
    return TextNode(text.substring(from, end), marks: marks);
  }

  /// Returns a new text node with the given [marks].
  TextNode withMarks(List<Mark> newMarks) => TextNode(text, marks: newMarks);

  /// Returns a new text node with the mark [mark] added.
  TextNode addMark(Mark mark) => TextNode(text, marks: marks.addMark(mark));

  /// Returns a new text node with the mark of type [type] removed.
  TextNode removeMark(String type) =>
      TextNode(text, marks: marks.removeMark(type));

  @override
  Node copy(Fragment newContent) => this; // Text nodes have no content

  @override
  Node withAttrs(Map<String, Object?> newAttrs) => this; // Text has no attrs

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'text': text,
    if (marks.isNotEmpty) 'marks': marks.map((m) => m.toJson()).toList(),
  };

  factory TextNode.fromJson(Map<String, dynamic> json) => TextNode(
    json['text'] as String,
    marks:
        (json['marks'] as List<dynamic>?)
            ?.map((m) => Mark.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextNode &&
          text == other.text &&
          const ListEquality<Mark>().equals(marks, other.marks);

  @override
  int get hashCode => Object.hash(text, const ListEquality<Mark>().hash(marks));

  @override
  String toString() {
    final marksStr = marks.isEmpty ? '' : ', marks: [${marks.join(', ')}]';
    final display = text.length > 40 ? '${text.substring(0, 37)}...' : text;
    return 'TextNode("$display"$marksStr)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BlockNode — Non-leaf node for block-level content
// ─────────────────────────────────────────────────────────────────────────────

/// A block-level node that can contain child nodes.
///
/// Block nodes form the backbone of the document tree:
/// paragraphs, headings, blockquotes, lists, tables, etc.
///
/// A block can be:
/// - **Textblock**: contains inline content (paragraph, heading)
/// - **Container**: contains other blocks (blockquote, list)
/// - **Leaf block**: no content (image, divider, horizontal rule)
class BlockNode extends Node {
  /// Creates a block node.
  const BlockNode({
    required super.type,
    super.attrs = const {},
    super.content = Fragment.empty,
    bool isLeaf = false,
    bool isInline = false,
    bool inlineContent = false,
    bool isAtom = false,
  }) : _isLeaf = isLeaf,
       _isInline = isInline,
       _inlineContent = inlineContent,
       _isAtom = isAtom;

  final bool _isLeaf;
  final bool _isInline;
  final bool _inlineContent;
  final bool _isAtom;

  @override
  bool get isLeaf => _isLeaf;

  @override
  bool get isInline => _isInline;

  @override
  bool get inlineContent => _inlineContent;

  @override
  bool get isAtom => _isAtom || _isLeaf;

  @override
  int get nodeSize => _isLeaf ? 1 : content.size + 2;

  @override
  Node copy(Fragment newContent) => BlockNode(
    type: type,
    attrs: attrs,
    content: newContent,
    isLeaf: _isLeaf,
    isInline: _isInline,
    inlineContent: _inlineContent,
    isAtom: _isAtom,
  );

  @override
  Node withAttrs(Map<String, Object?> newAttrs) => BlockNode(
    type: type,
    attrs: newAttrs,
    content: content,
    isLeaf: _isLeaf,
    isInline: _isInline,
    inlineContent: _inlineContent,
    isAtom: _isAtom,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    if (attrs.isNotEmpty) 'attrs': attrs,
    if (_isLeaf) 'isLeaf': true,
    if (_isAtom) 'isAtom': true,
    if (_isInline) 'isInline': true,
    if (content.isNotEmpty) 'content': content.toJson(),
  };

  factory BlockNode.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final attrs =
        (json['attrs'] as Map<String, dynamic>?)?.cast<String, Object?>() ??
        const {};
    final content = json['content'] != null
        ? Fragment.fromJson(json['content'] as List<dynamic>)
        : Fragment.empty;

    // Infer inlineContent from actual children
    final hasInline = content.isNotEmpty && content.children.first.isInline;

    return BlockNode(
      type: type,
      attrs: attrs,
      content: content,
      isLeaf: json['isLeaf'] as bool? ?? false,
      isAtom: json['isAtom'] as bool? ?? false,
      isInline: json['isInline'] as bool? ?? false,
      inlineContent: hasInline,
    );
  }

  @override
  String toString() {
    final attrStr = attrs.isEmpty ? '' : ', attrs: $attrs';
    final contentStr = content.isEmpty
        ? ''
        : ', ${content.childCount} children';
    return 'BlockNode($type$attrStr$contentStr)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// InlineWidgetNode — Inline non-text content (mentions, dates, emoji)
// ─────────────────────────────────────────────────────────────────────────────

/// An inline leaf node representing a non-text widget embedded in text.
///
/// Examples: @mentions, date chips, emoji, status badges, inline formulas.
///
/// Inline widgets:
/// - Are inline (appear within text flow)
/// - Are atoms (treated as a single unit, nodeSize = 1)
/// - Have no text content
/// - Carry data in [attrs] (e.g., userId for mentions)
/// - Can carry [marks] (e.g., a bold mention)
class InlineWidgetNode extends Node {
  /// Creates an inline widget node.
  InlineWidgetNode({
    required String widgetType,
    Map<String, Object?> attrs = const {},
    super.marks = const [],
  }) : super(
         type: 'inline_widget',
         attrs: {'widgetType': widgetType, ...attrs},
         content: Fragment.empty,
       );

  /// The widget type name (e.g., "mention", "date", "emoji").
  String get widgetType => attrs['widgetType'] as String;

  @override
  bool get isInline => true;

  @override
  bool get isLeaf => true;

  @override
  bool get isAtom => true;

  @override
  int get nodeSize => 1;

  @override
  Node copy(Fragment newContent) => this; // Leaf — no content

  @override
  Node withAttrs(Map<String, Object?> newAttrs) => InlineWidgetNode(
    widgetType: newAttrs['widgetType'] as String? ?? widgetType,
    attrs: newAttrs,
    marks: marks,
  );

  /// Returns a new inline widget with the given [marks].
  InlineWidgetNode withMarks(List<Mark> newMarks) =>
      InlineWidgetNode(widgetType: widgetType, attrs: attrs, marks: newMarks);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'inline_widget',
    'attrs': attrs,
    if (marks.isNotEmpty) 'marks': marks.map((m) => m.toJson()).toList(),
  };

  factory InlineWidgetNode.fromJson(Map<String, dynamic> json) =>
      InlineWidgetNode(
        widgetType:
            (json['attrs'] as Map<String, dynamic>)['widgetType'] as String,
        attrs: (json['attrs'] as Map<String, dynamic>).cast<String, Object?>(),
        marks:
            (json['marks'] as List<dynamic>?)
                ?.map((m) => Mark.fromJson(m as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() => 'InlineWidget($widgetType, $attrs)';
}

// ─────────────────────────────────────────────────────────────────────────────
// DocNode — Root document node
// ─────────────────────────────────────────────────────────────────────────────

/// The root node of a document.
///
/// A document is a single DocNode whose children are top-level blocks.
/// The DocNode itself is not rendered — it exists only as a container.
class DocNode extends Node {
  /// Creates a document node with the given block children.
  const DocNode({super.content = Fragment.empty}) : super(type: 'doc');

  /// Creates a document from a list of block nodes.
  factory DocNode.fromBlocks(List<Node> blocks) =>
      DocNode(content: Fragment(blocks));

  @override
  int get nodeSize => content.size + 2;

  @override
  bool get isBlock => true;

  @override
  Node copy(Fragment newContent) => DocNode(content: newContent);

  @override
  Node withAttrs(Map<String, Object?> newAttrs) => this; // Doc has no attrs

  @override
  Map<String, dynamic> toJson() => {
    'type': 'doc',
    if (content.isNotEmpty) 'content': content.toJson(),
  };

  factory DocNode.fromJson(Map<String, dynamic> json) => DocNode(
    content: json['content'] != null
        ? Fragment.fromJson(json['content'] as List<dynamic>)
        : Fragment.empty,
  );

  @override
  String toString() => 'DocNode(${content.childCount} blocks)';
}
