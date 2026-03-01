import 'dart:math' as math;
import 'package:meta/meta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PieceTable — Efficient per-block text buffer
// ─────────────────────────────────────────────────────────────────────────────

/// A piece table text buffer with red-black tree indexing.
///
/// Inspired by VS Code's piece tree implementation, simplified for per-block
/// scope. Each text-containing block in the document has its own PieceTable.
///
/// ## How it works
///
/// Two buffers:
/// - **Original buffer**: immutable, contains the initial text
/// - **Add buffer**: append-only, contains all inserted text
///
/// A red-black tree of "pieces" references spans in these buffers.
/// Each piece says: "characters [start..start+length) from buffer X".
///
/// ## Complexity
///
/// | Operation           | Time        |
/// |---------------------|-------------|
/// | Insert at offset    | O(log p)    |
/// | Delete range        | O(log p)    |
/// | Get text at offset  | O(log p)    |
/// | Get full text       | O(n)        |
/// | Line ↔ offset       | O(log p)    |
///
/// Where p = number of pieces, n = total characters.
///
/// ## Adaptive optimization
///
/// For blocks with < 256 chars and < 8 edits, PieceTable falls back to
/// simple string operations. The red-black tree is only constructed when
/// the content grows beyond this threshold. This avoids tree overhead
/// for 95%+ of typical document blocks.
class PieceTable {
  /// Creates a piece table from initial text.
  factory PieceTable([String initialText = '']) {
    if (initialText.isEmpty) {
      return PieceTable._(
        originalBuffer: '',
        addBuffer: StringBuffer(),
        root: _RBNode.sentinel,
        length: 0,
        lineCount: 1,
        useSimple: true,
        simpleText: '',
      );
    }

    final lineCount = _countLines(initialText) + 1;

    // For small texts, use simple mode
    if (initialText.length < _simpleThreshold) {
      return PieceTable._(
        originalBuffer: initialText,
        addBuffer: StringBuffer(),
        root: _RBNode.sentinel,
        length: initialText.length,
        lineCount: lineCount,
        useSimple: true,
        simpleText: initialText,
      );
    }

    // Build tree with single piece referencing original buffer
    final piece = _Piece(
      _BufferType.original,
      0,
      initialText.length,
      _countLineFeeds(initialText),
    );
    final node = _RBNode(piece)
      ..color = _Color.black
      ..sizeLeft = 0
      ..lfLeft = 0;

    return PieceTable._(
      originalBuffer: initialText,
      addBuffer: StringBuffer(),
      root: node,
      length: initialText.length,
      lineCount: lineCount,
      useSimple: false,
      simpleText: null,
    );
  }

  PieceTable._({
    required this.originalBuffer,
    required this.addBuffer,
    required _RBNode root,
    required this.length,
    required this.lineCount,
    required bool useSimple,
    required String? simpleText,
  }) : _root = root,
       _useSimple = useSimple,
       _simpleText = simpleText,
       _editCount = 0;

  static const _simpleThreshold = 256;
  static const _editThreshold = 8;

  /// The original (immutable) text buffer.
  final String originalBuffer;

  /// The append-only add buffer for inserted text.
  final StringBuffer addBuffer;

  _RBNode _root;
  bool _useSimple;
  String? _simpleText;
  int _editCount;

  /// Total character count.
  int length;

  /// Total line count (always >= 1).
  int lineCount;

  // ── Public API ──────────────────────────────────────────────────────

  String? _textCache;

  /// Returns the full text content.
  String getText() {
    if (_useSimple) return _simpleText!;
    if (_textCache != null) return _textCache!;
    final buffer = StringBuffer();
    _inorder(_root, (node) {
      final piece = node.piece;
      buffer.write(_pieceText(piece));
    });
    _textCache = buffer.toString();
    return _textCache!;
  }

  /// Returns a substring from [start] to [start + length].
  String getTextInRange(int start, int rangeLength) {
    if (rangeLength == 0) return '';
    if (_useSimple) {
      return _simpleText!.substring(start, start + rangeLength);
    }

    final buffer = StringBuffer();
    var remaining = rangeLength;
    var offset = start;

    _walkPiecesFrom(offset, (piece, pieceOffset, localOffset) {
      final available = piece.length - localOffset;
      final take = math.min(available, remaining);
      final text = _pieceText(piece);
      buffer.write(text.substring(localOffset, localOffset + take));
      remaining -= take;
      return remaining > 0; // continue if more needed
    });

    return buffer.toString();
  }

