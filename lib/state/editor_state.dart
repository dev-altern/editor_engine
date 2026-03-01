import 'package:meta/meta.dart';

import '../model/node.dart';
import '../schema/schema.dart';
import '../transform/transaction.dart';
import 'selection.dart';

export 'history.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditorState — Immutable state snapshot
// ─────────────────────────────────────────────────────────────────────────────

/// The complete, immutable state of the editor at a point in time.
///
/// An EditorState contains:
/// - The [doc]ument (the content tree)
/// - The current [selection]
/// - The [schema] defining document structure
/// - Plugin states (extensible)
///
/// State is never mutated directly. Instead, create a [Transaction],
/// apply operations to it, and call [apply] to produce a new state.
///
/// ```dart
/// final newState = state.apply(
///   state.transaction..insertText(5, "hello")
/// );
/// ```
@immutable
class EditorState {
  /// Creates an editor state.
  const EditorState({
    required this.doc,
    required this.selection,
    required this.schema,
    this.plugins = const [],
    this.pluginStates = const {},
  });

  /// Creates an initial editor state from a schema and optional content.
  factory EditorState.create({
    required Schema schema,
    DocNode? doc,
    Selection? selection,
    List<Plugin> plugins = const [],
  }) {
    final document = doc ??
        DocNode.fromBlocks([
          schema.block('paragraph', content: [schema.text('')]),
        ]);

    final sel = selection ?? TextSelection.collapsed(1); // inside first block

    // Initialize plugin states
    final pluginStates = <String, Object>{};
    for (final plugin in plugins) {
      final state = plugin.init(document, sel);
      if (state != null) {
        pluginStates[plugin.key] = state;
      }
    }

    return EditorState(
      doc: document,
      selection: sel,
      schema: schema,
      plugins: plugins,
      pluginStates: pluginStates,
    );
  }

  /// The document.
  final DocNode doc;

  /// The current selection.
  final Selection selection;

  /// The document schema.
  final Schema schema;

  /// Registered plugins.
  final List<Plugin> plugins;

  /// Plugin state data.
  final Map<String, Object> pluginStates;

  // ── Convenience accessors ───────────────────────────────────────────

  /// The full text content of the document.
  String get textContent => doc.textContent;

  /// The number of top-level blocks in the document.
  int get blockCount => doc.content.childCount;

  /// Creates a new transaction on this state.
  Transaction get transaction => Transaction(doc);

  // ── State application ───────────────────────────────────────────────

  /// Applies a [transaction] to produce a new state.
  ///
  /// This is the ONLY way to change editor state.
  EditorState apply(Transaction tr) {
    final newDoc = tr.doc;

    // Use mapThrough for accurate sequential position mapping
    final newSelection = tr.selection ?? selection.mapThrough(tr.mapping);

    // Apply plugin transforms, passing selectionBefore without mutating tr
    final selBefore = selection;
    final newPluginStates = <String, Object>{};
    for (final plugin in plugins) {
      final oldState = pluginStates[plugin.key];
      final newState =
          plugin.apply(tr, oldState, selectionBefore: selBefore);
      if (newState != null) {
        newPluginStates[plugin.key] = newState;
      }
    }

    return EditorState(
      doc: newDoc,
      selection: newSelection,
      schema: schema,
      plugins: plugins,
      pluginStates: newPluginStates,
    );
  }

  /// Gets the state for a specific plugin.
  T? pluginState<T>(String key) => pluginStates[key] as T?;

  @override
  String toString() =>
      'EditorState(${doc.content.childCount} blocks, sel: $selection)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Plugin — State extension mechanism
// ─────────────────────────────────────────────────────────────────────────────

/// A plugin that extends editor state with custom data.
///
/// Plugins can:
/// - Maintain their own state alongside the editor state
/// - React to transactions
/// - Transform transactions before application
///
/// Example: HistoryPlugin tracks undo/redo state.
abstract class Plugin {
  /// Unique key for this plugin.
  String get key;

  /// Initialize plugin state from the initial document and selection.
  Object? init(DocNode doc, Selection selection) => null;

  /// Apply a transaction to the plugin state.
  ///
  /// [selectionBefore] is the selection from before the transaction was applied.
  /// Returns the new plugin state, or null to remove it.
  Object? apply(Transaction tr, Object? state, {Selection? selectionBefore}) =>
      state;
}
