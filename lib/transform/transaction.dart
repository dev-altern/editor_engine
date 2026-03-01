import '../model/fragment.dart';
import '../model/mark.dart';
import '../model/node.dart';
import '../state/selection.dart';
import 'step_map.dart';
import 'step.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Transaction — Atomic editing operation (may contain multiple steps)
// ─────────────────────────────────────────────────────────────────────────────

/// A transaction groups multiple [Step]s into an atomic editing operation
/// that forms a single undo unit.
///
/// Usage:
/// ```dart
/// final tr = Transaction(state.doc)
///   ..insertText(5, "hello")
///   ..addMark(5, 10, Mark.bold)
///   ..setSelection(TextSelection.collapsed(10));
///
/// final newState = state.apply(tr);
/// ```
class Transaction {
  /// Creates a transaction starting from the given document.
  Transaction(this._doc)
      : _steps = [],
        _maps = [],
        _currentDoc = _doc;

  final DocNode _doc;
  final List<Step> _steps;
  final List<StepMap> _maps;
  DocNode _currentDoc;
  Selection? _selection;
  bool _scrollIntoView = false;
  final Map<String, Object?> _metadata = {};

  /// The original document before any steps.
  DocNode get docBefore => _doc;

  /// The current document after all applied steps.
  DocNode get doc => _currentDoc;

  /// All steps in this transaction.
  List<Step> get steps => List.unmodifiable(_steps);

  /// All step maps in this transaction.
  List<StepMap> get maps => List.unmodifiable(_maps);

  /// The selection to set (null if unchanged).
  Selection? get selection => _selection;

  /// Whether to scroll the view to the cursor after applying.
  bool get scrollIntoView => _scrollIntoView;

  /// Transaction metadata (e.g., "addToHistory": false).
  Map<String, Object?> get metadata => _metadata;

  /// Whether this transaction has any steps.
  bool get hasSteps => _steps.isNotEmpty;

  /// The composed mapping of all steps.
  Mapping get mapping => Mapping.from(_maps);

  // ── Step application ────────────────────────────────────────────────

  /// Adds a step to this transaction.
  ///
  /// The step is applied immediately to the working document.
  /// Returns this transaction for chaining.
  Transaction addStep(Step step) {
    final result = step.apply(_currentDoc);
    if (!result.isOk) {
      throw StateError('Step failed: ${result.error}');
    }
    _steps.add(step);
    _maps.add(step.getMap());
    _currentDoc = result.doc!;

    // Map existing selection through the step
    if (_selection != null) {
      _selection = _selection!.map(step.getMap());
    }

    return this;
  }

  // ── Convenience methods ─────────────────────────────────────────────

  /// Inserts text at [pos].
  Transaction insertText(int pos, String text, {List<Mark>? marks}) {
    final textNode = TextNode(text, marks: marks ?? const []);
    final slice = Slice(Fragment.from(textNode), 0, 0);
    return addStep(ReplaceStep.insert(pos, slice));
  }

  /// Deletes content between [from] and [to].
  Transaction deleteRange(int from, int to) {
    if (from == to) return this;
    return addStep(ReplaceStep.delete(from, to));
  }

  /// Replaces content between [from] and [to] with [slice].
  Transaction replace(int from, int to, Slice slice) =>
      addStep(ReplaceStep(from, to, slice));

  /// Replaces content between [from] and [to] with [text].
  Transaction replaceText(int from, int to, String text, {List<Mark>? marks}) {
    if (text.isEmpty) return deleteRange(from, to);
    final textNode = TextNode(text, marks: marks ?? const []);
    final slice = Slice(Fragment.from(textNode), 0, 0);
    return addStep(ReplaceStep(from, to, slice));
  }

  /// Inserts a block node at the given document position.
  Transaction insertBlock(int pos, Node block) {
    final slice = Slice(Fragment.from(block), 0, 0);
    return addStep(ReplaceStep.insert(pos, slice));
  }

  /// Adds a mark to the range [from]..[to].
  Transaction addMark(int from, int to, Mark mark) =>
      addStep(AddMarkStep(from, to, mark));

  /// Removes a mark from the range [from]..[to].
  Transaction removeMark(int from, int to, Mark mark) =>
      addStep(RemoveMarkStep(from, to, mark));

  /// Changes a node attribute.
  Transaction setNodeAttr(int pos, String key, Object? value) =>
      addStep(SetAttrStep(pos, key, value));

  // ── Selection ───────────────────────────────────────────────────────

  /// Sets the selection after applying this transaction.
  Transaction setSelection(Selection sel) {
    _selection = sel;
    return this;
  }

  /// Sets a collapsed cursor at [pos].
  Transaction setCursor(int pos) {
    _selection = TextSelection.collapsed(pos);
    return this;
  }

  /// Marks that the view should scroll to the cursor after applying.
  Transaction ensureVisible() {
    _scrollIntoView = true;
    return this;
  }

  // ── Metadata ────────────────────────────────────────────────────────

  /// Sets a metadata value.
  Transaction setMeta(String key, Object? value) {
    _metadata[key] = value;
    return this;
  }

  /// Gets a metadata value.
  Object? getMeta(String key) => _metadata[key];

  /// Whether this transaction should be added to the undo history.
  bool get addToHistory => _metadata['addToHistory'] != false;

  @override
  String toString() =>
      'Transaction(${_steps.length} steps, selection: $_selection)';
}