  /// Returns the character at [offset].
  ///
  /// Throws [RangeError] if [offset] is out of bounds.
  String charAt(int offset) {
    RangeError.checkValueInInterval(offset, 0, length - 1, 'offset');
    return getTextInRange(offset, 1);
  }

  /// Inserts [text] at [offset].
  ///
  /// Throws [RangeError] if [offset] is out of bounds.
  void insert(int offset, String text) {
    if (text.isEmpty) return;
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    _editCount++;
    _textCache = null;

    if (_useSimple &&
        _editCount < _editThreshold &&
        length + text.length < _simpleThreshold) {
      _simpleText =
          _simpleText!.substring(0, offset) +
          text +
          _simpleText!.substring(offset);
      length += text.length;
      lineCount += _countLines(text);
      return;
    }

    if (_useSimple) {
      _promoteToTree();
    }

    final addStart = addBuffer.length;
    addBuffer.write(text);
    _addBufferCache = null; // Invalidate cache
    final newPiece = _Piece(
      _BufferType.add,
      addStart,
      text.length,
      _countLineFeeds(text),
    );

    if (_root == _RBNode.sentinel) {
      _root = _RBNode(newPiece)..color = _Color.black;
    } else {
      _insertPiece(offset, newPiece);
    }

    length += text.length;
    lineCount += _countLines(text);
  }

  /// Deletes [deleteLength] characters starting at [offset].
  ///
  /// Throws [RangeError] if the range is out of bounds.
  void delete(int offset, int deleteLength) {
    if (deleteLength == 0) return;
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    RangeError.checkValueInInterval(
      offset + deleteLength,
      offset,
      length,
      'offset + deleteLength',
    );
    _editCount++;
    _textCache = null;

    if (_useSimple && _editCount < _editThreshold) {
      final deleted = _simpleText!.substring(offset, offset + deleteLength);
      _simpleText =
          _simpleText!.substring(0, offset) +
          _simpleText!.substring(offset + deleteLength);
      length -= deleteLength;
      lineCount -= _countLines(deleted);
      return;
    }

    if (_useSimple) {
      _promoteToTree();
    }

    _deletePieces(offset, deleteLength);
    length -= deleteLength;
    // Line count recalculation is handled by _deletePieces
  }

  /// Replaces [deleteLength] characters at [offset] with [text].
  void replace(int offset, int deleteLength, String text) {
    if (deleteLength > 0) delete(offset, deleteLength);
    if (text.isNotEmpty) insert(offset, text);
  }

  /// Returns the line number (0-based) for the given [offset].
  int lineAt(int offset) {
    if (_useSimple) {
      var line = 0;
      for (var i = 0; i < offset && i < _simpleText!.length; i++) {
        if (_simpleText!.codeUnitAt(i) == 0x0A) line++;
      }
      return line;
    }
    return _lineAtOffset(offset);
  }

  /// Returns the offset of the start of line [line] (0-based).
  int lineStart(int line) {
    if (line == 0) return 0;
    if (_useSimple) {
      var currentLine = 0;
      for (var i = 0; i < _simpleText!.length; i++) {
        if (_simpleText!.codeUnitAt(i) == 0x0A) {
          currentLine++;
          if (currentLine == line) return i + 1;
        }
      }
      return length;
    }
    return _offsetAtLine(line);
  }

  /// Creates a snapshot of the current state for undo.
  PieceTableSnapshot snapshot() => PieceTableSnapshot._(
    addBufferLength: addBuffer.length,
    treeSnapshot: _useSimple ? null : _cloneTree(_root),
    simpleText: _useSimple ? _simpleText : null,
    length: length,
    lineCount: lineCount,
    useSimple: _useSimple,
    editCount: _editCount,
  );

  /// Restores from a snapshot.
  void restore(PieceTableSnapshot snap) {
    _useSimple = snap.useSimple;
    _simpleText = snap.simpleText;
    length = snap.length;
    lineCount = snap.lineCount;
    _editCount = snap.editCount;
    _textCache = null;
    if (!_useSimple && snap.treeSnapshot != null) {
      _root = snap.treeSnapshot!;
    } else if (_useSimple) {
      _root = _RBNode.sentinel;
    }
  }

