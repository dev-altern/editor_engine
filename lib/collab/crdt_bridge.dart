import '../state/editor_state.dart';
import '../transform/transaction.dart';
import 'awareness.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CrdtOp — Abstract CRDT operation
// ─────────────────────────────────────────────────────────────────────────────

/// A single CRDT operation.
///
/// Opaque to the editor engine — the concrete type depends on the CRDT
/// implementation (Yjs, Loro, Automerge, etc.). The editor engine only
/// requires that operations can be serialized to JSON for transport.
abstract class CrdtOp {
  /// Serializes this operation for transport.
  Map<String, dynamic> toJson();
}

// ─────────────────────────────────────────────────────────────────────────────
// CrdtBridge — Abstract bridge between editor transactions and CRDT ops
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract interface for bridging editor transactions to/from CRDT operations.
///
/// Implementations bind a specific CRDT library (e.g., y_crdt, loro_dart)
/// to the editor engine's transaction model. The bridge operates in two
/// directions:
///
/// 1. **Local edits:** [Transaction] → CRDT ops (for broadcast to peers)
/// 2. **Remote edits:** CRDT ops → [Transaction] (for local application)
///
/// Concrete implementations live in separate packages (e.g.,
/// `editor_engine_yjs`, `editor_engine_loro`).
///
/// ```dart
/// // Example usage pattern:
/// class YjsBridge implements CrdtBridge {
///   final YDoc _yDoc;
///
///   @override
///   List<CrdtOp> transactionToCrdtOps(Transaction tr, EditorState stateBefore) {
///     // Convert editor steps to Y.js operations
///   }
///
///   @override
///   Transaction? crdtOpsToTransaction(List<CrdtOp> ops, EditorState currentState) {
///     // Convert Y.js operations to editor transaction
///   }
///   // ...
/// }
/// ```
abstract class CrdtBridge {
  /// Converts a local editor transaction into CRDT operations.
  ///
  /// Called after a local edit is applied to [EditorState]. The returned
  /// ops should be broadcast to remote peers via the CRDT layer.
  ///
  /// Returns an empty list if the transaction produced no CRDT-relevant
  /// changes (e.g., selection-only changes).
  List<CrdtOp> transactionToCrdtOps(Transaction tr, EditorState stateBefore);

  /// Converts remote CRDT operations into an editor transaction.
  ///
  /// Called when the CRDT layer receives changes from remote peers.
  /// The returned transaction should be applied to the local [EditorState].
  ///
  /// Returns `null` if no document changes are needed.
  Transaction? crdtOpsToTransaction(List<CrdtOp> ops, EditorState currentState);

  /// The current CRDT document state as a serializable snapshot.
  ///
  /// Used for persistence and initial sync when a client connects.
  Map<String, dynamic> get snapshot;

  /// Initializes the CRDT state from a previously saved snapshot.
  void loadSnapshot(Map<String, dynamic> snapshot);
}

// ─────────────────────────────────────────────────────────────────────────────
// CrdtAwarenessBridge — Abstract bridge for awareness/presence state
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract interface for bridging awareness state through a CRDT layer.
///
/// Awareness data (cursors, presence) typically travels on a separate
/// channel from document operations, since it is ephemeral and high-frequency.
abstract class CrdtAwarenessBridge {
  /// Encodes local awareness state for broadcast to peers.
  Map<String, dynamic> encodeLocalAwareness(AwarenessState state);

  /// Decodes a remote peer's awareness update.
  AwarenessPeer decodeRemoteAwareness(Map<String, dynamic> data);

  /// Called when a remote peer disconnects.
  ///
  /// Implementations should clean up any CRDT-layer resources for the peer.
  void onPeerDisconnect(String clientId);
}
