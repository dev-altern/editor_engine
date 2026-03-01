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
      expect(
        () => receiveSteps(state, 0, [step], []),
        throwsArgumentError,
      );
    });
  });
}
