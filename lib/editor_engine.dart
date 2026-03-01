/// A state-of-the-art, pure Dart editor engine.
///
/// Features:
/// - Schema-validated document model (ProseMirror-grade)
/// - Per-block piece table text buffers
/// - Transactional editing with atomic undo
/// - Position mapping through edits
/// - Multi-cursor selection model
/// - Branching undo/redo history
/// - Plugin architecture for extensibility
/// - CRDT-ready collaborative editing bridge
/// - JSON/HTML/Markdown serialization
///
/// ## Quick Start
///
/// ```dart
/// import 'package:editor_engine/editor_engine.dart';
///
/// // Create a document
/// final doc = DocNode.fromBlocks([
///   BlockNode(type: 'paragraph', inlineContent: true, content: Fragment([
///     TextNode('Hello '),
///     TextNode('world', marks: [Mark.bold]),
///   ])),
/// ]);
///
/// // Create editor state
/// final state = EditorState.create(
///   schema: basicSchema,
///   doc: doc,
/// );
///
/// // Edit via transactions
/// final tr = state.transaction
///   ..insertText(6, 'beautiful ')
///   ..addMark(6, 16, Mark.italic);
///
/// final newState = state.apply(tr);
/// ```
library;

// Model
export 'model/node.dart';
export 'model/fragment.dart';
export 'model/mark.dart';
export 'model/slice.dart';
export 'model/resolved_pos.dart';

// Schema
export 'schema/schema.dart';

// Buffer
export 'buffer/piece_table.dart';

// Transform
export 'transform/step.dart';
export 'transform/step_map.dart';
export 'transform/transaction.dart';

// State
export 'state/editor_state.dart';
export 'state/selection.dart';

// Decorations
export 'state/decoration.dart';

// Markers
export 'markers/marker.dart';
export 'markers/marker_collection.dart';
export 'markers/interval_tree.dart';

// Serialization
export 'serialization/json_serializer.dart';
export 'serialization/html_serializer.dart';
export 'serialization/markdown_serializer.dart';
export 'serialization/delta_serializer.dart';

// Collaborative editing
export 'collab/collab.dart';
export 'collab/awareness.dart';
export 'collab/crdt_bridge.dart';
