import 'package:meta/meta.dart';

import '../model/fragment.dart';
import '../model/mark.dart';
import '../model/node.dart';
import '../schema/schema.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DeltaSerializer — Document ↔ Quill Delta conversion
// ─────────────────────────────────────────────────────────────────────────────

/// Serializes and deserializes documents to/from Quill Delta format.
///
/// The Delta format represents documents as a flat list of `insert` operations,
/// each with optional `attributes`:
///
/// ```json
/// [
///   {"insert": "Hello "},
///   {"insert": "bold text", "attributes": {"bold": true}},
///   {"insert": "\n"},
///   {"insert": "Next paragraph\n"}
/// ]
/// ```
///
/// ## Mapping rules
///
/// - Text with marks → insert ops with attributes
/// - Block-level formatting → attributes on the trailing `\n` insert
/// - Images → `{"insert": {"image": "url"}}`
/// - Inline widgets → `{"insert": {"inline_widget": type, ...attrs}}`
/// - Horizontal rule → `{"insert": {"divider": true}}`
///
/// ## Limitations
///
/// - Deeply nested structures (nested blockquotes, tables) are flattened
/// - Table cell structure is not preserved in Delta format
@immutable
class DeltaSerializer {
  /// Creates a Delta serializer with an optional [schema].
  const DeltaSerializer({this.schema});

  /// The schema for type-aware deserialization.
  final Schema? schema;

  // ── Serialization ───────────────────────────────────────────────────

  /// Serializes a document to Quill Delta ops.
  List<Map<String, dynamic>> serialize(DocNode doc) {
    final ops = <Map<String, dynamic>>[];
    doc.content.forEach((block, _, __) {
      _serializeBlock(block, ops);
    });
    return ops;
  }

  void _serializeBlock(
    Node block,
    List<Map<String, dynamic>> ops, [
    String? parentType,
  ]) {
    final type = block.type;

    // Empty inline-content blocks — just emit trailing newline with attrs.
    if (block.inlineContent && block.content.isEmpty) {
      final blockAttrs = _blockAttributes(block, parentType);
      if (blockAttrs.isEmpty) {
        ops.add({'insert': '\n'});
      } else {
        ops.add({'insert': '\n', 'attributes': blockAttrs});
      }
      return;
    }

    // Leaf blocks (images, dividers, embeds).
    if (block.isLeaf || block.content.isEmpty) {
      switch (type) {
        case 'image':
          final src = block.attrs['src'] as String? ?? '';
          ops.add({
            'insert': {'image': src},
          });
        case 'horizontal_rule' || 'divider':
          ops.add({
            'insert': {'divider': true},
          });
        default:
          // Unknown leaf block — emit as embed.
          ops.add({
            'insert': {type: block.attrs.isEmpty ? true : block.attrs},
          });
      }
      return;
    }

    // Container blocks (blockquote, lists) — recurse into children.
    if (!block.inlineContent) {
      block.content.forEach((child, _, __) {
        _serializeBlock(child, ops, type);
      });
      return;
    }

    // Inline content blocks (paragraph, heading, code_block, list_item).
    _serializeInlineContent(block.content, ops);

    // Trailing newline with block-level attributes.
    final blockAttrs = _blockAttributes(block, parentType);
    if (blockAttrs.isEmpty) {
      ops.add({'insert': '\n'});
    } else {
      ops.add({'insert': '\n', 'attributes': blockAttrs});
    }
  }

  void _serializeInlineContent(
    Fragment content,
    List<Map<String, dynamic>> ops,
  ) {
    content.forEach((node, _, __) {
      if (node.isText) {
        final textNode = node as TextNode;
        final attrs = _marksToAttributes(textNode.marks);
        if (attrs.isEmpty) {
          ops.add({'insert': textNode.text});
        } else {
          ops.add({'insert': textNode.text, 'attributes': attrs});
        }
      } else if (node is InlineWidgetNode) {
        ops.add({
          'insert': {
            'inline_widget': node.widgetType,
            ...node.attrs.cast<String, dynamic>(),
          },
        });
      } else if (node.type == 'hard_break') {
        // Use a special embed to avoid splitting the block.
        ops.add({
          'insert': {'hard_break': true},
        });
      }
    });
  }

