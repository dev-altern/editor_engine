import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  group('StepMap', () {
    test('identity maps all positions unchanged', () {
      expect(StepMap.identity.map(0), 0);
      expect(StepMap.identity.map(10), 10);
    });

    test('simple insertion shifts positions after', () {
      final map = StepMap.simple(5, 0, 3);
      expect(map.map(3), 3);
      expect(map.map(5, assoc: 1), 8);
      expect(map.map(5, assoc: -1), 5);
      expect(map.map(10), 13);
    });

    test('simple deletion shifts positions', () {
      final map = StepMap.simple(5, 3, 0);
      expect(map.map(3), 3);
      expect(map.map(6, assoc: -1), 5);
      expect(map.map(6, assoc: 1), 5);
      expect(map.map(10), 7);
    });

    test('replacement maps correctly', () {
      final map = StepMap.simple(5, 2, 4);
      expect(map.map(3), 3);
      expect(map.map(10), 12);
    });

    test('mapOrNull returns null for deleted positions', () {
      final map = StepMap.simple(5, 3, 0);
      expect(map.mapOrNull(6), null);
    });

    test('inverse swaps old/new sizes', () {
      final map = StepMap.simple(5, 3, 0);
      final inv = map.inverse;
      expect(inv.ranges, [5, 0, 3]);
    });
  });

  group('Mapping', () {
    test('maps through sequence', () {
      final m = Mapping();
      m.appendMap(StepMap.simple(0, 0, 5));
      m.appendMap(StepMap.simple(5, 0, 3));
      expect(m.map(0, assoc: 1), 8);
    });

    test('inverse reverses', () {
      final m = Mapping();
      m.appendMap(StepMap.simple(0, 0, 5));
      final inv = m.inverse;
      expect(inv.maps.length, 1);
      expect(inv.maps[0].ranges, [0, 5, 0]);
    });
  });

  group('ReplaceStep', () {
    test('insertion adds text', () {
      final d = doc([para('Hello')]);
      final slice = Slice(Fragment([TextNode(' World')]), 0, 0);
      final step = ReplaceStep.insert(6, slice);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.textContent, 'Hello World');
    });

    test('deletion removes text', () {
      final d = doc([para('Hello World')]);
      final step = ReplaceStep.delete(6, 12);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.textContent, 'Hello');
    });

    test('invert produces correct undo step', () {
      final d = doc([para('Hello')]);
      final slice = Slice(Fragment([TextNode(' World')]), 0, 0);
      final step = ReplaceStep.insert(6, slice);

      final result = step.apply(d);
      expect(result.isOk, true);

      final inverse = step.invert(d);
      final undone = inverse.apply(result.doc!);
      expect(undone.isOk, true);
      expect(undone.doc!.textContent, 'Hello');
    });

    test('getMap returns correct StepMap', () {
      final step = ReplaceStep.insert(
        5,
        Slice(Fragment([TextNode('Hi')]), 0, 0),
      );
      final map = step.getMap();
      expect(map.ranges, [5, 0, 2]);
    });

    test('delete getMap', () {
      final step = ReplaceStep.delete(5, 8);
      final map = step.getMap();
      expect(map.ranges, [5, 3, 0]);
    });
  });

  group('AddMarkStep', () {
    test('adds mark to text range', () {
      final d = doc([para('Hello')]);
      final step = AddMarkStep(1, 6, Mark.bold);
      final result = step.apply(d);

      expect(result.isOk, true);
      final textNodes = result.doc!.textNodes.toList();
      expect(textNodes.length, 1);
      expect(textNodes[0].marks.hasMark('bold'), true);
    });

    test('adds mark to partial text', () {
      final d = doc([para('Hello')]);
      final step = AddMarkStep(1, 3, Mark.bold);
      final result = step.apply(d);

      expect(result.isOk, true);
      final textNodes = result.doc!.textNodes.toList();
      expect(textNodes.length, 2);
      expect(textNodes[0].text, 'He');
      expect(textNodes[0].marks.hasMark('bold'), true);
      expect(textNodes[1].text, 'llo');
      expect(textNodes[1].marks.hasMark('bold'), false);
    });

    test('adds mark to InlineWidgetNode', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('Hi '),
            InlineWidgetNode(widgetType: 'mention', attrs: {'userId': '1'}),
            TextNode(' there'),
          ]),
        ),
      ]);
      final step = AddMarkStep(1, 5, Mark.bold);
      final result = step.apply(d);
      expect(result.isOk, true);

      final p = result.doc!.content.child(0);
      final widget = p.content.children.firstWhere(
        (n) => n is InlineWidgetNode,
      );
      expect(widget.marks.hasMark('bold'), true);
    });

    test('invert produces RemoveMarkStep', () {
      final d = doc([para('Hello')]);
      final step = AddMarkStep(1, 6, Mark.bold);
      final inverse = step.invert(d);
      expect(inverse, isA<RemoveMarkStep>());
    });
  });

  group('RemoveMarkStep', () {
    test('removes mark from text', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('Hello', marks: [Mark.bold]),
          ]),
        ),
      ]);
      final step = RemoveMarkStep(1, 6, Mark.bold);
      final result = step.apply(d);

      expect(result.isOk, true);
      final textNodes = result.doc!.textNodes.toList();
      expect(textNodes.length, 1);
      expect(textNodes[0].marks.hasMark('bold'), false);
    });
  });

  group('SetAttrStep', () {
    test('changes node attribute', () {
      final d = doc([heading('Title', level: 1)]);
      final step = SetAttrStep(0, 'level', 2);
      final result = step.apply(d);

      expect(result.isOk, true);
      final h = result.doc!.content.child(0);
      expect(h.attrs['level'], 2);
    });
  });

  group('Transaction', () {
    test('insertText adds text', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..insertText(6, ' World');
      expect(tr.doc.textContent, 'Hello World');
      expect(tr.steps.length, 1);
    });

    test('deleteRange removes text', () {
      final d = doc([para('Hello World')]);
      final tr = Transaction(d)..deleteRange(6, 12);
      expect(tr.doc.textContent, 'Hello');
    });

    test('multiple steps compose', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)
        ..insertText(6, ' World')
        ..addMark(1, 6, Mark.bold);

      expect(tr.doc.textContent, 'Hello World');
      expect(tr.steps.length, 2);
      expect(tr.maps.length, 2);
    });

    test('mapping maps positions through all steps', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..insertText(1, 'XXX');
      expect(tr.mapping.map(3), 6);
    });

    test('setSelection stores selection', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)
        ..insertText(1, 'X')
        ..setSelection(TextSelection.collapsed(2));
      expect(tr.selection, isA<TextSelection>());
      expect(tr.selection!.anchor, 2);
    });

    test('metadata works', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..setMeta('custom', 42);
      expect(tr.getMeta('custom'), 42);
    });

    test('addToHistory defaults to true', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d);
      expect(tr.addToHistory, true);
    });

    test('addToHistory can be disabled', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..setMeta('addToHistory', false);
      expect(tr.addToHistory, false);
    });
  });

  group('Complex transforms', () {
    test('StepMap.compose with non-overlapping ranges', () {
      final a = StepMap([5, 0, 3]);
      final b = StepMap([20, 0, 2]);
      final composed = a.compose(b);

      for (final pos in [0, 3, 5, 10, 15, 20, 25]) {
        final sequential = b.map(a.map(pos));
        final direct = composed.map(pos);
        expect(direct, sequential, reason: 'pos=$pos');
      }
    });

    test('StepMap.compose with overlapping ranges (B inside A output)', () {
      final a = StepMap([5, 0, 3]);
      final b = StepMap([6, 2, 0]);
      final composed = a.compose(b);

      for (final pos in [0, 3, 5, 10, 15]) {
        final sequential = b.map(a.map(pos));
        final direct = composed.map(pos);
        expect(direct, sequential, reason: 'pos=$pos');
      }
    });

    test('StepMap.compose with deletion then insertion', () {
      final a = StepMap([5, 3, 0]);
      final b = StepMap([5, 0, 2]);
      final composed = a.compose(b);

      for (final pos in [0, 3, 5, 8, 10, 15]) {
        final sequential = b.map(a.map(pos));
        final direct = composed.map(pos);
        expect(direct, sequential, reason: 'pos=$pos');
      }
    });

    test('Mapping.composed matches sequential mapping', () {
      final mapping = Mapping.from([
        StepMap([2, 3, 5]),
        StepMap([10, 0, 2]),
        StepMap([5, 2, 0]),
      ]);
      final composed = mapping.composed;

      for (final pos in [0, 1, 2, 3, 5, 7, 10, 12, 15, 20]) {
        final seq = mapping.map(pos);
        final direct = composed.map(pos);
        expect(direct, seq, reason: 'pos=$pos');
      }
    });

    test('ReplaceStep on multi-paragraph doc', () {
      final d = doc([para('Hello'), para('World')]);
      final step = ReplaceStep(3, 10, Slice.empty);
      final result = step.apply(d);
      expect(result.isOk, true);
      expect(result.doc!.textContent, 'Herld');
    });

    test('ReplaceStep insert with open slice (split paragraph)', () {
      final d = doc([para('HelloWorld')]);
      final slice = Slice(
        Fragment([
          BlockNode(type: 'paragraph', inlineContent: true),
          BlockNode(type: 'paragraph', inlineContent: true),
        ]),
        1,
        1,
      );
      final step = ReplaceStep(6, 6, slice);
      final result = step.apply(d);
      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 2);
      expect(result.doc!.content.child(0).textContent, 'Hello');
      expect(result.doc!.content.child(1).textContent, 'World');
    });

    test('multiple steps accumulate maps correctly', () {
      final d = doc([para('Hello world')]);
      final tr = Transaction(d)
        ..insertText(1, 'AAA')
        ..insertText(10, 'BBB');

      expect(tr.maps.length, 2);
      expect(tr.steps.length, 2);

      final mapping = tr.mapping;
      expect(mapping.map(0, assoc: -1), 0);
    });
  });

  group('Step.fromJson', () {
    test('ReplaceStep insertion round-trips', () {
      final step = ReplaceStep(
        5,
        5,
        Slice(Fragment([TextNode('hello')]), 0, 0),
      );
      final json = step.toJson();
      final restored = Step.fromJson(json) as ReplaceStep;
      expect(restored.from, 5);
      expect(restored.to, 5);
      expect(restored.slice.size, 5);
      expect(restored.slice.content.child(0).textContent, 'hello');
    });

    test('ReplaceStep deletion round-trips', () {
      final step = ReplaceStep.delete(3, 8);
      final json = step.toJson();
      final restored = Step.fromJson(json) as ReplaceStep;
      expect(restored.from, 3);
      expect(restored.to, 8);
      expect(restored.slice.isEmpty, true);
    });

    test('ReplaceStep with open slice round-trips', () {
      final slice = Slice(
        Fragment([
          BlockNode(type: 'paragraph', inlineContent: true),
          BlockNode(type: 'paragraph', inlineContent: true),
        ]),
        1,
        1,
      );
      final step = ReplaceStep(6, 6, slice);
      final json = step.toJson();
      final restored = Step.fromJson(json) as ReplaceStep;
      expect(restored.from, 6);
      expect(restored.to, 6);
      expect(restored.slice.openStart, 1);
      expect(restored.slice.openEnd, 1);
      expect(restored.slice.content.childCount, 2);
    });

    test('AddMarkStep round-trips', () {
      final step = AddMarkStep(2, 10, Mark.bold);
      final json = step.toJson();
      final restored = Step.fromJson(json) as AddMarkStep;
      expect(restored.from, 2);
      expect(restored.to, 10);
      expect(restored.mark, Mark.bold);
    });

    test('AddMarkStep with attrs round-trips', () {
      final step = AddMarkStep(
        0,
        5,
        Mark.link('https://example.com', title: 'Example'),
      );
      final json = step.toJson();
      final restored = Step.fromJson(json) as AddMarkStep;
      expect(restored.from, 0);
      expect(restored.to, 5);
      expect(restored.mark.type, 'link');
      expect(restored.mark.attrs['href'], 'https://example.com');
      expect(restored.mark.attrs['title'], 'Example');
    });

    test('RemoveMarkStep round-trips', () {
      final step = RemoveMarkStep(5, 15, Mark.italic);
      final json = step.toJson();
      final restored = Step.fromJson(json) as RemoveMarkStep;
      expect(restored.from, 5);
      expect(restored.to, 15);
      expect(restored.mark, Mark.italic);
    });

    test('SetAttrStep round-trips', () {
      final step = SetAttrStep(0, 'level', 3);
      final json = step.toJson();
      final restored = Step.fromJson(json) as SetAttrStep;
      expect(restored.pos, 0);
      expect(restored.key, 'level');
      expect(restored.value, 3);
    });

    test('SetAttrStep with null value round-trips', () {
      final step = SetAttrStep(0, 'src', null);
      final json = step.toJson();
      final restored = Step.fromJson(json) as SetAttrStep;
      expect(restored.pos, 0);
      expect(restored.key, 'src');
      expect(restored.value, isNull);
    });

    test('unknown step type throws FormatException', () {
      expect(
        () => Step.fromJson({'stepType': 'unknown'}),
        throwsFormatException,
      );
    });

    test('ReplaceStep apply after round-trip produces same result', () {
      final d = doc([para('Hello world')]);
      final step = ReplaceStep(
        1,
        6,
        Slice(Fragment([TextNode('Goodbye')]), 0, 0),
      );

      final resultBefore = step.apply(d);
      final restored = Step.fromJson(step.toJson()) as ReplaceStep;
      final resultAfter = restored.apply(d);

      expect(resultBefore.doc!.textContent, resultAfter.doc!.textContent);
    });
  });
}
