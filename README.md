# editor_engine

A pure Dart editor engine with a ProseMirror-grade document model, transactional editing, collaborative OT, and multi-format serialization. Zero Flutter dependency — usable anywhere Dart runs.

| Metric | Value |
| -------- | ------- |
| Dart SDK | ^3.11.0 |
| Dependencies | `collection`, `meta` (no Flutter) |
| Lib files | 31 |
| Lib lines | ~10,900 |
| Test files | 13 |
| Test cases | 383 |
| Analysis issues | 0 errors, 0 warnings |

---

## Table of contents

- [Install](#install)
- [Quick start](#quick-start)
- [Architecture](#architecture)
- [Position model](#position-model)
- [Document model](#document-model)
  - [Node types](#node-types)
  - [Fragment](#fragment)
  - [Mark](#mark)
  - [ResolvedPos](#resolvedpos)
  - [Slice](#slice)
- [Schema](#schema)
  - [NodeSpec](#nodespec)
  - [MarkSpec](#markspec)
  - [Content expressions](#content-expressions)
  - [Built-in schemas](#built-in-schemas)
- [Transforms](#transforms)
  - [Steps](#steps)
  - [StepMap and Mapping](#stepmap-and-mapping)
  - [Transaction](#transaction)
- [State](#state)
  - [EditorState](#editorstate)
  - [Selections](#selections)
  - [Plugins](#plugins)
  - [History (undo/redo)](#history-undoredo)
  - [Decorations](#decorations)
- [Markers](#markers)
  - [Marker behaviors](#marker-behaviors)
  - [MarkerCollection](#markercollection)
  - [IntervalTree](#intervaltree)
  - [MarkerPlugin](#markerplugin)
- [Serialization](#serialization)
  - [JSON](#json)
  - [HTML](#html)
  - [Markdown](#markdown)
  - [Quill Delta](#quill-delta)
- [Collaborative editing](#collaborative-editing)
  - [Authority (server)](#authority-server)
  - [CollabPlugin (client)](#collabplugin-client)
  - [Step transformation (OT)](#step-transformation-ot)
  - [Awareness](#awareness)
  - [CRDT bridge](#crdt-bridge)
- [PieceTable buffer](#piecetable-buffer)
- [Do's and don'ts](#dos-and-donts)
- [Known limitations](#known-limitations)
- [Tests](#tests)
- [Full file map](#full-file-map)
- [API reference](#api-reference)

---

## Install

```yaml
# pubspec.yaml
dependencies:
  editor_engine:
    git:
      url: https://github.com/dev-altern/editor_engine.git
```

```dart
import 'package:editor_engine/editor_engine.dart';
```

The single barrel export gives you every public class. No need to import individual files.

---

## Quick start

```dart
import 'package:editor_engine/editor_engine.dart';

// 1. Define a schema
final schema = Schema(
  nodes: {
    'doc': NodeSpec(name: 'doc', content: 'block+'),
    'paragraph': NodeSpec(name: 'paragraph', content: 'inline*', group: 'block'),
    'heading': NodeSpec(
      name: 'heading', content: 'inline*', group: 'block',
      attrs: {'level': AttrSpec(defaultValue: 1)},
    ),
    'image': NodeSpec(name: 'image', group: 'block', atom: true),
  },
  marks: {
    'bold': MarkSpec(name: 'bold'),
    'italic': MarkSpec(name: 'italic'),
    'link': MarkSpec(name: 'link', attrs: {'href': AttrSpec(required: true)}),
  },
);

// 2. Build a document
final doc = schema.doc([
  schema.block('paragraph', content: [schema.text('Hello world')]),
]);

// 3. Create editor state with plugins
final state = EditorState.create(
  schema: schema,
  doc: doc,
  plugins: [HistoryPlugin()],
);

// 4. Edit via transactions
final tr = state.transaction
  ..insertText(6, 'beautiful ')
  ..addMark(6, 16, Mark.italic)
  ..setSelection(TextSelection.collapsed(16));

final newState = state.apply(tr);
print(newState.doc.textContent); // "Hello beautiful world"

// 5. Undo
final undone = undo(newState);
print(undone!.doc.textContent); // "Hello world"
```

---

## Architecture

```text
lib/
  editor_engine.dart          Barrel export (single import for everything)
  model/
    node.dart                 Node, TextNode, BlockNode, InlineWidgetNode, DocNode
    fragment.dart             Fragment (immutable child list with text merging)
    mark.dart                 Mark (inline formatting)
    resolved_pos.dart         ResolvedPos (position → tree path resolution)
    slice.dart                Slice (content with open depths for cut/paste)
  schema/
    schema.dart               Schema (structural validation)
    node_spec.dart            NodeSpec, MarkSpec, AttrSpec
    content_expression.dart   ContentExpression parser
  transform/
    step.dart                 Step (abstract), StepResult
    replace_step.dart         ReplaceStep (insert/delete/replace)
    mark_step.dart            AddMarkStep, RemoveMarkStep
    attr_step.dart            SetAttrStep
    structure_step.dart       SplitStep, JoinStep, WrapStep, UnwrapStep
    step_map.dart             StepMap, Mapping (position mapping)
    transaction.dart          Transaction (multi-step atomic operation)
  state/
    editor_state.dart         EditorState, Plugin (abstract)
    selection.dart            Selection, TextSelection, NodeSelection,
                              MultiCursorSelection, AllSelection
    history.dart              HistoryPlugin, HistoryState, HistoryEntry,
                              undo(), redo()
    decoration.dart           Decoration, InlineDecoration, NodeDecoration,
                              WidgetDecoration, DecorationSet, DecorationPlugin
  markers/
    marker.dart               Marker, MarkerBehavior
    marker_collection.dart    MarkerCollection, MarkerPlugin
    interval_tree.dart        IntervalTree, IntervalEntry
  serialization/
    json_serializer.dart      JsonSerializer
    html_serializer.dart      HtmlSerializer
    markdown_serializer.dart  MarkdownSerializer
    delta_serializer.dart     DeltaSerializer
  collab/
    collab.dart               Authority, CollabPlugin, CollabState,
                              sendableSteps(), receiveSteps(),
                              transformStep(), transformSteps()
    awareness.dart            AwarenessPlugin, AwarenessState, AwarenessUser,
                              AwarenessCursor, AwarenessPeer
    crdt_bridge.dart          CrdtBridge, CrdtOp, CrdtAwarenessBridge (abstract)
  buffer/
    piece_table.dart          PieceTable, PieceTableSnapshot
```

---

## Position model

The document uses a flat integer position system (ProseMirror-compatible). Every character, node boundary, and leaf node occupies positions:

```text
    0   1    2   3    4      5   6    7    8
    <p> "H"  "i" </p> <img/> <p> "B"  "y" </p>
```

Rules:

- Each character in a text node = **1 position**
- Each leaf/atom node (image, divider, inline widget) = **1 position**
- Each non-leaf node = **2 positions** (open + close tokens) + its content size

So a paragraph containing "Hi" has `nodeSize` = 2 + 2 = 4 (open token, "H", "i", close token).

Position 0 is always right before the first child of the document root. Position `doc.contentSize` is right after the last child. Positions outside `0..doc.contentSize` will throw `RangeError`.

---

## Document model

All nodes are **immutable**. Every edit returns a new tree (copy-on-write from the edited node up to root). Mutations happen through transactions, never by mutating nodes directly.

### Node types

#### `Node` (abstract base)

```dart
abstract class Node {
  String type;                    // "paragraph", "heading", "text", etc.
  Map<String, Object?> attrs;     // Node attributes (level, src, etc.)
  Fragment content;               // Child nodes (empty for leaves)
  List<Mark> marks;               // Inline formatting (text/inline nodes only)

  int get nodeSize;               // Size in position space
  int get contentSize;            // Content size (nodeSize - 2 for non-leaf)
  int get childCount;             // Number of direct children

  bool get isText;
  bool get isBlock;
  bool get isInline;
  bool get isLeaf;
  bool get isAtom;                // Leaf that is not text
  bool get isTextblock;           // Block that contains inline content
  bool get inlineContent;         // Whether children are inline

  Node child(int index);
  Node? maybeChild(int index);
  void forEach(void Function(Node, int offset, int index) callback);
  String get textContent;         // Concatenated text of all descendants
  List<TextNode> get textNodes;   // All text nodes flattened
  void descendants(bool Function(Node, int pos, Node? parent) callback);
  ResolvedPos resolve(int pos);   // Resolve flat position to tree path
  Node copy(Fragment newContent);
  Node withAttrs(Map<String, Object?> newAttrs);

  Map<String, dynamic> toJson();
  static Node nodeFromJson(Map<String, dynamic> json);
}
```

#### `TextNode`

Leaf inline node containing a string. `nodeSize` = `text.length`.

```dart
final node = TextNode('Hello', marks: [Mark.bold]);
final cut = node.cut(1, 3);           // TextNode("el", marks: [bold])
final withItalic = node.addMark(Mark.italic);
final plain = node.removeMark('bold');
final remarked = node.withMarks([Mark.italic]);
```

#### `BlockNode`

Non-leaf node for structural content. Constructor flags control node behavior:

```dart
final paragraph = BlockNode(
  type: 'paragraph',
  inlineContent: true,     // children are inline (text, widgets)
  content: Fragment([TextNode('Hello')]),
);

final image = BlockNode(
  type: 'image',
  isLeaf: true,            // no children allowed
  isAtom: true,            // selectable as a unit
  attrs: {'src': 'photo.jpg', 'alt': 'A photo'},
);

final blockquote = BlockNode(
  type: 'blockquote',
  content: Fragment([paragraph]),  // block children
);
```

**Flags:**

- `isLeaf: true` — no content (image, divider). `nodeSize` = 1.
- `isAtom: true` — treated as a single unit for selection.
- `isInline: true` — inline node (rare, use InlineWidgetNode instead).
- `inlineContent: true` — children are inline nodes (paragraph, heading).

#### `InlineWidgetNode`

Leaf inline atom for non-text inline content. `nodeSize` = 1.

```dart
final mention = InlineWidgetNode(
  widgetType: 'mention',
  attrs: {'userId': 'u123', 'name': 'Alice'},
  marks: [Mark.bold],
);
```

#### `DocNode`

Root document node. Always a block with block children.

```dart
final doc = DocNode.fromBlocks([paragraph1, paragraph2, image]);
```

### Fragment

Immutable ordered list of child nodes. Automatically merges adjacent text nodes with the same marks on construction.

```dart
final f = Fragment([TextNode('Hello '), TextNode('world')]);
f.childCount;           // 1 (merged into single TextNode)
f.size;                 // 11 (total position space)
f.child(0);             // TextNode("Hello world")
f.firstChild;
f.lastChild;
f.isEmpty;

// Querying
final (node, index, innerOffset) = f.findChild(5);

// Mutation (returns new Fragment)
f.append(TextNode('!'));
f.insert(0, otherNode);
f.removeAt(0);
f.replaceChild(0, newNode);
f.cut(3, 8);

// Iteration
f.forEach((node, offset, index) { ... });
```

Fragments with 8+ children use binary search via prefix sums for O(log n) `findChild` and `offsetAt`.

### Mark

Immutable value object for inline formatting. Equality is by `type` + `attrs`.

```dart
// Built-in factories
Mark.bold
Mark.italic
Mark.underline
Mark.strikethrough
Mark.code
Mark.superscript
Mark.subscript
Mark.link('https://example.com', 'title')
Mark.color('#ff0000')
Mark.highlight('yellow')

// Custom marks
final custom = Mark('myMark', {'key': 'value'});

// Operations
mark.withAttrs({'href': 'new-url'});
mark.withAttr('href', 'new-url');
mark.isType('bold');                // true/false
mark.hasAttrs;                      // true if attrs is non-empty

// List<Mark> extension methods
marks.hasMark('bold');              // bool
marks.getMark('bold');              // Mark?
marks.addMark(Mark.italic);        // List<Mark> (replaces same type)
marks.removeMark('bold');           // List<Mark>
marks.sameMarks(otherMarks);       // bool
```

### ResolvedPos

Resolves a flat integer position into the document tree structure. Tells you which node you're in, at what depth, what index, etc.

```dart
final $pos = doc.resolve(5);

$pos.pos;               // 5 (absolute position)
$pos.depth;             // nesting depth (0 = doc root)
$pos.parent;            // innermost containing node
$pos.parentOffset;      // offset within parent
$pos.parentStart;       // absolute start of parent content
$pos.parentIndex;       // index into parent's children

$pos.node(0);           // node at depth 0 (the doc)
$pos.node(1);           // node at depth 1 (first block)
$pos.index(depth);      // child index at depth
$pos.start(depth);      // content start position at depth
$pos.end(depth);        // content end position at depth

$pos.textOffset;        // offset within text node (0 if not in text)
$pos.nodeAfter;         // node directly after this position
$pos.nodeBefore;        // node directly before this position
$pos.sharedDepth(10);   // deepest common ancestor with position 10
```

### Slice

A chunk of document content with open depths, used for copy/paste and replace operations.

```dart
final slice = Slice(fragment, openStart, openEnd);

slice.content;      // Fragment
slice.openStart;    // how many levels open at the start
slice.openEnd;      // how many levels open at the end
slice.size;         // content.size - openStart - openEnd
slice.isEmpty;

Slice.empty;        // static empty slice

// Serialization
slice.toJson();
Slice.fromJson(json);
```

`openStart: 1` means the first node in the fragment is a "partial" block (its start boundary was cut). `openEnd: 1` means the last node's end boundary was cut. This is how cross-block selections are represented.

---

## Schema

A schema defines which node/mark types exist, how they nest, and what attributes they have.

```dart
final schema = Schema(
  nodes: {
    'doc': NodeSpec(name: 'doc', content: 'block+'),
    'paragraph': NodeSpec(name: 'paragraph', content: 'inline*', group: 'block'),
    'heading': NodeSpec(
      name: 'heading', content: 'inline*', group: 'block',
      attrs: {'level': AttrSpec(defaultValue: 1)},
    ),
    'blockquote': NodeSpec(name: 'blockquote', content: 'block+', group: 'block'),
    'bullet_list': NodeSpec(name: 'bullet_list', content: 'list_item+', group: 'block'),
    'list_item': NodeSpec(name: 'list_item', content: 'block+'),
    'image': NodeSpec(name: 'image', group: 'block', atom: true),
    'horizontal_rule': NodeSpec(name: 'horizontal_rule', group: 'block', atom: true),
    'hard_break': NodeSpec(name: 'hard_break', inline: true, atom: true),
    'text': NodeSpec(name: 'text', group: 'inline', inline: true),
  },
  marks: {
    'bold': MarkSpec(name: 'bold'),
    'italic': MarkSpec(name: 'italic'),
    'code': MarkSpec(name: 'code', excludes: '_'),  // excludes all other marks
    'link': MarkSpec(
      name: 'link', inclusive: false,
      attrs: {'href': AttrSpec(required: true), 'title': AttrSpec()},
    ),
  },
);
```

### Schema methods

```dart
// Create nodes via schema (applies defaults, validates)
schema.text('Hello', [Mark.bold]);
schema.block('paragraph', content: [schema.text('Hi')]);
schema.block('heading', attrs: {'level': 2}, content: [...]);
schema.inlineWidget('mention', attrs: {'name': 'Alice'});
schema.doc([paragraph, heading]);
schema.mark('bold');
schema.mark('link', {'href': 'https://...'});

// Validation
schema.validateDocument(doc);               // List<String> of errors (empty = valid)
schema.validateContent(node);               // bool
schema.allowsChild('paragraph', 'text');    // bool
schema.allowsMark('paragraph', 'bold');     // bool
schema.marksExclude('code', existingMarks); // bool

// Introspection
schema.nodeSpec('paragraph');               // NodeSpec?
schema.contentExpression('doc');            // ContentExpression?
```

### NodeSpec

```dart
NodeSpec(
  name: 'heading',         // required
  content: 'inline*',      // content expression (empty = leaf)
  group: 'block',          // group membership for content expressions
  marks: '_',              // allowed marks ('_' = all, '' = none, 'bold italic' = specific)
  attrs: {                 // attribute definitions
    'level': AttrSpec(defaultValue: 1),
    'id': AttrSpec(required: true),
  },
  inline: false,           // whether this is an inline node
  atom: false,             // whether this is an atom (leaf, no editable content)
  selectable: true,        // whether NodeSelection can target this
  draggable: false,        // hint for UI (no engine behavior)
  isolating: false,        // hint for UI (no engine behavior)
  defining: false,         // hint: whether to preserve type on Enter
)
```

Computed: `isLeaf` (content expression is empty), `hasInlineContent` (content contains "inline" or "text").

### MarkSpec

```dart
MarkSpec(
  name: 'link',
  attrs: {'href': AttrSpec(required: true)},
  inclusive: false,        // new text at mark boundary doesn't get this mark
  excludes: '',            // space-separated mark types this excludes ('_' = all)
  group: '',               // group membership
  spanning: true,          // whether mark can span across nodes
)
```

### Content expressions

ProseMirror-compatible grammar:

| Expression | Meaning |
| ----------- | --------- |
| `block+` | One or more nodes in the "block" group |
| `inline*` | Zero or more nodes in the "inline" group |
| `paragraph` | Exactly one paragraph node |
| `(paragraph \| heading)+` | One or more paragraphs or headings |
| `heading paragraph+` | One heading followed by one or more paragraphs |
| `block?` | Zero or one block |
| (empty string) | Leaf node (no children allowed) |

Group names reference NodeSpec `group` fields. Node names reference specific types.

### Built-in schemas

```dart
// Basic: doc, paragraph, heading, image, horizontal_rule, hard_break, text
//        bold, italic, link
basicSchema

// Rich: everything in basic + blockquote, bullet_list, ordered_list,
//       check_list, list_item, check_item, code_block, table, table_row,
//       table_cell, callout, embed, inline_widget
//       + underline, strikethrough, code, superscript, subscript,
//         color, highlight, font_family, font_size
richSchema
```

---

## Transforms

### Steps

Eight step types, each atomic and invertible:

| Step | Purpose | StepMap effect |
| ------ | --------- | --------------- |
| `ReplaceStep(from, to, slice)` | Insert, delete, or replace content | Adjusts positions around replaced range |
| `AddMarkStep(from, to, mark)` | Apply formatting to a range | Identity (no position change) |
| `RemoveMarkStep(from, to, mark)` | Remove formatting from a range | Identity |
| `SetAttrStep(pos, key, value)` | Change a node attribute | Identity |
| `SplitStep(pos, depth, ...)` | Split block at position | Adds 2*depth positions |
| `JoinStep(pos, depth)` | Merge two adjacent blocks | Removes 2*depth positions |
| `WrapStep(from, to, type, ...)` | Wrap blocks in a container | Adds 2 positions |
| `UnwrapStep(pos, wrapperNodeSize)` | Remove container, promote children | Removes 2 positions |

Every step:

- `apply(doc)` returns `StepResult.ok(newDoc)` or `StepResult.fail(error)`
- `invert(doc)` returns the inverse step (for undo)
- `getMap()` returns a `StepMap` for position mapping
- `toJson()` / `Step.fromJson(json)` for serialization
- `merge(other)` attempts to merge with another step (returns null if not mergeable)

Inverse pairs: Split ↔ Join, Wrap ↔ Unwrap, AddMark ↔ RemoveMark, Replace ↔ Replace(inverse slice).

```dart
// Direct step usage (rare — prefer Transaction methods)
final step = ReplaceStep.insert(5, Slice(Fragment.from(TextNode('hi')), 0, 0));
final result = step.apply(doc);
if (result.isOk) {
  final newDoc = result.doc!;
  final undoStep = step.invert(doc);
}
```

### StepMap and Mapping

`StepMap` maps positions through a single edit. `Mapping` chains multiple maps.

```dart
// StepMap: flat triples [pos, oldSize, newSize, ...]
final map = StepMap.simple(5, 0, 3);  // insertion of 3 chars at pos 5
map.map(3);                           // 3 (before insertion, unchanged)
map.map(5, assoc: -1);               // 5 (at insertion, stay left)
map.map(5, assoc: 1);                // 8 (at insertion, stay right)
map.map(7);                           // 10 (after insertion, shifted by 3)
map.mapOrNull(5);                     // null for deleted positions
map.inverse;                          // inverted map

// Mapping: chain of StepMaps
final mapping = Mapping.from([map1, map2, map3]);
mapping.map(pos);
mapping.mapOrNull(pos);
mapping.inverse;
mapping.composed;                     // single composed StepMap

// Compose two maps
final combined = map1.compose(map2);
```

**Assoc parameter** controls behavior at edit boundaries:

- `assoc: 1` (default) — map to the right of insertions
- `assoc: -1` — map to the left of insertions
- `assoc: 0` — closest side

### Transaction

Groups multiple steps into a single atomic operation. All methods return `this` for fluent chaining.

```dart
final tr = state.transaction;  // or Transaction(doc)

// Text operations
tr.insertText(pos, 'hello', marks: [Mark.bold]);
tr.deleteRange(from, to);
tr.replaceText(from, to, 'new text');
tr.replace(from, to, slice);

// Mark operations
tr.addMark(from, to, Mark.bold);
tr.removeMark(from, to, Mark.bold);

// Attribute operations
tr.setNodeAttr(pos, 'level', 2);

// Structure operations
tr.split(pos);
tr.split(pos, typeAfter: 'paragraph');
tr.split(pos, depth: 2, attrsAfter: {'level': 1});
tr.join(pos);
tr.join(pos, depth: 2);
tr.wrap(from, to, 'blockquote');
tr.wrap(from, to, 'bullet_list', wrapperAttrs: {'tight': true});
tr.unwrap(pos, wrapperNodeSize: size);

// Block operations (convenience)
tr.setBlockType(pos, 'heading', attrs: {'level': 2});
tr.deleteBlock(pos);
tr.insertBlockAfter(pos, newBlock);
tr.insertBlockBefore(pos, newBlock);

// Selection
tr.setSelection(TextSelection.collapsed(10));
tr.setCursor(10);                // shorthand for collapsed TextSelection
tr.ensureVisible();              // hint to scroll cursor into view

// Metadata
tr.setMeta('addToHistory', false);
tr.setMeta('myPlugin', someData);
tr.getMeta('myPlugin');
tr.addToHistory;                 // bool, defaults to true

// Inspect
tr.docBefore;                    // document before any steps
tr.doc;                          // document after all steps
tr.steps;                        // List<Step>
tr.maps;                         // List<StepMap>
tr.mapping;                      // Mapping (composed)
tr.hasSteps;                     // bool
```

**Important:** Steps in a transaction are applied immediately and sequentially. Positions used in later calls must account for earlier steps. The transaction maps its selection through each step automatically, but positions you pass to methods are against the *current* (post-previous-steps) document.

---

## State

### EditorState

Immutable snapshot of the entire editor state.

```dart
// Create
final state = EditorState.create(
  schema: schema,
  doc: doc,                              // optional, defaults to minimal doc
  selection: TextSelection.collapsed(0), // optional
  plugins: [HistoryPlugin(), MarkerPlugin(), DecorationPlugin()],
);

// Read
state.doc;                // DocNode
state.selection;          // Selection
state.schema;             // Schema
state.plugins;            // List<Plugin>
state.pluginStates;       // Map<String, Object?>
state.textContent;        // all text concatenated
state.blockCount;         // number of top-level blocks

// Access plugin state
final history = state.pluginState<HistoryState>('history');
final markers = state.pluginState<MarkerCollection>('markers');
final decorations = state.pluginState<DecorationSet>('decorations');

// Edit (always returns a new state)
final tr = state.transaction;
// ... add steps ...
final newState = state.apply(tr);
```

`apply(tr)`:

1. Updates the document from `tr.doc`
2. Maps the selection through `tr.mapping` (or uses `tr.selection` if explicitly set)
3. Runs each plugin's `apply(tr, pluginState)` to update plugin states
4. Returns a new `EditorState`

### Selections

Four selection types, all immutable:

```dart
// Text cursor / range (most common)
TextSelection.collapsed(5);             // cursor at position 5
TextSelection(anchor: 3, head: 10);     // forward selection 3→10
TextSelection(anchor: 10, head: 3);     // backward selection 10→3
TextSelection.range(anchor: 3, head: 10);

// Node selection (images, dividers, embeds)
NodeSelection(pos);                     // selects the node at pos
NodeSelection(pos, 5);                  // with explicit nodeSize

// Multi-cursor
MultiCursorSelection([
  TextSelection.collapsed(5),
  TextSelection.collapsed(20),
  TextSelection(anchor: 30, head: 35),
]);

// Select all
AllSelection(doc.contentSize);
```

Common properties:

```dart
sel.anchor;   // fixed end
sel.head;     // moving end (cursor)
sel.from;     // min(anchor, head)
sel.to;       // max(anchor, head)
sel.empty;    // from == to
```

Mapping:

```dart
sel.map(stepMap);           // map through one step
sel.mapThrough(mapping);    // map through a chain of steps
```

**Mapping behavior for TextSelection:**

- Collapsed: both endpoints use `assoc: 1` (move right on insertion at cursor)
- Forward range (`anchor <= head`): anchor maps `assoc: 1`, head maps `assoc: -1`
- Backward range (`anchor > head`): anchor maps `assoc: -1`, head maps `assoc: 1`

This means the selected range stays tight around the original content when insertions happen at its boundaries.

### Plugins

Extend editor state with custom data that persists across transactions.

```dart
class WordCountPlugin extends Plugin {
  @override
  String get key => 'wordCount';

  @override
  Object init(DocNode doc, Selection selection) {
    return doc.textContent.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  @override
  Object apply(Transaction tr, Object? state, {Selection? selectionBefore}) {
    if (!tr.hasSteps) return state!;
    return tr.doc.textContent.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
}

// Use it
final state = EditorState.create(
  schema: schema,
  doc: doc,
  plugins: [WordCountPlugin()],
);
final count = state.pluginState<int>('wordCount'); // e.g., 42
```

**Built-in plugins:** `HistoryPlugin`, `CollabPlugin`, `MarkerPlugin`, `DecorationPlugin`, `AwarenessPlugin`

### History (undo/redo)

```dart
final state = EditorState.create(
  schema: schema,
  doc: doc,
  plugins: [HistoryPlugin(maxDepth: 200)],
);

// Edit
final newState = state.apply(state.transaction..insertText(0, 'Hi'));

// Undo / redo (top-level functions)
final undone = undo(newState);       // EditorState? (null if nothing to undo)
final redone = redo(undone!);        // EditorState? (null if nothing to redo)

// Check availability
final history = newState.pluginState<HistoryState>('history')!;
history.canUndo;   // bool
history.canRedo;   // bool
```

**How it works:**

- Each transaction with `addToHistory: true` (default) creates a `HistoryEntry`
- Inverse steps are pre-computed at apply time against the correct intermediate documents
- When you undo then make a new edit, the redo stack is saved as a branch (accessible via `history.branches`)
- `tr.setMeta('addToHistory', false)` skips history (use for programmatic/remote changes)
- `maxDepth` caps the undo stack size

### Decorations

Ephemeral visual annotations that don't modify the document. They track through edits.

```dart
// Types
InlineDecoration(from, to, {'class': 'highlight'});         // range annotation
InlineDecoration(from, to, {'class': 'search'}, DecorationSpec(type: 'search'));
NodeDecoration(pos, {'class': 'selected'});                  // annotate entire node
WidgetDecoration(pos, side: false, attrs: {'type': 'gutter'}); // widget at position
  // side: false = before position, side: true = after position

// DecorationSet
final decs = DecorationSet.empty
  .add(InlineDecoration(5, 10, {'class': 'highlight'}))
  .add(NodeDecoration(0, {'class': 'selected'}));

decs.find();                        // all decorations
decs.find(from: 3, to: 8);         // decorations overlapping range
decs.find(type: 'search');          // by DecorationSpec type
decs.findInline(3, 8);             // InlineDecorations in range
decs.findNode(0);                  // NodeDecorations at pos
decs.findWidget(5);                // WidgetDecorations at pos
decs.remove(decoration);           // returns new set
decs.map(mapping);                 // maps all decorations through edits

// Via plugin
final state = EditorState.create(
  schema: schema, doc: doc,
  plugins: [DecorationPlugin()],
);
// Decorations map through edits automatically via the plugin
```

**Decorations vs Markers:**

- **Decorations** = ephemeral, view-layer only, not persisted, no boundary behavior
- **Markers** = persistent tracked ranges with boundary behaviors, persisted, queryable

---

## Markers

Persistent tracked ranges that survive edits. Use for comments, highlights, diagnostics, bookmarks.

```dart
final marker = Marker(
  id: 'comment-1',
  from: 5,
  to: 25,
  type: 'comment',
  attrs: {'author': 'alice', 'text': 'Needs revision'},
  behavior: MarkerBehavior.exclusive,
);
```

### Marker behaviors

Controls what happens when text is inserted at marker boundaries:

| Behavior | Insert at `from` | Insert at `to` |
| ---------- | ------------------ | ---------------- |
| `exclusive` (default) | Marker stays right (doesn't expand) | Marker stays left (doesn't expand) |
| `startInclusive` | Marker expands left | Marker stays left |
| `endInclusive` | Marker stays right | Marker expands right |
| `inclusive` | Marker expands left | Marker expands right |

```dart
// Comment: exclusive (text typed at edges is NOT part of the comment)
Marker(id: 'c1', from: 5, to: 15, type: 'comment', behavior: MarkerBehavior.exclusive)

// Highlight: inclusive (text typed inside extends the highlight)
Marker(id: 'h1', from: 5, to: 15, type: 'highlight', behavior: MarkerBehavior.inclusive)
```

If a marker's range collapses to zero (all its content deleted), `mapThrough` returns `null` (marker is removed).

### MarkerCollection

```dart
final markers = MarkerCollection([marker1, marker2, marker3]);
// or MarkerCollection.empty

markers.findOverlapping(5, 20);    // List<Marker> overlapping this range
markers.findAt(10);                // List<Marker> containing this point
markers.findByType('comment');     // List<Marker> of this type
markers.findById('comment-1');     // Marker?

markers.add(newMarker);           // returns new collection
markers.remove('comment-1');      // returns new collection
markers.update('comment-1', (m) => m.copyWith(attrs: {...}));

markers.mapThrough(mapping);     // map all markers through edits (removes collapsed)
markers.toJson();
MarkerCollection.fromJson(json);
```

### IntervalTree

The backing data structure for `MarkerCollection`. Sorted-list-based with a prefix-max array for O(log n + k) range queries.

```dart
final tree = IntervalTree<String>([
  IntervalEntry(id: 'a', from: 0, to: 10, data: 'first'),
  IntervalEntry(id: 'b', from: 5, to: 20, data: 'second'),
]);

tree.query(3, 8);       // entries overlapping [3, 8)
tree.queryPoint(5);      // entries containing point 5
tree.add(entry);         // new tree with entry added
tree.remove('a');        // new tree without entry 'a'
tree.length;
tree.isEmpty;
tree.entries;
```

### MarkerPlugin

Manages markers in `EditorState` via transaction metadata.

```dart
final state = EditorState.create(
  schema: schema, doc: doc,
  plugins: [MarkerPlugin()],
);

// Add marker
final tr = state.transaction
  ..setMeta('addMarker', Marker(id: 'c1', from: 5, to: 15, type: 'comment'));
final s2 = state.apply(tr);

// Remove marker
final tr2 = s2.transaction..setMeta('removeMarker', 'c1');
final s3 = s2.apply(tr2);

// Update marker attributes
final tr3 = state.transaction
  ..setMeta('updateMarker', {'id': 'c1', 'attrs': {'resolved': true}});

// Query
final markers = s2.pluginState<MarkerCollection>('markers')!;
markers.findOverlapping(0, 20);
```

Markers are automatically mapped through any steps in the transaction.

---

## Serialization

All four serializers have the same pattern:

```dart
final serializer = XxxSerializer(schema: schema); // schema is optional
final output = serializer.serialize(doc);
final restored = serializer.deserialize(input);
```

Passing a schema enables accurate node flag reconstruction (`isLeaf`, `inlineContent`, `isAtom`). Without a schema, the serializer infers flags from content (may be incorrect for empty nodes).

### JSON

Canonical lossless format. Mirrors ProseMirror's JSON structure.

```dart
final json = JsonSerializer(schema: schema);

final data = json.serialize(doc);
// {
//   "type": "doc",
//   "content": [
//     {"type": "paragraph", "content": [
//       {"type": "text", "text": "Hello "},
//       {"type": "text", "text": "world", "marks": [{"type": "bold"}]}
//     ]}
//   ]
// }

final doc = json.deserialize(data);

// Individual nodes
json.serializeNode(node);
json.serializeFragment(fragment);
json.deserializeNode(json);
```

### HTML

```dart
final html = HtmlSerializer(schema: schema);

final str = html.serialize(doc);
// <p>Hello <strong>world</strong></p>

final doc = html.deserialize('<p>Hello <strong>world</strong></p>');

// Mark → tag mapping:
// bold → <strong>, italic → <em>, underline → <u>,
// strikethrough → <s>, code → <code>, superscript → <sup>,
// subscript → <sub>, link → <a href="...">,
// color → <span style="color:...">,
// highlight → <span style="background-color:...">

// Block → tag mapping:
// paragraph → <p>, heading → <h1>-<h6>, blockquote → <blockquote>,
// code_block → <pre><code>, bullet_list → <ul>, ordered_list → <ol>,
// check_list → <ul class="checklist">, list_item → <li>,
// check_item → <li data-checked="true">,
// image → <img>, horizontal_rule → <hr>,
// table → <table>, table_row → <tr>, table_cell → <td>,
// callout → <div class="callout">, embed → <div data-embed-type="...">

// Special handling:
// - HTML entities decoded correctly (&amp; &lt; &gt; &quot; &#xNNNN;)
// - Inline styles parsed (color, background-color, font-family, font-size)
// - <div> with block children → BlockNode(type: 'div')
// - data-* attributes preserved
```

### Markdown

GitHub-Flavored Markdown (GFM) support.

```dart
final md = MarkdownSerializer(schema: schema);

final str = md.serialize(doc);
final doc = md.deserialize('# Title\n\nSome **bold** text.');
```

**Serialize support:**

| Block type | Markdown output |
| ----------- | ---------------- |
| paragraph | plain text + blank line |
| heading (1–6) | `#` through `######` |
| blockquote | `>` prefix |
| code_block | fenced with ```` ``` ```` and language hint |
| bullet_list/list_item | `-` prefix |
| ordered_list/list_item | `1.` prefix |
| check_list/check_item | `- [ ]` / `- [x]` |
| image | `![alt](src "title")` |
| horizontal_rule | `---` |
| hard_break | trailing two spaces + newline |
| inline_widget | `<!-- widget:type {"attrs":"..."} -->` |

| Mark | Markdown output |
| ------ | ---------------- |
| bold | `**text**` |
| italic | `*text*` |
| strikethrough | `~~text~~` |
| code | `` `text` `` |
| link | `[text](href "title")` |
| other marks | silently dropped |

**Deserialize support:**
Headings, bold, italic, strikethrough, inline code, links, images, bullet lists, ordered lists, checklists, blockquotes, fenced code blocks, indented code blocks, horizontal rules, inline widgets from HTML comments.

### Quill Delta

Flat operation list compatible with the Quill.js ecosystem.

```dart
final delta = DeltaSerializer(schema: schema);

final ops = delta.serialize(doc);
// [
//   {"insert": "Hello "},
//   {"insert": "world", "attributes": {"bold": true}},
//   {"insert": "\n"}
// ]

final doc = delta.deserialize([
  {'insert': 'Hello '},
  {'insert': 'bold', 'attributes': {'bold': true}},
  {'insert': '\n', 'attributes': {'header': 2}},
]);
```

**Mapping rules:**

- Text + marks → `{"insert": "text", "attributes": {...}}`
- Block-level attrs → attributes on trailing `\n`: `{"insert": "\n", "attributes": {"header": 1}}`
- Image → `{"insert": {"image": "url"}}`
- Divider → `{"insert": {"divider": true}}`
- Inline widget → `{"insert": {"inline_widget": type, ...attrs}}`
- Checklist → `"attributes": {"list": "checked"}` or `{"list": "unchecked"}`

**Limitations:** Tables, nested blockquotes, and deeply nested structures lose their nesting when serialized to Delta format (Delta is inherently flat).

---

## Collaborative editing

Full OT (Operational Transformation) system with central authority and client-side rebasing.

### Authority (server)

```dart
final authority = Authority(doc: initialDoc);

authority.doc;       // current canonical document
authority.version;   // number of accepted steps

// Client sends steps tagged with its version
final result = authority.receiveSteps(clientVersion, steps, clientId);
// result: ({int version, List<Step> steps})? — null if rejected

// Catch-up: get steps a client missed
final missed = authority.stepsSince(clientVersion);
// List<AuthorityStep> (step + clientId)
```

**How it works:**

- If `clientVersion == authority.version`, steps are applied directly
- If `clientVersion < authority.version`, the authority replays the document to the client's version, transforms the steps over intervening edits, and applies
- If `clientVersion > authority.version`, rejects (shouldn't happen)
- Returns null if steps fail to apply after transformation

### CollabPlugin (client)

```dart
final state = EditorState.create(
  schema: schema,
  doc: doc,
  plugins: [CollabPlugin(clientId: 'alice', version: 0)],
);

// 1. User makes local edits (normal transactions)
final s2 = state.apply(state.transaction..insertText(1, 'Hi'));

// 2. Extract steps to send to server
final sendable = sendableSteps(s2);
// ({int version, List<Step> steps, String clientId})?

// 3. Server responds with confirmed steps from all clients
// Apply them to local state:
final s3 = receiveSteps(s2, serverVersion, serverSteps, clientIds);
// EditorState? (null on error)

// Access collab state
final collab = s3!.pluginState<CollabState>('collab')!;
collab.version;            // confirmed server version
collab.unconfirmedSteps;   // steps not yet confirmed
collab.hasPending;         // has unconfirmed steps
```

**Protocol:**

1. Local edits accumulate as unconfirmed steps in `CollabState`
2. `sendableSteps()` extracts them with the current version
3. Send to server; server calls `authority.receiveSteps()`
4. Server broadcasts accepted steps to all clients
5. `receiveSteps()` on client: confirms own steps, applies others' steps, rebases unconfirmed local steps via OT

**Metadata keys used by CollabPlugin:**

- `'local'` — mark transaction as local (steps become unconfirmed)
- `'receive'` — mark transaction as remote (don't add to unconfirmed)
- `'confirm'` + `'confirmVersion'` + `'confirmCount'` — confirm N steps
- `'rebase'` + `'rebaseVersion'` + `'rebaseSteps'` + `'rebaseMaps'` — set rebased steps

### Step transformation (OT)

```dart
// Transform one step over another
final transformed = transformStep(stepA, stepB, doc);
// Step? (null if conflict, e.g., overlapping structural changes)

// Transform a list of steps over another list
final transformedList = transformSteps(stepsA, stepsB, doc);
// List<Step> (conflicts silently dropped)
```

All 64 combinations (8 step types x 8 step types) are handled. Replace over Replace with overlapping ranges gives priority to `stepB`. Conflicting structural changes (e.g., both clients try to join the same blocks) drop the conflicting step.

### Awareness

Remote cursor positions and presence state.

```dart
final state = EditorState.create(
  schema: schema, doc: doc,
  plugins: [
    AwarenessPlugin(localUser: AwarenessUser(
      clientId: 'alice', name: 'Alice', color: '#ff0000',
    )),
  ],
);

// Access awareness state
final awareness = state.pluginState<AwarenessState>('awareness')!;
awareness.localUser;       // AwarenessUser?
awareness.localCursor;     // AwarenessCursor?
awareness.peers;           // Map<String, AwarenessPeer>

// Update from remote peer (via transaction metadata)
final tr = state.transaction
  ..setMeta('awarenessUpdate', {
    'clientId': 'bob',
    'user': AwarenessUser(clientId: 'bob', name: 'Bob', color: '#0000ff').toJson(),
    'cursor': AwarenessCursor(anchor: 5, head: 10).toJson(),
  });

// Remove a peer
final tr2 = state.transaction..setMeta('awarenessRemove', 'bob');
```

**What maps through edits:** Peer cursors are mapped through transaction steps automatically. When edits shift positions, remote cursors stay at the correct locations.

```dart
// AwarenessUser
AwarenessUser(clientId: 'alice', name: 'Alice', color: '#ff0000', avatarUrl: '...');

// AwarenessCursor
AwarenessCursor(anchor: 5, head: 10);
AwarenessCursor.collapsed(5);
cursor.isCollapsed;
cursor.from;  // min
cursor.to;    // max
cursor.mapThrough(mapping);  // AwarenessCursor? (null if deleted)

// AwarenessPeer
AwarenessPeer(user: user, cursor: cursor);

// AwarenessState
state.withPeer('bob', peer);
state.withoutPeer('bob');
state.withLocalCursor(cursor);
state.mapThrough(mapping);
```

### CRDT bridge

Abstract interfaces for integrating with CRDT libraries (Yjs, Automerge, Loro). No concrete implementation — that lives in separate packages.

```dart
// Implement these for your CRDT library:

abstract class CrdtBridge {
  List<CrdtOp> transactionToCrdtOps(Transaction tr, EditorState stateBefore);
  Transaction? crdtOpsToTransaction(List<CrdtOp> ops, EditorState currentState);
  Map<String, dynamic> get snapshot;
  void loadSnapshot(Map<String, dynamic> snapshot);
}

abstract class CrdtAwarenessBridge {
  Map<String, dynamic> encodeLocalAwareness(AwarenessState state);
  AwarenessPeer decodeRemoteAwareness(Map<String, dynamic> data);
  void onPeerDisconnect(String clientId);
}

abstract class CrdtOp {
  Map<String, dynamic> toJson();
}
```

---

## PieceTable buffer

Per-block text buffer with O(log n) insert/delete. Adaptive: uses simple string concatenation for small content (< 256 chars, < 8 edits), promotes to a red-black tree indexed piece table when complexity grows.

```dart
final buf = PieceTable('Hello world');

buf.length;                          // 11
buf.getText();                       // "Hello world"
buf.charAt(0);                       // "H"
buf.getTextInRange(0, 5);           // "Hello"

buf.insert(5, ' beautiful');         // mutates in-place
buf.delete(0, 6);                    // mutates in-place
buf.replace(0, 5, 'Goodbye');       // delete + insert

buf.lineCount;                       // number of \n + 1
buf.lineAt(5);                       // line number containing offset 5
buf.lineStart(1);                    // offset of line 1 start

// Snapshot/restore (for undo)
final snap = buf.snapshot();
buf.insert(0, 'X');
buf.restore(snap);                   // back to state at snapshot
```

**Note:** PieceTable is a standalone utility. The document model (Node/Fragment/TextNode) does NOT use PieceTable internally — it uses immutable strings. PieceTable is available for UI layers that want mutable per-block text buffers for IME composition or large text blocks.

---

## Do's and don'ts

### Do

- **Always edit through transactions.** Never try to mutate a Node directly.

  ```dart
  // Correct
  final tr = state.transaction..insertText(5, 'hi');
  final newState = state.apply(tr);
  ```

- **Pass a schema to serializers** when deserializing, so node flags (`isLeaf`, `inlineContent`, `isAtom`) are set correctly.

  ```dart
  final doc = JsonSerializer(schema: schema).deserialize(json);
  ```

- **Use `addToHistory: false`** for programmatic or remote changes that shouldn't be undoable.

  ```dart
  tr.setMeta('addToHistory', false);
  ```

- **Check `StepResult.isOk`** when using steps directly (transactions throw on failure).

- **Use `mapThrough`** to track positions across multiple edits.

  ```dart
  final newPos = mapping.map(oldPos, assoc: 1);
  ```

- **Use the correct marker behavior** for your use case. Comments should be `exclusive`, highlights should be `inclusive`.

- **Serialize to JSON** for storage. It's the only lossless format.

### Don't

- **Don't use positions from before a transaction** after applying steps. All positions shift.

  ```dart
  // WRONG — pos 5 may have shifted after deleteRange
  tr.deleteRange(0, 3);
  tr.insertText(5, 'oops');  // position 5 is now wrong

  // RIGHT — account for the shift
  tr.deleteRange(0, 3);
  tr.insertText(2, 'correct');  // 5 - 3 = 2
  ```

- **Don't rely on Markdown or Delta for lossless storage.** Both lose information:

  - Markdown drops marks it doesn't know (color, highlight, font)
  - Delta flattens nested structures (tables, nested blockquotes)
  - HTML drops InlineWidgetNode details without custom rendering

- **Don't create BlockNode with wrong flags.** A paragraph needs `inlineContent: true`. An image needs `isLeaf: true, isAtom: true`. Wrong flags cause position calculation errors.

- **Don't use `PieceTable` as a replacement for the document model.** It's an optional buffer for text editing UI, not a document representation.

- **Don't share `Transaction` instances across threads.** Transactions are mutable during construction. Create, populate, apply, and discard.

- **Don't assume `undo()` always succeeds.** It returns `null` when there's nothing to undo.

- **Don't forget that `NodeSelection.empty` is always `false`.** A node selection always spans a node.

- **Don't use `receiveSteps` without matching `clientIds` length.** The clientIds list must have the same length as the steps list.

---

## Known limitations

1. **No text-level diffing.** `ReplaceStep` works at the content/slice level. There's no built-in character-by-character diff algorithm. A UI layer would need to diff old and new text to produce minimal `ReplaceStep`s.

2. **No input rules / auto-formatting.** Markdown shortcuts (`#` → heading, `**text**` → bold) are not built in. The engine provides the primitives (`split`, `setBlockType`, `addMark`); the UI layer implements the pattern matching.

3. **No key bindings or commands.** This is a pure logic engine. Keyboard handling, command dispatch, and shortcut registration are UI-layer concerns.

4. **Schema validation is structural only.** It checks which node types can nest where and which marks are allowed. It does not validate attribute values (e.g., heading level must be 1–6).

5. **No table-specific operations.** There are no built-in steps for "add row", "merge cells", etc. Tables are just nested nodes; structure operations (replace, split, join, wrap) can manipulate them, but high-level table commands must be built on top.

6. **Delta serializer loses nesting.** Quill Delta is a flat format. Tables, nested blockquotes, and nested lists cannot round-trip losslessly through Delta.

7. **Markdown serializer drops unknown marks.** Marks without a Markdown equivalent (color, highlight, font-family, font-size) are silently dropped during serialization.

8. **No collaborative transport.** The engine provides the OT math (Authority, step transformation, rebasing). Network transport (WebSocket, HTTP, etc.) must be implemented separately.

9. **No CRDT implementation.** `CrdtBridge` is an abstract interface only. A concrete Yjs/Automerge/Loro binding must be implemented in a separate package.

10. **PieceTable is standalone.** The immutable document model (Node/Fragment) does not use PieceTable internally. PieceTable is an optional utility for mutable text editing scenarios.

11. **No concurrent transaction safety.** Two transactions created from the same state cannot be applied sequentially without rebasing. The second transaction's positions are invalid after the first is applied.

12. **History doesn't group by time.** Each transaction is one undo entry. Grouping consecutive keystrokes into a single undo entry must be done at the UI layer (by batching characters into a single transaction before applying).

---

## Tests

383 tests covering all modules. 0 failures.

```bash
dart test
```

| Test file | Tests | What it covers |
| ----------- | ------- | --------------- |
| `model_test.dart` | 41 | Node, Fragment, Mark, ResolvedPos, Slice |
| `schema_test.dart` | 14 | Schema validation, content expressions, mark exclusion |
| `transform_test.dart` | 55 | StepMap, Mapping, ReplaceStep, AddMarkStep, RemoveMarkStep, SetAttrStep, Transaction, Step.fromJson |
| `structure_test.dart` | 96 | SplitStep, JoinStep, WrapStep, UnwrapStep, round-trips, position mapping, Transaction convenience methods |
| `state_test.dart` | 54 | Selection types, EditorState, History (undo/redo), Decorations |
| `markers_test.dart` | 62 | IntervalTree, Marker behaviors, MarkerCollection, MarkerPlugin |
| `serialization_test.dart` | 40 | JSON, HTML, Markdown round-trips, edge cases |
| `delta_serializer_test.dart` | 57 | Delta serialize, deserialize, round-trip |
| `collab_test.dart` | 16 | CollabPlugin, Authority, step transformation, multi-client |
| `awareness_test.dart` | 31 | AwarenessCursor, AwarenessUser, AwarenessPeer, AwarenessState, AwarenessPlugin |
| `crdt_bridge_test.dart` | 11 | CrdtOp, CrdtBridge, CrdtAwarenessBridge (mock implementations) |
| `buffer_test.dart` | 17 | PieceTable insert/delete/replace, lines, snapshot/restore |

**Not covered by tests:**

- Performance benchmarks at scale (10K+ nodes, 1K+ markers)
- Unicode edge cases (RTL, combining characters, ZWJ sequences)
- Memory usage and leak detection
- 3+ client collaborative scenarios
- Cross-format round-trips (serialize to Markdown, deserialize as HTML)

---

## Full file map

```text
lib/                                    31 files, ~10,900 lines
  editor_engine.dart                    Barrel export (all public API)
  model/
    node.dart                           Node, TextNode, BlockNode, InlineWidgetNode, DocNode
    fragment.dart                       Fragment (child list with text merging, binary search)
    mark.dart                           Mark, List<Mark> extensions
    resolved_pos.dart                   ResolvedPos (position → tree path)
    slice.dart                          Slice (cut content with open depths)
  schema/
    schema.dart                         Schema, basicSchema, richSchema
    node_spec.dart                      NodeSpec, MarkSpec, AttrSpec
    content_expression.dart             ContentExpression parser
  transform/
    step.dart                           Step (abstract), StepResult
    replace_step.dart                   ReplaceStep
    mark_step.dart                      AddMarkStep, RemoveMarkStep
    attr_step.dart                      SetAttrStep
    structure_step.dart                 SplitStep, JoinStep, WrapStep, UnwrapStep
    step_map.dart                       StepMap, Mapping
    transaction.dart                    Transaction
  state/
    editor_state.dart                   EditorState, Plugin (abstract)
    selection.dart                      Selection, TextSelection, NodeSelection,
                                        MultiCursorSelection, AllSelection
    history.dart                        HistoryPlugin, HistoryState, HistoryEntry,
                                        undo(), redo()
    decoration.dart                     Decoration (sealed), InlineDecoration,
                                        NodeDecoration, WidgetDecoration,
                                        DecorationSpec, DecorationSet, DecorationPlugin
  markers/
    marker.dart                         Marker, MarkerBehavior
    marker_collection.dart              MarkerCollection, MarkerPlugin
    interval_tree.dart                  IntervalTree, IntervalEntry
  serialization/
    json_serializer.dart                JsonSerializer
    html_serializer.dart                HtmlSerializer
    markdown_serializer.dart            MarkdownSerializer
    delta_serializer.dart               DeltaSerializer
  collab/
    collab.dart                         Authority, AuthorityStep, CollabPlugin,
                                        CollabState, sendableSteps(), receiveSteps(),
                                        transformStep(), transformSteps()
    awareness.dart                      AwarenessPlugin, AwarenessState,
                                        AwarenessUser, AwarenessCursor, AwarenessPeer
    crdt_bridge.dart                    CrdtBridge, CrdtOp, CrdtAwarenessBridge
  buffer/
    piece_table.dart                    PieceTable, PieceTableSnapshot

test/                                   13 files, ~4,350 lines
  helpers.dart                          Test document builders
  model_test.dart                       41 tests
  schema_test.dart                      14 tests
  transform_test.dart                   55 tests
  structure_test.dart                   96 tests
  state_test.dart                       54 tests
  markers_test.dart                     62 tests
  serialization_test.dart               40 tests
  delta_serializer_test.dart            57 tests
  collab_test.dart                      16 tests
  awareness_test.dart                   31 tests
  crdt_bridge_test.dart                 11 tests
  buffer_test.dart                      17 tests
```

---

## API reference

### Exports from `package:editor_engine/editor_engine.dart`

**Model:**
`Node`, `TextNode`, `BlockNode`, `InlineWidgetNode`, `DocNode`, `Fragment`, `Mark`, `Slice`, `ResolvedPos`

**Schema:**
`Schema`, `NodeSpec`, `MarkSpec`, `AttrSpec`, `ContentExpression`, `basicSchema`, `richSchema`

**Buffer:**
`PieceTable`, `PieceTableSnapshot`

**Transform:**
`Step`, `StepResult`, `ReplaceStep`, `AddMarkStep`, `RemoveMarkStep`, `SetAttrStep`, `SplitStep`, `JoinStep`, `WrapStep`, `UnwrapStep`, `StepMap`, `Mapping`, `Transaction`

**State:**
`EditorState`, `Plugin`, `Selection`, `TextSelection`, `NodeSelection`, `MultiCursorSelection`, `AllSelection`, `HistoryPlugin`, `HistoryState`, `HistoryEntry`, `undo()`, `redo()`, `Decoration`, `InlineDecoration`, `NodeDecoration`, `WidgetDecoration`, `DecorationSpec`, `DecorationSet`, `DecorationPlugin`

**Markers:**
`Marker`, `MarkerBehavior`, `MarkerCollection`, `MarkerPlugin`, `IntervalTree`, `IntervalEntry`

**Serialization:**
`JsonSerializer`, `HtmlSerializer`, `MarkdownSerializer`, `DeltaSerializer`

**Collab:**
`Authority`, `AuthorityStep`, `CollabPlugin`, `CollabState`, `sendableSteps()`, `receiveSteps()`, `transformStep()`, `transformSteps()`, `AwarenessPlugin`, `AwarenessState`, `AwarenessUser`, `AwarenessCursor`, `AwarenessPeer`, `CrdtBridge`, `CrdtOp`, `CrdtAwarenessBridge`
