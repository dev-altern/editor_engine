import 'package:meta/meta.dart';

import '../model/node.dart';
import '../state/editor_state.dart';
import '../state/selection.dart';
import '../transform/step.dart';
import '../transform/step_map.dart';
import '../transform/transaction.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CollabState — Tracks collaborative state per client
// ─────────────────────────────────────────────────────────────────────────────

/// The collaborative editing state for a single client.
///
/// Tracks the last confirmed server version and any steps that have been
/// sent to the server but not yet confirmed. These unconfirmed steps need
/// to be rebased when remote changes arrive.
///
/// This state is managed by [CollabPlugin] and stored in the editor's
/// plugin state map under the key `'collab'`.
@immutable
class CollabState {
  /// Creates a collaborative state.
  const CollabState({
    required this.version,
    required this.clientId,
    this.unconfirmedSteps = const [],
    this.unconfirmedMaps = const [],
  });

  /// The last confirmed server version.
  ///
  /// This represents the version number of the most recent step that has
  /// been acknowledged by the authority. All unconfirmed steps are based
  /// on the document at this version.
  final int version;

  /// This client's unique identifier.
  ///
  /// Used to distinguish this client's steps from other clients' steps
  /// when receiving confirmed steps from the authority.
  final String clientId;

  /// Steps sent to the server but not yet confirmed.
  ///
  /// These steps have been applied locally but the authority has not yet
  /// acknowledged them. When remote steps arrive, these need to be
  /// rebased on top of the remote changes via operational transform.
  final List<Step> unconfirmedSteps;

  /// Maps for unconfirmed steps (for rebasing).
  ///
  /// Each map corresponds to the step at the same index in
  /// [unconfirmedSteps]. Used for position mapping during rebase.
  final List<StepMap> unconfirmedMaps;

  /// Number of unconfirmed steps pending.
  int get pendingCount => unconfirmedSteps.length;

  /// Whether there are unconfirmed steps.
  bool get hasPending => unconfirmedSteps.isNotEmpty;

  /// Returns a copy with updated fields.
  CollabState copyWith({
    int? version,
    String? clientId,
    List<Step>? unconfirmedSteps,
    List<StepMap>? unconfirmedMaps,
  }) =>
      CollabState(
        version: version ?? this.version,
        clientId: clientId ?? this.clientId,
        unconfirmedSteps: unconfirmedSteps ?? this.unconfirmedSteps,
        unconfirmedMaps: unconfirmedMaps ?? this.unconfirmedMaps,
      );

  @override
  String toString() =>
      'CollabState(v$version, client: $clientId, pending: $pendingCount)';
}

// ─────────────────────────────────────────────────────────────────────────────
// CollabPlugin — Plugin that tracks collab state
// ─────────────────────────────────────────────────────────────────────────────

/// Plugin that integrates collaborative editing into the editor state.
///
/// Tracks local steps that need to be sent to the authority, and manages
/// the confirmation/rebase cycle when remote steps arrive.
///
/// ## Transaction metadata protocol
///
/// The plugin responds to the `'collab'` metadata key on transactions:
///
/// - `'local'` — The transaction contains local user edits. Steps are
///   accumulated as unconfirmed and will be sent to the authority.
///
/// - `'receive'` — The transaction contains remote changes that have
///   already been applied. Steps are NOT accumulated (they came from
///   outside).
///
/// - `'confirm'` with `'confirmVersion'` and `'confirmCount'` — The
///   authority has confirmed some of our steps. Removes the confirmed
///   steps from the unconfirmed list and bumps the version.
///
/// Transactions without a `'collab'` metadata key are treated as local
/// edits by default (same as `'local'`).
class CollabPlugin extends Plugin {
  /// Creates a collab plugin for the given [clientId].
  ///
  /// [version] is the starting server version (default 0).
  CollabPlugin({required this.clientId, this.version = 0});

  /// This client's unique identifier.
  final String clientId;

