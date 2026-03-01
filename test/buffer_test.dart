import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

void main() {
  group('PieceTable', () {
    test('empty table', () {
      final pt = PieceTable();
      expect(pt.getText(), '');
      expect(pt.length, 0);
      expect(pt.lineCount, 1);
    });

    test('initial text', () {
      final pt = PieceTable('Hello World');
      expect(pt.getText(), 'Hello World');
      expect(pt.length, 11);
    });

    test('insert at beginning', () {
      final pt = PieceTable('World');
      pt.insert(0, 'Hello ');
      expect(pt.getText(), 'Hello World');
    });

    test('insert at end', () {
      final pt = PieceTable('Hello');
      pt.insert(5, ' World');
      expect(pt.getText(), 'Hello World');
    });

    test('insert in middle', () {
      final pt = PieceTable('Hllo');
      pt.insert(1, 'e');
      expect(pt.getText(), 'Hello');
    });

    test('delete from beginning', () {
      final pt = PieceTable('Hello World');
      pt.delete(0, 6);
      expect(pt.getText(), 'World');
    });

    test('delete from end', () {
      final pt = PieceTable('Hello World');
      pt.delete(5, 6);
      expect(pt.getText(), 'Hello');
    });

    test('delete from middle', () {
      final pt = PieceTable('Hello World');
      pt.delete(5, 1);
      expect(pt.getText(), 'HelloWorld');
    });

    test('replace', () {
      final pt = PieceTable('Hello World');
      pt.replace(5, 6, ' Dart');
      expect(pt.getText(), 'Hello Dart');
    });

    test('charAt', () {
      final pt = PieceTable('Hello');
      expect(pt.charAt(0), 'H');
      expect(pt.charAt(4), 'o');
    });

    test('getTextInRange', () {
      final pt = PieceTable('Hello World');
      expect(pt.getTextInRange(6, 5), 'World');
    });

    test('line tracking', () {
      final pt = PieceTable('Line1\nLine2\nLine3');
      expect(pt.lineCount, 3);
      expect(pt.lineAt(0), 0);
      expect(pt.lineAt(6), 1);
      expect(pt.lineAt(12), 2);
    });

    test('lineStart', () {
      final pt = PieceTable('Line1\nLine2\nLine3');
      expect(pt.lineStart(0), 0);
      expect(pt.lineStart(1), 6);
      expect(pt.lineStart(2), 12);
    });

    test('bounds checking on insert', () {
      final pt = PieceTable('Hello');
      expect(() => pt.insert(-1, 'X'), throwsRangeError);
      expect(() => pt.insert(6, 'X'), throwsRangeError);
    });

    test('bounds checking on delete', () {
      final pt = PieceTable('Hello');
      expect(() => pt.delete(-1, 1), throwsRangeError);
      expect(() => pt.delete(3, 5), throwsRangeError);
    });

    test('multiple edits promote to tree', () {
      final pt = PieceTable('Hello');
      for (var i = 0; i < 10; i++) {
        pt.insert(pt.length, ' more');
      }
      expect(pt.getText().startsWith('Hello'), true);
      expect(pt.length, 55);
    });

    test('snapshot and restore', () {
      final pt = PieceTable('Hello');
      final snap = pt.snapshot();
      pt.insert(5, ' World');
      expect(pt.getText(), 'Hello World');
      pt.restore(snap);
      expect(pt.getText(), 'Hello');
    });
  });
}
