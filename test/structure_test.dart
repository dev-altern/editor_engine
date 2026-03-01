import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  group('SplitStep', () {
    test('splits paragraph in the middle', () {
      final d = doc([para('Hello')]);
      // Position 4 is between "Hel" and "lo" (1 for open token + 3 chars)
      final step = SplitStep(4);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 2);
      expect(result.doc!.content.child(0).textContent, 'Hel');
      expect(result.doc!.content.child(1).textContent, 'lo');
    });

    test('splits at start of block creates empty block before', () {
      final d = doc([para('Hello')]);
      // Position 1 is right after the open token
      final step = SplitStep(1);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 2);
      expect(result.doc!.content.child(0).textContent, '');
      expect(result.doc!.content.child(1).textContent, 'Hello');
    });

    test('splits at end of block creates empty block after', () {
      final d = doc([para('Hello')]);
      // Position 6 is right before the close token (1 + 5 chars)
      final step = SplitStep(6);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 2);
      expect(result.doc!.content.child(0).textContent, 'Hello');
      expect(result.doc!.content.child(1).textContent, '');
    });

    test('splits with type change (heading to paragraph)', () {
      final d = doc([heading('Title', level: 1)]);
      final step = SplitStep(4, typeAfter: 'paragraph');
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 2);
      expect(result.doc!.content.child(0).type, 'heading');
      expect(result.doc!.content.child(0).textContent, 'Tit');
      expect(result.doc!.content.child(1).type, 'paragraph');
      expect(result.doc!.content.child(1).textContent, 'le');
    });

    test('splits preserving block attributes', () {
      final d = doc([heading('Title', level: 2)]);
      final step = SplitStep(4);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.child(0).attrs['level'], 2);
      expect(result.doc!.content.child(1).attrs['level'], 2);
    });

    test('splits with attrsAfter overrides second block attrs', () {
      final d = doc([heading('Title', level: 2)]);
      final step = SplitStep(4, attrsAfter: {'level': 1});
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.child(0).attrs['level'], 2);
      expect(result.doc!.content.child(1).attrs['level'], 1);
    });

    test('produces correct StepMap', () {
      final step = SplitStep(5);
      final map = step.getMap();
      // Inserts 2 tokens (close + open) at position 5
      expect(map.ranges, [5, 0, 2]);
    });

    test('produces correct StepMap with depth 2', () {
      final step = SplitStep(5, depth: 2);
      final map = step.getMap();
      // Inserts 4 tokens at position 5
      expect(map.ranges, [5, 0, 4]);
    });

    test('inversion round-trip restores original', () {
      final d = doc([para('Hello')]);
      final step = SplitStep(4);
      final result = step.apply(d);
      expect(result.isOk, true);

      final inverse = step.invert(d);
      final undone = inverse.apply(result.doc!);
      expect(undone.isOk, true);
      expect(undone.doc!.content.childCount, 1);
      expect(undone.doc!.textContent, 'Hello');
    });

    test('inversion of split with typeAfter restores original', () {
      final d = doc([heading('Title', level: 1)]);
      final step = SplitStep(4, typeAfter: 'paragraph');
      final result = step.apply(d);
      expect(result.isOk, true);

      final inverse = step.invert(d);
      final undone = inverse.apply(result.doc!);
      expect(undone.isOk, true);
      expect(undone.doc!.content.childCount, 1);
      expect(undone.doc!.textContent, 'Title');
    });

    test('JSON serialization round-trip', () {
      final step = SplitStep(
        5,
        typeAfter: 'paragraph',
        attrsAfter: {'level': 1},
      );
      final json = step.toJson();
      final restored = Step.fromJson(json) as SplitStep;
      expect(restored.pos, 5);
      expect(restored.depth, 1);
      expect(restored.typeAfter, 'paragraph');
      expect(restored.attrsAfter, {'level': 1});
    });

    test('JSON serialization omits null fields', () {
      final step = SplitStep(5);
      final json = step.toJson();
      expect(json.containsKey('typeAfter'), false);
      expect(json.containsKey('attrsAfter'), false);
    });

    test('toString', () {
      expect(SplitStep(5).toString(), 'SplitStep(5)');
      expect(SplitStep(5, depth: 2).toString(), 'SplitStep(5, depth: 2)');
      expect(
        SplitStep(5, typeAfter: 'paragraph').toString(),
        'SplitStep(5, typeAfter: paragraph)',
      );
    });
  });

  group('JoinStep', () {
    test('joins two paragraphs', () {
      final d = doc([para('Hello'), para('World')]);
      // Gap position is after first para: 1 (open) + 5 (text) + 1 (close) = 7
      final step = JoinStep(7);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 1);
      expect(result.doc!.textContent, 'HelloWorld');
    });

    test('joins empty paragraph with non-empty', () {
      final d = doc([emptyPara(), para('World')]);
      // Gap: 1 (open) + 0 (empty) + 1 (close) = 2
      final step = JoinStep(2);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 1);
      expect(result.doc!.textContent, 'World');
    });

    test('joins non-empty with empty paragraph', () {
      final d = doc([para('Hello'), emptyPara()]);
      // Gap: 1 + 5 + 1 = 7
      final step = JoinStep(7);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 1);
      expect(result.doc!.textContent, 'Hello');
    });

    test('produces correct StepMap', () {
      final step = JoinStep(7);
      final map = step.getMap();
      // Removes 2 tokens starting at position 6
      expect(map.ranges, [6, 2, 0]);
    });

    test('inversion round-trip restores original', () {
      final d = doc([para('Hello'), para('World')]);
      final step = JoinStep(7);
      final result = step.apply(d);
      expect(result.isOk, true);

      final inverse = step.invert(d);
      final undone = inverse.apply(result.doc!);
      expect(undone.isOk, true);
      expect(undone.doc!.content.childCount, 2);
      expect(undone.doc!.content.child(0).textContent, 'Hello');
      expect(undone.doc!.content.child(1).textContent, 'World');
    });

    test('inversion captures type difference', () {
      final d = doc([heading('Title', level: 1), para('Text')]);
      // Gap: 1 + 5 + 1 = 7
      final step = JoinStep(7);
      final inverse = step.invert(d);
      expect(inverse, isA<SplitStep>());
      final split = inverse as SplitStep;
      expect(split.typeAfter, 'paragraph');
    });

    test('inversion captures attr difference', () {
      final d = doc([heading('Title', level: 1), heading('Sub', level: 2)]);
      // Gap: 1 + 5 + 1 = 7
      final step = JoinStep(7);
      final inverse = step.invert(d);
      final split = inverse as SplitStep;
      expect(split.attrsAfter, {'level': 2});
    });

    test('inversion omits type/attrs when blocks match', () {
      final d = doc([para('Hello'), para('World')]);
      final step = JoinStep(7);
      final inverse = step.invert(d);
      final split = inverse as SplitStep;
      expect(split.typeAfter, isNull);
      expect(split.attrsAfter, isNull);
    });

    test('JSON serialization round-trip', () {
      final step = JoinStep(7, depth: 2);
      final json = step.toJson();
      final restored = Step.fromJson(json) as JoinStep;
      expect(restored.pos, 7);
      expect(restored.depth, 2);
    });

    test('toString', () {
      expect(JoinStep(7).toString(), 'JoinStep(7)');
      expect(JoinStep(7, depth: 2).toString(), 'JoinStep(7, depth: 2)');
    });
  });

  group('Split-Join round-trip', () {
    test('split then join restores original', () {
      final d = doc([para('Hello')]);
      final splitStep = SplitStep(4);
      final splitResult = splitStep.apply(d);
      expect(splitResult.isOk, true);

      // After split at 4, gap is at 4 + 1 = 5
      final joinStep = JoinStep(5);
      final joinResult = joinStep.apply(splitResult.doc!);
      expect(joinResult.isOk, true);
      expect(joinResult.doc!.content.childCount, 1);
      expect(joinResult.doc!.textContent, 'Hello');
    });

    test('join then split restores original', () {
      final d = doc([para('Hello'), para('World')]);
      final joinStep = JoinStep(7);
      final joinResult = joinStep.apply(d);
      expect(joinResult.isOk, true);

      // After join, "HelloWorld" is one block. Split at where "World" starts.
      // Position in joined doc: 1 (open) + 5 (Hello) = 6
      final splitStep = SplitStep(6);
      final splitResult = splitStep.apply(joinResult.doc!);
      expect(splitResult.isOk, true);
      expect(splitResult.doc!.content.childCount, 2);
      expect(splitResult.doc!.content.child(0).textContent, 'Hello');
      expect(splitResult.doc!.content.child(1).textContent, 'World');
    });
  });

  group('WrapStep', () {
    test('wraps single paragraph in blockquote', () {
      final d = doc([para('Hello')]);
      // Single para has nodeSize = 7 (1 + 5 + 1), from=0 to=7
      final step = WrapStep(0, 7, 'blockquote');
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 1);
      final wrapper = result.doc!.content.child(0);
      expect(wrapper.type, 'blockquote');
      expect(wrapper.content.childCount, 1);
      expect(wrapper.content.child(0).textContent, 'Hello');
    });

    test('wraps multiple paragraphs in blockquote', () {
      final d = doc([para('Hello'), para('World')]);
      // Total size: 7 + 7 = 14, from=0 to=14
      final step = WrapStep(0, 14, 'blockquote');
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 1);
      final wrapper = result.doc!.content.child(0);
      expect(wrapper.type, 'blockquote');
      expect(wrapper.content.childCount, 2);
      expect(wrapper.content.child(0).textContent, 'Hello');
      expect(wrapper.content.child(1).textContent, 'World');
    });

    test('wraps subset of paragraphs', () {
      final d = doc([para('One'), para('Two'), para('Three')]);
      // para("One") nodeSize=5, para("Two") nodeSize=5
      // Wrap first two: from=0, to=10
      final step = WrapStep(0, 10, 'blockquote');
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 2);
      expect(result.doc!.content.child(0).type, 'blockquote');
      expect(result.doc!.content.child(0).content.childCount, 2);
      expect(result.doc!.content.child(1).type, 'paragraph');
      expect(result.doc!.content.child(1).textContent, 'Three');
    });

    test('wraps with attrs', () {
      final d = doc([para('Item 1'), para('Item 2')]);
      final step = WrapStep(0, 16, 'ordered_list', wrapperAttrs: {'start': 1});
      final result = step.apply(d);

      expect(result.isOk, true);
      final wrapper = result.doc!.content.child(0);
      expect(wrapper.type, 'ordered_list');
      expect(wrapper.attrs['start'], 1);
    });

    test('fails with invalid range', () {
      final d = doc([para('Hello')]);
      final step = WrapStep(0, 3, 'blockquote'); // not on block boundary
      final result = step.apply(d);
      expect(result.isFail, true);
    });

    test('produces correct StepMap', () {
      final step = WrapStep(0, 7, 'blockquote');
      final map = step.getMap();
      // Inserts open token at 0, close token at 7
      expect(map.ranges, [0, 0, 1, 7, 0, 1]);
    });

    test('inversion round-trip restores original', () {
      final d = doc([para('Hello'), para('World')]);
      final step = WrapStep(0, 14, 'blockquote');
      final result = step.apply(d);
      expect(result.isOk, true);

      final inverse = step.invert(d);
      final undone = inverse.apply(result.doc!);
      expect(undone.isOk, true);
      expect(undone.doc!.content.childCount, 2);
      expect(undone.doc!.content.child(0).textContent, 'Hello');
      expect(undone.doc!.content.child(1).textContent, 'World');
    });

    test('JSON serialization round-trip', () {
      final step = WrapStep(
        0,
        14,
        'blockquote',
        wrapperAttrs: {'class': 'fancy'},
      );
      final json = step.toJson();
      final restored = Step.fromJson(json) as WrapStep;
      expect(restored.from, 0);
      expect(restored.to, 14);
      expect(restored.wrapperType, 'blockquote');
      expect(restored.wrapperAttrs['class'], 'fancy');
    });

    test('JSON serialization omits empty attrs', () {
      final step = WrapStep(0, 7, 'blockquote');
      final json = step.toJson();
      expect(json.containsKey('wrapperAttrs'), false);
    });

    test('toString', () {
      expect(
        WrapStep(0, 7, 'blockquote').toString(),
        'WrapStep(0, 7, blockquote)',
      );
    });
  });

  group('UnwrapStep', () {
    test('unwraps blockquote with single child', () {
      final d = doc([
        blockquote([para('Hello')]),
      ]);
      // blockquote nodeSize = 1 + 7 + 1 = 9
      final step = UnwrapStep(0, wrapperNodeSize: 9);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 1);
      expect(result.doc!.content.child(0).type, 'paragraph');
      expect(result.doc!.content.child(0).textContent, 'Hello');
    });

    test('unwraps blockquote with multiple children', () {
      final d = doc([
        blockquote([para('Hello'), para('World')]),
      ]);
      // blockquote nodeSize = 1 + 14 + 1 = 16
      final step = UnwrapStep(0, wrapperNodeSize: 16);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 2);
      expect(result.doc!.content.child(0).textContent, 'Hello');
      expect(result.doc!.content.child(1).textContent, 'World');
    });

    test('unwraps preserving surrounding blocks', () {
      final d = doc([
        para('Before'),
        blockquote([para('Inside')]),
        para('After'),
      ]);
      // para("Before") nodeSize = 8, starts at 0, ends at 8
      // blockquote starts at 8, nodeSize = 1 + 8 + 1 = 10
      final step = UnwrapStep(8, wrapperNodeSize: 10);
      final result = step.apply(d);

      expect(result.isOk, true);
      expect(result.doc!.content.childCount, 3);
      expect(result.doc!.content.child(0).textContent, 'Before');
      expect(result.doc!.content.child(1).textContent, 'Inside');
      expect(result.doc!.content.child(2).textContent, 'After');
    });

    test('fails on leaf node', () {
      final d = doc([para('Hello')]);
      final step = UnwrapStep(
        1,
        wrapperNodeSize: 5,
      ); // text node, not a wrapper
      final result = step.apply(d);
      expect(result.isFail, true);
    });

    test('produces correct StepMap', () {
      // wrapperNodeSize = 9: open at 0, close at 8
      final step = UnwrapStep(0, wrapperNodeSize: 9);
      final map = step.getMap();
      expect(map.ranges, [0, 1, 0, 8, 1, 0]);
    });

    test('inversion round-trip restores original', () {
      final d = doc([
        blockquote([para('Hello'), para('World')]),
      ]);
      final step = UnwrapStep(0, wrapperNodeSize: 16);
      final result = step.apply(d);
      expect(result.isOk, true);

      final inverse = step.invert(d);
      final undone = inverse.apply(result.doc!);
      expect(undone.isOk, true);
      expect(undone.doc!.content.childCount, 1);
      expect(undone.doc!.content.child(0).type, 'blockquote');
      expect(undone.doc!.content.child(0).content.childCount, 2);
    });

    test('JSON serialization round-trip', () {
      final step = UnwrapStep(5, wrapperNodeSize: 12);
      final json = step.toJson();
      final restored = Step.fromJson(json) as UnwrapStep;
      expect(restored.pos, 5);
      expect(restored.wrapperNodeSize, 12);
    });

    test('toString', () {
      expect(
        UnwrapStep(0, wrapperNodeSize: 9).toString(),
        'UnwrapStep(0, wrapperNodeSize: 9)',
      );
    });
  });

  group('Wrap-Unwrap round-trip', () {
    test('wrap then unwrap restores original', () {
      final d = doc([para('Hello'), para('World')]);
      final wrapStep = WrapStep(0, 14, 'blockquote');
      final wrapResult = wrapStep.apply(d);
      expect(wrapResult.isOk, true);

      // After wrapping, blockquote is at pos 0, nodeSize = 14 + 2 = 16
      final unwrapStep = UnwrapStep(0, wrapperNodeSize: 16);
      final unwrapResult = unwrapStep.apply(wrapResult.doc!);
      expect(unwrapResult.isOk, true);
      expect(unwrapResult.doc!.content.childCount, 2);
      expect(unwrapResult.doc!.content.child(0).textContent, 'Hello');
      expect(unwrapResult.doc!.content.child(1).textContent, 'World');
    });

    test('unwrap then wrap restores original', () {
      final d = doc([
        blockquote([para('Hello'), para('World')]),
      ]);
      // blockquote nodeSize = 16
      final unwrapStep = UnwrapStep(0, wrapperNodeSize: 16);
      final unwrapResult = unwrapStep.apply(d);
      expect(unwrapResult.isOk, true);

      // After unwrap, two paras at doc level. Wrap them back.
      final wrapStep = WrapStep(0, 14, 'blockquote');
      final wrapResult = wrapStep.apply(unwrapResult.doc!);
      expect(wrapResult.isOk, true);
      expect(wrapResult.doc!.content.childCount, 1);
      expect(wrapResult.doc!.content.child(0).type, 'blockquote');
      expect(wrapResult.doc!.content.child(0).content.childCount, 2);
    });
  });

  group('Position mapping through structure steps', () {
    test('positions before split point unchanged', () {
      final step = SplitStep(5);
      final map = step.getMap();
      expect(map.map(3), 3);
    });

    test('positions after split point shift by +2', () {
      final step = SplitStep(5);
      final map = step.getMap();
      expect(map.map(10), 12);
    });

    test('positions before join point unchanged', () {
      final step = JoinStep(7);
      final map = step.getMap();
      expect(map.map(3), 3);
    });

    test('positions after join point shift by -2', () {
      final step = JoinStep(7);
      final map = step.getMap();
      expect(map.map(10), 8);
    });

    test('WrapStep shifts interior positions by +1', () {
      final step = WrapStep(0, 7, 'blockquote');
      final map = step.getMap();
      // Position inside the wrapped range shifts by +1 (wrapper open token)
      expect(map.map(3), 4);
    });

    test('WrapStep shifts positions after range by +2', () {
      final step = WrapStep(0, 7, 'blockquote');
      final map = step.getMap();
      // Position after the wrapped range shifts by +2 (open + close tokens)
      expect(map.map(10), 12);
    });

    test('UnwrapStep shifts interior positions by -1', () {
      // wrapperNodeSize = 9, so open at 0, close at 8
      final step = UnwrapStep(0, wrapperNodeSize: 9);
      final map = step.getMap();
      // Position inside the wrapper (after open token) shifts by -1
      expect(map.map(3), 2);
    });
  });

  group('Structure step serialization via Step.fromJson', () {
    test('SplitStep round-trips', () {
      final step = SplitStep(10, depth: 2, typeAfter: 'paragraph');
      final json = step.toJson();
      final restored = Step.fromJson(json);
      expect(restored, isA<SplitStep>());
      final s = restored as SplitStep;
      expect(s.pos, 10);
      expect(s.depth, 2);
      expect(s.typeAfter, 'paragraph');
    });

    test('JoinStep round-trips', () {
      final step = JoinStep(15, depth: 2);
      final json = step.toJson();
      final restored = Step.fromJson(json);
      expect(restored, isA<JoinStep>());
      final j = restored as JoinStep;
      expect(j.pos, 15);
      expect(j.depth, 2);
    });

    test('WrapStep round-trips', () {
      final step = WrapStep(
        0,
        14,
        'bullet_list',
        wrapperAttrs: {'tight': true},
      );
      final json = step.toJson();
      final restored = Step.fromJson(json);
      expect(restored, isA<WrapStep>());
      final w = restored as WrapStep;
      expect(w.from, 0);
      expect(w.to, 14);
      expect(w.wrapperType, 'bullet_list');
      expect(w.wrapperAttrs['tight'], true);
    });

    test('UnwrapStep round-trips', () {
      final step = UnwrapStep(5, wrapperNodeSize: 20);
      final json = step.toJson();
      final restored = Step.fromJson(json);
      expect(restored, isA<UnwrapStep>());
      final u = restored as UnwrapStep;
      expect(u.pos, 5);
      expect(u.wrapperNodeSize, 20);
    });
  });

  group('Transaction structure convenience', () {
    test('split via Transaction.addStep', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..addStep(SplitStep(4));

      expect(tr.doc.content.childCount, 2);
      expect(tr.doc.content.child(0).textContent, 'Hel');
      expect(tr.doc.content.child(1).textContent, 'lo');
      expect(tr.steps.length, 1);
    });

    test('join via Transaction.addStep', () {
      final d = doc([para('Hello'), para('World')]);
      final tr = Transaction(d)..addStep(JoinStep(7));

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.textContent, 'HelloWorld');
    });

    test('wrap via Transaction.addStep', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..addStep(WrapStep(0, 7, 'blockquote'));

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.content.child(0).type, 'blockquote');
    });

    test('unwrap via Transaction.addStep', () {
      final d = doc([
        blockquote([para('Hello')]),
      ]);
      final tr = Transaction(d)..addStep(UnwrapStep(0, wrapperNodeSize: 9));

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.content.child(0).type, 'paragraph');
    });

    test('split then add mark composes correctly', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)
        ..addStep(SplitStep(4))
        ..addMark(1, 4, Mark.bold);

      expect(tr.doc.content.childCount, 2);
      expect(tr.steps.length, 2);
      expect(tr.maps.length, 2);
    });

    test('mapping through split + insert', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)
        ..addStep(SplitStep(4))
        ..insertText(6, 'X');

      // After split: <p>Hel</p><p>lo</p> (positions 0-5, 6-9)
      // After insert X at 6: <p>Hel</p><p>Xlo</p>
      expect(tr.doc.content.child(1).textContent, 'Xlo');
    });
  });

  group('Transaction convenience methods', () {
    test('split() splits a block', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..split(4);

      expect(tr.doc.content.childCount, 2);
      expect(tr.doc.content.child(0).textContent, 'Hel');
      expect(tr.doc.content.child(1).textContent, 'lo');
    });

    test('split() with typeAfter changes second block type', () {
      final d = doc([heading('Title', level: 1)]);
      final tr = Transaction(d)..split(4, typeAfter: 'paragraph');

      expect(tr.doc.content.child(0).type, 'heading');
      expect(tr.doc.content.child(1).type, 'paragraph');
    });

    test('join() joins two blocks', () {
      final d = doc([para('Hello'), para('World')]);
      final tr = Transaction(d)..join(7);

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.textContent, 'HelloWorld');
    });

    test('wrap() wraps blocks in a container', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..wrap(0, 7, 'blockquote');

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.content.child(0).type, 'blockquote');
      expect(tr.doc.content.child(0).content.child(0).textContent, 'Hello');
    });

    test('unwrap() removes a wrapper', () {
      final d = doc([
        blockquote([para('Hello')]),
      ]);
      final tr = Transaction(d)..unwrap(0, wrapperNodeSize: 9);

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.content.child(0).type, 'paragraph');
      expect(tr.doc.textContent, 'Hello');
    });

    test('setBlockType() changes block type', () {
      final d = doc([para('Hello')]);
      // Position 0 is the doc boundary, the paragraph starts at 0.
      final tr = Transaction(d)
        ..setBlockType(0, 'heading', attrs: {'level': 1});

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.content.child(0).type, 'heading');
      expect(tr.doc.content.child(0).attrs['level'], 1);
      expect(tr.doc.textContent, 'Hello');
    });

    test('deleteBlock() removes a block', () {
      final d = doc([para('Hello'), para('World')]);
      // First paragraph spans positions 0..7, second starts at 7.
      final tr = Transaction(d)..deleteBlock(0);

      expect(tr.doc.content.childCount, 1);
      expect(tr.doc.textContent, 'World');
    });

    test('insertBlockAfter() inserts after a block', () {
      final d = doc([para('Hello')]);
      final tr = Transaction(d)..insertBlockAfter(0, para('World'));

      expect(tr.doc.content.childCount, 2);
      expect(tr.doc.content.child(0).textContent, 'Hello');
      expect(tr.doc.content.child(1).textContent, 'World');
    });

    test('insertBlockBefore() inserts before a block', () {
      final d = doc([para('World')]);
      final tr = Transaction(d)..insertBlockBefore(0, para('Hello'));

      expect(tr.doc.content.childCount, 2);
      expect(tr.doc.content.child(0).textContent, 'Hello');
      expect(tr.doc.content.child(1).textContent, 'World');
    });
  });
}
