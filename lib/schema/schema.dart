import 'package:meta/meta.dart';

import '../model/fragment.dart';
import '../model/mark.dart';
import '../model/node.dart';
import 'content_expression.dart';
import 'node_spec.dart';

export 'content_expression.dart';
export 'node_spec.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Schema — The document schema
// ─────────────────────────────────────────────────────────────────────────────

/// Defines the structure of documents — what nodes and marks are allowed,
/// and how they can be nested.
///
/// Every document must conform to a schema. The schema enforces structural
/// validity, provides node/mark creation utilities, and drives serialization.
///
/// Example:
/// ```dart
/// final schema = Schema(
///   nodes: {
///     'doc': NodeSpec(name: 'doc', content: 'block+'),
///     'paragraph': NodeSpec(name: 'paragraph', group: 'block', content: 'inline*'),
///     'heading': NodeSpec(name: 'heading', group: 'block', content: 'inline*',
///       attrs: {'level': AttrSpec(defaultValue: 1)}),
///     'image': NodeSpec(name: 'image', group: 'block', atom: true),
///     'text': NodeSpec(name: 'text', group: 'inline', inline: true),
///   },
///   marks: {
///     'bold': MarkSpec(name: 'bold'),
///     'italic': MarkSpec(name: 'italic'),
///     'link': MarkSpec(name: 'link', inclusive: false,
///       attrs: {'href': AttrSpec(required: true)}),
///   },
/// );
/// ```
@immutable
class Schema {
  /// Creates a schema from node and mark specifications.
  Schema({
    required Map<String, NodeSpec> nodes,
    Map<String, MarkSpec> marks = const {},
  }) : _nodeSpecs = Map.unmodifiable(nodes),
       _markSpecs = Map.unmodifiable(marks),
       _contentExpressions = Map.unmodifiable(
         nodes.map((k, v) => MapEntry(k, ContentExpression.parse(v.content))),
       ),
       _allowedMarksCache = Map.unmodifiable(
         Map.fromEntries(
           nodes.entries
               .where((e) => e.value.marks != '_' && e.value.marks.isNotEmpty)
               .map((e) => MapEntry(e.key, e.value.marks.split(' ').toSet())),
         ),
       ),
       _excludesCache = Map.unmodifiable(
         Map.fromEntries(
           marks.entries
               .where(
                 (e) => e.value.excludes != null && e.value.excludes != '_',
               )
               .map(
                 (e) => MapEntry(e.key, e.value.excludes!.split(' ').toSet()),
               ),
         ),
       );

  final Map<String, NodeSpec> _nodeSpecs;
  final Map<String, MarkSpec> _markSpecs;
  final Map<String, ContentExpression> _contentExpressions;
  final Map<String, Set<String>> _allowedMarksCache;
  final Map<String, Set<String>> _excludesCache;

  /// All registered node specs.
  Map<String, NodeSpec> get nodeSpecs => _nodeSpecs;

  /// All registered mark specs.
  Map<String, MarkSpec> get markSpecs => _markSpecs;

  /// Returns the NodeSpec for the given [type], or null.
  NodeSpec? nodeSpec(String type) => _nodeSpecs[type];

  /// Returns the MarkSpec for the given [type], or null.
  MarkSpec? markSpec(String type) => _markSpecs[type];

  /// Returns the parsed content expression for the given node [type].
  ContentExpression contentExpression(String type) =>
      _contentExpressions[type] ?? ContentExpression.empty;

  // ── Node creation ───────────────────────────────────────────────────

  /// Creates a text node with the given [text] and [marks].
  TextNode text(String text, {List<Mark> marks = const []}) =>
      TextNode(text, marks: marks);

  /// Creates a block node of the given [type].
  BlockNode block(
    String type, {
    Map<String, Object?> attrs = const {},
    List<Node>? content,
  }) {
    final spec = _nodeSpecs[type];
    if (spec == null) {
      throw ArgumentError('Unknown node type: $type');
    }

    final resolvedAttrs = _resolveAttrs(spec.attrs, attrs);
    final fragment = content != null ? Fragment(content) : Fragment.empty;

    return BlockNode(
      type: type,
      attrs: resolvedAttrs,
      content: fragment,
      isLeaf: spec.isLeaf,
      isInline: spec.inline,
      inlineContent: spec.hasInlineContent,
      isAtom: spec.atom,
    );
  }

  /// Creates an inline widget node.
  InlineWidgetNode inlineWidget(
    String widgetType, {
    Map<String, Object?> attrs = const {},
    List<Mark> marks = const [],
  }) => InlineWidgetNode(widgetType: widgetType, attrs: attrs, marks: marks);

  /// Creates a document node with the given [blocks].
  DocNode doc(List<Node> blocks) => DocNode.fromBlocks(blocks);

