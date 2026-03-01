import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  group('Node', () {
    test('TextNode has correct nodeSize', () {
      final text = TextNode('Hello');
      expect(text.nodeSize, 5);
      expect(text.isText, true);
      expect(text.isInline, true);
      expect(text.isLeaf, true);
    });

    test('BlockNode has correct nodeSize', () {
      final p = para('Hello');
      expect(p.nodeSize, 7);
      expect(p.isBlock, true);
      expect(p.isTextblock, true);
      expect(p.contentSize, 5);
    });

    test('DocNode has correct nodeSize', () {
      final d = doc([para('Hi'), para('World')]);
      expect(d.nodeSize, 13);
      expect(d.content.childCount, 2);
    });

    test('empty BlockNode is leaf', () {
      final hr = BlockNode(type: 'horizontal_rule', isLeaf: true);
      expect(hr.isLeaf, true);
      expect(hr.nodeSize, 1);
    });

    test('InlineWidgetNode has nodeSize 1', () {
      final widget = InlineWidgetNode(
        widgetType: 'mention',
        attrs: {'userId': '123'},
      );
      expect(widget.nodeSize, 1);
      expect(widget.isInline, true);
      expect(widget.isAtom, true);
      expect(widget.widgetType, 'mention');
    });

    test('textContent returns all text', () {
      final d = doc([para('Hello'), para('World')]);
      expect(d.textContent, 'HelloWorld');
    });

    test('Node equality works', () {
      final a = para('Hello');
      final b = para('Hello');
      expect(a, equals(b));
    });

    test('Node inequality on different text', () {
      final a = para('Hello');
      final b = para('World');
      expect(a, isNot(equals(b)));
    });
  });

  group('Fragment', () {
    test('computes size correctly', () {
      final frag = Fragment([TextNode('Hi'), TextNode('World')]);
      expect(frag.size, 7);
    });

    test('merges adjacent text nodes with same marks', () {
      final frag = Fragment([TextNode('He'), TextNode('llo')]);
      expect(frag.childCount, 1);
      expect((frag.children.first as TextNode).text, 'Hello');
    });

    test('does not merge text nodes with different marks', () {
      final frag = Fragment([
        TextNode('He', marks: [Mark.bold]),
        TextNode('llo'),
      ]);
      expect(frag.childCount, 2);
    });

    test('cut returns sub-fragment', () {
      final frag = Fragment([TextNode('Hello World')]);
      final cut = frag.cut(5, 11);
      expect(cut.childCount, 1);
      expect((cut.children.first as TextNode).text, ' World');
    });

    test('cut handles block nodes', () {
      final frag = Fragment([para('AB'), para('CD')]);
      final cut = frag.cut(1, 6);
      expect(cut.childCount, 2);
    });

    test('empty fragment is empty', () {
      expect(Fragment.empty.isEmpty, true);
      expect(Fragment.empty.size, 0);
    });

    test('replaceChild returns new fragment', () {
      final frag = Fragment([
        TextNode('A', marks: [Mark.bold]),
        TextNode('B'),
      ]);
      final replaced = frag.replaceChild(0, TextNode('X', marks: [Mark.bold]));
      expect((replaced.children.first as TextNode).text, 'X');
      expect((frag.children.first as TextNode).text, 'A');
    });

    test('fromJson round-trips', () {
      final frag = Fragment([
        TextNode('Hello'),
        TextNode('World', marks: [Mark.bold]),
      ]);
      final json = frag.toJson();
      final restored = Fragment.fromJson(json);
      expect(restored, equals(frag));
    });
  });

  group('Mark', () {
    test('equality works', () {
      expect(Mark.bold, equals(const Mark('bold')));
      expect(Mark.bold, isNot(equals(Mark.italic)));
    });

    test('link mark with attrs', () {
      final link = Mark.link('https://example.com', title: 'Example');
      expect(link.type, 'link');
      expect(link.attrs['href'], 'https://example.com');
      expect(link.attrs['title'], 'Example');
    });

    test('addMark adds and sorts', () {
      final marks = <Mark>[Mark.italic].addMark(Mark.bold);
      expect(marks.length, 2);
      expect(marks[0].type, 'bold');
      expect(marks[1].type, 'italic');
    });

    test('addMark replaces same type', () {
      final link1 = Mark.link('https://a.com');
      final link2 = Mark.link('https://b.com');
      final marks = [link1].addMark(link2);
      expect(marks.length, 1);
      expect(marks[0].attrs['href'], 'https://b.com');
    });

    test('removeMark removes by type', () {
      final marks = [Mark.bold, Mark.italic].removeMark('bold');
      expect(marks.length, 1);
      expect(marks[0].type, 'italic');
    });

    test('sameMarks compares correctly', () {
      expect(
        [Mark.bold, Mark.italic].sameMarks([Mark.bold, Mark.italic]),
        true,
      );
      expect([Mark.bold].sameMarks([Mark.italic]), false);
    });

    test('fromJson round-trips', () {
      final mark = Mark.link('https://example.com');
      final json = mark.toJson();
      final restored = Mark.fromJson(json);
      expect(restored, equals(mark));
    });
  });

  group('ResolvedPos', () {
    test('resolves position in simple doc', () {
      final d = doc([para('Hello')]);
      final pos = d.resolve(3);
      expect(pos.pos, 3);
      expect(pos.depth, 1);
      expect(pos.parent.type, 'paragraph');
    });

    test('resolves start of doc (before paragraph)', () {
      final d = doc([para('Hi')]);
      final pos = d.resolve(0);
      expect(pos.depth, 0);
    });

    test('resolves between paragraphs', () {
      final d = doc([para('AB'), para('CD')]);
      final pos = d.resolve(4);
      expect(pos.depth, 0);
      expect(pos.parentIndex, 1);
    });

    test('sharedDepth works', () {
      final d = doc([para('Hello')]);
      final from = d.resolve(1);
      expect(from.sharedDepth(5), 1);
    });

    test('sharedDepth across paragraphs is 0', () {
      final d = doc([para('AB'), para('CD')]);
      final from = d.resolve(1);
      expect(from.sharedDepth(5), 0);
    });

    test('end returns content end', () {
      final d = doc([para('Hello')]);
      final pos = d.resolve(1);
      expect(pos.end(1), 6);
    });

    test('throws on out of range', () {
      final d = doc([para('Hi')]);
      expect(() => d.resolve(100), throwsRangeError);
      expect(() => d.resolve(-1), throwsRangeError);
    });
  });

  group('Slice', () {
    test('empty slice', () {
      expect(Slice.empty.isEmpty, true);
      expect(Slice.empty.size, 0);
    });

    test('slice with content', () {
      final slice = Slice(Fragment([TextNode('Hi')]), 0, 0);
      expect(slice.size, 2);
      expect(slice.openStart, 0);
      expect(slice.openEnd, 0);
    });

    test('fromJson round-trips', () {
      final slice = Slice(Fragment([TextNode('Hi')]), 1, 0);
      final json = slice.toJson();
      final restored = Slice.fromJson(json);
      expect(restored, equals(slice));
    });
  });
}
