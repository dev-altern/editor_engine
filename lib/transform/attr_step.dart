import '../model/node.dart';
import 'step.dart';
import 'step_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SetAttrStep — Change a node's attributes
// ─────────────────────────────────────────────────────────────────────────────

/// Changes an attribute on the node at the given position.
class SetAttrStep extends Step {
  const SetAttrStep(this.pos, this.key, this.value);

  /// The position of the node (its open token position).
  final int pos;

  /// The attribute key to set.
  final String key;

  /// The new value.
  final Object? value;

  @override
  StepMap getMap() => StepMap.identity;

  @override
  StepResult apply(DocNode doc) {
    try {
      final resolved = doc.resolve(pos);
      final node = resolved.nodeAfter;
      if (node == null) {
        return const StepResult.fail('No node at position');
      }
      final newAttrs = {...node.attrs, key: value};
      final newNode = node.withAttrs(newAttrs);

      // Replace the node in its parent
      final parent = resolved.parent;
      final index = resolved.parentIndex;
      final newContent = parent.content.replaceChild(index, newNode);
      final newParent = parent.copy(newContent);

      // Rebuild up to root
      return StepResult.ok(_rebuildToRoot(doc, resolved, newParent));
    } catch (e) {
      return StepResult.fail(e.toString());
    }
  }

  @override
  Step invert(DocNode doc) {
    final resolved = doc.resolve(pos);
    final node = resolved.nodeAfter;
    final oldValue = node?.attrs[key];
    return SetAttrStep(pos, key, oldValue);
  }

  @override
  Map<String, dynamic> toJson() => {
        'stepType': 'setAttr',
        'pos': pos,
        'key': key,
        'value': value,
      };

  DocNode _rebuildToRoot(DocNode doc, ResolvedPos resolved, Node newParent) {
    // Walk back up the tree, rebuilding each ancestor
    if (resolved.depth == 0) {
      return DocNode(content: (newParent as DocNode).content);
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
}