  /// Creates a mark of the given [type].
  Mark mark(String type, {Map<String, Object?> attrs = const {}}) {
    final spec = _markSpecs[type];
    if (spec == null) {
      throw ArgumentError('Unknown mark type: $type');
    }
    final resolvedAttrs = _resolveAttrs(spec.attrs, attrs);
    return Mark(type, resolvedAttrs);
  }

  // ── Validation ──────────────────────────────────────────────────────

  /// Validates that a node's content conforms to its spec.
  bool validateContent(Node node) {
    final expr = _contentExpressions[node.type];
    if (expr == null) return true; // Unknown type — permissive
    return expr.validate(node.content.children, this);
  }

  /// Validates that the marks on a node are allowed by its parent spec.
  bool validateMarks(Node node, String parentType) {
    if (node.marks.isEmpty) return true;
    final parentSpec = _nodeSpecs[parentType];
    if (parentSpec == null) return true;

    final allowed = parentSpec.marks;
    if (allowed == '_') return true; // All marks allowed
    if (allowed.isEmpty) return node.marks.isEmpty;

    final allowedSet = _allowedMarksCache[parentType] ?? const {};
    return node.marks.every((m) => allowedSet.contains(m.type));
  }

  /// Validates an entire document tree.
  List<String> validateDocument(Node doc) {
    final errors = <String>[];
    _validateNode(doc, errors);
    return errors;
  }

  void _validateNode(Node node, List<String> errors) {
    // Validate content expression
    if (!validateContent(node)) {
      errors.add('Node "${node.type}" has invalid content: ${node.content}');
    }

    // Validate children recursively
    node.content.forEach((child, _, _) {
      // Validate marks
      if (!validateMarks(child, node.type)) {
        errors.add(
          'Node "${child.type}" has marks not allowed in "${node.type}"',
        );
      }

      // Validate mark exclusion rules
      for (var i = 0; i < child.marks.length; i++) {
        final mark = child.marks[i];
        final markSpec = _markSpecs[mark.type];
        if (markSpec?.excludes != null) {
          for (var j = i + 1; j < child.marks.length; j++) {
            final other = child.marks[j];
            final excludedSet = _excludesCache[mark.type] ?? const {};
            if (markSpec!.excludes == '_' || excludedSet.contains(other.type)) {
              errors.add(
                'Mark "${mark.type}" excludes "${other.type}" on "${child.type}" in "${node.type}"',
              );
            }
          }
        }
      }

      _validateNode(child, errors);
    });
  }

  /// Whether adding [markType] would conflict with any existing [existingMarks].
  ///
  /// Checks both directions:
  /// - Whether the new mark's `excludes` rule forbids any existing mark.
  /// - Whether any existing mark's `excludes` rule forbids the new mark.
  bool marksExclude(String markType, List<Mark> existingMarks) {
    final spec = _markSpecs[markType];
    if (spec == null) return false;

    // Check if the new mark excludes any existing mark
    if (spec.excludes != null) {
      if (spec.excludes == '_') return existingMarks.isNotEmpty;
      final excluded = _excludesCache[markType] ?? const {};
      if (existingMarks.any((m) => excluded.contains(m.type))) return true;
    }

    // Check if any existing mark excludes the new mark
    for (final existing in existingMarks) {
      final existingSpec = _markSpecs[existing.type];
      if (existingSpec?.excludes == null) continue;
      if (existingSpec!.excludes == '_') return true;
      final existingExcludes = _excludesCache[existing.type] ?? const {};
      if (existingExcludes.contains(markType)) return true;
    }

    return false;
  }

  /// Whether a mark of [markType] is allowed inside [nodeType].
  bool allowsMark(String nodeType, String markType) {
    final spec = _nodeSpecs[nodeType];
    if (spec == null) return false;
    if (spec.marks == '_') return true;
    if (spec.marks.isEmpty) return false;
    final allowedSet = _allowedMarksCache[nodeType] ?? const {};
    return allowedSet.contains(markType);
  }

  /// Whether a child of [childType] is allowed inside [parentType].
  bool allowsChild(String parentType, String childType) {
    final expr = _contentExpressions[parentType];
    if (expr == null) return false;

    final childSpec = _nodeSpecs[childType];
    if (childSpec == null) return false;

    for (final element in expr.elements) {
      final namesToCheck = element.isChoice ? element.choices : [element.name];
      for (final name in namesToCheck) {
        if (name == childType) return true;
        if (childSpec.group != null && name == childSpec.group) {
          return true;
        }
        if (name == 'inline' && (childSpec.inline || childType == 'text')) {
          return true;
        }
        if (name == 'block' && !childSpec.inline && childType != 'doc') {
          return true;
        }
      }
    }
    return false;
  }

