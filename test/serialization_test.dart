import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  group('JsonSerializer', () {
    test('round-trips simple document', () {
      final d = doc([para('Hello'), para('World')]);
      final serializer = JsonSerializer();
      final json = serializer.serialize(d);
      final restored = serializer.deserialize(json);
      expect(restored, equals(d));
    });

    test('round-trips with marks', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('Hello ', marks: [Mark.bold]),
            TextNode('World'),
          ]),
        ),
      ]);
      final serializer = JsonSerializer();
      final json = serializer.serialize(d);
      final restored = serializer.deserialize(json);
      expect(restored.textContent, 'Hello World');
    });

    test('schema-aware deserialization preserves flags', () {
      final serializer = JsonSerializer(schema: basicSchema);
      final d = basicSchema.doc([
        basicSchema.block('paragraph', content: [basicSchema.text('Hi')]),
        basicSchema.block('image', attrs: {'src': 'img.png'}),
      ]);
      final json = serializer.serialize(d);
      final restored = serializer.deserialize(json);

      final image = restored.content.child(1);
      expect(image.isLeaf, true);
      expect(image.isAtom, true);
    });
  });

  group('HtmlSerializer', () {
    final html = HtmlSerializer();

    test('round-trips paragraph with bold and italic', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('Hello '),
            TextNode('bold', marks: [Mark.bold]),
            TextNode(' and '),
            TextNode('italic', marks: [Mark.italic]),
          ]),
        ),
      ]);
      final serialized = html.serialize(d);
      expect(serialized, contains('<strong>bold</strong>'));
      expect(serialized, contains('<em>italic</em>'));
      final restored = html.deserialize(serialized);
      expect(restored.content.childCount, 1);
      expect(restored.textContent, 'Hello bold and italic');
    });

    test('round-trips heading', () {
      final d = doc([heading('Title', level: 2)]);
      final serialized = html.serialize(d);
      expect(serialized, contains('<h2>'));
      final restored = html.deserialize(serialized);
      expect(restored.content.child(0).type, 'heading');
      expect(restored.textContent, 'Title');
    });

    test('round-trips code block', () {
      final d = doc([
        BlockNode(
          type: 'code_block',
          attrs: {'language': 'dart'},
          inlineContent: true,
          content: Fragment([TextNode('void main() {}')]),
        ),
      ]);
      final serialized = html.serialize(d);
      expect(serialized, contains('<pre'));
      final restored = html.deserialize(serialized);
      expect(restored.content.child(0).type, 'code_block');
    });

    test('round-trips blockquote', () {
      final d = doc([
        BlockNode(type: 'blockquote', content: Fragment([para('Quoted text')])),
      ]);
      final serialized = html.serialize(d);
      expect(serialized, contains('<blockquote>'));
      final restored = html.deserialize(serialized);
      expect(restored.content.child(0).type, 'blockquote');
      expect(restored.textContent, 'Quoted text');
    });

    test('round-trips link mark', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('Click ', marks: [Mark.link('https://example.com')]),
          ]),
        ),
      ]);
      final serialized = html.serialize(d);
      expect(serialized, contains('href="https://example.com"'));
      final restored = html.deserialize(serialized);
      final text = restored.content.child(0).content.child(0) as TextNode;
      expect(text.marks.hasMark('link'), true);
    });

    test('empty input returns doc with one paragraph', () {
      final restored = html.deserialize('');
      expect(restored.content.childCount, 1);
      expect(restored.content.child(0).type, 'paragraph');
    });

    test('whitespace-only input returns doc with one paragraph', () {
      final restored = html.deserialize('   \n  ');
      expect(restored.content.childCount, 1);
      expect(restored.content.child(0).type, 'paragraph');
    });

    test('round-trips horizontal rule', () {
      final d = doc([
        para('Before'),
        const BlockNode(type: 'horizontal_rule', isLeaf: true),
        para('After'),
      ]);
      final serialized = html.serialize(d);
      expect(serialized, contains('<hr'));
      final restored = html.deserialize(serialized);
      expect(restored.content.childCount, 3);
    });
  });

  group('MarkdownSerializer', () {
    final md = MarkdownSerializer();

    test('round-trips paragraph', () {
      final d = doc([para('Hello world')]);
      final serialized = md.serialize(d);
      expect(serialized, 'Hello world');
      final restored = md.deserialize(serialized);
      expect(restored.textContent, 'Hello world');
    });

    test('round-trips heading', () {
      final d = doc([heading('Title', level: 2)]);
      final serialized = md.serialize(d);
      expect(serialized, contains('## Title'));
      final restored = md.deserialize(serialized);
      expect(restored.content.child(0).type, 'heading');
      expect(restored.content.child(0).attrs['level'], 2);
    });

    test('round-trips bold and italic', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('normal '),
            TextNode('bold', marks: [Mark.bold]),
            TextNode(' and '),
            TextNode('italic', marks: [Mark.italic]),
          ]),
        ),
      ]);
      final serialized = md.serialize(d);
      expect(serialized, contains('**bold**'));
      expect(serialized, contains('*italic*'));
      final restored = md.deserialize(serialized);
      expect(restored.textContent, 'normal bold and italic');
    });

    test('round-trips code block', () {
      final d = doc([
        BlockNode(
          type: 'code_block',
          attrs: {'language': 'dart'},
          inlineContent: true,
          content: Fragment([TextNode('print("hi");')]),
        ),
      ]);
      final serialized = md.serialize(d);
      expect(serialized, contains('```dart'));
      final restored = md.deserialize(serialized);
      expect(restored.content.child(0).type, 'code_block');
    });

    test('round-trips blockquote', () {
      final d = doc([
        BlockNode(type: 'blockquote', content: Fragment([para('Quoted')])),
      ]);
      final serialized = md.serialize(d);
      expect(serialized, contains('> Quoted'));
      final restored = md.deserialize(serialized);
      expect(restored.content.child(0).type, 'blockquote');
    });

    test('round-trips horizontal rule', () {
      final d = doc([
        para('Before'),
        const BlockNode(type: 'horizontal_rule', isLeaf: true),
        para('After'),
      ]);
      final serialized = md.serialize(d);
      expect(serialized, contains('---'));
      final restored = md.deserialize(serialized);
      expect(restored.content.childCount, 3);
    });

    test('empty input returns doc with one paragraph', () {
      final restored = md.deserialize('');
      expect(restored.content.childCount, 1);
      expect(restored.content.child(0).type, 'paragraph');
    });

    test('round-trips strikethrough', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('deleted', marks: [Mark.strikethrough]),
          ]),
        ),
      ]);
      final serialized = md.serialize(d);
      expect(serialized, contains('~~deleted~~'));
      final restored = md.deserialize(serialized);
      final text = restored.content.child(0).content.child(0) as TextNode;
      expect(text.marks.hasMark('strikethrough'), true);
    });

    test('round-trips inline code', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('use '),
            TextNode('code()', marks: [Mark.code]),
          ]),
        ),
      ]);
      final serialized = md.serialize(d);
      expect(serialized, contains('`code()`'));
      final restored = md.deserialize(serialized);
      expect(restored.textContent, 'use code()');
    });

    test('round-trips inline widget via HTML comment', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('before '),
            InlineWidgetNode(widgetType: 'mention', attrs: {'userId': 'u123'}),
            TextNode(' after'),
          ]),
        ),
      ]);
      final serialized = md.serialize(d);
      expect(serialized, contains('<!-- widget:mention'));
      final restored = md.deserialize(serialized);
      final block = restored.content.child(0);
      var foundWidget = false;
      block.content.forEach((node, _, __) {
        if (node is InlineWidgetNode) {
          expect(node.widgetType, 'mention');
          expect(node.attrs['userId'], 'u123');
          foundWidget = true;
        }
      });
      expect(foundWidget, true);
    });
  });

  group('JsonSerializer — edge cases', () {
    final jsonSerializer = JsonSerializer();

    test('round-trips inline widget', () {
      final d = doc([
        BlockNode(
          type: 'paragraph',
          inlineContent: true,
          content: Fragment([
            TextNode('Hello '),
            InlineWidgetNode(widgetType: 'emoji', attrs: {'code': 'smile'}),
          ]),
        ),
      ]);
      final serialized = jsonSerializer.serialize(d);
      final restored = jsonSerializer.deserialize(serialized);
      final block = restored.content.child(0);
      var foundWidget = false;
      block.content.forEach((node, _, __) {
        if (node is InlineWidgetNode) {
          expect(node.widgetType, 'emoji');
          expect(node.attrs['code'], 'smile');
          foundWidget = true;
        }
      });
      expect(foundWidget, true);
    });

    test('round-trips nested list in blockquote', () {
      final d = doc([
        BlockNode(
          type: 'blockquote',
          content: Fragment([
            bulletList([
              listItem([para('Item 1')]),
              listItem([para('Item 2')]),
            ]),
          ]),
        ),
      ]);
      final serialized = jsonSerializer.serialize(d);
      final restored = jsonSerializer.deserialize(serialized);
      final bq = restored.content.child(0);
      expect(bq.type, 'blockquote');
      final list = bq.content.child(0);
      expect(list.type, 'bullet_list');
      expect(list.content.childCount, 2);
    });
  });

  group('HtmlSerializer — edge cases', () {
    final html = HtmlSerializer();

    test('round-trips bullet list', () {
      final d = doc([
        bulletList([
          listItem([para('Item 1')]),
          listItem([para('Item 2')]),
        ]),
      ]);
      final serialized = html.serialize(d);
      expect(serialized, contains('<ul>'));
      expect(serialized, contains('<li>'));
      final restored = html.deserialize(serialized);
      expect(restored.content.child(0).type, 'bullet_list');
    });

    test('round-trips image', () {
      final d = doc([
        BlockNode(
          type: 'image',
          attrs: {'src': 'photo.jpg', 'alt': 'A photo'},
          isLeaf: true,
          isAtom: true,
        ),
      ]);
      final serialized = html.serialize(d);
      expect(serialized, contains('<img'));
      expect(serialized, contains('photo.jpg'));
      final restored = html.deserialize(serialized);
      expect(restored.content.child(0).type, 'image');
    });
  });
}
