import 'package:meta/meta.dart';

import '../model/node.dart';
import '../transform/step.dart';
import '../transform/step_map.dart';
import '../transform/transaction.dart';
import 'editor_state.dart';
import 'selection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// History — Undo/Redo tracking plugin
// ─────────────────────────────────────────────────────────────────────────────

/// Plugin that tracks undo/redo history.
///
/// Supports branching undo (when you undo, then make a new edit,
/// the redo stack becomes a branch rather than being lost).
class HistoryPlugin extends Plugin {
  HistoryPlugin({this.maxDepth = 200});

  /// Maximum number of undo entries.
  final int maxDepth;

  @override
  String get key => 'history';

  @override
  Object init(DocNode doc, Selection selection) =>
      HistoryState(
        undoStack: const [],
        redoStack: const [],
        branches: const [],
      );

  @override
  Object apply(Transaction tr, Object? state,
      {Selection? selectionBefore}) {
    final history = state as HistoryState? ??
        HistoryState(
          undoStack: const [],
          redoStack: const [],
          branches: const [],
        );

    if (!tr.addToHistory || !tr.hasSteps) return history;

    // Use selectionBefore passed from EditorState.apply
    final selBefore = selectionBefore ?? TextSelection.collapsed(0);

    // Compute inverse steps at apply-time while we have access to
    // intermediate documents. Each step is inverted against the doc
    // it was originally applied to.
    final inverseSteps = <Step>[];
    var doc = tr.docBefore;
    for (final step in tr.steps) {
      inverseSteps.add(step.invert(doc));
      final result = step.apply(doc);
      if (result.isOk) doc = result.doc!;
    }

    final entry = HistoryEntry(
      steps: tr.steps,
      inverseSteps: inverseSteps.reversed.toList(),
      maps: tr.maps,
      selectionBefore: selBefore,
      timestamp: DateTime.now(),
    );

    var newUndo = [...history.undoStack, entry];
    if (newUndo.length > maxDepth) {
      newUndo = newUndo.sublist(newUndo.length - maxDepth);
    }

    // If there's a redo stack, save it as a branch
    var newBranches = history.branches;
    if (history.redoStack.isNotEmpty) {
      newBranches = [...newBranches, history.redoStack];
    }

    return HistoryState(
      undoStack: newUndo,
      redoStack: const [],
      branches: newBranches,
    );
  }
}

/// The state maintained by [HistoryPlugin].
@immutable
class HistoryState {
  const HistoryState({
    required this.undoStack,
    required this.redoStack,
    required this.branches,
  });

  /// Stack of undoable entries (most recent last).
  final List<HistoryEntry> undoStack;

  /// Stack of redoable entries (most recent last).
  final List<HistoryEntry> redoStack;

  /// Saved redo branches (from undo + new edit).
  final List<List<HistoryEntry>> branches;

  /// Whether undo is available.
  bool get canUndo => undoStack.isNotEmpty;

  /// Whether redo is available.
  bool get canRedo => redoStack.isNotEmpty;
}

/// A single undo/redo entry.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.steps,
    required this.inverseSteps,
    required this.maps,
    required this.selectionBefore,
    required this.timestamp,
  });

  /// The steps that were applied.
  final List<Step> steps;

  /// Pre-computed inverse steps (in reverse order, ready for undo).
  ///
  /// Computed at apply-time against the correct intermediate documents
  /// to ensure accurate inversion for multi-step transactions.
  final List<Step> inverseSteps;

  /// The step maps from those steps.
  final List<StepMap> maps;

  /// The selection before this edit.
  final Selection selectionBefore;

  /// When this edit was made.
  final DateTime timestamp;
}

// ─────────────────────────────────────────────────────────────────────────────
// Undo / Redo operations
// ─────────────────────────────────────────────────────────────────────────────

/// Performs an undo operation on the editor state.
///
/// Returns null if there's nothing to undo.
EditorState? undo(EditorState state) {
  final history = state.pluginState<HistoryState>('history');
  if (history == null || !history.canUndo) return null;

  final entry = history.undoStack.last;

  // Build inverse transaction using pre-computed inverse steps
  final tr = Transaction(state.doc)..setMeta('addToHistory', false);

  for (final inverseStep in entry.inverseSteps) {
    tr.addStep(inverseStep);
  }

  tr.setSelection(entry.selectionBefore);

  // Update history state
  final newHistory = HistoryState(
    undoStack: history.undoStack.sublist(0, history.undoStack.length - 1),
    redoStack: [...history.redoStack, entry],
    branches: history.branches,
  );

  final newState = state.apply(tr);
  return EditorState(
    doc: newState.doc,
    selection: newState.selection,
    schema: state.schema,
    plugins: state.plugins,
    pluginStates: {...newState.pluginStates, 'history': newHistory},
  );
}

/// Performs a redo operation on the editor state.
///
/// Returns null if there's nothing to redo.
EditorState? redo(EditorState state) {
  final history = state.pluginState<HistoryState>('history');
  if (history == null || !history.canRedo) return null;

  final entry = history.redoStack.last;
  final tr = Transaction(state.doc)..setMeta('addToHistory', false);

  for (final step in entry.steps) {
    tr.addStep(step);
  }

  final newHistory = HistoryState(
    undoStack: [...history.undoStack, entry],
    redoStack: history.redoStack.sublist(0, history.redoStack.length - 1),
    branches: history.branches,
  );

  final newState = state.apply(tr);
  return EditorState(
    doc: newState.doc,
    selection: newState.selection,
    schema: state.schema,
    plugins: state.plugins,
    pluginStates: {...newState.pluginStates, 'history': newHistory},
  );
}