  // ── Private: Simple → Tree promotion ─────────────────────────────────

  void _promoteToTree() {
    if (!_useSimple || _simpleText == null) return;

    final text = _simpleText!;
    _simpleText = null;
    _useSimple = false;

    if (text.isEmpty) {
      _root = _RBNode.sentinel;
      return;
    }

    // Check if text is in original or needs to go in add buffer
    if (text ==
            originalBuffer.substring(
              0,
              math.min(text.length, originalBuffer.length),
            ) &&
        text.length <= originalBuffer.length) {
      final piece = _Piece(
        _BufferType.original,
        0,
        text.length,
        _countLineFeeds(text),
      );
      _root = _RBNode(piece)..color = _Color.black;
    } else {
      final addStart = addBuffer.length;
      addBuffer.write(text);
      final piece = _Piece(
        _BufferType.add,
        addStart,
        text.length,
        _countLineFeeds(text),
      );
      _root = _RBNode(piece)..color = _Color.black;
    }
  }

  // ── Private: Tree operations ────────────────────────────────────────

  void _insertPiece(int offset, _Piece piece) {
    // Find the node and position to split
    final result = _findNodeAtOffset(offset);
    if (result == null) {
      // Append at end
      final node = _RBNode(piece)
        ..sizeLeft = 0
        ..lfLeft = 0;
      _appendNode(node);
      return;
    }

    final (:targetNode, :localOffset) = result;

    if (localOffset == 0) {
      // Insert before this node
      final node = _RBNode(piece)
        ..sizeLeft = 0
        ..lfLeft = 0;
      _insertBefore(targetNode, node);
    } else if (localOffset == targetNode.piece.length) {
      // Insert after this node
      final node = _RBNode(piece)
        ..sizeLeft = 0
        ..lfLeft = 0;
      _insertAfter(targetNode, node);
    } else {
      // Split the target node
      final origPiece = targetNode.piece;
      final leftPiece = _Piece(
        origPiece.bufferType,
        origPiece.start,
        localOffset,
        _countLineFeedsInRange(origPiece, 0, localOffset),
      );
      final rightPiece = _Piece(
        origPiece.bufferType,
        origPiece.start + localOffset,
        origPiece.length - localOffset,
        _countLineFeedsInRange(origPiece, localOffset, origPiece.length),
      );

      // Replace target with left piece
      targetNode.piece = leftPiece;
      _updateMetadata(targetNode);

      // Insert new piece and right piece after
      final newNode = _RBNode(piece)
        ..sizeLeft = 0
        ..lfLeft = 0;
      _insertAfter(targetNode, newNode);

      final rightNode = _RBNode(rightPiece)
        ..sizeLeft = 0
        ..lfLeft = 0;
      _insertAfter(newNode, rightNode);
    }
  }

  void _deletePieces(int offset, int deleteLength) {
    var remaining = deleteLength;
    var currentOffset = offset;
    var linesRemoved = 0;

    while (remaining > 0) {
      final result = _findNodeAtOffset(currentOffset);
      if (result == null) break;

      final (:targetNode, :localOffset) = result;
      final piece = targetNode.piece;
      final available = piece.length - localOffset;

      if (localOffset == 0 && remaining >= piece.length) {
        // Delete entire piece
        linesRemoved += piece.lfCount;
        remaining -= piece.length;
        _removeNode(targetNode);
      } else if (localOffset == 0) {
        // Delete from start of piece
        final deletedText = _pieceText(piece).substring(0, remaining);
        linesRemoved += _countLines(deletedText);
        targetNode.piece = _Piece(
          piece.bufferType,
          piece.start + remaining,
          piece.length - remaining,
          piece.lfCount - _countLines(deletedText),
        );
        _updateMetadata(targetNode);
        remaining = 0;
      } else if (remaining >= available) {
        // Delete from offset to end of piece
        final deletedText = _pieceText(piece).substring(localOffset);
        linesRemoved += _countLines(deletedText);
        targetNode.piece = _Piece(
          piece.bufferType,
          piece.start,
          localOffset,
          piece.lfCount - _countLines(deletedText),
        );
        _updateMetadata(targetNode);
        remaining -= available;
      } else {
        // Delete middle of piece — split into two
        final deletedText = _pieceText(
          piece,
        ).substring(localOffset, localOffset + remaining);
        linesRemoved += _countLines(deletedText);

        final rightPiece = _Piece(
          piece.bufferType,
          piece.start + localOffset + remaining,
          piece.length - localOffset - remaining,
          _countLineFeedsInRange(piece, localOffset + remaining, piece.length),
        );

        targetNode.piece = _Piece(
          piece.bufferType,
          piece.start,
          localOffset,
          _countLineFeedsInRange(piece, 0, localOffset),
        );
        _updateMetadata(targetNode);

        final rightNode = _RBNode(rightPiece)
          ..sizeLeft = 0
          ..lfLeft = 0;
        _insertAfter(targetNode, rightNode);

        remaining = 0;
      }
    }

    lineCount -= linesRemoved;
  }

