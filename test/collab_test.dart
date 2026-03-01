import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  group('Collab', () {
    test('CollabPlugin tracks unconfirmed steps', () {
      final d = doc([para('Hello')]);
      final state = EditorState.create(
        schema: basicSchema,
        doc: d,
        plugins: [CollabPlugin(clientId: 'alice', version: 0)],
      );

      final tr = state.transaction..insertText(1, 'X');
      final newState = state.apply(tr);

      final collab = newState.pluginState<CollabState>('collab')!;
      expect(collab.unconfirmedSteps.length, 1);
      expect(collab.version, 0);
      expect(collab.clientId, 'alice');
    });

    test('sendableSteps returns pending steps', () {
      final d = doc([para('Hello')]);
      final state = EditorState.create(
        schema: basicSchema,
        doc: d,
        plugins: [CollabPlugin(clientId: 'alice', version: 0)],
      );

      expect(sendableSteps(state), isNull);

      final tr = state.transaction..insertText(1, 'X');
      final newState = state.apply(tr);

      final sendable = sendableSteps(newState);
      expect(sendable, isNotNull);
      expect(sendable!.steps.length, 1);
      expect(sendable.clientId, 'alice');
      expect(sendable.version, 0);
    });

    test('transformStep non-overlapping replaces', () {
      final d = doc([para('Hello world')]);
      final stepA = ReplaceStep(1, 1, Slice(Fragment([TextNode('X')]), 0, 0));
      final stepB = ReplaceStep(7, 7, Slice(Fragment([TextNode('Y')]), 0, 0));

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isNotNull);
      expect(transformed, isA<ReplaceStep>());
    });

    test('transformStep AddMarkStep adjusts positions', () {
      final d = doc([para('Hello world')]);
      final stepB = ReplaceStep(1, 1, Slice(Fragment([TextNode('XXX')]), 0, 0));
      final stepA = AddMarkStep(2, 6, Mark.bold);

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isNotNull);
      expect(transformed, isA<AddMarkStep>());
      final tMark = transformed as AddMarkStep;
      expect(tMark.from, 5);
      expect(tMark.to, 9);
    });

    test('Authority accepts steps and increments version', () {
      final d = doc([para('Hello')]);
      final authority = Authority(doc: d);

      expect(authority.version, 0);

      final step = ReplaceStep(1, 1, Slice(Fragment([TextNode('X')]), 0, 0));
      final result = authority.receiveSteps(0, [step], 'alice');

      expect(result, isNotNull);
      expect(authority.version, 1);
      expect(authority.doc.textContent, 'XHello');
    });

    test('Authority rejects steps from future version', () {
      final d = doc([para('Hello')]);
      final authority = Authority(doc: d);

      final step = ReplaceStep(1, 1, Slice(Fragment([TextNode('X')]), 0, 0));
      final result = authority.receiveSteps(5, [step], 'alice');

      expect(result, isNull);
      expect(authority.version, 0);
    });

    test('Authority transforms steps from behind client', () {
      final d = doc([para('Hello')]);
      final authority = Authority(doc: d);

      final stepA = ReplaceStep(1, 1, Slice(Fragment([TextNode('A')]), 0, 0));
      authority.receiveSteps(0, [stepA], 'alice');
      expect(authority.version, 1);

      final stepB = ReplaceStep(6, 6, Slice(Fragment([TextNode('B')]), 0, 0));
      final result = authority.receiveSteps(0, [stepB], 'bob');

      expect(result, isNotNull);
      expect(authority.version, 2);
      expect(authority.doc.textContent, contains('A'));
      expect(authority.doc.textContent, contains('B'));
    });

    test('receiveSteps validates clientIds length', () {
      final d = doc([para('Hello')]);
      final state = EditorState.create(
        schema: basicSchema,
        doc: d,
        plugins: [CollabPlugin(clientId: 'alice', version: 0)],
      );

      final step = ReplaceStep(1, 1, Slice(Fragment([TextNode('X')]), 0, 0));
      expect(() => receiveSteps(state, 0, [step], []), throwsArgumentError);
    });

    // ── Structure step transform tests ────────────────────────────────

    test('transformStep SplitStep over ReplaceStep', () {
      final d = doc([para('Hello world')]);
      // stepB inserts "XX" at pos 1.
      final stepB = ReplaceStep(1, 1, Slice(Fragment([TextNode('XX')]), 0, 0));
      // stepA splits at pos 6 (after "Hello").
      final stepA = SplitStep(6, depth: 1);

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isA<SplitStep>());
      final tSplit = transformed as SplitStep;
      expect(tSplit.pos, 8); // shifted by 2
      expect(tSplit.depth, 1);
    });

    test('transformStep JoinStep over ReplaceStep', () {
      final d = doc([para('Hello'), para('World')]);
      // stepB inserts at pos 1 in the first paragraph.
      final stepB = ReplaceStep(1, 1, Slice(Fragment([TextNode('X')]), 0, 0));
      // stepA joins at the boundary between paragraphs.
      // In doc [para('Hello'), para('World')], boundary is at pos 8
      // (1 open + 5 text + 1 close + 1 open = 8).
      final stepA = JoinStep(8, depth: 1);

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isA<JoinStep>());
      final tJoin = transformed as JoinStep;
      expect(tJoin.pos, 9); // shifted by 1
    });

    test('transformStep WrapStep over ReplaceStep', () {
      final d = doc([para('Hello world')]);
      // stepB inserts "X" at pos 1.
      final stepB = ReplaceStep(1, 1, Slice(Fragment([TextNode('X')]), 0, 0));
      // stepA wraps the paragraph (pos 0..13).
      final stepA = WrapStep(0, 13, 'blockquote');

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isA<WrapStep>());
      final tWrap = transformed as WrapStep;
      expect(tWrap.from, 0);
      expect(tWrap.to, 14); // shifted by 1
    });

    test('transformStep WrapStep collapse returns null', () {
      final d = doc([para('Hello world')]);
      // stepB deletes the entire content (pos 0..13).
      final stepB = ReplaceStep.delete(0, 13);
      // stepA wraps the same range.
      final stepA = WrapStep(0, 13, 'blockquote');

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isNull);
    });

    test('transformStep UnwrapStep over ReplaceStep', () {
      final d = doc([
        blockquote([para('Hello')]),
      ]);
      // stepB inserts "X" at pos 2 inside the blockquote paragraph.
      final stepB = ReplaceStep(2, 2, Slice(Fragment([TextNode('X')]), 0, 0));
      // stepA unwraps the blockquote at pos 0.
      final stepA = UnwrapStep(0, wrapperNodeSize: 9);

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isA<UnwrapStep>());
      final tUnwrap = transformed as UnwrapStep;
      expect(tUnwrap.pos, 0);
    });

    // ── ReplaceStep overlap cases ────────────────────────────────────

    test('transformStep overlapping replaces — A before B', () {
      final d = doc([para('Hello world')]);
      // A deletes positions 1..4 ("Hel")
      final stepA = ReplaceStep.delete(1, 4);
      // B deletes positions 3..7 ("lo w")
      final stepB = ReplaceStep.delete(3, 7);

      final transformed = transformStep(stepA, stepB, d);
      expect(transformed, isNotNull);
    });

    test('transformStep overlapping replaces — complete overlap', () {
      final d = doc([para('Hello world')]);
      // A deletes positions 1..6
      final stepA = ReplaceStep.delete(1, 6);
      // B deletes positions 1..6 (same range)
      final stepB = ReplaceStep.delete(1, 6);

      // Complete overlap: stepA's range already deleted by stepB.
      // Should return null or a collapsed no-op.
      transformStep(stepA, stepB, d);
    });

    // ── Multi-client scenario ────────────────────────────────────────

    test('Authority handles concurrent inserts from multiple clients', () {
      final d = doc([para('Hello')]);
      final authority = Authority(doc: d);

      // Alice inserts at position 1.
      final stepAlice = ReplaceStep(
        1,
        1,
        Slice(Fragment([TextNode('A')]), 0, 0),
      );
      authority.receiveSteps(0, [stepAlice], 'alice');
      expect(authority.version, 1);

      // Bob sends a step based on version 0 (before Alice's change).
      final stepBob = ReplaceStep(6, 6, Slice(Fragment([TextNode('B')]), 0, 0));
      final result = authority.receiveSteps(0, [stepBob], 'bob');
      expect(result, isNotNull);
      expect(authority.version, 2);

      // Both chars should be in the document.
      final text = authority.doc.textContent;
      expect(text, contains('A'));
      expect(text, contains('B'));
    });

    test('Authority handles concurrent inserts at same position', () {
      final d = doc([para('Hello')]);
      final authority = Authority(doc: d);

      final stepAlice = ReplaceStep(
        1,
        1,
        Slice(Fragment([TextNode('A')]), 0, 0),
      );
      authority.receiveSteps(0, [stepAlice], 'alice');

      // Bob also inserts at position 1, but based on v0.
      final stepBob = ReplaceStep(1, 1, Slice(Fragment([TextNode('B')]), 0, 0));
      final result = authority.receiveSteps(0, [stepBob], 'bob');
      expect(result, isNotNull);
      expect(authority.version, 2);
      // Both should exist.
      expect(authority.doc.textContent, contains('A'));
      expect(authority.doc.textContent, contains('B'));
    });
  });
}
