import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  // ── IntervalTree ──────────────────────────────────────────────────────

  group('IntervalTree', () {
    test('empty tree has no entries', () {
      final tree = IntervalTree.empty<String>();
      expect(tree.isEmpty, true);
      expect(tree.length, 0);
      expect(tree.entries, isEmpty);
    });

    test('construction sorts entries by from', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'b', from: 10, to: 20, data: 'B'),
        IntervalEntry(id: 'a', from: 5, to: 15, data: 'A'),
        IntervalEntry(id: 'c', from: 1, to: 8, data: 'C'),
      ]);
      expect(tree.length, 3);
      expect(tree.entries[0].id, 'c');
      expect(tree.entries[1].id, 'a');
      expect(tree.entries[2].id, 'b');
    });

    test('point query finds containing intervals', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 10, data: 'A'),
        IntervalEntry(id: 'b', from: 5, to: 15, data: 'B'),
        IntervalEntry(id: 'c', from: 20, to: 30, data: 'C'),
      ]);
      final at7 = tree.queryPoint(7);
      expect(at7.map((e) => e.id), containsAll(['a', 'b']));
      expect(at7.length, 2);
    });

    test('point query at boundary — from is inclusive, to is exclusive', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 5, to: 10, data: 'A'),
      ]);
      expect(tree.queryPoint(5).length, 1);
      expect(tree.queryPoint(9).length, 1);
      expect(tree.queryPoint(10).length, 0);
      expect(tree.queryPoint(4).length, 0);
    });

    test('range query finds overlapping intervals', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 5, data: 'A'),
        IntervalEntry(id: 'b', from: 3, to: 8, data: 'B'),
        IntervalEntry(id: 'c', from: 10, to: 15, data: 'C'),
        IntervalEntry(id: 'd', from: 20, to: 25, data: 'D'),
      ]);
      final result = tree.query(4, 12);
      final ids = result.map((e) => e.id).toSet();
      expect(ids, containsAll(['a', 'b', 'c']));
      expect(ids.contains('d'), false);
    });

    test('range query with no overlap returns empty', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 5, data: 'A'),
        IntervalEntry(id: 'b', from: 10, to: 15, data: 'B'),
      ]);
      expect(tree.query(6, 9), isEmpty);
    });

    test('add returns new tree with entry', () {
      final tree = IntervalTree.empty<String>();
      final newTree = tree.add(
        IntervalEntry(id: 'a', from: 0, to: 10, data: 'A'),
      );
      expect(tree.isEmpty, true);
      expect(newTree.length, 1);
    });

    test('remove returns new tree without entry', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 10, data: 'A'),
        IntervalEntry(id: 'b', from: 5, to: 15, data: 'B'),
      ]);
      final newTree = tree.remove('a');
      expect(newTree.length, 1);
      expect(newTree.entries[0].id, 'b');
    });

    test('remove nonexistent id returns same tree', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 10, data: 'A'),
      ]);
      final same = tree.remove('nonexistent');
      expect(identical(same, tree), true);
    });

    test('map transforms entries', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 10, data: 'A'),
        IntervalEntry(id: 'b', from: 5, to: 15, data: 'B'),
      ]);
      final shifted = tree.map(
        (e) => e.copyWith(from: e.from + 5, to: e.to + 5),
      );
      expect(shifted.entries[0].from, 5);
      expect(shifted.entries[0].to, 15);
      expect(shifted.entries[1].from, 10);
      expect(shifted.entries[1].to, 20);
    });

    test('map removes entries returning null', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 10, data: 'A'),
        IntervalEntry(id: 'b', from: 5, to: 15, data: 'B'),
      ]);
      final filtered = tree.map((e) => e.id == 'a' ? null : e);
      expect(filtered.length, 1);
      expect(filtered.entries[0].id, 'b');
    });

    test('map removes entries where from >= to', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 5, to: 10, data: 'A'),
      ]);
      final collapsed = tree.map((e) => e.copyWith(from: 10, to: 10));
      expect(collapsed.isEmpty, true);
    });

    test('map returns same tree when nothing changed', () {
      final tree = IntervalTree<String>([
        IntervalEntry(id: 'a', from: 0, to: 10, data: 'A'),
      ]);
      final same = tree.map((e) => e);
      expect(identical(same, tree), true);
    });

    test('IntervalEntry overlaps', () {
      final entry = IntervalEntry(id: 'a', from: 5, to: 10, data: 'A');
      expect(entry.overlaps(0, 6), true);
      expect(entry.overlaps(9, 15), true);
      expect(entry.overlaps(6, 8), true);
      expect(entry.overlaps(0, 5), false);
      expect(entry.overlaps(10, 15), false);
    });

    test('IntervalEntry contains', () {
      final entry = IntervalEntry(id: 'a', from: 5, to: 10, data: 'A');
      expect(entry.contains(5), true);
      expect(entry.contains(9), true);
      expect(entry.contains(4), false);
      expect(entry.contains(10), false);
    });

    test('IntervalEntry equality', () {
      final a = IntervalEntry(id: 'a', from: 5, to: 10, data: 'A');
      final b = IntervalEntry(id: 'a', from: 5, to: 10, data: 'B');
      final c = IntervalEntry(id: 'a', from: 5, to: 11, data: 'A');
      expect(a, equals(b)); // same id, from, to
      expect(a, isNot(equals(c)));
    });
  });

  // ── Marker ────────────────────────────────────────────────────────────

  group('Marker', () {
    test('creates with defaults', () {
      final m = Marker(id: 'm1', from: 0, to: 10, type: 'comment');
      expect(m.behavior, MarkerBehavior.exclusive);
      expect(m.attrs, isEmpty);
    });

    test('copyWith creates modified copy', () {
      final m = Marker(id: 'm1', from: 0, to: 10, type: 'comment');
      final c = m.copyWith(from: 5, to: 15);
      expect(c.id, 'm1');
      expect(c.from, 5);
      expect(c.to, 15);
      expect(c.type, 'comment');
    });

    test('toJson / fromJson round-trip', () {
      final m = Marker(
        id: 'm1',
        from: 10,
        to: 20,
        type: 'highlight',
        attrs: {'color': 'yellow'},
        behavior: MarkerBehavior.inclusive,
      );
      final json = m.toJson();
      final restored = Marker.fromJson(json);
      expect(restored.id, 'm1');
      expect(restored.from, 10);
      expect(restored.to, 20);
      expect(restored.type, 'highlight');
      expect(restored.attrs['color'], 'yellow');
      expect(restored.behavior, MarkerBehavior.inclusive);
    });

    test('toJson omits defaults', () {
      final m = Marker(id: 'm1', from: 0, to: 10, type: 'comment');
      final json = m.toJson();
      expect(json.containsKey('attrs'), false);
      expect(json.containsKey('behavior'), false);
    });

    test('equality', () {
      final a = Marker(
        id: 'm1',
        from: 0,
        to: 10,
        type: 'comment',
        attrs: {'threadId': 'abc'},
      );
      final b = Marker(
        id: 'm1',
        from: 0,
        to: 10,
        type: 'comment',
        attrs: {'threadId': 'abc'},
      );
      expect(a, equals(b));
    });

    group('mapThrough', () {
      test('exclusive: boundary insertions do not expand', () {
        final m = Marker(
          id: 'm1',
          from: 5,
          to: 10,
          type: 'comment',
          behavior: MarkerBehavior.exclusive,
        );
        // Insert 3 chars at pos 5 (at start boundary).
        final mapping = Mapping.from([StepMap.simple(5, 0, 3)]);
        final mapped = m.mapThrough(mapping)!;
        // Exclusive from assoc=1: maps forward, so from = 8.
        expect(mapped.from, 8);
        expect(mapped.to, 13);
      });

      test('startInclusive: insertion at start expands', () {
        final m = Marker(
          id: 'm1',
          from: 5,
          to: 10,
          type: 'comment',
          behavior: MarkerBehavior.startInclusive,
        );
        // Insert at pos 5 (at start).
        final mapping = Mapping.from([StepMap.simple(5, 0, 3)]);
        final mapped = m.mapThrough(mapping)!;
        // startInclusive from assoc=-1: stays at 5.
        expect(mapped.from, 5);
        expect(mapped.to, 13);
      });

      test('endInclusive: insertion at end expands', () {
        final m = Marker(
          id: 'm1',
          from: 5,
          to: 10,
          type: 'comment',
          behavior: MarkerBehavior.endInclusive,
        );
        // Insert at pos 10 (at end).
        final mapping = Mapping.from([StepMap.simple(10, 0, 3)]);
        final mapped = m.mapThrough(mapping)!;
        // endInclusive to assoc=1: expands to 13.
        expect(mapped.from, 5);
        expect(mapped.to, 13);
      });

      test('inclusive: boundary insertions expand both sides', () {
        final m = Marker(
          id: 'm1',
          from: 5,
          to: 10,
          type: 'comment',
          behavior: MarkerBehavior.inclusive,
        );
        // Insert at pos 5.
        final mapping = Mapping.from([StepMap.simple(5, 0, 3)]);
        final mapped = m.mapThrough(mapping)!;
        // inclusive from assoc=-1: stays at 5, to shifts to 13.
        expect(mapped.from, 5);
        expect(mapped.to, 13);
      });

      test('deletion collapses marker returns null', () {
        final m = Marker(
          id: 'm1',
          from: 5,
          to: 10,
          type: 'comment',
          behavior: MarkerBehavior.exclusive,
        );
        // Delete the entire range 5..10.
        final mapping = Mapping.from([StepMap.simple(5, 5, 0)]);
        final mapped = m.mapThrough(mapping);
        expect(mapped, isNull);
      });

      test('insertion in middle shifts end', () {
        final m = Marker(
          id: 'm1',
          from: 5,
          to: 10,
          type: 'comment',
          behavior: MarkerBehavior.exclusive,
        );
        // Insert 2 at pos 7 (inside marker).
        final mapping = Mapping.from([StepMap.simple(7, 0, 2)]);
        final mapped = m.mapThrough(mapping)!;
        expect(mapped.from, 5);
        expect(mapped.to, 12);
      });

      test('insertion before shifts both', () {
        final m = Marker(id: 'm1', from: 10, to: 20, type: 'comment');
        final mapping = Mapping.from([StepMap.simple(5, 0, 3)]);
        final mapped = m.mapThrough(mapping)!;
        expect(mapped.from, 13);
        expect(mapped.to, 23);
      });

      test('returns same marker if positions unchanged', () {
        final m = Marker(id: 'm1', from: 10, to: 20, type: 'comment');
        final mapping = Mapping.from([StepMap.simple(25, 0, 5)]);
        final mapped = m.mapThrough(mapping)!;
        expect(identical(mapped, m), true);
      });
    });
  });

  // ── MarkerCollection ──────────────────────────────────────────────────

  group('MarkerCollection', () {
    test('empty collection', () {
      expect(MarkerCollection.empty.isEmpty, true);
      expect(MarkerCollection.empty.length, 0);
    });

    test('create from list', () {
      final coll = MarkerCollection([
        Marker(id: 'm1', from: 0, to: 10, type: 'comment'),
        Marker(id: 'm2', from: 5, to: 15, type: 'highlight'),
      ]);
      expect(coll.length, 2);
    });

    test('add and findById', () {
      var coll = MarkerCollection.empty;
      coll = coll.add(Marker(id: 'm1', from: 0, to: 10, type: 'comment'));
      expect(coll.findById('m1')!.type, 'comment');
      expect(coll.findById('nonexistent'), isNull);
    });

    test('remove', () {
      var coll = MarkerCollection([
        Marker(id: 'm1', from: 0, to: 10, type: 'comment'),
        Marker(id: 'm2', from: 5, to: 15, type: 'highlight'),
      ]);
      coll = coll.remove('m1');
      expect(coll.length, 1);
      expect(coll.findById('m1'), isNull);
      expect(coll.findById('m2'), isNotNull);
    });

    test('remove nonexistent returns same', () {
      final coll = MarkerCollection([
        Marker(id: 'm1', from: 0, to: 10, type: 'comment'),
      ]);
      final same = coll.remove('nonexistent');
      expect(identical(same, coll), true);
    });

    test('update', () {
      var coll = MarkerCollection([
        Marker(
          id: 'm1',
          from: 0,
          to: 10,
          type: 'comment',
          attrs: {'resolved': false},
        ),
      ]);
      coll = coll.update('m1', (m) => m.copyWith(attrs: {'resolved': true}));
      expect(coll.findById('m1')!.attrs['resolved'], true);
    });

    test('findOverlapping', () {
      final coll = MarkerCollection([
        Marker(id: 'm1', from: 0, to: 10, type: 'comment'),
        Marker(id: 'm2', from: 8, to: 20, type: 'highlight'),
        Marker(id: 'm3', from: 25, to: 30, type: 'diagnostic'),
      ]);
      final result = coll.findOverlapping(5, 12);
      expect(result.length, 2);
      final ids = result.map((m) => m.id).toSet();
      expect(ids, containsAll(['m1', 'm2']));
    });

    test('findAt', () {
      final coll = MarkerCollection([
        Marker(id: 'm1', from: 0, to: 10, type: 'comment'),
        Marker(id: 'm2', from: 5, to: 15, type: 'highlight'),
      ]);
      final at7 = coll.findAt(7);
      expect(at7.length, 2);
      final at12 = coll.findAt(12);
      expect(at12.length, 1);
      expect(at12[0].id, 'm2');
    });

    test('findByType', () {
      final coll = MarkerCollection([
        Marker(id: 'm1', from: 0, to: 10, type: 'comment'),
        Marker(id: 'm2', from: 5, to: 15, type: 'highlight'),
        Marker(id: 'm3', from: 10, to: 20, type: 'comment'),
      ]);
      final comments = coll.findByType('comment');
      expect(comments.length, 2);
      expect(coll.findByType('diagnostic'), isEmpty);
    });

    test('mapThrough shifts markers', () {
      var coll = MarkerCollection([
        Marker(id: 'm1', from: 5, to: 10, type: 'comment'),
        Marker(id: 'm2', from: 15, to: 20, type: 'highlight'),
      ]);
      // Insert 3 chars at pos 0.
      final mapping = Mapping.from([StepMap.simple(0, 0, 3)]);
      coll = coll.mapThrough(mapping);
      expect(coll.findById('m1')!.from, 8);
      expect(coll.findById('m1')!.to, 13);
      expect(coll.findById('m2')!.from, 18);
      expect(coll.findById('m2')!.to, 23);
    });

    test('mapThrough removes collapsed markers', () {
      var coll = MarkerCollection([
        Marker(id: 'm1', from: 5, to: 10, type: 'comment'),
      ]);
      // Delete range 5..10.
      final mapping = Mapping.from([StepMap.simple(5, 5, 0)]);
      coll = coll.mapThrough(mapping);
      expect(coll.isEmpty, true);
    });

    test('toJson / fromJson round-trip', () {
      final coll = MarkerCollection([
        Marker(
          id: 'm1',
          from: 0,
          to: 10,
          type: 'comment',
          attrs: {'threadId': 'abc'},
        ),
        Marker(id: 'm2', from: 5, to: 15, type: 'highlight'),
      ]);
      final json = coll.toJson();
      final restored = MarkerCollection.fromJson(json);
      expect(restored.length, 2);
      expect(restored.findById('m1')!.attrs['threadId'], 'abc');
      expect(restored.findById('m2')!.type, 'highlight');
    });

    test('markers iterable', () {
      final coll = MarkerCollection([
        Marker(id: 'm1', from: 0, to: 10, type: 'comment'),
        Marker(id: 'm2', from: 5, to: 15, type: 'highlight'),
      ]);
      expect(coll.markers.length, 2);
    });
  });

  // ── MarkerPlugin ──────────────────────────────────────────────────────

  group('MarkerPlugin', () {
    late EditorState state;

    setUp(() {
      state = EditorState.create(
        schema: basicSchema,
        doc: doc([para('Hello world')]),
        plugins: [MarkerPlugin()],
      );
    });

    test('init returns empty MarkerCollection', () {
      final markers = state.pluginState<MarkerCollection>('markers');
      expect(markers, isNotNull);
      expect(markers!.isEmpty, true);
    });

    test('add marker via transaction metadata', () {
      final tr = state.transaction
        ..setMeta(
          'addMarker',
          Marker(id: 'm1', from: 1, to: 6, type: 'comment'),
        );
      final newState = state.apply(tr);
      final markers = newState.pluginState<MarkerCollection>('markers')!;
      expect(markers.length, 1);
      expect(markers.findById('m1')!.type, 'comment');
    });

    test('remove marker via transaction metadata', () {
      // Add first.
      var tr = state.transaction
        ..setMeta(
          'addMarker',
          Marker(id: 'm1', from: 1, to: 6, type: 'comment'),
        );
      var s = state.apply(tr);

      // Then remove.
      tr = s.transaction..setMeta('removeMarker', 'm1');
      s = s.apply(tr);
      final markers = s.pluginState<MarkerCollection>('markers')!;
      expect(markers.isEmpty, true);
    });

    test('update marker attrs via transaction metadata', () {
      var tr = state.transaction
        ..setMeta(
          'addMarker',
          Marker(
            id: 'm1',
            from: 1,
            to: 6,
            type: 'comment',
            attrs: {'resolved': false},
          ),
        );
      var s = state.apply(tr);

      tr = s.transaction
        ..setMeta('updateMarker', {
          'id': 'm1',
          'attrs': {'resolved': true},
        });
      s = s.apply(tr);
      final markers = s.pluginState<MarkerCollection>('markers')!;
      expect(markers.findById('m1')!.attrs['resolved'], true);
    });

    test('markers shift when text is inserted', () {
      // Add marker on "Hello" (pos 1..6 in doc).
      var tr = state.transaction
        ..setMeta(
          'addMarker',
          Marker(id: 'm1', from: 1, to: 6, type: 'comment'),
        );
      var s = state.apply(tr);

      // Insert "Hi " at position 1 (before "Hello").
      tr = s.transaction..insertText(1, 'Hi ');
      s = s.apply(tr);

      final markers = s.pluginState<MarkerCollection>('markers')!;
      final m = markers.findById('m1')!;
      // Marker should shift right by 3.
      expect(m.from, 4);
      expect(m.to, 9);
    });

    test('marker deleted when its text range is deleted', () {
      // Add marker at 1..6.
      var tr = state.transaction
        ..setMeta(
          'addMarker',
          Marker(id: 'm1', from: 1, to: 6, type: 'comment'),
        );
      var s = state.apply(tr);

      // Delete range 1..6.
      tr = s.transaction..deleteRange(1, 6);
      s = s.apply(tr);

      final markers = s.pluginState<MarkerCollection>('markers')!;
      expect(markers.findById('m1'), isNull);
    });
  });
}
