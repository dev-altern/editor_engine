import 'package:meta/meta.dart';

import '../model/fragment.dart';
import '../model/node.dart';
import 'step.dart';
import 'step_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SplitStep — Split a block at a position
// ─────────────────────────────────────────────────────────────────────────────

/// Splits a block node at the given position, creating two sibling blocks.
///
/// This is the step behind pressing Enter inside a paragraph: the text before
/// the cursor stays in the original block, and text after goes into a new block.
///
/// [pos] is a position inside a textblock (e.g., between characters).
/// [depth] controls how many nesting levels to split (usually 1).
/// [typeAfter] and [attrsAfter] optionally change the type/attrs of the
/// new block (e.g., splitting a heading creates heading + paragraph).
///
/// ```dart
/// // Split "Hello" at position 4 → "Hel" + "lo"
/// final step = SplitStep(4);
/// ```
@immutable
class SplitStep extends Step {
  const SplitStep(this.pos, {this.depth = 1, this.typeAfter, this.attrsAfter});

  /// The position inside a textblock where the split occurs.
  final int pos;

  /// How many nesting levels to split (default 1).
  final int depth;

  /// Optional type for the new block after the split.
  final String? typeAfter;

  /// Optional attributes for the new block after the split.
  final Map<String, Object?>? attrsAfter;