  Map<String, Object?> _resolveAttrs(
    Map<String, AttrSpec> specs,
    Map<String, Object?> provided,
  ) {
    if (specs.isEmpty) return provided;

    final result = <String, Object?>{...provided};

    for (final entry in specs.entries) {
      if (!result.containsKey(entry.key)) {
        if (entry.value.hasDefault) {
          result[entry.key] = entry.value.defaultValue;
        } else if (entry.value.required) {
          throw ArgumentError('Required attribute "${entry.key}" not provided');
        }
      }
    }

    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Built-in schemas
// ─────────────────────────────────────────────────────────────────────────────

/// A minimal schema with paragraphs, headings, and basic marks.
///
/// Useful as a starting point or for testing.
final Schema basicSchema = Schema(
  nodes: {
    'doc': const NodeSpec(name: 'doc', content: 'block+'),
    'paragraph': const NodeSpec(
      name: 'paragraph',
      group: 'block',
      content: 'inline*',
    ),
    'heading': NodeSpec(
      name: 'heading',
      group: 'block',
      content: 'inline*',
      attrs: {'level': const AttrSpec(defaultValue: 1)},
    ),
    'blockquote': const NodeSpec(
      name: 'blockquote',
      group: 'block',
      content: 'block+',
      defining: true,
    ),
    'code_block': const NodeSpec(
      name: 'code_block',
      group: 'block',
      content: 'text*',
      marks: '',
      defining: true,
    ),
    'horizontal_rule': const NodeSpec(name: 'horizontal_rule', group: 'block'),
    'image': NodeSpec(
      name: 'image',
      group: 'block',
      atom: true,
      attrs: {
        'src': const AttrSpec(required: true),
        'alt': const AttrSpec(defaultValue: ''),
        'title': const AttrSpec(defaultValue: ''),
      },
    ),
    'hard_break': const NodeSpec(
      name: 'hard_break',
      group: 'inline',
      inline: true,
    ),
    'text': const NodeSpec(name: 'text', group: 'inline', inline: true),
  },
  marks: {
    'bold': const MarkSpec(name: 'bold'),
    'italic': const MarkSpec(name: 'italic'),
    'underline': const MarkSpec(name: 'underline'),
    'strikethrough': const MarkSpec(name: 'strikethrough'),
    'code': const MarkSpec(name: 'code', excludes: '_'),
    'link': MarkSpec(
      name: 'link',
      inclusive: false,
      attrs: {
        'href': const AttrSpec(required: true),
        'title': const AttrSpec(defaultValue: ''),
      },
    ),
  },
);

/// A rich schema with all common block types for a Notion-like editor.
final Schema richSchema = Schema(
  nodes: {
    ...basicSchema.nodeSpecs,
    'bullet_list': const NodeSpec(
      name: 'bullet_list',
      group: 'block',
      content: 'list_item+',
    ),
    'ordered_list': NodeSpec(
      name: 'ordered_list',
      group: 'block',
      content: 'list_item+',
      attrs: {'start': const AttrSpec(defaultValue: 1)},
    ),
    'check_list': const NodeSpec(
      name: 'check_list',
      group: 'block',
      content: 'check_item+',
    ),
    'list_item': const NodeSpec(
      name: 'list_item',
      group: 'list_item',
      content: 'block+',
      defining: true,
    ),
    'check_item': NodeSpec(
      name: 'check_item',
      group: 'check_item',
      content: 'block+',
      attrs: {'checked': const AttrSpec(defaultValue: false)},
    ),
    'table': const NodeSpec(
      name: 'table',
      group: 'block',
      content: 'table_row+',
      isolating: true,
    ),
    'table_row': const NodeSpec(name: 'table_row', content: 'table_cell+'),
    'table_cell': NodeSpec(
      name: 'table_cell',
      content: 'block+',
      isolating: true,
      attrs: {
        'colspan': const AttrSpec(defaultValue: 1),
        'rowspan': const AttrSpec(defaultValue: 1),
      },
    ),
    'callout': NodeSpec(
      name: 'callout',
      group: 'block',
      content: 'block+',
      attrs: {'icon': const AttrSpec(defaultValue: '💡')},
    ),
    'embed': NodeSpec(
      name: 'embed',
      group: 'block',
      atom: true,
      attrs: {
        'embedType': const AttrSpec(required: true),
        'data': const AttrSpec(defaultValue: {}),
      },
    ),
    'divider': const NodeSpec(name: 'divider', group: 'block'),
  },
  marks: {
    ...basicSchema.markSpecs,
    'highlight': MarkSpec(
      name: 'highlight',
      attrs: {'color': const AttrSpec(defaultValue: 'yellow')},
    ),
    'color': MarkSpec(
      name: 'color',
      attrs: {'color': const AttrSpec(required: true)},
    ),
    'superscript': const MarkSpec(name: 'superscript'),
    'subscript': const MarkSpec(name: 'subscript'),
  },
);
