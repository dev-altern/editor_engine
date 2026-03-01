import 'package:meta/meta.dart';

import '../model/node.dart';
import '../state/editor_state.dart';
import '../state/selection.dart';
import '../transform/step_map.dart';
import '../transform/transaction.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AwarenessUser — Remote peer identity
// ─────────────────────────────────────────────────────────────────────────────

/// Identity information for a collaborative editing peer.
///
/// Includes the peer's display name and cursor color for rendering
/// remote cursors and presence indicators.
@immutable
class AwarenessUser {
  /// Creates an awareness user.
  const AwarenessUser({
    required this.clientId,
    required this.name,
    this.color = '#000000',
    this.avatarUrl,
  });

  /// The peer's unique client identifier.
  final String clientId;

  /// Display name for the peer.
  final String name;

  /// Cursor/selection color (CSS hex format).
  final String color;

  /// Optional avatar URL.
  final String? avatarUrl;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'name': name,
    'color': color,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  /// Deserializes from JSON.
  factory AwarenessUser.fromJson(Map<String, dynamic> json) => AwarenessUser(
    clientId: json['clientId'] as String,
    name: json['name'] as String,
    color: json['color'] as String? ?? '#000000',
    avatarUrl: json['avatarUrl'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AwarenessUser &&
          clientId == other.clientId &&
          name == other.name &&
          color == other.color &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(clientId, name, color, avatarUrl);

  @override
  String toString() => 'AwarenessUser($clientId, $name)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AwarenessCursor — A remote peer's cursor/selection
// ─────────────────────────────────────────────────────────────────────────────

/// A cursor position or selection range for a collaborative peer.
///
/// Maps through document edits to stay synchronized with the document state.
@immutable
class AwarenessCursor {
  /// Creates a cursor.
  const AwarenessCursor({required this.anchor, required this.head});

  /// Creates a collapsed cursor at [pos].
  const AwarenessCursor.collapsed(int pos) : anchor = pos, head = pos;

  /// The anchor position (where selection started).
  final int anchor;

  /// The head position (where selection ends / cursor is).
  final int head;

  /// Whether this is a collapsed cursor (no selection range).
  bool get isCollapsed => anchor == head;

  /// Start of the selection range.
  int get from => anchor < head ? anchor : head;

  /// End of the selection range.
  int get to => anchor > head ? anchor : head;

  /// Maps this cursor through a [Mapping].
  ///
  /// Returns `null` if the cursor position was deleted.
  AwarenessCursor? mapThrough(Mapping mapping) {
    final newAnchor = mapping.mapOrNull(anchor, assoc: -1);
    final newHead = mapping.mapOrNull(head, assoc: 1);
    if (newAnchor == null || newHead == null) return null;
    if (newAnchor == anchor && newHead == head) return this;
    return AwarenessCursor(anchor: newAnchor, head: newHead);
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {'anchor': anchor, 'head': head};

  /// Deserializes from JSON.
  factory AwarenessCursor.fromJson(Map<String, dynamic> json) =>
      AwarenessCursor(anchor: json['anchor'] as int, head: json['head'] as int);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AwarenessCursor && anchor == other.anchor && head == other.head;

  @override
  int get hashCode => Object.hash(anchor, head);

  @override
  String toString() => isCollapsed
      ? 'AwarenessCursor($anchor)'
      : 'AwarenessCursor($anchor..$head)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AwarenessPeer — Combined user + cursor for a single peer
// ─────────────────────────────────────────────────────────────────────────────

/// A remote peer's complete awareness state (identity + cursor).
@immutable
class AwarenessPeer {
  /// Creates a peer state.
  const AwarenessPeer({required this.user, this.cursor});

  /// The peer's identity.
  final AwarenessUser user;

  /// The peer's cursor, or null if the peer has no active selection.
  final AwarenessCursor? cursor;

  /// Returns a copy with an updated cursor.
  AwarenessPeer withCursor(AwarenessCursor? cursor) =>
      AwarenessPeer(user: user, cursor: cursor);

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    if (cursor != null) 'cursor': cursor!.toJson(),
  };

  /// Deserializes from JSON.
  factory AwarenessPeer.fromJson(Map<String, dynamic> json) => AwarenessPeer(
    user: AwarenessUser.fromJson(json['user'] as Map<String, dynamic>),
    cursor: json['cursor'] != null
        ? AwarenessCursor.fromJson(json['cursor'] as Map<String, dynamic>)
        : null,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AwarenessPeer && user == other.user && cursor == other.cursor;

  @override
  int get hashCode => Object.hash(user, cursor);

  @override
  String toString() => 'AwarenessPeer(${user.name}, $cursor)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AwarenessState — Full awareness state (local + remote peers)
// ─────────────────────────────────────────────────────────────────────────────

/// The complete awareness state for a collaborative editing session.
///
/// Tracks the local user's cursor and all remote peers' cursors.
/// Managed by [AwarenessPlugin] and stored in editor state under key
/// `'awareness'`.
@immutable
class AwarenessState {
  /// Creates an awareness state.
  const AwarenessState({
    this.peers = const {},
    this.localUser,
    this.localCursor,
  });

  /// Remote peers indexed by clientId.
  final Map<String, AwarenessPeer> peers;

  /// The local user's identity (set at initialization).
  final AwarenessUser? localUser;

  /// The local user's cursor (updated from selection each transaction).
  final AwarenessCursor? localCursor;

  /// Returns state with a peer added or updated.
  AwarenessState withPeer(String clientId, AwarenessPeer peer) =>
      AwarenessState(
        peers: {...peers, clientId: peer},
        localUser: localUser,
        localCursor: localCursor,
      );

  /// Returns state with a peer removed.
  AwarenessState withoutPeer(String clientId) {
    if (!peers.containsKey(clientId)) return this;
    return AwarenessState(
      peers: Map.of(peers)..remove(clientId),
      localUser: localUser,
      localCursor: localCursor,
    );
  }

  /// Returns state with the local cursor updated.
  AwarenessState withLocalCursor(AwarenessCursor? cursor) =>
      AwarenessState(peers: peers, localUser: localUser, localCursor: cursor);

  /// Maps all peer cursors through a [Mapping].
  ///
  /// Peers whose cursors are fully deleted keep their user info but
  /// lose their cursor position.
  AwarenessState mapThrough(Mapping mapping) {
    var changed = false;
    final newPeers = <String, AwarenessPeer>{};
    for (final entry in peers.entries) {
      final peer = entry.value;
      if (peer.cursor != null) {
        final mapped = peer.cursor!.mapThrough(mapping);
        if (mapped != peer.cursor) {
          newPeers[entry.key] = peer.withCursor(mapped);
          changed = true;
          continue;
        }
      }
      newPeers[entry.key] = peer;
    }

    AwarenessCursor? newLocal = localCursor;
    if (localCursor != null) {
      newLocal = localCursor!.mapThrough(mapping);
      if (newLocal != localCursor) changed = true;
    }

    if (!changed) return this;
    return AwarenessState(
      peers: newPeers,
      localUser: localUser,
      localCursor: newLocal,
    );
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    if (localUser != null) 'localUser': localUser!.toJson(),
    if (localCursor != null) 'localCursor': localCursor!.toJson(),
    'peers': {
      for (final entry in peers.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Deserializes from JSON.
  factory AwarenessState.fromJson(Map<String, dynamic> json) {
    final peersJson = json['peers'] as Map<String, dynamic>? ?? {};
    final peers = <String, AwarenessPeer>{};
    for (final entry in peersJson.entries) {
      peers[entry.key] = AwarenessPeer.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return AwarenessState(
      localUser: json['localUser'] != null
          ? AwarenessUser.fromJson(json['localUser'] as Map<String, dynamic>)
          : null,
      localCursor: json['localCursor'] != null
          ? AwarenessCursor.fromJson(
              json['localCursor'] as Map<String, dynamic>,
            )
          : null,
      peers: peers,
    );
  }

  @override
  String toString() =>
      'AwarenessState(local: ${localUser?.name}, ${peers.length} peers)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AwarenessPlugin — Plugin that manages awareness state
// ─────────────────────────────────────────────────────────────────────────────

/// Plugin that tracks collaborative awareness state (cursors and presence).
///
/// Access via: `state.pluginState<AwarenessState>('awareness')`
///
/// ## Transaction metadata protocol
///
/// - Selection changes on any transaction automatically update the local cursor.
/// - `'awarenessUpdate'` (`Map<String, dynamic>`) — Apply a remote peer update.
///   Expected format: `{'clientId': '...', 'user': {...}, 'cursor': {...}}`
/// - `'awarenessRemove'` (String) — Remove a peer by clientId (disconnect).
class AwarenessPlugin extends Plugin {
  /// Creates an awareness plugin with the local user's identity.
  AwarenessPlugin({required this.localUser});

  /// The local user's identity.
  final AwarenessUser localUser;

  @override
  String get key => 'awareness';

  @override
  Object init(DocNode doc, Selection selection) => AwarenessState(
    localUser: localUser,
    localCursor: AwarenessCursor(
      anchor: selection.anchor,
      head: selection.head,
    ),
  );

  @override
  Object apply(Transaction tr, Object? state, {Selection? selectionBefore}) {
    var awareness =
        state as AwarenessState? ?? AwarenessState(localUser: localUser);

    // Map remote cursors through document changes.
    if (tr.hasSteps) {
      awareness = awareness.mapThrough(tr.mapping);
    }

    // Update local cursor from transaction selection.
    final sel = tr.selection;
    if (sel != null) {
      awareness = awareness.withLocalCursor(
        AwarenessCursor(anchor: sel.anchor, head: sel.head),
      );
    }

    // Process remote awareness updates.
    final update = tr.getMeta('awarenessUpdate');
    if (update is Map<String, dynamic>) {
      final clientId = update['clientId'] as String?;
      if (clientId != null) {
        final peer = AwarenessPeer.fromJson(update);
        awareness = awareness.withPeer(clientId, peer);
      }
    }

    final removePeer = tr.getMeta('awarenessRemove');
    if (removePeer is String) {
      awareness = awareness.withoutPeer(removePeer);
    }

    return awareness;
  }
}