  @override
  StepResult apply(DocNode doc) {
    try {
      final $pos = doc.resolve(pos);

      if ($pos.depth < depth) {
        return StepResult.fail(
          'Split depth ($depth) exceeds nesting depth (${$pos.depth})',
        );
      }

      final parent = $pos.parent;
      final offset = $pos.parentOffset;

      // Split the innermost block's content at the cursor offset.
      final leftContent = parent.content.cut(0, offset);
      final rightContent = parent.content.cut(offset);

      // Left block keeps original type; right block may change type/attrs.
      Node leftNode = parent.copy(leftContent);
      Node rightNode = BlockNode(
        type: typeAfter ?? parent.type,
        attrs: attrsAfter ?? parent.attrs,
        inlineContent: parent.inlineContent,
        content: rightContent,
      );

      // For depth > 1, split outer levels upward.
      for (var d = $pos.depth - 1; d > $pos.depth - depth; d--) {
        final ancestor = $pos.node(d);
        final idx = $pos.index(d);

        leftNode = ancestor.copy(
          Fragment([
            for (var i = 0; i < idx; i++) ancestor.content.child(i),
            leftNode,
          ]),
        );

        rightNode = ancestor.copy(
          Fragment([
            rightNode,
            for (var i = idx + 1; i < ancestor.content.childCount; i++)
              ancestor.content.child(i),
          ]),
        );
      }

      // Insert leftNode and rightNode into the container.
      final containerDepth = $pos.depth - depth;
      final container = $pos.node(containerDepth);
      final containerIdx = $pos.index(containerDepth);

      final newChildren = <Node>[
        for (var i = 0; i < containerIdx; i++) container.content.child(i),
        leftNode,
        rightNode,
        for (var i = containerIdx + 1; i < container.content.childCount; i++)
          container.content.child(i),
      ];

      final newContainer = container.copy(Fragment(newChildren));

      // Rebuild from containerDepth up to root.
      if (containerDepth == 0) {
        return StepResult.ok(DocNode(content: newContainer.content));
      }

      Node current = newContainer;
      for (var d = containerDepth - 1; d >= 0; d--) {
        final ancestor = $pos.node(d);
        final idx = $pos.index(d);
        current = ancestor.copy(ancestor.content.replaceChild(idx, current));
      }

      return StepResult.ok(DocNode(content: current.content));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  StepMap getMap() => StepMap.simple(pos, 0, depth * 2);

  @override
  Step invert(DocNode doc) => JoinStep(pos + depth, depth: depth);

  @override
  Step? merge(Step other) => null;

  @override
  Map<String, dynamic> toJson() => {
    'stepType': 'split',
    'pos': pos,
    'depth': depth,
    if (typeAfter != null) 'typeAfter': typeAfter,
    if (attrsAfter != null) 'attrsAfter': attrsAfter,
  };

  @override
  String toString() {
    final extra = <String>[];
    if (depth != 1) extra.add('depth: $depth');
    if (typeAfter != null) extra.add('typeAfter: $typeAfter');
    final suffix = extra.isEmpty ? '' : ', ${extra.join(', ')}';
    return 'SplitStep($pos$suffix)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JoinStep — Join two adjacent sibling blocks
// ─────────────────────────────────────────────────────────────────────────────

/// Joins two adjacent sibling blocks into one.
///
/// This is the step behind pressing Backspace at the start of a block:
/// the block's content is appended to the preceding block.
///
/// [pos] is the "gap" position between two sibling blocks — the position
/// right after the first block's close token and before the second block's
/// open token. For example, in `<p>Hello</p><p>World</p>`, the gap between
/// the two paragraphs is at position 7 (after the first `</p>`).
///
/// Internally delegates to [ReplaceStep.delete] across the block boundary,
/// triggering the existing two-way join in `replace_step.dart`.
///
/// ```dart
/// // Join two paragraphs at position 7
/// final step = JoinStep(7);
/// ```
@immutable
class JoinStep extends Step {
  const JoinStep(this.pos, {this.depth = 1});

  /// The gap position between two sibling blocks.
  final int pos;

  /// How many nesting levels to join (default 1).
  final int depth;

  @override
  StepResult apply(DocNode doc) {
    try {
      // pos is the gap between two sibling blocks.
      // pos-1 is inside the first block, pos+1 is inside the second block (for depth=1).
      final $before = doc.resolve(pos - depth);

      // Both resolved positions should share a container at depth-1.
      final containerDepth = $before.depth - 1;
      if (containerDepth < 0) {
        return const StepResult.fail('Cannot join at document root');
      }

      final container = $before.node(containerDepth);
      final firstIdx = $before.index(containerDepth);
      final secondIdx = firstIdx + 1;

      if (secondIdx >= container.content.childCount) {
        return const StepResult.fail('No second block to join with');
      }

      final firstBlock = container.content.child(firstIdx);
      final secondBlock = container.content.child(secondIdx);

      // Merge: combine first block's content with second block's content.
      // The first block keeps its type.
      final mergedContent = Fragment([
        ...firstBlock.content.children,
        ...secondBlock.content.children,
      ]);
      final mergedBlock = firstBlock.copy(mergedContent);

      // Build new container content replacing both blocks with the merged one.
      final newChildren = <Node>[
        for (var i = 0; i < firstIdx; i++) container.content.child(i),
        mergedBlock,
        for (var i = secondIdx + 1; i < container.content.childCount; i++)
          container.content.child(i),
      ];

      final newContainer = container.copy(Fragment(newChildren));

      // Rebuild from containerDepth up to root.
      if (containerDepth == 0) {
        return StepResult.ok(DocNode(content: newContainer.content));
      }

      Node current = newContainer;
      for (var d = containerDepth - 1; d >= 0; d--) {
        final ancestor = $before.node(d);
        final idx = $before.index(d);
        current = ancestor.copy(ancestor.content.replaceChild(idx, current));
      }

      return StepResult.ok(DocNode(content: current.content));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  StepMap getMap() => StepMap.simple(pos - depth, depth * 2, 0);

  @override
  Step invert(DocNode doc) {
    // Find the second block's type/attrs before joining.
    // pos+1 is inside the second block.
    final $to = doc.resolve(pos + 1);
    final secondBlock = $to.parent;

    // pos-1 is inside the first block.
    final $from = doc.resolve(pos - 1);
    final firstBlock = $from.parent;

    return SplitStep(
      pos - depth,
      depth: depth,
      typeAfter: secondBlock.type != firstBlock.type ? secondBlock.type : null,
      attrsAfter: !_mapsEqual(secondBlock.attrs, firstBlock.attrs)
          ? Map<String, Object?>.of(secondBlock.attrs)
          : null,
    );
  }

  @override
  Step? merge(Step other) => null;

  @override
  Map<String, dynamic> toJson() => {
    'stepType': 'join',
    'pos': pos,
    'depth': depth,
  };

  @override
  String toString() {
    final extra = depth != 1 ? ', depth: $depth' : '';
    return 'JoinStep($pos$extra)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WrapStep — Wrap a range of blocks in a container
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a range of sibling blocks in a new container node.
///
/// This is the step behind indenting paragraphs into a blockquote, converting
/// paragraphs to a list, etc.
///
/// [from] and [to] are positions at block boundaries in the parent's content
/// space. The step finds all blocks whose positions fall within [from]..[to]
/// and wraps them in a new node of [wrapperType].
///
/// ```dart
/// // Wrap two paragraphs in a blockquote
/// final step = WrapStep(0, 6, 'blockquote');
/// ```
@immutable
class WrapStep extends Step {
  const WrapStep(
    this.from,
    this.to,
    this.wrapperType, {
    this.wrapperAttrs = const {},
  });

  /// Start of the range to wrap (position of first block's open token).
  final int from;

  /// End of the range to wrap (position after last block's close token).
  final int to;

  /// The type of the wrapper node to create.
  final String wrapperType;

  /// Attributes for the wrapper node.
  final Map<String, Object?> wrapperAttrs;

  @override
  StepResult apply(DocNode doc) {
    try {
      // Find the range of children to wrap by walking the doc content.
      var startIdx = -1;
      var endIdx = -1;
      var offset = 0;

      for (var i = 0; i < doc.content.childCount; i++) {
        if (offset == from) startIdx = i;
        offset += doc.content.child(i).nodeSize;
        if (offset == to) {
          endIdx = i + 1;
          break;
        }
      }

      if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx) {
        return const StepResult.fail(
          'Invalid wrap range: from/to must align with block boundaries',
        );
      }

      // Extract blocks to wrap.
      final blocksToWrap = <Node>[];
      for (var i = startIdx; i < endIdx; i++) {
        blocksToWrap.add(doc.content.child(i));
      }

      // Create the wrapper node.
      final wrapper = BlockNode(
        type: wrapperType,
        attrs: wrapperAttrs,
        content: Fragment(blocksToWrap),
      );

      // Build new doc content with wrapper replacing the wrapped range.
      final newChildren = <Node>[
        for (var i = 0; i < startIdx; i++) doc.content.child(i),
        wrapper,
        for (var i = endIdx; i < doc.content.childCount; i++)
          doc.content.child(i),
      ];

      return StepResult.ok(DocNode(content: Fragment(newChildren)));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  StepMap getMap() => StepMap([from, 0, 1, to, 0, 1]);

  @override
  Step invert(DocNode doc) => UnwrapStep(from, wrapperNodeSize: to - from + 2);

  @override
  Step? merge(Step other) => null;

  @override
  Map<String, dynamic> toJson() => {
    'stepType': 'wrap',
    'from': from,
    'to': to,
    'wrapperType': wrapperType,
    if (wrapperAttrs.isNotEmpty) 'wrapperAttrs': wrapperAttrs,
  };

  @override
  String toString() {
    final attrStr = wrapperAttrs.isNotEmpty ? ', $wrapperAttrs' : '';
    return 'WrapStep($from, $to, $wrapperType$attrStr)';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UnwrapStep — Remove a wrapper, promoting children to siblings
// ─────────────────────────────────────────────────────────────────────────────

/// Removes a wrapping container node, promoting its children to siblings.
///
/// This is the step behind outdenting from a blockquote or list: the wrapper
/// is removed and its children become direct children of the wrapper's parent.
///
/// [pos] is the position of the wrapper node's open token.
/// [wrapperNodeSize] is the wrapper's nodeSize, needed for accurate position
/// mapping. It is typically computed from the document when constructing
/// the step (e.g., via `Transaction.unwrap()` or `WrapStep.invert()`).
///
/// ```dart
/// // Unwrap a blockquote at position 0 (nodeSize 9)
/// final step = UnwrapStep(0, wrapperNodeSize: 9);
/// ```
@immutable
class UnwrapStep extends Step {
  const UnwrapStep(this.pos, {required this.wrapperNodeSize});

  /// The position of the wrapper node's open token.
  final int pos;

  /// The wrapper's nodeSize (content size + 2).
  ///
  /// Needed for accurate [StepMap] generation, since `getMap()` does not
  /// have access to the document.
  final int wrapperNodeSize;

  @override
  StepResult apply(DocNode doc) {
    try {
      final $pos = doc.resolve(pos);
      final wrapper = $pos.nodeAfter;
      if (wrapper == null || wrapper.isLeaf || wrapper.content.isEmpty) {
        return const StepResult.fail(
          'No wrapping node at position, or node has no content',
        );
      }

      // Replace the wrapper with its children in the parent.
      final parent = $pos.parent;
      final wrapperIndex = $pos.parentIndex;
      final newChildren = <Node>[
        for (var i = 0; i < wrapperIndex; i++) parent.content.child(i),
        ...wrapper.content.children,
        for (var i = wrapperIndex + 1; i < parent.content.childCount; i++)
          parent.content.child(i),
      ];

      final newParent = parent.copy(Fragment(newChildren));
      return StepResult.ok(_rebuildToRoot(doc, $pos, newParent));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  StepMap getMap() {
    // Remove open token at pos, remove close token at the end of the wrapper.
    final closePos = pos + wrapperNodeSize - 1;
    return StepMap([pos, 1, 0, closePos, 1, 0]);
  }

  @override
  Step invert(DocNode doc) {
    final $pos = doc.resolve(pos);
    final wrapper = $pos.nodeAfter!;
    return WrapStep(
      pos,
      pos + wrapper.contentSize,
      wrapper.type,
      wrapperAttrs: wrapper.attrs,
    );
  }

  @override
  Step? merge(Step other) => null;

  @override
  Map<String, dynamic> toJson() => {
    'stepType': 'unwrap',
    'pos': pos,
    'wrapperNodeSize': wrapperNodeSize,
  };

  @override
  String toString() => 'UnwrapStep($pos, wrapperNodeSize: $wrapperNodeSize)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Rebuilds the tree from a modified node at [depth] back to the document root.
DocNode _rebuildToRoot(DocNode doc, ResolvedPos resolved, Node newParent) {
  if (resolved.depth == 0) {
    return DocNode(content: newParent.content);
  }

  var current = newParent;
  for (var d = resolved.depth - 1; d >= 0; d--) {
    final ancestor = resolved.node(d);
    final idx = resolved.index(d);
    final newContent = ancestor.content.replaceChild(idx, current);
    current = ancestor.copy(newContent);
  }

  return DocNode(content: current.content);
}

/// Map equality check (same as decoration.dart's _mapsEqual).
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