  ({_RBNode targetNode, int localOffset})? _findNodeAtOffset(int offset) {
    var node = _root;
    var accum = 0;

    while (node != _RBNode.sentinel) {
      final leftSize = node.sizeLeft;
      if (offset < accum + leftSize) {
        node = node.left;
      } else if (offset >= accum + leftSize + node.piece.length) {
        accum += leftSize + node.piece.length;
        node = node.right;
      } else {
        return (targetNode: node, localOffset: offset - accum - leftSize);
      }
    }

    return null;
  }

  int _lineAtOffset(int offset) {
    var node = _root;
    var accum = 0;
    var lfAccum = 0;

    while (node != _RBNode.sentinel) {
      final leftSize = node.sizeLeft;
      if (offset < accum + leftSize) {
        node = node.left;
      } else if (offset >= accum + leftSize + node.piece.length) {
        lfAccum += node.lfLeft + node.piece.lfCount;
        accum += leftSize + node.piece.length;
        node = node.right;
      } else {
        lfAccum += node.lfLeft;
        final localOff = offset - accum - leftSize;
        final text = _pieceText(node.piece).substring(0, localOff);
        lfAccum += _countLines(text);
        return lfAccum;
      }
    }
    return lfAccum;
  }

  int _offsetAtLine(int line) {
    var node = _root;
    var accum = 0;
    var lfAccum = 0;

    while (node != _RBNode.sentinel) {
      if (line <= lfAccum + node.lfLeft) {
        node = node.left;
      } else if (line > lfAccum + node.lfLeft + node.piece.lfCount) {
        lfAccum += node.lfLeft + node.piece.lfCount;
        accum += node.sizeLeft + node.piece.length;
        node = node.right;
      } else {
        accum += node.sizeLeft;
        lfAccum += node.lfLeft;
        final targetLf = line - lfAccum;

        final text = _pieceText(node.piece);
        var lfCount = 0;
        for (var i = 0; i < text.length; i++) {
          if (text.codeUnitAt(i) == 0x0A) {
            lfCount++;
            if (lfCount == targetLf) return accum + i + 1;
          }
        }
        return accum + text.length;
      }
    }
    return accum;
  }

  // ── Private: RB-tree operations (simplified) ────────────────────────

  void _insertBefore(_RBNode target, _RBNode newNode) {
    if (target.left == _RBNode.sentinel) {
      target.left = newNode;
      newNode.parent = target;
    } else {
      var pred = target.left;
      while (pred.right != _RBNode.sentinel) {
        pred = pred.right;
      }
      pred.right = newNode;
      newNode.parent = pred;
    }
    newNode.color = _Color.red;
    _fixAfterInsert(newNode);
    _updateAncestorMetadata(newNode);
  }

  void _insertAfter(_RBNode target, _RBNode newNode) {
    if (target.right == _RBNode.sentinel) {
      target.right = newNode;
      newNode.parent = target;
    } else {
      var succ = target.right;
      while (succ.left != _RBNode.sentinel) {
        succ = succ.left;
      }
      succ.left = newNode;
      newNode.parent = succ;
    }
    newNode.color = _Color.red;
    _fixAfterInsert(newNode);
    _updateAncestorMetadata(newNode);
  }

  void _appendNode(_RBNode newNode) {
    if (_root == _RBNode.sentinel) {
      _root = newNode;
      newNode.color = _Color.black;
      return;
    }

    var node = _root;
    while (node.right != _RBNode.sentinel) {
      node = node.right;
    }
    node.right = newNode;
    newNode.parent = node;
    newNode.color = _Color.red;
    _fixAfterInsert(newNode);
    _updateAncestorMetadata(newNode);
  }

