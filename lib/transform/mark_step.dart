import '../model/fragment.dart';
import '../model/mark.dart';
import '../model/node.dart';
import 'step.dart';
import 'step_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AddMarkStep — Apply a mark to a range
// ─────────────────────────────────────────────────────────────────────────────

/// Applies a mark to inline content in the given range.
class AddMarkStep extends Step {
  const AddMarkStep(this.from, this.to, this.mark);

  final int from;
  final int to;
  final Mark mark;

  @override
  StepMap getMap() => StepMap.identity;

  @override
  StepResult apply(DocNode doc) {
    try {
      final newContent = _applyMark(doc.content, from, to, mark, 0);
      return StepResult.ok(DocNode(content: newContent));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  Step invert(DocNode doc) => RemoveMarkStep(from, to, mark);

  @override
  Map<String, dynamic> toJson() => {
    'stepType': 'addMark',
    'from': from,
    'to': to,
    'mark': mark.toJson(),
  };

  Fragment _applyMark(
    Fragment fragment,
    int from,
    int to,
    Mark mark,
    int base,
  ) {
    final children = <Node>[];
    var pos = base;

    for (var i = 0; i < fragment.childCount; i++) {
      final child = fragment.child(i);
      final childEnd = pos + child.nodeSize;

      if (child.isText && childEnd > from && pos < to) {
        final textChild = child as TextNode;
        final markFrom = (from - pos).clamp(0, textChild.text.length);
        final markTo = (to - pos).clamp(0, textChild.text.length);

        if (markFrom > 0) {
          children.add(textChild.cut(0, markFrom));
        }
        children.add(textChild.cut(markFrom, markTo).addMark(mark));
        if (markTo < textChild.text.length) {
          children.add(textChild.cut(markTo));
        }
      } else if (child is InlineWidgetNode && childEnd > from && pos < to) {
        // Inline widgets can also carry marks
        children.add(child.withMarks(child.marks.addMark(mark)));
      } else if (!child.isLeaf && child.content.isNotEmpty) {
        final newContent = _applyMark(child.content, from, to, mark, pos + 1);
        children.add(child.copy(newContent));
      } else {
        children.add(child);
      }

      pos = childEnd;
    }

    return Fragment(children);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RemoveMarkStep — Remove a mark from a range
// ─────────────────────────────────────────────────────────────────────────────

/// Removes a mark from inline content in the given range.
class RemoveMarkStep extends Step {
  const RemoveMarkStep(this.from, this.to, this.mark);

  final int from;
  final int to;
  final Mark mark;

  @override
  StepMap getMap() => StepMap.identity;

  @override
  StepResult apply(DocNode doc) {
    try {
      final newContent = _removeMark(doc.content, from, to, mark, 0);
      return StepResult.ok(DocNode(content: newContent));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  Step invert(DocNode doc) => AddMarkStep(from, to, mark);

  @override
  Map<String, dynamic> toJson() => {
    'stepType': 'removeMark',
    'from': from,
    'to': to,
    'mark': mark.toJson(),
  };

  Fragment _removeMark(
    Fragment fragment,
    int from,
    int to,
    Mark mark,
    int base,
  ) {
    final children = <Node>[];
    var pos = base;

    for (var i = 0; i < fragment.childCount; i++) {
      final child = fragment.child(i);
      final childEnd = pos + child.nodeSize;

      if (child.isText && childEnd > from && pos < to) {
        final textChild = child as TextNode;
        if (textChild.marks.hasMark(mark.type)) {
          final markFrom = (from - pos).clamp(0, textChild.text.length);
          final markTo = (to - pos).clamp(0, textChild.text.length);

          if (markFrom > 0) {
            children.add(textChild.cut(0, markFrom));
          }
          children.add(textChild.cut(markFrom, markTo).removeMark(mark.type));
          if (markTo < textChild.text.length) {
            children.add(textChild.cut(markTo));
          }
        } else {
          children.add(child);
        }
      } else if (child is InlineWidgetNode &&
          childEnd > from &&
          pos < to &&
          child.marks.hasMark(mark.type)) {
        // Inline widgets can also carry marks
        children.add(child.withMarks(child.marks.removeMark(mark.type)));
      } else if (!child.isLeaf && child.content.isNotEmpty) {
        final newContent = _removeMark(child.content, from, to, mark, pos + 1);
        children.add(child.copy(newContent));
      } else {
        children.add(child);
      }

      pos = childEnd;
    }

    return Fragment(children);
  }
}
