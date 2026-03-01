import 'package:meta/meta.dart';

import 'mark.dart';
import 'node.dart';

/// An ordered sequence of child nodes within a parent node.
///
/// Fragment is immutable. All mutation operations return new fragments.
/// Empty fragments share a singleton instance to avoid allocation.
///
/// Fragments track their total "size" in the document's integer position space:
/// - Each text character counts as 1
/// - Each leaf node (image, divider) counts as 1
/// - Each non-leaf node adds 2 (open + close tokens) plus its content size
@immutable
class Fragment {
  /// Creates a fragment from a list of nodes.
  ///
  /// Adjacent text nodes with identical mark sets are automatically merged.
  factory Fragment(List<Node> children) {
    final merged = _mergeTextNodes(children);
    if (merged.isEmpty) return empty;
    final unmodifiable = List<Node>.unmodifiable(merged);
    final size = _computeSize(unmodifiable);
    // Build prefix sums for fragments with many children (O(log n) lookup).
    final prefixSums = unmodifiable.length >= _bsearchThreshold
        ? _buildPrefixSums(unmodifiable)
        : null;
    return Fragment._(unmodifiable, size, prefixSums);
  }

  const Fragment._(this._children, this._size, this._prefixSums);

  /// The empty fragment singleton (const-constructable).
  static const Fragment empty = Fragment._([], 0, null);

  /// Creates a fragment from a single node.
  factory Fragment.from(Node node) => Fragment([node]);

  /// Creates a fragment from an iterable of nodes.
  factory Fragment.fromIterable(Iterable<Node> nodes) =>
      Fragment(nodes.toList());

  /// Threshold above which we build prefix sums for binary search.
  static const _bsearchThreshold = 8;

  final List<Node> _children;
  final int _size;

  /// Prefix sums: `_prefixSums[i]` = sum of nodeSizes for children [0..i).
  /// `_prefixSums[0] == 0`, `_prefixSums[length] == _size`.
  /// Null for small fragments where linear scan is faster.
  final List<int>? _prefixSums;

  /// The total size of this fragment in index space.
  int get size => _size;

  /// The number of direct child nodes.
  int get childCount => _children.length;

  /// Whether this fragment has no children.
  bool get isEmpty => _children.isEmpty;

  /// Whether this fragment has children.
  bool get isNotEmpty => _children.isNotEmpty;

  /// The first child node, or null if empty.
  Node? get firstChild => _children.isEmpty ? null : _children.first;

  /// The last child node, or null if empty.
  Node? get lastChild => _children.isEmpty ? null : _children.last;

  /// Returns the child at [index].
  ///
  /// Throws [RangeError] if [index] is out of bounds.
  Node child(int index) => _children[index];

  /// Returns the child at [index], or null if out of bounds.
  Node? maybeChild(int index) =>
      (index >= 0 && index < _children.length) ? _children[index] : null;

  /// Iterates over all child nodes.
  void forEach(void Function(Node node, int offset, int index) callback) {
    if (_prefixSums != null) {
      for (var i = 0; i < _children.length; i++) {
        callback(_children[i], _prefixSums[i], i);
      }
    } else {
      var offset = 0;
      for (var i = 0; i < _children.length; i++) {
        final child = _children[i];
        callback(child, offset, i);
        offset += child.nodeSize;
      }
    }
  }

  /// Returns the child that contains the given [offset] and the offset
  /// within that child.
  ///
  /// Returns a record of (node, childIndex, innerOffset).
  ({Node node, int index, int innerOffset}) findChild(int offset) {
    if (_children.length == 1) {
      return (node: _children[0], index: 0, innerOffset: offset);
    }

    // Use binary search on prefix sums for large fragments.
    if (_prefixSums != null) {
      return _findChildBinary(offset);
    }

    // Linear scan for small fragments.
    var pos = 0;
    for (var i = 0; i < _children.length; i++) {
      final child = _children[i];
      final end = pos + child.nodeSize;
      if (offset < end) {
        return (node: child, index: i, innerOffset: offset - pos);
      }
      pos = end;
    }
    throw RangeError('Offset $offset is beyond fragment size $_size');
  }