  void _removeNode(_RBNode z) {
    if (z.left != _RBNode.sentinel && z.right != _RBNode.sentinel) {
      // Two children — replace with in-order successor
      var y = z.right;
      while (y.left != _RBNode.sentinel) {
        y = y.left;
      }
      z.piece = y.piece;
      _removeNode(y);
      _updateMetadata(z);
      return;
    }

    // 0 or 1 children
    final x = z.left != _RBNode.sentinel ? z.left : z.right;
    final xParent = z.parent;
    final wasLeft = xParent != null && z == xParent.left;

    // Splice out z
    _transplant(z, x);

    // Fix up colors
    if (z.color == _Color.black) {
      if (x != _RBNode.sentinel && x.color == _Color.red) {
        x.color = _Color.black;
      } else if (xParent != null) {
        _fixAfterDelete(x, xParent, wasLeft);
      }
    }

    if (xParent != null) _updateAncestorMetadata(xParent);
    _root.color = _Color.black;
  }

  void _transplant(_RBNode u, _RBNode v) {
    if (u.parent == null) {
      _root = v;
    } else if (u == u.parent!.left) {
      u.parent!.left = v;
    } else {
      u.parent!.right = v;
    }
    if (v != _RBNode.sentinel) v.parent = u.parent;
  }

  void _fixAfterDelete(_RBNode x, _RBNode? parent, bool isLeft) {
    while (x != _root && _colorOf(x) == _Color.black) {
      if (parent == null) break;

      if (isLeft) {
        var w = parent.right;
        if (w.color == _Color.red) {
          w.color = _Color.black;
          parent.color = _Color.red;
          _rotateLeft(parent);
          w = parent.right;
        }
        if (_colorOf(w.left) == _Color.black &&
            _colorOf(w.right) == _Color.black) {
          w.color = _Color.red;
          x = parent;
          parent = x.parent;
          isLeft = parent != null && x == parent.left;
        } else {
          if (_colorOf(w.right) == _Color.black) {
            if (w.left != _RBNode.sentinel) w.left.color = _Color.black;
            w.color = _Color.red;
            _rotateRight(w);
            w = parent.right;
          }
          w.color = parent.color;
          parent.color = _Color.black;
          if (w.right != _RBNode.sentinel) w.right.color = _Color.black;
          _rotateLeft(parent);
          x = _root;
        }
      } else {
        var w = parent.left;
        if (w.color == _Color.red) {
          w.color = _Color.black;
          parent.color = _Color.red;
          _rotateRight(parent);
          w = parent.left;
        }
        if (_colorOf(w.right) == _Color.black &&
            _colorOf(w.left) == _Color.black) {
          w.color = _Color.red;
          x = parent;
          parent = x.parent;
          isLeft = parent != null && x == parent.left;
        } else {
          if (_colorOf(w.left) == _Color.black) {
            if (w.right != _RBNode.sentinel) w.right.color = _Color.black;
            w.color = _Color.red;
            _rotateLeft(w);
            w = parent.left;
          }
          w.color = parent.color;
          parent.color = _Color.black;
          if (w.left != _RBNode.sentinel) w.left.color = _Color.black;
          _rotateRight(parent);
          x = _root;
        }
      }
    }
    if (x != _RBNode.sentinel) x.color = _Color.black;
  }

  _Color _colorOf(_RBNode node) =>
      node == _RBNode.sentinel ? _Color.black : node.color;

  void _fixAfterInsert(_RBNode node) {
    while (node != _root && node.parent?.color == _Color.red) {
      final parent = node.parent!;
      final grandparent = parent.parent;
      if (grandparent == null) break;

      if (parent == grandparent.left) {
        final uncle = grandparent.right;
        if (uncle.color == _Color.red) {
          parent.color = _Color.black;
          uncle.color = _Color.black;
          grandparent.color = _Color.red;
          node = grandparent;
        } else {
          if (node == parent.right) {
            node = parent;
            _rotateLeft(node);
          }
          node.parent!.color = _Color.black;
          node.parent!.parent?.color = _Color.red;
          if (node.parent!.parent != null) {
            _rotateRight(node.parent!.parent!);
          }
        }
      } else {
        final uncle = grandparent.left;
        if (uncle.color == _Color.red) {
          parent.color = _Color.black;
          uncle.color = _Color.black;
          grandparent.color = _Color.red;
          node = grandparent;
        } else {
          if (node == parent.left) {
            node = parent;
            _rotateRight(node);
          }
          node.parent!.color = _Color.black;
          node.parent!.parent?.color = _Color.red;
          if (node.parent!.parent != null) {
            _rotateLeft(node.parent!.parent!);
          }
        }
      }
    }
    _root.color = _Color.black;
  }

