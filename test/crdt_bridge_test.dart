import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

// ── Mock implementations ──────────────────────────────────────────────────

class MockCrdtOp extends CrdtOp {
  MockCrdtOp(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;

  @override
  Map<String, dynamic> toJson() => {'type': type, ...data};
}

class MockCrdtBridge implements CrdtBridge {
  final List<Map<String, dynamic>> appliedOps = [];
  Map<String, dynamic> _snapshot = {};

  @override
  List<CrdtOp> transactionToCrdtOps(Transaction tr, EditorState stateBefore) {
    if (!tr.hasSteps) return [];
    return [
      MockCrdtOp('edit', {'stepCount': tr.steps.length}),
    ];
  }

  @override
  Transaction? crdtOpsToTransaction(
    List<CrdtOp> ops,
    EditorState currentState,
  ) {
    if (ops.isEmpty) return null;
    for (final op in ops) {
      appliedOps.add(op.toJson());
    }
    // Return a no-op transaction for testing.
    return currentState.transaction;
  }

  @override
  Map<String, dynamic> get snapshot => _snapshot;

  @override
  void loadSnapshot(Map<String, dynamic> snapshot) {
    _snapshot = Map.of(snapshot);
  }
}

class MockAwarenessBridge implements CrdtAwarenessBridge {
  @override
  Map<String, dynamic> encodeLocalAwareness(AwarenessState state) => {
    'clientId': state.localUser?.clientId ?? '',
    'cursor': state.localCursor?.toJson(),
  };

  @override
  AwarenessPeer decodeRemoteAwareness(Map<String, dynamic> data) =>
      AwarenessPeer(
        user: AwarenessUser(
          clientId: data['clientId'] as String,
          name: data['name'] as String? ?? 'Unknown',
        ),
        cursor: data['cursor'] != null
            ? AwarenessCursor.fromJson(data['cursor'] as Map<String, dynamic>)
            : null,
      );

  @override
  void onPeerDisconnect(String clientId) {
    // no-op for tests
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('CrdtOp', () {
    test('toJson serializes', () {
      final op = MockCrdtOp('insert', {'pos': 5, 'text': 'hello'});
      final json = op.toJson();
      expect(json['type'], 'insert');
      expect(json['pos'], 5);
      expect(json['text'], 'hello');
    });
  });

  group('CrdtBridge', () {
    late MockCrdtBridge bridge;
    late EditorState state;

    setUp(() {
      bridge = MockCrdtBridge();
      state = EditorState.create(
        schema: basicSchema,
        doc: doc([para('Hello world')]),
      );
    });

    test('transactionToCrdtOps returns ops for transactions with steps', () {
      final tr = state.transaction..insertText(1, 'X');
      final ops = bridge.transactionToCrdtOps(tr, state);
      expect(ops.length, 1);
      expect((ops[0] as MockCrdtOp).type, 'edit');
    });

    test('transactionToCrdtOps returns empty for selection-only', () {
      final tr = state.transaction..setSelection(TextSelection.collapsed(3));
      final ops = bridge.transactionToCrdtOps(tr, state);
      expect(ops, isEmpty);
    });

    test('crdtOpsToTransaction creates transaction from ops', () {
      final ops = [
        MockCrdtOp('insert', {'text': 'X'}),
      ];
      final tr = bridge.crdtOpsToTransaction(ops, state);
      expect(tr, isNotNull);
      expect(bridge.appliedOps.length, 1);
    });

    test('crdtOpsToTransaction returns null for empty ops', () {
      final tr = bridge.crdtOpsToTransaction([], state);
      expect(tr, isNull);
    });

    test('snapshot / loadSnapshot round-trip', () {
      bridge.loadSnapshot({'version': 1, 'data': 'test'});
      expect(bridge.snapshot['version'], 1);
      expect(bridge.snapshot['data'], 'test');
    });
  });

  group('CrdtAwarenessBridge', () {
    late MockAwarenessBridge bridge;

    setUp(() {
      bridge = MockAwarenessBridge();
    });

    test('encodeLocalAwareness', () {
      final state = AwarenessState(
        localUser: AwarenessUser(clientId: 'local', name: 'Me'),
        localCursor: AwarenessCursor(anchor: 5, head: 10),
      );
      final encoded = bridge.encodeLocalAwareness(state);
      expect(encoded['clientId'], 'local');
      expect(encoded['cursor'], isNotNull);
    });

    test('decodeRemoteAwareness', () {
      final peer = bridge.decodeRemoteAwareness({
        'clientId': 'c1',
        'name': 'Alice',
        'cursor': {'anchor': 3, 'head': 7},
      });
      expect(peer.user.clientId, 'c1');
      expect(peer.user.name, 'Alice');
      expect(peer.cursor!.anchor, 3);
      expect(peer.cursor!.head, 7);
    });

    test('decodeRemoteAwareness without cursor', () {
      final peer = bridge.decodeRemoteAwareness({
        'clientId': 'c1',
        'name': 'Bob',
      });
      expect(peer.cursor, isNull);
    });
  });
}
