import 'package:test/test.dart';
import 'package:editor_engine/editor_engine.dart';

import 'helpers.dart';

void main() {
  // ── AwarenessCursor ───────────────────────────────────────────────────

  group('AwarenessCursor', () {
    test('collapsed cursor', () {
      final c = AwarenessCursor.collapsed(5);
      expect(c.anchor, 5);
      expect(c.head, 5);
      expect(c.isCollapsed, true);
      expect(c.from, 5);
      expect(c.to, 5);
    });

    test('range cursor', () {
      final c = AwarenessCursor(anchor: 5, head: 10);
      expect(c.isCollapsed, false);
      expect(c.from, 5);
      expect(c.to, 10);
    });

    test('backward range cursor', () {
      final c = AwarenessCursor(anchor: 10, head: 5);
      expect(c.from, 5);
      expect(c.to, 10);
    });

    test('mapThrough shifts positions', () {
      final c = AwarenessCursor(anchor: 5, head: 10);
      final mapping = Mapping.from([StepMap.simple(0, 0, 3)]);
      final mapped = c.mapThrough(mapping)!;
      expect(mapped.anchor, 8);
      expect(mapped.head, 13);
    });

    test('mapThrough returns same when unchanged', () {
      final c = AwarenessCursor(anchor: 5, head: 10);
      final mapping = Mapping.from([StepMap.simple(15, 0, 3)]);
      final mapped = c.mapThrough(mapping)!;
      expect(identical(mapped, c), true);
    });

    test('toJson / fromJson round-trip', () {
      final c = AwarenessCursor(anchor: 3, head: 12);
      final json = c.toJson();
      final restored = AwarenessCursor.fromJson(json);
      expect(restored, equals(c));
    });

    test('equality', () {
      final a = AwarenessCursor(anchor: 5, head: 10);
      final b = AwarenessCursor(anchor: 5, head: 10);
      final c = AwarenessCursor(anchor: 5, head: 11);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // ── AwarenessUser ─────────────────────────────────────────────────────

  group('AwarenessUser', () {
    test('creates with defaults', () {
      final u = AwarenessUser(clientId: 'c1', name: 'Alice');
      expect(u.color, '#000000');
      expect(u.avatarUrl, isNull);
    });

    test('toJson / fromJson round-trip', () {
      final u = AwarenessUser(
        clientId: 'c1',
        name: 'Alice',
        color: '#ff0000',
        avatarUrl: 'https://example.com/avatar.png',
      );
      final json = u.toJson();
      final restored = AwarenessUser.fromJson(json);
      expect(restored, equals(u));
    });

    test('toJson omits null avatarUrl', () {
      final u = AwarenessUser(clientId: 'c1', name: 'Alice');
      expect(u.toJson().containsKey('avatarUrl'), false);
    });

    test('equality', () {
      final a = AwarenessUser(clientId: 'c1', name: 'Alice');
      final b = AwarenessUser(clientId: 'c1', name: 'Alice');
      expect(a, equals(b));
    });
  });

  // ── AwarenessPeer ─────────────────────────────────────────────────────

  group('AwarenessPeer', () {
    test('creates with optional cursor', () {
      final user = AwarenessUser(clientId: 'c1', name: 'Alice');
      final peer = AwarenessPeer(user: user);
      expect(peer.cursor, isNull);
    });

    test('withCursor returns new peer', () {
      final user = AwarenessUser(clientId: 'c1', name: 'Alice');
      final peer = AwarenessPeer(user: user);
      final withCursor = peer.withCursor(AwarenessCursor(anchor: 5, head: 10));
      expect(withCursor.cursor!.anchor, 5);
      expect(peer.cursor, isNull); // original unchanged
    });

    test('toJson / fromJson round-trip', () {
      final peer = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
        cursor: AwarenessCursor(anchor: 5, head: 10),
      );
      final json = peer.toJson();
      final restored = AwarenessPeer.fromJson(json);
      expect(restored, equals(peer));
    });

    test('toJson omits null cursor', () {
      final peer = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
      );
      expect(peer.toJson().containsKey('cursor'), false);
    });
  });

  // ── AwarenessState ────────────────────────────────────────────────────

  group('AwarenessState', () {
    test('empty state', () {
      const state = AwarenessState();
      expect(state.peers, isEmpty);
      expect(state.localUser, isNull);
      expect(state.localCursor, isNull);
    });

    test('withPeer adds a peer', () {
      const state = AwarenessState();
      final peer = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
        cursor: AwarenessCursor.collapsed(5),
      );
      final updated = state.withPeer('c1', peer);
      expect(updated.peers.length, 1);
      expect(updated.peers['c1']!.user.name, 'Alice');
    });

    test('withPeer replaces existing peer', () {
      const state = AwarenessState();
      final peer1 = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
        cursor: AwarenessCursor.collapsed(5),
      );
      final peer2 = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
        cursor: AwarenessCursor.collapsed(10),
      );
      final s1 = state.withPeer('c1', peer1);
      final s2 = s1.withPeer('c1', peer2);
      expect(s2.peers.length, 1);
      expect(s2.peers['c1']!.cursor!.anchor, 10);
    });

    test('withoutPeer removes a peer', () {
      const state = AwarenessState();
      final peer = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
      );
      final added = state.withPeer('c1', peer);
      final removed = added.withoutPeer('c1');
      expect(removed.peers, isEmpty);
    });

    test('withoutPeer returns same when not found', () {
      const state = AwarenessState();
      final same = state.withoutPeer('nonexistent');
      expect(identical(same, state), true);
    });

    test('withLocalCursor', () {
      const state = AwarenessState();
      final updated = state.withLocalCursor(AwarenessCursor.collapsed(7));
      expect(updated.localCursor!.anchor, 7);
    });

    test('mapThrough shifts peer cursors', () {
      const state = AwarenessState();
      final peer = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
        cursor: AwarenessCursor(anchor: 5, head: 10),
      );
      final s = state
          .withPeer('c1', peer)
          .withLocalCursor(AwarenessCursor.collapsed(3));

      // Insert 2 chars at pos 0.
      final mapping = Mapping.from([StepMap.simple(0, 0, 2)]);
      final mapped = s.mapThrough(mapping);
      expect(mapped.peers['c1']!.cursor!.anchor, 7);
      expect(mapped.peers['c1']!.cursor!.head, 12);
      expect(mapped.localCursor!.anchor, 5);
    });

    test('mapThrough returns same when nothing changes', () {
      const state = AwarenessState();
      final peer = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
        cursor: AwarenessCursor(anchor: 5, head: 10),
      );
      final s = state.withPeer('c1', peer);
      // Edit after all cursors — no change.
      final mapping = Mapping.from([StepMap.simple(20, 0, 3)]);
      final mapped = s.mapThrough(mapping);
      expect(identical(mapped, s), true);
    });

    test('mapThrough sets peer cursor to null on deletion', () {
      const state = AwarenessState();
      final peer = AwarenessPeer(
        user: AwarenessUser(clientId: 'c1', name: 'Alice'),
        cursor: AwarenessCursor(anchor: 5, head: 10),
      );
      final s = state.withPeer('c1', peer);
      // Delete range 3..12 which contains the entire cursor range.
      final mapping = Mapping.from([StepMap.simple(3, 9, 0)]);
      final mapped = s.mapThrough(mapping);
      // mapOrNull returns null for deleted positions, so cursor becomes null.
      expect(mapped.peers['c1']!.cursor, isNull);
    });

    test('toJson / fromJson round-trip', () {
      final state = AwarenessState(
        localUser: AwarenessUser(clientId: 'local', name: 'Me'),
        localCursor: AwarenessCursor(anchor: 3, head: 8),
        peers: {
          'c1': AwarenessPeer(
            user: AwarenessUser(clientId: 'c1', name: 'Alice'),
            cursor: AwarenessCursor.collapsed(5),
          ),
        },
      );
      final json = state.toJson();
      final restored = AwarenessState.fromJson(json);
      expect(restored.localUser!.name, 'Me');
      expect(restored.localCursor!.anchor, 3);
      expect(restored.peers['c1']!.user.name, 'Alice');
      expect(restored.peers['c1']!.cursor!.anchor, 5);
    });
  });

  // ── AwarenessPlugin ───────────────────────────────────────────────────

  group('AwarenessPlugin', () {
    late EditorState state;

    setUp(() {
      state = EditorState.create(
        schema: basicSchema,
        doc: doc([para('Hello world')]),
        plugins: [
          AwarenessPlugin(
            localUser: AwarenessUser(clientId: 'local', name: 'Me'),
          ),
        ],
      );
    });

    test('init creates state with local user', () {
      final awareness = state.pluginState<AwarenessState>('awareness');
      expect(awareness, isNotNull);
      expect(awareness!.localUser!.name, 'Me');
    });

    test('selection change updates local cursor', () {
      final tr = state.transaction..setSelection(TextSelection.collapsed(3));
      final newState = state.apply(tr);
      final awareness = newState.pluginState<AwarenessState>('awareness')!;
      expect(awareness.localCursor!.anchor, 3);
    });

    test('awarenessUpdate adds remote peer', () {
      final tr = state.transaction
        ..setMeta('awarenessUpdate', {
          'clientId': 'c1',
          'user': {'clientId': 'c1', 'name': 'Alice', 'color': '#ff0000'},
          'cursor': {'anchor': 5, 'head': 10},
        });
      final newState = state.apply(tr);
      final awareness = newState.pluginState<AwarenessState>('awareness')!;
      expect(awareness.peers['c1']!.user.name, 'Alice');
      expect(awareness.peers['c1']!.cursor!.anchor, 5);
    });

    test('awarenessRemove removes peer', () {
      // First add a peer.
      var tr = state.transaction
        ..setMeta('awarenessUpdate', {
          'clientId': 'c1',
          'user': {'clientId': 'c1', 'name': 'Alice'},
          'cursor': {'anchor': 5, 'head': 5},
        });
      var s = state.apply(tr);

      // Then remove.
      tr = s.transaction..setMeta('awarenessRemove', 'c1');
      s = s.apply(tr);
      final awareness = s.pluginState<AwarenessState>('awareness')!;
      expect(awareness.peers.containsKey('c1'), false);
    });

    test('peer cursors shift through edits', () {
      // Add a remote peer.
      var tr = state.transaction
        ..setMeta('awarenessUpdate', {
          'clientId': 'c1',
          'user': {'clientId': 'c1', 'name': 'Alice'},
          'cursor': {'anchor': 5, 'head': 10},
        });
      var s = state.apply(tr);

      // Insert text before the peer's cursor.
      tr = s.transaction..insertText(1, 'Hi ');
      s = s.apply(tr);
      final awareness = s.pluginState<AwarenessState>('awareness')!;
      expect(awareness.peers['c1']!.cursor!.anchor, 8);
      expect(awareness.peers['c1']!.cursor!.head, 13);
    });
  });
}