  void _rotateLeft(_RBNode node) {
    final right = node.right;
    node.right = right.left;
    if (right.left != _RBNode.sentinel) {
      right.left.parent = node;
    }
    right.parent = node.parent;
    if (node.parent == null) {
      _root = right;
    } else if (node == node.parent!.left) {
      node.parent!.left = right;
    } else {
      node.parent!.right = right;
    }
    right.left = node;
    node.parent = right;

    // Recompute metadata bottom-up: node first (now child), then right (now parent)
    _updateMetadata(node);
    _updateMetadata(right);
  }

  void _rotateRight(_RBNode node) {
    final left = node.left;
    node.left = left.right;
    if (left.right != _RBNode.sentinel) {
      left.right.parent = node;
    }
    left.parent = node.parent;
    if (node.parent == null) {
      _root = left;
    } else if (node == node.parent!.right) {
      node.parent!.right = left;
    } else {
      node.parent!.left = left;
    }
    left.right = node;
    node.parent = left;

    // Recompute metadata bottom-up: node first (now child), then left (now parent)
    _updateMetadata(node);
    _updateMetadata(left);
  }

  void _updateMetadata(_RBNode node) {
    if (node == _RBNode.sentinel) return;
    final leftSize = node.left == _RBNode.sentinel ? 0 : node.left.subtreeSize;
    final rightSize = node.right == _RBNode.sentinel
        ? 0
        : node.right.subtreeSize;
    final leftLf = node.left == _RBNode.sentinel ? 0 : node.left.subtreeLfCount;
    final rightLf = node.right == _RBNode.sentinel
        ? 0
        : node.right.subtreeLfCount;
    node.sizeLeft = leftSize;
    node.lfLeft = leftLf;
    node.subtreeSize = leftSize + node.piece.length + rightSize;
    node.subtreeLfCount = leftLf + node.piece.lfCount + rightLf;
  }

  void _updateAncestorMetadata(_RBNode node) {
    var current = node;
    while (current != _RBNode.sentinel) {
      _updateMetadata(current);
      if (current.parent == null) break;
      current = current.parent!;
    }
  }

  // ── Private: Helpers ────────────────────────────────────────────────

  String? _addBufferCache;

  String _pieceText(_Piece piece) {
    if (piece.bufferType == _BufferType.original) {
      return originalBuffer.substring(piece.start, piece.start + piece.length);
    }
    // Cache addBuffer.toString() — invalidated on insert
    _addBufferCache ??= addBuffer.toString();
    return _addBufferCache!.substring(piece.start, piece.start + piece.length);
  }

  void _walkPiecesFrom(
    int offset,
    bool Function(_Piece piece, int pieceOffset, int localOffset) callback,
  ) {
    var node = _root;
    var accum = 0;

    // Find starting node
    while (node != _RBNode.sentinel) {
      final leftSize = node.sizeLeft;
      if (offset < accum + leftSize) {
        node = node.left;
      } else if (offset >= accum + leftSize + node.piece.length) {
        accum += leftSize + node.piece.length;
        node = node.right;
      } else {
        // Found the starting node
        final localOff = offset - accum - leftSize;
        if (!callback(node.piece, accum + leftSize, localOff)) return;
        accum = accum + leftSize + node.piece.length;

        // Continue with in-order successor
        _inorderFrom(node, accum, (n, off) {
          return callback(n.piece, off, 0);
        });
        return;
      }
    }
  }

  void _inorderFrom(
    _RBNode startNode,
    int startOffset,
    bool Function(_RBNode node, int offset) callback,
  ) {
    // Simple in-order traversal from successor
    var node = startNode;
    var offset = startOffset;

    // Go to right subtree
    if (node.right != _RBNode.sentinel) {
      _inorderVisit(node.right, offset, callback);
    }

    // Go up and right
    while (node.parent != null) {
      if (node == node.parent!.left) {
        offset = _nodeOffset(node.parent!);
        if (!callback(node.parent!, offset)) return;
        offset += node.parent!.piece.length;
        if (node.parent!.right != _RBNode.sentinel) {
          _inorderVisit(node.parent!.right, offset, callback);
        }
      }
      node = node.parent!;
    }
  }