  Map<String, dynamic> _marksToAttributes(List<Mark> marks) {
    if (marks.isEmpty) return const {};
    final attrs = <String, dynamic>{};
    for (final mark in marks) {
      switch (mark.type) {
        case 'bold':
          attrs['bold'] = true;
        case 'italic':
          attrs['italic'] = true;
        case 'underline':
          attrs['underline'] = true;
        case 'strikethrough':
          attrs['strike'] = true;
        case 'code':
          attrs['code'] = true;
        case 'link':
          attrs['link'] = mark.attrs['href'] as String? ?? '';
        case 'color':
          attrs['color'] = mark.attrs['color'] as String? ?? '';
        case 'highlight':
          attrs['background'] = mark.attrs['color'] as String? ?? '';
        case 'superscript':
          attrs['script'] = 'super';
        case 'subscript':
          attrs['script'] = 'sub';
        default:
          attrs[mark.type] = mark.attrs.isEmpty ? true : mark.attrs;
      }
    }
    return attrs;
  }

  Map<String, dynamic> _blockAttributes(Node block, [String? parentType]) {
    final attrs = <String, dynamic>{};
    switch (block.type) {
      case 'heading':
        final level = block.attrs['level'] as int? ?? 1;
        attrs['header'] = level;
      case 'blockquote':
        attrs['blockquote'] = true;
      case 'code_block':
        attrs['code-block'] = true;
        final lang = block.attrs['language'] as String?;
        if (lang != null) attrs['code-block'] = lang;
      case 'list_item':
        // Determine list type from parent context.
        attrs['list'] = parentType == 'ordered_list' ? 'ordered' : 'bullet';
      case 'check_item':
        final checked = block.attrs['checked'] as bool? ?? false;
        attrs['list'] = checked ? 'checked' : 'unchecked';
    }
    return attrs;
  }

  // ── Deserialization ─────────────────────────────────────────────────

  /// Deserializes Quill Delta ops into a document.
  DocNode deserialize(List<Map<String, dynamic>> ops) {
    final blocks = <Node>[];
    var inlineNodes = <Node>[];

    for (final op in ops) {
      final insert = op['insert'];
      final attrs = op['attributes'] as Map<String, dynamic>? ?? const {};

      if (insert is String) {
        // Split by newlines — each \n terminates a block.
        final parts = insert.split('\n');
        for (var i = 0; i < parts.length; i++) {
          final text = parts[i];
          if (text.isNotEmpty) {
            final marks = _attributesToMarks(attrs);
            inlineNodes.add(TextNode(text, marks: marks));
          }
          // Each \n (except trailing in last part) creates a block.
          if (i < parts.length - 1) {
            // The attributes on the \n determine block type.
            final blockAttrs = i == parts.length - 2
                ? attrs
                : const <String, dynamic>{};
            blocks.add(_buildBlock(inlineNodes, blockAttrs));
            inlineNodes = [];
          }
        }
      } else if (insert is Map<String, dynamic>) {
        // Embed insert.
        if (insert.containsKey('image')) {
          blocks.add(
            BlockNode(
              type: 'image',
              attrs: {'src': insert['image'] as String},
              isLeaf: true,
              isAtom: true,
            ),
          );
        } else if (insert.containsKey('divider')) {
          blocks.add(const BlockNode(type: 'horizontal_rule', isLeaf: true));
        } else if (insert.containsKey('hard_break')) {
          inlineNodes.add(
            const BlockNode(type: 'hard_break', isLeaf: true, isInline: true),
          );
        } else if (insert.containsKey('inline_widget')) {
          final widgetType = insert['inline_widget'] as String;
          final widgetAttrs = Map<String, Object?>.of(insert)
            ..remove('inline_widget');
          inlineNodes.add(
            InlineWidgetNode(widgetType: widgetType, attrs: widgetAttrs),
          );
        } else {
          // Unknown embed — preserve as a leaf block.
          final type = insert.keys.first;
          blocks.add(
            BlockNode(
              type: type,
              attrs: insert[type] is Map
                  ? Map<String, Object?>.from(insert[type] as Map)
                  : const {},
              isLeaf: true,
            ),
          );
        }
      }
    }

    // Flush remaining inline nodes.
    if (inlineNodes.isNotEmpty) {
      blocks.add(_buildBlock(inlineNodes, const {}));
    }

    // Ensure document has at least one block.
    if (blocks.isEmpty) {
      blocks.add(const BlockNode(type: 'paragraph', inlineContent: true));
    }

    // Merge consecutive list wrappers of the same type.
    final merged = _mergeConsecutiveLists(blocks);

    return DocNode(content: Fragment(merged));
  }

