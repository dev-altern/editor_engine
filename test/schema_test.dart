import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

void main() {
  group('Schema', () {
    test('creates text nodes', () {
      final text = basicSchema.text('Hello');
      expect(text.text, 'Hello');
    });

    test('creates block nodes', () {
      final p = basicSchema.block(
        'paragraph',
        content: [basicSchema.text('Hi')],
      );
      expect(p.type, 'paragraph');
      expect(p.inlineContent, true);
    });

    test('creates headings with attrs', () {
      final h2 = basicSchema.block('heading', attrs: {'level': 2});
      expect(h2.attrs['level'], 2);
    });

    test('default attrs are applied', () {
      final h = basicSchema.block('heading');
      expect(h.attrs['level'], 1);
    });

    test('throws on unknown node type', () {
      expect(() => basicSchema.block('unknown'), throwsArgumentError);
    });

    test('validates content', () {
      final p = basicSchema.block(
        'paragraph',
        content: [basicSchema.text('Hi')],
      );
      expect(basicSchema.validateContent(p), true);
    });

    test('validates document', () {
      final d = basicSchema.doc([
        basicSchema.block('paragraph', content: [basicSchema.text('Hi')]),
      ]);
      expect(basicSchema.validateDocument(d), isEmpty);
    });

    test('allowsMark checks correctly', () {
      expect(basicSchema.allowsMark('paragraph', 'bold'), true);
      expect(basicSchema.allowsMark('code_block', 'bold'), false);
    });

    test('allowsChild checks correctly', () {
      expect(basicSchema.allowsChild('doc', 'paragraph'), true);
      expect(basicSchema.allowsChild('paragraph', 'text'), true);
      expect(basicSchema.allowsChild('paragraph', 'paragraph'), false);
    });

    test('mark exclusion', () {
      expect(basicSchema.marksExclude('code', [Mark.bold]), true);
      expect(basicSchema.marksExclude('bold', []), false);
    });

    test('ContentExpression handles choice groups', () {
      final expr = ContentExpression.parse('(heading|paragraph)+');
      expect(expr.elements.length, 1);
      expect(expr.elements[0].isChoice, true);
      expect(expr.elements[0].choices, ['heading', 'paragraph']);
    });

    test('ContentExpression handles spaces in parens', () {
      final expr = ContentExpression.parse('(heading | paragraph)+');
      expect(expr.elements.length, 1);
      expect(expr.elements[0].isChoice, true);
      expect(expr.elements[0].choices, ['heading', 'paragraph']);
    });
  });
}
