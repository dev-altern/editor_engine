import 'package:meta/meta.dart';

import 'node.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ResolvedPos — A position resolved into the document tree
// ─────────────────────────────────────────────────────────────────────────────

/// A position within the document resolved to a specific node and offset.
///
/// A resolved position knows:
/// - Its absolute position in the document ([pos])
/// - The [depth] of nesting at this position
/// - The [parent] node at each depth
/// - The [index] into the parent's children at each depth
/// - The [textOffset] if inside a text node
///
/// This is the main tool for navigating the document tree from a flat
/// integer position.
@immutable
class ResolvedPos {
  const ResolvedPos._({
    required this.pos,
    required this.path,
    required this.parentOffset,
  });

  /// The absolute position in the document.
  final int pos;

  /// The path from root to this position.
  ///
  /// Stored as triples: [node, index, offset, node, index, offset, ...]
  /// where each triple represents (parent node, child index, start offset).
  final List<Object> path;

  /// The offset within the innermost parent node.
  final int parentOffset;

  /// The depth of nesting (0 = document root).
  int get depth => path.length ~/ 3 - 1;

  /// Returns the node at the given [depth].
  Node node(int depth) => path[depth * 3] as Node;

  /// Returns the child index at the given [depth].
  int index(int depth) => path[depth * 3 + 1] as int;

  /// Returns the start offset of the node at [depth].
  int start(int depth) => path[depth * 3 + 2] as int;

  /// The innermost parent node.
  Node get parent => node(depth);

  /// The start of the innermost parent.
  int get parentStart => start(depth);

  /// The index into the parent's children.
  int get parentIndex => index(depth);

  /// The end position of the node at the given [depth].
  int end(int depth) => start(depth) + node(depth).contentSize;

  /// Returns the depth of the deepest node that contains both this
  /// position and [otherPos].
  int sharedDepth(int otherPos) {
    for (var d = depth; d > 0; d--) {
      if (start(d) <= otherPos && end(d) >= otherPos) {
        return d;
      }
    }
    return 0;
  }

  /// The text offset if inside a text node (0 otherwise).
  int get textOffset {
    final p = parent;
    if (p.inlineContent && parentOffset > 0) {
      var offset = 0;
      for (var i = 0; i < p.content.childCount; i++) {
        final child = p.content.child(i);
        final end = offset + child.nodeSize;
        if (end > parentOffset) {
          if (child.isText) return parentOffset - offset;
          return 0;
        }
        offset = end;
      }
    }
    return 0;
  }

  /// The node directly after this position, or null.
  Node? get nodeAfter {
    final p = parent;
    final idx = parentIndex;
    if (idx < p.content.childCount) {
      final child = p.content.child(idx);
      if (textOffset > 0 && child.isText) {
        return (child as TextNode).cut(textOffset);
      }
      return child;
    }
    return null;
  }

  /// The node directly before this position, or null.
  Node? get nodeBefore {
    if (parentOffset == 0) return null;
    final p = parent;
    var offset = 0;
    for (var i = 0; i < p.content.childCount; i++) {
      final child = p.content.child(i);
      final end = offset + child.nodeSize;
      if (end >= parentOffset) {
        if (offset < parentOffset && child.isText) {
          return (child as TextNode).cut(0, parentOffset - offset);
        }
        if (offset == parentOffset) {
          return i > 0 ? p.content.child(i - 1) : null;
        }
        return child;
      }
      offset = end;
    }
    return p.content.lastChild;
  }

  /// Resolves a position within the document tree.
  static ResolvedPos resolve(Node doc, int pos) {
    if (pos < 0 || pos > doc.nodeSize - 2) {
      throw RangeError(
        'Position $pos out of range for document of size '
        '${doc.nodeSize - 2}',
      );
    }

    final path = <Object>[];
    var current = doc;
    var offset = 0;
    var parentOffset = pos;

    // Walk down the tree
    for (;;) {
      // Record this level
      var childIndex = 0;
      var childOffset = 0;

      if (current.content.isEmpty || current.isLeaf) {
        path.addAll([current, childIndex, offset]);
        break;
      }

      // Find which child contains this position
      var descend = false;
      var done = false;
      for (var i = 0; i < current.content.childCount; i++) {
        final child = current.content.child(i);
        final start = childOffset;
        final end = childOffset + child.nodeSize;

        if (parentOffset < end) {
          childIndex = i;

          if (child.isText || child.isLeaf || parentOffset == start) {
            // Terminal: text/leaf child or position at boundary
            path.addAll([current, childIndex, offset]);
            done = true;
            break;
          }

          // Descend into non-leaf, non-text child
          path.addAll([current, childIndex, offset]);
          current = child;
          offset = offset + start + 1; // +1 for open token
          parentOffset = parentOffset - start - 1;
          descend = true;
          break;
        }

        childOffset = end;
      }

      if (done) break;

      if (!descend) {
        path.addAll([current, current.content.childCount, offset]);
        break;
      }
    }

    return ResolvedPos._(pos: pos, path: path, parentOffset: parentOffset);
  }

  @override
  String toString() => 'ResolvedPos($pos, depth: $depth)';
}
