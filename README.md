# editor_engine

A pure Dart editor engine with a ProseMirror-grade document model, transactional editing, collaborative OT, and multi-format serialization. Zero Flutter dependency — usable anywhere Dart runs.

## Features

- **Immutable document tree** — Integer position model with open/close tokens, copy-on-write semantics
- **8 step types** — ReplaceStep, AddMarkStep, RemoveMarkStep, SetAttrStep, SplitStep, JoinStep, WrapStep, UnwrapStep
- **Transactional editing** — Atomic multi-step transactions with mapping, metadata, and selection tracking
- **Plugin architecture** — Extensible state management via plugins (history, decorations, markers, awareness)
- **Undo/redo** — Built-in HistoryPlugin with depth limits
- **Schema system** — Declarative node/mark definitions with content expressions and validation
- **Collaborative editing** — Full OT with Authority server, step transforms for all 8 step types, and client-side CollabPlugin
- **Marker system** — Tracked ranges with configurable boundary behavior, backed by an interval tree with O(log n + k) queries
- **Awareness** — Remote cursor/presence state model with position mapping through edits
- **CRDT bridge interface** — Abstract binding contract for Yjs/Automerge integration
- **Serialization** — JSON, HTML, Markdown, and Quill Delta formats
- **PieceTable text buffer** — Red-black tree indexed piece table for O(log n) per-block text operations
- **Decorations** — Inline, node, and widget decorations that track through edits
- **Selections** — Text, node, multi-cursor, and all-document selection types

## Quick start

```dart
import 'package:editor_engine/editor_engine.dart';

// Create a schema
final schema = Schema(
  nodes: {
    'doc': NodeSpec(name: 'doc', content: 'block+'),
    'paragraph': NodeSpec(name: 'paragraph', content: 'inline*', group: 'block'),
    'heading': NodeSpec(name: 'heading', content: 'inline*', group: 'block'),
    'image': NodeSpec(name: 'image', group: 'block', atom: true),
  },
  marks: {
    'bold': MarkSpec(name: 'bold'),
    'italic': MarkSpec(name: 'italic'),
    'link': MarkSpec(name: 'link'),
  },
);

// Build a document
final doc = schema.doc([
  schema.block('paragraph', content: [schema.text('Hello world')]),
]);

// Create editor state
final state = EditorState.create(
  schema: schema,
  doc: doc,
  plugins: [HistoryPlugin()],
);

// Apply a transaction
final tr = state.transaction
  ..insertText(6, 'beautiful ')
  ..setSelection(TextSelection.collapsed(16));
final newState = state.apply(tr);
print(newState.doc.textContent); // "Hello beautiful world"
```

## Serialization

```dart
// JSON round-trip
final json = JsonSerializer();
final data = json.serialize(doc);
final restored = json.deserialize(data);

// HTML
final html = HtmlSerializer();
final htmlStr = html.serialize(doc);
final fromHtml = html.deserialize('<p>Hello <strong>world</strong></p>');

// Markdown
final md = MarkdownSerializer();
final mdStr = md.serialize(doc);
final fromMd = md.deserialize('# Title\n\nSome **bold** text.');

// Quill Delta
final delta = DeltaSerializer();
final ops = delta.serialize(doc);
final fromDelta = delta.deserialize([
  {'insert': 'Hello '},
  {'insert': 'bold', 'attributes': {'bold': true}},
  {'insert': '\n'},
]);
```

## Collaborative editing

```dart
// Server-side authority
final authority = Authority(doc: initialDoc);

// Client sends steps
final result = authority.receiveSteps(clientVersion, steps, clientId);

// Client-side plugin
final state = EditorState.create(
  schema: schema,
  doc: doc,
  plugins: [CollabPlugin(clientId: 'alice', version: 0)],
);

// Get pending steps to send
final sendable = sendableSteps(state);
```

## Markers

```dart
// Track ranges through edits (comments, diagnostics, highlights)
final state = EditorState.create(
  schema: schema,
  doc: doc,
  plugins: [MarkerPlugin()],
);

final tr = state.transaction
  ..setMeta('addMarker', Marker(
    id: 'comment-1',
    from: 5,
    to: 15,
    type: 'comment',
    attrs: {'author': 'alice'},
    behavior: MarkerBehavior.exclusive,
  ));
final newState = state.apply(tr);

// Query markers
final markers = newState.pluginState<MarkerCollection>('markers')!;
final overlapping = markers.findOverlapping(8, 12);
```

## Architecture

```text
lib/
  model/          Document tree (Node, Fragment, Slice, ResolvedPos, TextNode, BlockNode, Mark)
  transform/      Steps, StepMap, Mapping, Transaction
  state/          EditorState, Selection, Plugin, History, Decoration
  schema/         Schema definitions, NodeSpec, MarkSpec, content expressions
  serialization/  JSON, HTML, Markdown, Delta serializers
  collab/         OT engine (Authority, CollabPlugin, Awareness, CRDT bridge)
  markers/        Tracked ranges (Marker, MarkerCollection, IntervalTree)
  buffer/         PieceTable text buffer
```

## Position model

The document uses an integer position system (ProseMirror-compatible):

```text
    0   1    2   3   4    5   6   7   8   9
    <p> "H"  "i" </p> <img/> <p> "B"  "y" </p>
```

- Each character = 1 position
- Each leaf node (image, divider) = 1 position
- Each non-leaf node = 2 (open + close) + content size

## Tests

383 tests covering all modules. Run with:

```bash
dart test
```