  bool _inorderVisit(
    _RBNode node,
    int offset,
    bool Function(_RBNode node, int offset) callback,
  ) {
    if (node == _RBNode.sentinel) return true;
    if (!_inorderVisit(node.left, offset, callback)) return false;
    final nodeOff = offset + node.sizeLeft;
    if (!callback(node, nodeOff)) return false;
    return _inorderVisit(node.right, nodeOff + node.piece.length, callback);
  }

  int _nodeOffset(_RBNode target) {
    var offset = target.sizeLeft;
    var node = target;
    while (node.parent != null) {
      if (node == node.parent!.right) {
        offset += node.parent!.sizeLeft + node.parent!.piece.length;
      }
      node = node.parent!;
    }
    return offset;
  }

  void _inorder(_RBNode node, void Function(_RBNode) callback) {
    if (node == _RBNode.sentinel) return;
    _inorder(node.left, callback);
    callback(node);
    _inorder(node.right, callback);
  }

  int _countLineFeedsInRange(_Piece piece, int from, int to) {
    final text = _pieceText(piece);
    var count = 0;
    for (var i = from; i < to && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }

  _RBNode _cloneTree(_RBNode node) {
    if (node == _RBNode.sentinel) return _RBNode.sentinel;
    final clone = _RBNode(node.piece)
      ..color = node.color
      ..sizeLeft = node.sizeLeft
      ..lfLeft = node.lfLeft
      ..subtreeSize = node.subtreeSize
      ..subtreeLfCount = node.subtreeLfCount;
    clone.left = _cloneTree(node.left);
    clone.right = _cloneTree(node.right);
    if (clone.left != _RBNode.sentinel) clone.left.parent = clone;
    if (clone.right != _RBNode.sentinel) clone.right.parent = clone;
    return clone;
  }

  static int _countLines(String text) {
    var count = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }

  static int _countLineFeeds(String text) => _countLines(text);

  @override
  String toString() =>
      'PieceTable(length: $length, lines: $lineCount, simple: $_useSimple)';
}

// ─────────────────────────────────────────────────────────────────────────────
// PieceTableSnapshot — Lightweight snapshot for undo
// ─────────────────────────────────────────────────────────────────────────────

/// A snapshot of a PieceTable's state for undo/redo.
///
/// Since piece tables use append-only buffers, snapshots are lightweight —
/// they only store the tree structure, not the text data.
@immutable
class PieceTableSnapshot {
  const PieceTableSnapshot._({
    required this.addBufferLength,
    required this.treeSnapshot,
    required this.simpleText,
    required this.length,
    required this.lineCount,
    required this.useSimple,
    required this.editCount,
  });

  final int addBufferLength;
  // ignore: library_private_types_in_public_api
  final _RBNode? treeSnapshot;
  final String? simpleText;
  final int length;
  final int lineCount;
  final bool useSimple;
  final int editCount;
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: Piece, RBNode, enums
// ─────────────────────────────────────────────────────────────────────────────

enum _BufferType { original, add }

enum _Color { red, black }

class _Piece {
  _Piece(this.bufferType, this.start, this.length, this.lfCount);

  final _BufferType bufferType;
  final int start;
  final int length;
  final int lfCount;
}

class _RBNode {
  _RBNode(this.piece) {
    left = sentinel;
    right = sentinel;
    subtreeSize = piece.length;
    subtreeLfCount = piece.lfCount;
  }

  _Piece piece;
  _Color color = _Color.red;
  _RBNode? parent;
  late _RBNode left;
  late _RBNode right;

  /// Total character count of the left subtree.
  int sizeLeft = 0;

  /// Total line feed count of the left subtree.
  int lfLeft = 0;

  /// Total character count of the entire subtree rooted at this node.
  int subtreeSize = 0;

  /// Total line feed count of the entire subtree rooted at this node.
  int subtreeLfCount = 0;

  static final _RBNode sentinel = _RBNode._sentinel();

  _RBNode._sentinel() : piece = _Piece(_BufferType.original, 0, 0, 0) {
    color = _Color.black;
    left = this;
    right = this;
    subtreeSize = 0;
    subtreeLfCount = 0;
  }
}
