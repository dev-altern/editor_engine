import '../model/fragment.dart';
import '../model/node.dart';
import 'step.dart';
import 'step_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReplaceStep — Insert, delete, or replace content
// ─────────────────────────────────────────────────────────────────────────────

/// Replaces a range of the document with new content.
///
/// This is the most fundamental step — insertions (from == to),
/// deletions (empty slice), and replacements are all ReplaceSteps.
class ReplaceStep extends Step {
  /// Creates a replace step.
  ///
  /// Replaces content between [from] and [to] with [slice].
  const ReplaceStep(this.from, this.to, this.slice);

  /// Creates an insertion step.
  factory ReplaceStep.insert(int pos, Slice slice) =>
      ReplaceStep(pos, pos, slice);

  /// Creates a deletion step.
  factory ReplaceStep.delete(int from, int to) =>
      ReplaceStep(from, to, Slice.empty);

  /// The start position of the range to replace.
  final int from;

  /// The end position of the range to replace.
  final int to;

  /// The content to insert (empty for deletion).
  final Slice slice;

  @override
  StepMap getMap() => StepMap.simple(from, to - from, slice.size);

  @override
  StepResult apply(DocNode doc) {
    try {
      final newContent = _replaceRange(doc, from, to, slice);
      return StepResult.ok(DocNode(content: newContent));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  Step invert(DocNode doc) {
    // The inverse replaces the inserted content with the deleted content
    final deletedSlice = _sliceFromRange(doc, from, to);
    return ReplaceStep(from, from + slice.size, deletedSlice);
  }

  @override
  Step? merge(Step other) {
    if (other is! ReplaceStep) return null;

    // Adjacent insertions can be merged
    if (to == other.from && slice.openEnd == 0 && other.slice.openStart == 0) {
      final combined = Slice(
        Fragment.fromIterable([
          ...slice.content.children,
          ...other.slice.content.children,
        ]),
        slice.openStart,
        other.slice.openEnd,
      );
      return ReplaceStep(from, other.to, combined);
    }

    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'stepType': 'replace',
    'from': from,
    'to': to,
    'slice': slice.toJson(),
  };

  @override
  String toString() => 'ReplaceStep($from, $to, $slice)';

  // ── Replace algorithm ──

  /// Replaces content in [doc] between [from] and [to] with [slice].
  ///
  /// Uses ResolvedPos to navigate the document tree and handles
  /// openStart/openEnd for cross-node operations.
  Fragment _replaceRange(DocNode doc, int from, int to, Slice slice) {
    if (from == to && slice.isEmpty) return doc.content;

    final $from = doc.resolve(from);
    final $to = doc.resolve(to);

    return _replaceOuter($from, $to, slice, 0).content;
  }

  /// Recursively descends the tree to find the right level for replacement.
  Node _replaceOuter(
    ResolvedPos $from,
    ResolvedPos $to,
    Slice slice,
    int depth,
  ) {
    final node = $from.node(depth);
    final fromIndex = $from.index(depth);
    final toIndex = $to.index(depth);

    // Case 1: from and to are in the same child — recurse deeper
    if (fromIndex == toIndex && depth < $from.depth - slice.openStart) {
      final inner = _replaceOuter($from, $to, slice, depth + 1);
      return node.copy(node.content.replaceChild(fromIndex, inner));
    }

    // Case 2: empty slice — two-way join (deletion)
    if (slice.isEmpty) {
      return node.copy(_joinTwoWay($from, $to, depth));
    }

    // Case 3: flat slice at the right depth (no open nodes)
    if (slice.openStart == 0 &&
        slice.openEnd == 0 &&
        $from.depth == depth &&
        $to.depth == depth) {
      final content = node.content;
      return node.copy(
        Fragment([
          ...content.cut(0, $from.parentOffset).children,
          ...slice.content.children,
          ...content.cut($to.parentOffset).children,
        ]),
      );
    }

    // Case 4: three-way join with open slice
    return node.copy(_joinThreeWay($from, $to, slice, depth));
  }

  /// Joins content from left of $from with content from right of $to.
  /// Used when the slice is empty (pure deletion / joining).
  Fragment _joinTwoWay(ResolvedPos $from, ResolvedPos $to, int depth) {
    final node = $from.node(depth);
    final children = <Node>[];

    // Add complete children before from
    for (var i = 0; i < $from.index(depth); i++) {
      children.add(node.content.child(i));
    }

    // Close left side + close right side, joining if compatible
    if ($from.depth > depth && $to.depth > depth) {
      final leftChild = node.content.child($from.index(depth));
      final rightChild = node.content.child($to.index(depth));
      final leftInner = _closeSide($from, depth + 1, isLeft: true);
      final rightInner = _closeSide($to, depth + 1, isLeft: false);

      // Join into one node if same type
      if (leftChild.type == rightChild.type && !leftChild.isLeaf) {
        children.add(
          leftChild.copy(
            Fragment([...leftInner.children, ...rightInner.children]),
          ),
        );
      } else {
        if (leftInner.isNotEmpty || !leftChild.isLeaf) {
          children.add(leftChild.copy(leftInner));
        }
        if (rightInner.isNotEmpty || !rightChild.isLeaf) {
          children.add(rightChild.copy(rightInner));
        }
      }
    } else if ($from.depth > depth) {
      final leftChild = node.content.child($from.index(depth));
      children.add(leftChild.copy(_closeSide($from, depth + 1, isLeft: true)));
    } else if ($to.depth > depth) {
      // Content before from at this level
      if ($from.parentOffset > 0) {
        children.addAll(node.content.cut(0, $from.parentOffset).children);
      }
      final rightChild = node.content.child($to.index(depth));
      children.add(rightChild.copy(_closeSide($to, depth + 1, isLeft: false)));
    } else {
      // Both at this depth — simple cut and join
      children.addAll(node.content.cut(0, $from.parentOffset).children);
      children.addAll(node.content.cut($to.parentOffset).children);
    }

    // Add complete children after to
    for (var i = $to.index(depth) + 1; i < node.content.childCount; i++) {
      children.add(node.content.child(i));
    }

    return Fragment(children);
  }

  /// Joins left side + slice content + right side for open slices.
  Fragment _joinThreeWay(
    ResolvedPos $from,
    ResolvedPos $to,
    Slice slice,
    int depth,
  ) {
    final node = $from.node(depth);
    final children = <Node>[];
    final openStart = slice.openStart;
    final openEnd = slice.openEnd;

    // Add complete children before from
    for (var i = 0; i < $from.index(depth); i++) {
      children.add(node.content.child(i));
    }

    // Left boundary: close left side and merge with open start of slice
    if ($from.depth > depth && openStart > 0) {
      final leftChild = node.content.child($from.index(depth));
      final leftInner = _closeSide($from, depth + 1, isLeft: true);
      final sliceStart = _openSliceSide(slice.content, openStart - 1, true);
      children.add(
        leftChild.copy(
          Fragment([...leftInner.children, ...sliceStart.children]),
        ),
      );
    } else if ($from.depth > depth) {
      final leftChild = node.content.child($from.index(depth));
      children.add(leftChild.copy(_closeSide($from, depth + 1, isLeft: true)));
      for (
        var i = 0;
        i < slice.content.childCount - (openEnd > 0 ? 1 : 0);
        i++
      ) {
        children.add(slice.content.child(i));
      }
    } else {
      // from is at this depth
      children.addAll(node.content.cut(0, $from.parentOffset).children);
      final sliceStart = openStart > 0 ? 1 : 0;
      final sliceEnd = slice.content.childCount - (openEnd > 0 ? 1 : 0);
      for (var i = sliceStart; i < sliceEnd; i++) {
        children.add(slice.content.child(i));
      }
    }

    // Middle: closed slice children (between open start and open end)
    if ($from.depth > depth && openStart > 0) {
      final sliceStart = 1; // skip the first (open start) child
      final sliceEnd = slice.content.childCount - (openEnd > 0 ? 1 : 0);
      for (var i = sliceStart; i < sliceEnd; i++) {
        children.add(slice.content.child(i));
      }
    }

    // Right boundary: merge open end of slice with right side
    if ($to.depth > depth && openEnd > 0) {
      final rightChild = node.content.child($to.index(depth));
      final rightInner = _closeSide($to, depth + 1, isLeft: false);
      final sliceEnd = _openSliceSide(slice.content, openEnd - 1, false);
      children.add(
        rightChild.copy(
          Fragment([...sliceEnd.children, ...rightInner.children]),
        ),
      );
    } else if ($to.depth > depth) {
      final rightChild = node.content.child($to.index(depth));
      children.add(rightChild.copy(_closeSide($to, depth + 1, isLeft: false)));
    } else {
      // to is at this depth
      if ($from.depth == depth && openEnd > 0) {
        // Slice end content was not added above
        final lastIdx = slice.content.childCount - 1;
        if (lastIdx >= 0) {
          final lastChild = slice.content.child(lastIdx);
          final sliceEnd = _openSliceSide(
            Fragment.from(lastChild),
            openEnd - 1,
            false,
          );
          children.addAll(sliceEnd.children);
        }
      }
      children.addAll(node.content.cut($to.parentOffset).children);
    }

    // Add complete children after to
    for (var i = $to.index(depth) + 1; i < node.content.childCount; i++) {
      children.add(node.content.child(i));
    }

    return Fragment(children);
  }

  /// Closes content on one side of a position going up to [depth].
  /// [isLeft] = true: returns content before the position at each level.
  /// [isLeft] = false: returns content after the position at each level.
  Fragment _closeSide(ResolvedPos $pos, int depth, {required bool isLeft}) {
    final node = $pos.node(depth);

    if ($pos.depth == depth) {
      if (isLeft) {
        return node.content.cut(0, $pos.parentOffset);
      } else {
        return node.content.cut($pos.parentOffset);
      }
    }

    // Recurse deeper
    final childIdx = $pos.index(depth);
    final child = node.content.child(childIdx);
    final innerContent = _closeSide($pos, depth + 1, isLeft: isLeft);
    final closedChild = child.copy(innerContent);

    if (isLeft) {
      final before = <Node>[];
      for (var i = 0; i < childIdx; i++) {
        before.add(node.content.child(i));
      }
      before.add(closedChild);
      return Fragment(before);
    } else {
      final after = <Node>[closedChild];
      for (var i = childIdx + 1; i < node.content.childCount; i++) {
        after.add(node.content.child(i));
      }
      return Fragment(after);
    }
  }

  /// Extracts the "open" side content from a slice.
  /// Descends [openDepth] levels into the first (left) or last (right) child.
  Fragment _openSliceSide(Fragment content, int openDepth, bool isLeft) {
    if (openDepth == 0 || content.isEmpty) return content;

    final child = isLeft ? content.children.first : content.children.last;
    if (child.content.isEmpty) return Fragment.empty;

    return _openSliceSide(child.content, openDepth - 1, isLeft);
  }

  /// Extracts a slice from a range in the document, computing correct
  /// open depths based on document structure.
  Slice _sliceFromRange(DocNode doc, int from, int to) {
    if (from == to) return Slice.empty;

    final $from = doc.resolve(from);
    final $to = doc.resolve(to);

    // Find the shared depth between from and to
    final sharedDepth = $from.sharedDepth(to);

    // openStart = how many levels deeper $from is than the shared ancestor
    final openStart = $from.depth - sharedDepth;
    // openEnd = how many levels deeper $to is than the shared ancestor
    final openEnd = $to.depth - sharedDepth;

    // Extract the content between from and to
    final content = doc.content.cut(from, to);

    return Slice(content, openStart, openEnd);
  }
}