  /// Merges consecutive list wrappers of the same type into single lists.
  List<Node> _mergeConsecutiveLists(List<Node> blocks) {
    if (blocks.length < 2) return blocks;
    final result = <Node>[blocks.first];
    for (var i = 1; i < blocks.length; i++) {
      final prev = result.last;
      final curr = blocks[i];
      if (_isListWrapper(prev.type) && prev.type == curr.type) {
        // Merge: combine children of both list wrappers.
        final mergedChildren = <Node>[];
        prev.content.forEach((n, _, __) => mergedChildren.add(n));
        curr.content.forEach((n, _, __) => mergedChildren.add(n));
        result[result.length - 1] = BlockNode(
          type: prev.type,
          attrs: prev.attrs,
          content: Fragment(mergedChildren),
        );
      } else {
        result.add(curr);
      }
    }
    return result;
  }

  bool _isListWrapper(String type) =>
      type == 'bullet_list' || type == 'ordered_list' || type == 'check_list';

  Node _buildBlock(List<Node> inlineNodes, Map<String, dynamic> blockAttrs) {
    // Determine block type from attributes.
    if (blockAttrs.containsKey('header')) {
      final level = blockAttrs['header'] as int? ?? 1;
      return BlockNode(
        type: 'heading',
        attrs: {'level': level},
        inlineContent: true,
        content: Fragment(inlineNodes),
      );
    }
    if (blockAttrs.containsKey('blockquote')) {
      // Wrap the paragraph in a blockquote.
      final para = BlockNode(
        type: 'paragraph',
        inlineContent: true,
        content: Fragment(inlineNodes),
      );
      return BlockNode(type: 'blockquote', content: Fragment([para]));
    }
    if (blockAttrs.containsKey('code-block')) {
      final lang = blockAttrs['code-block'];
      return BlockNode(
        type: 'code_block',
        attrs: lang is String ? {'language': lang} : const {},
        inlineContent: true,
        content: Fragment(inlineNodes),
      );
    }
    if (blockAttrs.containsKey('list')) {
      final listType = blockAttrs['list'] as String;
      final String itemType;
      final Map<String, Object?> itemAttrs;
      final String wrapperType;

      switch (listType) {
        case 'bullet':
          itemType = 'list_item';
          itemAttrs = const {};
          wrapperType = 'bullet_list';
        case 'ordered':
          itemType = 'list_item';
          itemAttrs = const {};
          wrapperType = 'ordered_list';
        case 'checked':
          itemType = 'check_item';
          itemAttrs = {'checked': true};
          wrapperType = 'check_list';
        case 'unchecked':
          itemType = 'check_item';
          itemAttrs = {'checked': false};
          wrapperType = 'check_list';
        default:
          itemType = 'list_item';
          itemAttrs = const {};
          wrapperType = 'bullet_list';
      }

      final para = BlockNode(
        type: 'paragraph',
        inlineContent: true,
        content: Fragment(inlineNodes),
      );
      final item = BlockNode(
        type: itemType,
        attrs: itemAttrs,
        content: Fragment([para]),
      );
      return BlockNode(type: wrapperType, content: Fragment([item]));
    }

    // Default: paragraph.
    return BlockNode(
      type: 'paragraph',
      inlineContent: true,
      content: Fragment(inlineNodes),
    );
  }

  List<Mark> _attributesToMarks(Map<String, dynamic> attrs) {
    if (attrs.isEmpty) return const [];
    final marks = <Mark>[];
    for (final entry in attrs.entries) {
      switch (entry.key) {
        case 'bold':
          if (entry.value == true) marks.add(Mark.bold);
        case 'italic':
          if (entry.value == true) marks.add(Mark.italic);
        case 'underline':
          if (entry.value == true) marks.add(Mark.underline);
        case 'strike':
          if (entry.value == true) marks.add(Mark.strikethrough);
        case 'code':
          if (entry.value == true) marks.add(Mark.code);
        case 'link':
          marks.add(Mark.link(entry.value as String));
        case 'color':
          marks.add(Mark('color', {'color': entry.value}));
        case 'background':
          marks.add(Mark('highlight', {'color': entry.value}));
        case 'script':
          if (entry.value == 'super') marks.add(Mark.superscript);
          if (entry.value == 'sub') marks.add(Mark.subscript);
        // Skip block-level attributes.
        case 'header' || 'blockquote' || 'code-block' || 'list':
          break;
        default:
          marks.add(
            Mark(
              entry.key,
              entry.value is Map
                  ? Map<String, Object?>.from(entry.value as Map)
                  : entry.value == true
                  ? const {}
                  : {'value': entry.value},
            ),
          );
      }
    }
    return marks;
  }
}