  /// The initial server version.
  final int version;

  @override
  String get key => 'collab';

  @override
  Object init(DocNode doc, Selection selection) => CollabState(
        version: version,
        clientId: clientId,
      );

  @override
  Object? apply(Transaction tr, Object? state, {Selection? selectionBefore}) {
    final collab = state as CollabState? ??
        CollabState(version: version, clientId: clientId);

    final meta = tr.getMeta('collab');

    // Remote changes — do not accumulate steps.
    if (meta == 'receive') {
      return collab;
    }

    // Confirmation — remove confirmed steps and bump version.
    if (meta == 'confirm') {
      final confirmVersion = tr.getMeta('confirmVersion') as int?;
      final confirmCount = tr.getMeta('confirmCount') as int?;
      if (confirmVersion == null || confirmCount == null) return collab;

      final remaining = confirmCount < collab.unconfirmedSteps.length
          ? collab.unconfirmedSteps.sublist(confirmCount)
          : const <Step>[];
      final remainingMaps = confirmCount < collab.unconfirmedMaps.length
          ? collab.unconfirmedMaps.sublist(confirmCount)
          : const <StepMap>[];

      return collab.copyWith(
        version: confirmVersion,
        unconfirmedSteps: remaining,
        unconfirmedMaps: remainingMaps,
      );
    }

    // Rebase — replace unconfirmed steps after a rebase operation.
    if (meta == 'rebase') {
      final newVersion = tr.getMeta('rebaseVersion') as int?;
      final newUnconfirmed = tr.getMeta('rebaseSteps') as List<Step>?;
      final newMaps = tr.getMeta('rebaseMaps') as List<StepMap>?;

      return collab.copyWith(
        version: newVersion ?? collab.version,
        unconfirmedSteps: newUnconfirmed ?? const [],
        unconfirmedMaps: newMaps ?? const [],
      );
    }

    // Local edit (explicit 'local' or no collab metadata) — accumulate steps.
    if (!tr.hasSteps) return collab;

    return collab.copyWith(
      unconfirmedSteps: [...collab.unconfirmedSteps, ...tr.steps],
      unconfirmedMaps: [...collab.unconfirmedMaps, ...tr.maps],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReceiveResult — Result of receiving remote steps
// ─────────────────────────────────────────────────────────────────────────────

/// The result of receiving confirmed steps from the authority.
///
/// Contains the transaction that was applied to incorporate the remote
/// changes, and the new collaborative state after rebasing.
@immutable
class ReceiveResult {
  /// Creates a receive result.
  const ReceiveResult({required this.transaction, required this.newState});

  /// The transaction that incorporates the remote changes.
  final Transaction transaction;

  /// The new collaborative state after rebasing.
  final CollabState newState;
}

// ─────────────────────────────────────────────────────────────────────────────
// sendableSteps — Extracts steps to send to the authority
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the local unconfirmed steps that should be sent to the authority.
///
/// Returns a record containing the base [version], the [steps] to send,
/// and the [clientId], or `null` if there are no steps to send or no
/// collab state is available.
///
/// Example:
/// ```dart
/// final sendable = sendableSteps(state);
/// if (sendable != null) {
///   authority.receiveSteps(sendable.version, sendable.steps, sendable.clientId);
/// }
/// ```
({int version, List<Step> steps, String clientId})? sendableSteps(
    EditorState state) {
  final collab = state.pluginState<CollabState>('collab');
  if (collab == null || !collab.hasPending) return null;

  return (
    version: collab.version,
    steps: collab.unconfirmedSteps,
    clientId: collab.clientId,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// receiveSteps — Receives confirmed steps from the authority
// ─────────────────────────────────────────────────────────────────────────────

/// Receives confirmed steps from the authority and integrates them into
/// the editor state.
///
/// This is the core of the collaborative editing protocol:
///
/// 1. Separates received steps into "ours" (matching [clientIds]) and
///    "theirs" (from other clients).
///
/// 2. For our own steps: confirms them by removing from the unconfirmed
///    list and bumping the version.
///
/// 3. For others' steps: applies them to the document and rebases any
///    remaining unconfirmed local steps on top using operational transform.
///
/// Returns the new editor state with all changes applied, or `null` if
/// no collab state is available.
///
/// [state] — The current editor state.
/// [version] — The server version these steps start from.
/// [steps] — The confirmed steps from the authority.
/// [clientIds] — The client ID for each step (parallel to [steps]).
EditorState? receiveSteps(
  EditorState state,
  int version,
  List<Step> steps,
  List<String> clientIds,
) {
  final collab = state.pluginState<CollabState>('collab');
  if (collab == null) return null;
  if (clientIds.length != steps.length) {
    throw ArgumentError('clientIds.length (${clientIds.length}) must equal '
        'steps.length (${steps.length})');
  }

  // The new version after all received steps are applied.
  final newVersion = version + steps.length;

  // Separate our confirmed steps from others' steps.
  // Our steps are at the beginning of the received list (they were sent
  // first and confirmed in order).
  var ownCount = 0;
  for (var i = 0; i < steps.length; i++) {
    if (clientIds[i] == collab.clientId &&
        ownCount < collab.unconfirmedSteps.length) {
      ownCount++;
    } else {
      break;
    }
  }

  // The steps from other clients that we need to apply and rebase over.
  final remoteSteps = steps.sublist(ownCount);

  // Our unconfirmed steps that were NOT in the confirmed batch.
  final remainingUnconfirmed = ownCount < collab.unconfirmedSteps.length
      ? collab.unconfirmedSteps.sublist(ownCount)
      : <Step>[];
  final remainingMaps = ownCount < collab.unconfirmedMaps.length
      ? collab.unconfirmedMaps.sublist(ownCount)
      : <StepMap>[];

  // If there are no remote steps, just confirm our own.
  if (remoteSteps.isEmpty) {
    // No document changes needed — just update the collab state.
    final newCollab = CollabState(
      version: newVersion,
      clientId: collab.clientId,
      unconfirmedSteps: remainingUnconfirmed,
      unconfirmedMaps: remainingMaps,
    );

    return EditorState(
      doc: state.doc,
      selection: state.selection,
      schema: state.schema,
      plugins: state.plugins,
      pluginStates: {...state.pluginStates, 'collab': newCollab},
    );
  }

  // We have remote steps to integrate. First, undo our unconfirmed
  // steps, apply the remote steps, then rebase our remaining unconfirmed
  // steps on top.

  // Step 1: Compute the document without our unconfirmed steps.
  // We do this by inverting our unconfirmed steps against the current doc.
  var baseDoc = state.doc;

  // Invert remaining unconfirmed steps to get back to the common base.
  final invertedUnconfirmed = <Step>[];
  {
    // Walk backwards through remaining unconfirmed, computing inverses.
    var tempDoc = baseDoc;
    final inversions = <Step>[];

    // First, compute the document states going forward from the base
    // to be able to invert correctly.
    // We need to start from the state BEFORE the remaining unconfirmed
    // steps were applied. We can get there by inverting them in reverse.

    // Collect the intermediate docs for inversion.
    // We need docs BEFORE each unconfirmed step was applied.
    // Since steps are already applied in state.doc, we invert backwards.
    final docs = <DocNode>[baseDoc];
    for (var i = remainingUnconfirmed.length - 1; i >= 0; i--) {
      final inv = remainingUnconfirmed[i].invert(tempDoc);
      final result = inv.apply(tempDoc);
      if (result.isOk) {
        tempDoc = result.doc!;
        inversions.insert(0, inv);
        docs.insert(0, tempDoc);
      } else {
        // If inversion fails, we cannot undo — bail out with what we have.
        break;
      }
    }

    invertedUnconfirmed.addAll(inversions);
    baseDoc = tempDoc;
  }

  // Step 2: Apply remote steps to the base document.
  var remoteDoc = baseDoc;
  final appliedRemoteMaps = <StepMap>[];
  final appliedRemoteSteps = <Step>[];
  for (final step in remoteSteps) {
    final result = step.apply(remoteDoc);
    if (result.isOk) {
      remoteDoc = result.doc!;
      appliedRemoteMaps.add(step.getMap());
      appliedRemoteSteps.add(step);
    }
    // If a remote step fails, skip it. The authority already accepted it,
    // so failure here indicates a local state inconsistency.
  }

  // Step 3: Rebase remaining unconfirmed steps on top of the remote changes.
  final rebasedSteps = <Step>[];
  final rebasedMaps = <StepMap>[];
  var rebaseDoc = remoteDoc;

  if (remainingUnconfirmed.isNotEmpty) {
    // Transform each unconfirmed step over all the remote steps.
    var currentSteps = List<Step>.of(remainingUnconfirmed);
    currentSteps = transformSteps(currentSteps, appliedRemoteSteps, baseDoc);

    // Apply the transformed steps.
    for (final step in currentSteps) {
      final result = step.apply(rebaseDoc);
      if (result.isOk) {
        rebaseDoc = result.doc!;
        rebasedSteps.add(step);
        rebasedMaps.add(step.getMap());
      }
      // If a rebased step fails, drop it — the conflict was unresolvable.
    }
  }

  // Step 4: Build the transaction that represents all changes.
  // We construct the transaction to go from state.doc -> rebaseDoc.
  // This uses the inverted unconfirmed + remote + rebased steps.
  final tr = Transaction(state.doc)
    ..setMeta('collab', 'receive')
    ..setMeta('addToHistory', false);

  // Apply inverted unconfirmed steps (undo local changes).
  for (final step in invertedUnconfirmed) {
    tr.addStep(step);
  }

  // Apply remote steps.
  for (final step in appliedRemoteSteps) {
    tr.addStep(step);
  }

  // Apply rebased local steps.
  for (final step in rebasedSteps) {
    tr.addStep(step);
  }

  // Step 5: Map selection through the changes.
  // The transaction already maps the selection through each step as it is
  // added, so the final selection in the applied state will be correct.

  // Step 6: Build the new collab state.
  final newCollab = CollabState(
    version: newVersion,
    clientId: collab.clientId,
    unconfirmedSteps: rebasedSteps,
    unconfirmedMaps: rebasedMaps,
  );

  // Step 7: Apply the transaction to get the new editor state.
  final newState = state.apply(tr);

  return EditorState(
    doc: newState.doc,
    selection: newState.selection,
    schema: state.schema,
    plugins: state.plugins,
    pluginStates: {...newState.pluginStates, 'collab': newCollab},
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Step transform utilities — Operational Transform (OT) core
// ─────────────────────────────────────────────────────────────────────────────

/// Transforms [stepA] so that it can be applied after [stepB].
///
/// This is the core operational transform (OT) function. Given two steps
/// that were both intended to apply to the same document state, it returns
/// a transformed version of [stepA] that produces the correct result when
/// applied after [stepB].
///
/// Returns `null` if the transform fails (e.g., an unresolvable conflict
/// where both steps modify the exact same content in incompatible ways).
///
/// [doc] is the document state that both steps were originally intended
/// to apply to.
///
/// ## Transform rules for ReplaceStep
///
/// - **Non-overlapping**: Adjust positions using [stepB]'s step map.
/// - **Overlapping**: [stepB] takes priority for the overlapping region.
///   [stepA] is adjusted to only affect the non-overlapping portion.
///
/// ## Transform rules for AddMarkStep / RemoveMarkStep
///
/// - Adjust the `from` and `to` positions through [stepB]'s step map.
///
/// ## Transform rules for SetAttrStep
///
/// - Adjust the `pos` through [stepB]'s step map.
Step? transformStep(Step stepA, Step stepB, DocNode doc) {
  final mapB = stepB.getMap();

  // ── ReplaceStep over ReplaceStep ─────────────────────────────────────
  if (stepA is ReplaceStep && stepB is ReplaceStep) {
    return _transformReplaceOverReplace(stepA, stepB, mapB);
  }

  // ── ReplaceStep over mark/attr step (identity map) ───────────────────
  if (stepA is ReplaceStep) {
    // Mark and attr steps have identity maps, so no position adjustment.
    if (mapB.ranges.isEmpty) return stepA;
    return _mapReplaceStep(stepA, mapB);
  }

  // ── AddMarkStep over any step ────────────────────────────────────────
  if (stepA is AddMarkStep) {
    final newFrom = mapB.map(stepA.from, assoc: 1);
    final newTo = mapB.map(stepA.to, assoc: -1);
    if (newFrom >= newTo) return null; // Range collapsed — mark is void.
    return AddMarkStep(newFrom, newTo, stepA.mark);
  }

  // ── RemoveMarkStep over any step ─────────────────────────────────────
  if (stepA is RemoveMarkStep) {
    final newFrom = mapB.map(stepA.from, assoc: 1);
    final newTo = mapB.map(stepA.to, assoc: -1);
    if (newFrom >= newTo) return null; // Range collapsed.
    return RemoveMarkStep(newFrom, newTo, stepA.mark);
  }

  // ── SetAttrStep over any step ────────────────────────────────────────
  if (stepA is SetAttrStep) {
    final newPos = mapB.map(stepA.pos, assoc: 1);
    return SetAttrStep(newPos, stepA.key, stepA.value);
  }

  // Unknown step type — cannot transform.
  return null;
}

/// Transforms [stepA] (a ReplaceStep) over [stepB] (a ReplaceStep).
///
/// Handles the three cases:
/// 1. stepA is entirely before stepB — just map positions.
/// 2. stepA is entirely after stepB — just map positions.
/// 3. Overlapping — stepB takes priority; adjust stepA to cover only
///    the non-overlapping region.
ReplaceStep? _transformReplaceOverReplace(
  ReplaceStep stepA,
  ReplaceStep stepB,
  StepMap mapB,
) {
  // Case 1 & 2: No overlap — stepA's range does not intersect stepB's range.
  if (stepA.to <= stepB.from || stepA.from >= stepB.to) {
    return _mapReplaceStep(stepA, mapB);
  }

  // Case 3: Overlapping ranges. stepB takes priority.
  //
  // We need to figure out what part of stepA's effect is still valid
  // after stepB has been applied.

  // If stepB completely covers stepA's range, stepA's deletion is
  // already handled by stepB. We only need stepA's insertion.
  if (stepB.from <= stepA.from && stepB.to >= stepA.to) {
    // stepA's entire deleted range is subsumed by stepB.
    // Place stepA's insertion content at the mapped position.
    if (stepA.slice.isEmpty) {
      // Pure deletion that is already covered by stepB — nothing to do.
      return null;
    }
    // Insert stepA's content at the position where stepA.from maps to
    // after stepB.
    final newPos = mapB.map(stepA.from, assoc: 1);
    return ReplaceStep(newPos, newPos, stepA.slice);
  }

  // If stepA completely covers stepB's range, adjust stepA to account
  // for stepB's changes within its range.
  if (stepA.from <= stepB.from && stepA.to >= stepB.to) {
    // stepA's range is larger. After stepB, the region that stepB
    // replaced is now different size. Adjust stepA's range.
    final sizeDiff = stepB.slice.size - (stepB.to - stepB.from);
    final newFrom = stepA.from;
    final newTo = stepA.to + sizeDiff;
    return ReplaceStep(newFrom, newTo, stepA.slice);
  }

  // Partial overlap: stepA and stepB partially intersect.
  // stepB takes priority for the overlapping region.

  if (stepA.from < stepB.from) {
    // stepA starts before stepB. Keep stepA's effect on the part
    // before stepB, and adjust the rest.
    // stepA covers [stepA.from, stepA.to), stepB covers [stepB.from, stepB.to).
    // After stepB, the region [stepB.from, stepB.to) has been replaced.
    // stepA should now cover [stepA.from, stepB.from) for deletion,
    // plus insert stepA's content.
    final newFrom = stepA.from;
    final newTo = stepB.from;
    if (newFrom == newTo && stepA.slice.isEmpty) return null;
    return ReplaceStep(newFrom, newTo, stepA.slice);
  } else {
    // stepA starts inside or after stepB's range.
    // After stepB, the overlap region has been replaced.
    // stepA should cover [stepB.to mapped, stepA.to mapped) for deletion.
    final newFrom = mapB.map(stepB.to, assoc: 1);
    final newTo = mapB.map(stepA.to, assoc: 1);
    if (newFrom == newTo && stepA.slice.isEmpty) return null;
    if (newFrom > newTo) return null; // Invalid range after mapping.
    return ReplaceStep(newFrom, newTo, stepA.slice);
  }
}

/// Maps a ReplaceStep's positions through a StepMap.
ReplaceStep _mapReplaceStep(ReplaceStep step, StepMap map) {
  final newFrom = map.map(step.from, assoc: 1);
  final newTo = map.map(step.to, assoc: -1);
  // Ensure valid range after mapping.
  if (newFrom > newTo) {
    // The range was swallowed by the mapping — treat as insertion.
    return ReplaceStep(newFrom, newFrom, step.slice);
  }
  return ReplaceStep(newFrom, newTo, step.slice);
}

/// Transforms a list of steps [stepsA] so they can be applied after
/// all steps in [stepsB].
///
/// Each step in [stepsA] is transformed over every step in [stepsB]
/// (and over the already-transformed steps in [stepsA] that precede it,
/// to maintain consistency).
///
/// [doc] is the document state that both lists of steps were originally
/// intended to apply to.
///
/// Returns the transformed versions of [stepsA]. Steps that could not
/// be transformed (conflicts) are dropped.
List<Step> transformSteps(
  List<Step> stepsA,
  List<Step> stepsB,
  DocNode doc,
) {
  if (stepsA.isEmpty || stepsB.isEmpty) return List.of(stepsA);

  final result = <Step>[];

  for (var i = 0; i < stepsA.length; i++) {
    Step? current = stepsA[i];

    // Transform current step over each step in stepsB.
    for (var j = 0; j < stepsB.length; j++) {
      if (current == null) break;
      current = transformStep(current, stepsB[j], doc);
    }

    // Also transform over the already-accepted transformed steps from
    // stepsA, since those will be applied before this one.
    if (current != null) {
      for (final prev in result) {
        if (current == null) break;
        current = transformStep(current, prev, doc);
      }
    }

    if (current != null) {
      result.add(current);
    }
  }

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthorityStep — A step tagged with its origin client
// ─────────────────────────────────────────────────────────────────────────────

/// A step in the authority's history, tagged with the client that sent it.
///
/// Used by [Authority] to track the full ordered history of all edits.
@immutable
class AuthorityStep {
  /// Creates an authority step.
  const AuthorityStep({required this.step, required this.clientId});

  /// The editing step.
  final Step step;

  /// The client that sent this step.
  final String clientId;

  @override
  String toString() => 'AuthorityStep($step, client: $clientId)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Authority — Central authority for ordering steps
// ─────────────────────────────────────────────────────────────────────────────

/// A central authority that establishes a total order on editing steps.
///
/// In a collaborative editing system, the authority is the single source
/// of truth for the document state. All clients send their local steps
/// to the authority, which:
///
/// 1. Checks that the client's base version matches expectations.
/// 2. Transforms the steps if needed (when the client is behind).
/// 3. Applies the steps to the canonical document.
/// 4. Broadcasts the accepted steps to all clients.
///
/// The authority can run server-side for production use, or locally
/// for testing.
///
/// ## Example
///
/// ```dart
/// final authority = Authority(doc: initialDoc);
///
/// // Client sends steps
/// final result = authority.receiveSteps(0, [step1, step2], 'client-a');
/// if (result != null) {
///   // Broadcast result.steps to all clients
///   for (final client in clients) {
///     client.receive(result.version, result.steps);
///   }
/// }
/// ```
class Authority {
  /// Creates an authority with the given initial document.
  Authority({required DocNode doc})
      : _doc = doc,
        _steps = [];

  DocNode _doc;
  final List<AuthorityStep> _steps;

  /// The current canonical document.
  DocNode get doc => _doc;

  /// The current version number (equal to the total number of steps applied).
  int get version => _steps.length;

  /// The full step history.
  List<AuthorityStep> get steps => List.unmodifiable(_steps);

  /// Returns steps from [sinceVersion] to the current version.
  ///
  /// Useful for clients that need to catch up after reconnecting.
  List<AuthorityStep> stepsSince(int sinceVersion) {
    if (sinceVersion >= _steps.length) return const [];
    return _steps.sublist(sinceVersion);
  }

  /// Receives steps from a client and applies them to the canonical document.
  ///
  /// [clientVersion] — The server version the client's steps are based on.
  /// [steps] — The steps the client wants to apply.
  /// [clientId] — The client that sent these steps.
  ///
  /// Returns a record with the new [version] and the [steps] that were
  /// accepted (possibly transformed), or `null` if the steps could not
  /// be applied.
  ///
  /// ## Version handling
  ///
  /// If [clientVersion] is behind the current version, the client's steps
  /// are transformed over the intervening steps using operational transform.
  /// If [clientVersion] is ahead of the current version, the request is
  /// rejected (returns `null`).
  ({int version, List<Step> steps})? receiveSteps(
    int clientVersion,
    List<Step> steps,
    String clientId,
  ) {
    // Reject if the client claims a version ahead of ours.
    if (clientVersion > version) return null;

    // If the client is behind, transform their steps over the
    // intervening authority steps.
    var stepsToApply = steps;
    if (clientVersion < version) {
      final missed = _steps.sublist(clientVersion);
      final missedSteps = missed.map((s) => s.step).toList();

      // The base document at clientVersion.
      var baseDoc = _replayDoc(clientVersion);
      stepsToApply = transformSteps(stepsToApply, missedSteps, baseDoc);
    }

    // Apply the (possibly transformed) steps to the canonical document.
    final appliedSteps = <Step>[];
    var currentDoc = _doc;
    for (final step in stepsToApply) {
      final result = step.apply(currentDoc);
      if (!result.isOk) {
        // If any step fails, reject the entire batch.
        return null;
      }
      currentDoc = result.doc!;
      appliedSteps.add(step);
    }

    // Commit: update the canonical document and step history.
    _doc = currentDoc;
    for (final step in appliedSteps) {
      _steps.add(AuthorityStep(step: step, clientId: clientId));
    }

    return (version: version, steps: appliedSteps);
  }

  /// Replays the document from the initial state up to [targetVersion].
  ///
  /// This is used internally to get the document at a past version for
  /// accurate OT transforms. For efficiency in production, you would
  /// cache document snapshots at intervals.
  DocNode _replayDoc(int targetVersion) {
    // Walk backwards from the current doc, inverting steps.
    var doc = _doc;
    for (var i = _steps.length - 1; i >= targetVersion; i--) {
      final inverse = _steps[i].step.invert(doc);
      final result = inverse.apply(doc);
      if (result.isOk) {
        doc = result.doc!;
      }
    }
    return doc;
  }
}
