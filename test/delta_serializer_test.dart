import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  final serializer = DeltaSerializer();

  group('DeltaSerializer — serialize', () {
    test('plain paragraph', () {
      final d = doc([para('Hello world')]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {'insert': 'Hello world'},
        {'insert': '\n'},
      ]);
    });

    test('paragraph with bold mark', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('Hello '),
            TextNode('bold', marks: [Mark.bold]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {'insert': 'Hello '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);
    });

    test('multiple marks', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('styled', marks: [Mark.bold, Mark.italic]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[0]['attributes'], containsPair('bold', true));
      expect(ops[0]['attributes'], containsPair('italic', true));
    });

    test('heading', () {
      final d = doc([heading('Title', level: 2)]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
      ]);
    });

    test('code block', () {
      final d = doc([
        BlockNode(
          type: 'code_block',
          attrs: {'language': 'dart'},
          inlineContent: true,
          content: Fragment([TextNode('void main() {}')]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {'insert': 'void main() {}'},
        {
          'insert': '\n',
          'attributes': {'code-block': 'dart'},
        },
      ]);
    });

    test('code block without language', () {
      final d = doc([
        BlockNode(
          type: 'code_block',
          inlineContent: true,
          content: Fragment([TextNode('code')]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[1]['attributes'], containsPair('code-block', true));
    });

    test('blockquote wrapping paragraph', () {
      final d = doc([
        blockquote([para('Quoted text')]),
      ]);
      final ops = serializer.serialize(d);
      // Blockquote contains a paragraph — serialization recurses into it.
      expect(ops[0], {'insert': 'Quoted text'});
      expect(ops[1], {'insert': '\n'});
    });

    test('list item', () {
      final d = doc([
        bulletList([
          listItem([para('Item 1')]),
        ]),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[0], {'insert': 'Item 1'});
      // list_item emits trailing \n with list attrs.
      // But since list_item contains a paragraph, the paragraph emits \n.
      expect(ops[1], {'insert': '\n'});
    });

    test('image', () {
      final d = doc([
        BlockNode(
          type: 'image',
          attrs: {'src': 'https://example.com/img.png'},
          isLeaf: true,
          isAtom: true,
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {
          'insert': {'image': 'https://example.com/img.png'},
        },
      ]);
    });

    test('horizontal rule', () {
      final d = doc([const BlockNode(type: 'horizontal_rule', isLeaf: true)]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {
          'insert': {'divider': true},
        },
      ]);
    });

    test('link mark', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('click here', marks: [Mark.link('https://example.com')]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[0]['attributes'], containsPair('link', 'https://example.com'));
    });

    test('strikethrough mark', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('crossed', marks: [Mark.strikethrough]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[0]['attributes'], containsPair('strike', true));
    });

    test('color mark', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('red text', marks: [Mark.color('#ff0000')]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[0]['attributes'], containsPair('color', '#ff0000'));
    });

    test('highlight mark', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('highlighted', marks: [Mark.highlight('yellow')]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[0]['attributes'], containsPair('background', 'yellow'));
    });

    test('superscript and subscript marks', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('sup', marks: [Mark.superscript]),
            TextNode('sub', marks: [Mark.subscript]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[0]['attributes'], containsPair('script', 'super'));
      expect(ops[1]['attributes'], containsPair('script', 'sub'));
    });

    test('check item checked', () {
      final d = doc([
        BlockNode(
          type: 'check_item',
          attrs: {'checked': true},
          inlineContent: true,
          content: Fragment([TextNode('Done')]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[1]['attributes'], containsPair('list', 'checked'));
    });

    test('check item unchecked', () {
      final d = doc([
        BlockNode(
          type: 'check_item',
          attrs: {'checked': false},
          inlineContent: true,
          content: Fragment([TextNode('Todo')]),
        ),
      ]);
      final ops = serializer.serialize(d);
      expect(ops[1]['attributes'], containsPair('list', 'unchecked'));
    });

    test('empty paragraph', () {
      final d = doc([emptyPara()]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {'insert': '\n'},
      ]);
    });

    test('multiple paragraphs', () {
      final d = doc([para('First'), para('Second')]);
      final ops = serializer.serialize(d);
      expect(ops, [
        {'insert': 'First'},
        {'insert': '\n'},
        {'insert': 'Second'},
        {'insert': '\n'},
      ]);
    });
  });

  group('DeltaSerializer — deserialize', () {
    test('plain text', () {
      final d = serializer.deserialize([
        {'insert': 'Hello world\n'},
      ]);
      expect(d.content.childCount, 1);
      expect(d.content.child(0).type, 'paragraph');
      expect(d.content.child(0).textContent, 'Hello world');
    });

    test('bold text', () {
      final d = serializer.deserialize([
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);
      final block = d.content.child(0);
      final text = block.content.child(0) as TextNode;
      expect(text.marks.hasMark('bold'), true);
    });

    test('heading from header attribute', () {
      final d = serializer.deserialize([
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
      ]);
      final block = d.content.child(0);
      expect(block.type, 'heading');
      expect(block.attrs['level'], 2);
      expect(block.textContent, 'Title');
    });

    test('code block', () {
      final d = serializer.deserialize([
        {'insert': 'print("hi")'},
        {
          'insert': '\n',
          'attributes': {'code-block': 'python'},
        },
      ]);
      final block = d.content.child(0);
      expect(block.type, 'code_block');
      expect(block.attrs['language'], 'python');
    });

    test('blockquote', () {
      final d = serializer.deserialize([
        {'insert': 'Quoted'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ]);
      final block = d.content.child(0);
      expect(block.type, 'blockquote');
      expect(block.content.child(0).type, 'paragraph');
      expect(block.content.child(0).textContent, 'Quoted');
    });

    test('bullet list', () {
      final d = serializer.deserialize([
        {'insert': 'Item'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]);
      final block = d.content.child(0);
      expect(block.type, 'bullet_list');
      final item = block.content.child(0);
      expect(item.type, 'list_item');
    });

    test('ordered list', () {
      final d = serializer.deserialize([
        {'insert': 'First'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
      ]);
      final block = d.content.child(0);
      expect(block.type, 'ordered_list');
    });

    test('checklist items', () {
      final d = serializer.deserialize([
        {'insert': 'Done'},
        {
          'insert': '\n',
          'attributes': {'list': 'checked'},
        },
        {'insert': 'Todo'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
      ]);
      // Consecutive check items are merged into one check_list.
      final list = d.content.child(0);
      expect(list.type, 'check_list');
      expect(list.content.childCount, 2);
      expect(list.content.child(0).attrs['checked'], true);
      expect(list.content.child(1).attrs['checked'], false);
    });

    test('image embed', () {
      final d = serializer.deserialize([
        {
          'insert': {'image': 'https://example.com/img.png'},
        },
      ]);
      final block = d.content.child(0);
      expect(block.type, 'image');
      expect(block.attrs['src'], 'https://example.com/img.png');
    });

    test('divider embed', () {
      final d = serializer.deserialize([
        {
          'insert': {'divider': true},
        },
      ]);
      final block = d.content.child(0);
      expect(block.type, 'horizontal_rule');
    });

    test('link mark', () {
      final d = serializer.deserialize([
        {
          'insert': 'click',
          'attributes': {'link': 'https://example.com'},
        },
        {'insert': '\n'},
      ]);
      final text = d.content.child(0).content.child(0) as TextNode;
      expect(text.marks.hasMark('link'), true);
      expect(text.marks.getMark('link')!.attrs['href'], 'https://example.com');
    });

    test('strikethrough mark', () {
      final d = serializer.deserialize([
        {
          'insert': 'deleted',
          'attributes': {'strike': true},
        },
        {'insert': '\n'},
      ]);
      final text = d.content.child(0).content.child(0) as TextNode;
      expect(text.marks.hasMark('strikethrough'), true);
    });

    test('color and background marks', () {
      final d = serializer.deserialize([
        {
          'insert': 'colored',
          'attributes': {'color': 'red', 'background': 'yellow'},
        },
        {'insert': '\n'},
      ]);
      final text = d.content.child(0).content.child(0) as TextNode;
      expect(text.marks.hasMark('color'), true);
      expect(text.marks.getMark('color')!.attrs['color'], 'red');
      expect(text.marks.hasMark('highlight'), true);
      expect(text.marks.getMark('highlight')!.attrs['color'], 'yellow');
    });

    test('script marks', () {
      final d = serializer.deserialize([
        {
          'insert': 'sup',
          'attributes': {'script': 'super'},
        },
        {
          'insert': 'sub',
          'attributes': {'script': 'sub'},
        },
        {'insert': '\n'},
      ]);
      final block = d.content.child(0);
      final sup = block.content.child(0) as TextNode;
      expect(sup.marks.hasMark('superscript'), true);
      final sub = block.content.child(1) as TextNode;
      expect(sub.marks.hasMark('subscript'), true);
    });

    test('empty ops produces empty paragraph', () {
      final d = serializer.deserialize([]);
      expect(d.content.childCount, 1);
      expect(d.content.child(0).type, 'paragraph');
    });

    test('text without trailing newline flushes', () {
      final d = serializer.deserialize([
        {'insert': 'No newline'},
      ]);
      expect(d.content.childCount, 1);
      expect(d.content.child(0).textContent, 'No newline');
    });

    test('multiple newlines in one insert', () {
      final d = serializer.deserialize([
        {'insert': 'Line1\nLine2\nLine3\n'},
      ]);
      expect(d.content.childCount, 3);
      expect(d.content.child(0).textContent, 'Line1');
      expect(d.content.child(1).textContent, 'Line2');
      expect(d.content.child(2).textContent, 'Line3');
    });
  });

  group('DeltaSerializer — round-trip', () {
    test('plain paragraphs round-trip', () {
      final original = doc([para('Hello'), para('World')]);
      final ops = serializer.serialize(original);
      final restored = serializer.deserialize(ops);
      expect(restored.content.childCount, 2);
      expect(restored.content.child(0).textContent, 'Hello');
      expect(restored.content.child(1).textContent, 'World');
    });

    test('heading round-trip', () {
      final original = doc([heading('Title', level: 3)]);
      final ops = serializer.serialize(original);
      final restored = serializer.deserialize(ops);
      expect(restored.content.child(0).type, 'heading');
      expect(restored.content.child(0).attrs['level'], 3);
      expect(restored.content.child(0).textContent, 'Title');
    });

    test('bold text round-trip', () {
      final original = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('normal '),
            TextNode('bold', marks: [Mark.bold]),
          ]),
        ),
      ]);
      final ops = serializer.serialize(original);
      final restored = serializer.deserialize(ops);
      final block = restored.content.child(0);
      expect(block.content.childCount, 2);
      final boldText = block.content.child(1) as TextNode;
      expect(boldText.text, 'bold');
      expect(boldText.marks.hasMark('bold'), true);
    });

    test('image round-trip', () {
      final original = doc([
        BlockNode(
          type: 'image',
          attrs: {'src': 'test.png'},
          isLeaf: true,
          isAtom: true,
        ),
      ]);
      final ops = serializer.serialize(original);
      final restored = serializer.deserialize(ops);
      expect(restored.content.child(0).type, 'image');
      expect(restored.content.child(0).attrs['src'], 'test.png');
    });

    test('divider round-trip', () {
      final original = doc([
        const BlockNode(type: 'horizontal_rule', isLeaf: true),
      ]);
      final ops = serializer.serialize(original);
      final restored = serializer.deserialize(ops);
      expect(restored.content.child(0).type, 'horizontal_rule');
    });
  });
}
