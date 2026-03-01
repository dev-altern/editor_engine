import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  group('Selection', () {
    test('TextSelection collapsed', () {
      final sel = TextSelection.collapsed(5);
      expect(sel.anchor, 5);
      expect(sel.head, 5);
      expect(sel.empty, true);
      expect(sel.from, 5);
      expect(sel.to, 5);
    });

    test('TextSelection range', () {
      final sel = TextSelection.range(anchor: 2, head: 8);
      expect(sel.empty, false);
      expect(sel.from, 2);
      expect(sel.to, 8);
    });

    test('TextSelection backward range', () {
      final sel = TextSelection.range(anchor: 8, head: 2);
      expect(sel.from, 2);
      expect(sel.to, 8);
    });

    test('TextSelection maps through StepMap', () {
      final sel = TextSelection.collapsed(5);
      final map = StepMap.simple(3, 0, 2);
      final mapped = sel.map(map);
      expect(mapped.anchor, 7);
    });

    test('NodeSelection with size', () {
      final sel = NodeSelection(5, 7);
      expect(sel.anchor, 5);
      expect(sel.head, 12);
      expect(sel.nodeSize, 7);
      expect(sel.empty, false);
    });

    test('NodeSelection defaults to size 1', () {
      final sel = NodeSelection(5);
      expect(sel.head, 6);
      expect(sel.nodeSize, 1);
    });

    test('MultiCursorSelection', () {
      final sel = MultiCursorSelection([
        TextSelection.collapsed(1),
        TextSelection.collapsed(5),
      ]);
      expect(sel.ranges.length, 2);
      expect(sel.primary.anchor, 5);
      expect(sel.anchor, 5);
    });

    test('AllSelection', () {
      final sel = AllSelection(20);
      expect(sel.anchor, 0);
      expect(sel.head, 20);
      expect(sel.from, 0);
      expect(sel.to, 20);
    });

    test('AllSelection equality', () {
      expect(AllSelection(20), equals(AllSelection(20)));
      expect(AllSelection(20), isNot(equals(AllSelection(30))));
    });

    test('mapThrough maps through Mapping', () {
      final sel = TextSelection.collapsed(5);
      final mapping = Mapping()
        ..appendMap(StepMap.simple(0, 0, 3))
        ..appendMap(StepMap.simple(3, 0, 2));
      final mapped = sel.mapThrough(mapping);
      expect(mapped.anchor, 10);
    });

    test('Selection.fromJson round-trips', () {
      final text = TextSelection.range(anchor: 2, head: 8);
      expect(Selection.fromJson(text.toJson()), equals(text));

      final node = NodeSelection(5, 3);
      expect(Selection.fromJson(node.toJson()), equals(node));

      final all = AllSelection(20);
      expect(Selection.fromJson(all.toJson()), equals(all));
    });
  });

  group('EditorState', () {
    test('create with defaults', () {
      final state = EditorState.create(schema: basicSchema);
      expect(state.doc.content.childCount, 1);
      expect(state.selection, isA<TextSelection>());
    });

    test('apply transaction updates doc', () {
      final state = EditorState.create(schema: basicSchema);
      final tr = state.transaction..insertText(1, 'Hello');
      final newState = state.apply(tr);
      expect(newState.textContent, 'Hello');
    });

    test('apply updates selection', () {
      final state = EditorState.create(schema: basicSchema);
      final tr = state.transaction
        ..insertText(1, 'Hello')
        ..setSelection(TextSelection.collapsed(6));
      final newState = state.apply(tr);
      expect(newState.selection.anchor, 6);
    });

    test('apply maps selection when not explicitly set', () {
      final state = EditorState.create(
        schema: basicSchema,
        selection: TextSelection.collapsed(1),
      );
      final tr = state.transaction..insertText(1, 'XYZ');
      final newState = state.apply(tr);
      expect(newState.selection.anchor, 4);
    });

    test('apply does not mutate transaction', () {
      final state = EditorState.create(schema: basicSchema);
      final tr = state.transaction..insertText(1, 'Hello');

      expect(tr.getMeta('selectionBefore'), isNull);
      state.apply(tr);
      expect(tr.getMeta('selectionBefore'), isNull);
    });

    test('plugin state is maintained', () {
      final state = EditorState.create(
        schema: basicSchema,
        plugins: [HistoryPlugin()],
      );
      expect(state.pluginState<HistoryState>('history'), isNotNull);
    });
  });

  group('History', () {
    EditorState createState() => EditorState.create(
          schema: basicSchema,
          plugins: [HistoryPlugin()],
        );

    test('undo reverts insert', () {
      var state = createState();
      final tr = state.transaction..insertText(1, 'Hello');
      state = state.apply(tr);
      expect(state.textContent, 'Hello');

      final undone = undo(state);
      expect(undone, isNotNull);
      expect(undone!.textContent, '');
    });

    test('redo restores insert', () {
      var state = createState();
      state = state.apply(state.transaction..insertText(1, 'Hello'));

      state = undo(state)!;
      expect(state.textContent, '');

      state = redo(state)!;
      expect(state.textContent, 'Hello');
    });

    test('undo/redo with multiple steps', () {
      var state = createState();
      state = state.apply(state.transaction..insertText(1, 'AB'));
      state = state.apply(state.transaction..insertText(3, 'CD'));
      expect(state.textContent, 'ABCD');

      state = undo(state)!;
      expect(state.textContent, 'AB');

      state = undo(state)!;
      expect(state.textContent, '');

      state = redo(state)!;
      expect(state.textContent, 'AB');
    });

    test('undo returns null when nothing to undo', () {
      final state = createState();
      expect(undo(state), isNull);
    });

    test('redo returns null when nothing to redo', () {
      final state = createState();
      expect(redo(state), isNull);
    });

    test('new edit after undo clears redo stack', () {
      var state = createState();
      state = state.apply(state.transaction..insertText(1, 'AB'));
      state = undo(state)!;

      state = state.apply(state.transaction..insertText(1, 'XY'));
      expect(redo(state), isNull);
    });

    test('addToHistory false skips history', () {
      var state = createState();
      final tr = state.transaction
        ..insertText(1, 'Hello')
        ..setMeta('addToHistory', false);
      state = state.apply(tr);
      expect(state.textContent, 'Hello');
      expect(undo(state), isNull);
    });
  });

  group('Decoration', () {
    test('InlineDecoration stores from/to/attrs', () {
      final d = InlineDecoration(5, 15, {'class': 'highlight'});
      expect(d.from, 5);
      expect(d.to, 15);
      expect(d.attrs['class'], 'highlight');
    });

    test('NodeDecoration stores pos/attrs', () {
      final d = NodeDecoration(0, {'class': 'selected'});
      expect(d.pos, 0);
      expect(d.attrs['class'], 'selected');
    });

    test('WidgetDecoration stores pos/side/attrs', () {
      final d = WidgetDecoration(10, side: true, attrs: {'line': 5});
      expect(d.pos, 10);
      expect(d.side, true);
      expect(d.attrs['line'], 5);
    });

    test('InlineDecoration maps through insertion before range', () {
      final d = InlineDecoration(10, 20, {'class': 'hi'});
      final mapping = Mapping.from([StepMap([5, 0, 3])]);
      final mapped = d.mapThrough(mapping) as InlineDecoration;
      expect(mapped.from, 13);
      expect(mapped.to, 23);
    });

    test('InlineDecoration maps through deletion of entire range', () {
      final d = InlineDecoration(5, 10, {'class': 'hi'});
      final mapping = Mapping.from([StepMap([3, 10, 0])]);
      final mapped = d.mapThrough(mapping);
      expect(mapped, isNull);
    });

    test('InlineDecoration does not expand on boundary insertion', () {
      final d = InlineDecoration(5, 10, {'class': 'hi'});
      final mapping = Mapping.from([StepMap([5, 0, 3])]);
      final mapped = d.mapThrough(mapping) as InlineDecoration;
      expect(mapped.from, 8);
      expect(mapped.to, 13);
    });

    test('NodeDecoration maps through insertion', () {
      final d = NodeDecoration(5, {'class': 'sel'});
      final mapping = Mapping.from([StepMap([3, 0, 2])]);
      final mapped = d.mapThrough(mapping) as NodeDecoration;
      expect(mapped.pos, 7);
    });

    test('NodeDecoration removed when position deleted', () {
      final d = NodeDecoration(5, {'class': 'sel'});
      final mapping = Mapping.from([StepMap([4, 3, 0])]);
      final mapped = d.mapThrough(mapping);
      expect(mapped, isNull);
    });

    test('WidgetDecoration side affects mapping direction', () {
      final before = WidgetDecoration(5, side: false);
      final after = WidgetDecoration(5, side: true);
      final mapping = Mapping.from([StepMap([5, 0, 3])]);

      final mappedBefore = before.mapThrough(mapping) as WidgetDecoration;
      final mappedAfter = after.mapThrough(mapping) as WidgetDecoration;

      expect(mappedBefore.pos, 5);
      expect(mappedAfter.pos, 8);
    });

    test('DecorationSet add/remove/find', () {
      var set = DecorationSet.empty;
      final d1 = InlineDecoration(0, 10, {'class': 'a'},
          spec: DecorationSpec(type: 'search'));
      final d2 = InlineDecoration(20, 30, {'class': 'b'},
          spec: DecorationSpec(type: 'lint'));
      final d3 = NodeDecoration(5, {'class': 'c'});

      set = set.add(d1).add(d2).add(d3);
      expect(set.length, 3);

      expect(set.find(type: 'search').length, 1);
      expect(set.find(type: 'lint').length, 1);

      expect(set.findInline(0, 15).length, 1);
      expect(set.findInline(0, 25).length, 2);

      expect(set.findNode(5).length, 1);
      expect(set.findNode(0).length, 0);

      set = set.remove(d1);
      expect(set.length, 2);
    });

    test('DecorationSet maps through edits', () {
      var set = DecorationSet.empty;
      set = set.add(InlineDecoration(5, 10, {'class': 'a'}));
      set = set.add(NodeDecoration(15, {'class': 'b'}));

      final mapping = Mapping.from([StepMap([0, 0, 3])]);
      final mapped = set.map(mapping);

      final inline = mapped.findInline(0, 100).first;
      expect(inline.from, 8);
      expect(inline.to, 13);

      final node = mapped.findNode(18);
      expect(node.length, 1);
    });

    test('DecorationPlugin maps decorations on transaction', () {
      final d = doc([para('Hello world')]);
      final state = EditorState.create(
        schema: basicSchema,
        doc: d,
        plugins: [DecorationPlugin()],
      );

      var decos = state.pluginState<DecorationSet>('decorations')!;
      decos = decos.add(InlineDecoration(1, 5, {'class': 'hi'}));

      final stateWithDeco = EditorState(
        doc: state.doc,
        selection: state.selection,
        schema: state.schema,
        plugins: state.plugins,
        pluginStates: {...state.pluginStates, 'decorations': decos},
      );

      final tr = Transaction(stateWithDeco.doc)
        ..insertText(1, 'XX');
      final newState = stateWithDeco.apply(tr);

      final newDecos = newState.pluginState<DecorationSet>('decorations')!;
      final found = newDecos.findInline(0, 100);
      expect(found.length, 1);
      expect(found.first.from, 3);
      expect(found.first.to, 7);
    });
  });
}