  ({Node node, int index, int innerOffset}) _findChildBinary(int offset) {
    final ps = _prefixSums!;
    // Binary search: find the largest i where ps[i] <= offset.
    var lo = 0;
    var hi = _children.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (ps[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (node: _children[lo], index: lo, innerOffset: offset - ps[lo]);
  }

  /// Returns the offset of the child at [index].
  int offsetAt(int index) {
    if (index == 0) return 0;
    if (index >= _children.length) return _size;
    if (_prefixSums != null) return _prefixSums[index];
    var offset = 0;
    for (var i = 0; i < index; i++) {
      offset += _children[i].nodeSize;
    }
    return offset;
  }

  /// Returns a new fragment with the given [node] appended.
  Fragment append(Node node) => Fragment([..._children, node]);

  /// Returns a new fragment with the given [node] inserted at [index].
  Fragment insert(int index, Node node) {
    final result = List<Node>.of(_children)..insert(index, node);
    return Fragment(result);
  }

  /// Returns a new fragment with the child at [index] removed.
  Fragment removeAt(int index) {
    final result = List<Node>.of(_children)..removeAt(index);
    return Fragment(result);
  }

  /// Returns a new fragment with the child at [index] replaced.
  Fragment replaceChild(int index, Node node) {
    final result = List<Node>.of(_children)..[index] = node;
    return Fragment(result);
  }

  /// Returns a sub-fragment between [from] and [to] offsets.
  Fragment cut(int from, [int? to]) {
    final end = to ?? _size;
    if (from == 0 && end == _size) return this;

    final result = <Node>[];
    var pos = 0;

    for (var i = 0; i < _children.length && pos < end; i++) {
      final child = _children[i];
      final childEnd = pos + child.nodeSize;

      if (childEnd > from) {
        if (pos < from || childEnd > end) {
          // Partial child — cut into it
          if (child.isText) {
            final textChild = child as TextNode;
            final startCut = from > pos ? from - pos : 0;
            final endCut = end < childEnd ? end - pos : textChild.text.length;
            result.add(textChild.cut(startCut, endCut));
          } else if (child.content.isNotEmpty) {
            final startCut = from > pos + 1 ? from - pos - 1 : 0;
            final endCut = end < childEnd - 1
                ? end - pos - 1
                : child.content.size;
            result.add(child.copy(child.content.cut(startCut, endCut)));
          } else {
            result.add(child);
          }
        } else {
          result.add(child);
        }
      }

      pos = childEnd;
    }

    return Fragment(result);
  }

  /// Returns an unmodifiable view of the children list.
  List<Node> get children => _children;

  /// Serializes this fragment to a list of JSON-compatible maps.
  List<Map<String, dynamic>> toJson() =>
      _children.map((n) => n.toJson()).toList();

  /// Deserializes a fragment from a list of JSON-compatible maps.
  static Fragment fromJson(List<dynamic> json) => Fragment(
    json.cast<Map<String, dynamic>>().map((m) => Node.nodeFromJson(m)).toList(),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Fragment) return false;
    if (_children.length != other._children.length) return false;
    for (var i = 0; i < _children.length; i++) {
      if (_children[i] != other._children[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_children);

  @override
  String toString() {
    if (_children.isEmpty) return 'Fragment.empty';
    final content = _children.map((n) => n.toString()).join(', ');
    return 'Fragment([$content])';
  }

  static int _computeSize(List<Node> children) {
    var size = 0;
    for (final child in children) {
      size += child.nodeSize;
    }
    return size;
  }

  /// Builds prefix-sum array: prefixSums[i] = sum of nodeSizes for [0..i).
  static List<int> _buildPrefixSums(List<Node> children) {
    final sums = List<int>.filled(children.length + 1, 0);
    for (var i = 0; i < children.length; i++) {
      sums[i + 1] = sums[i] + children[i].nodeSize;
    }
    return sums;
  }

  /// Merges adjacent text nodes with identical mark sets.
  static List<Node> _mergeTextNodes(List<Node> children) {
    if (children.length < 2) return children;

    // Quick check: is any merging needed?
    var needsMerge = false;
    for (var i = 1; i < children.length; i++) {
      if (children[i].isText && children[i - 1].isText) {
        final prev = children[i - 1] as TextNode;
        final curr = children[i] as TextNode;
        if (prev.marks.sameMarks(curr.marks)) {
          needsMerge = true;
          break;
        }
      }
    }
    if (!needsMerge) return children;

    final result = <Node>[children.first];
    for (var i = 1; i < children.length; i++) {
      final child = children[i];
      final prev = result.last;
      if (child.isText && prev.isText) {
        final prevText = prev as TextNode;
        final currText = child as TextNode;
        if (prevText.marks.sameMarks(currText.marks)) {
          result[result.length - 1] = TextNode(
            prevText.text + currText.text,
            marks: prevText.marks,
          );
          continue;
        }
      }
      result.add(child);
    }
    return result;
  }
}
