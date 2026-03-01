import 'package:meta/meta.dart';

import '../model/mark.dart';
import '../model/node.dart';
import 'attr_step.dart';
import 'mark_step.dart';
import 'replace_step.dart';
import 'step_map.dart';

export 'attr_step.dart';
export 'mark_step.dart';
export 'replace_step.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Step — Base class for atomic editing operations
// ─────────────────────────────────────────────────────────────────────────────

/// An atomic, invertible editing operation on a document.
///
/// Steps are the fundamental unit of document transformation:
/// - Each step produces a [StepMap] for position mapping
/// - Each step can be [invert]ed to produce an undo step
/// - Steps can be applied to a document to produce a new document
///
/// Steps are composed into [Transaction]s, which group multiple steps
/// into a single undo unit.
@immutable
abstract class Step {
  const Step();

  /// Applies this step to [doc], returning the result.
  ///
  /// Returns a [StepResult] which is either success (with the new document)
  /// or failure (with an error message).
  StepResult apply(DocNode doc);

  /// Returns the [StepMap] for this step (position mapping).
  StepMap getMap();

  /// Returns the inverse of this step (for undo).
  Step invert(DocNode doc);

  /// Attempts to merge this step with [other].
  ///
  /// Returns the merged step, or null if they can't be merged.
  Step? merge(Step other) => null;

  /// Serializes this step to JSON.
  Map<String, dynamic> toJson();

  /// Deserializes a step from JSON.
  ///
  /// Dispatches on the `stepType` field to construct the correct subclass.
  static Step fromJson(Map<String, dynamic> json) {
    final stepType = json['stepType'] as String;
    return switch (stepType) {
      'replace' => ReplaceStep(
          json['from'] as int,
          json['to'] as int,
          Slice.fromJson(json['slice'] as Map<String, dynamic>),
        ),
      'addMark' => AddMarkStep(
          json['from'] as int,
          json['to'] as int,
          Mark.fromJson(json['mark'] as Map<String, dynamic>),
        ),
      'removeMark' => RemoveMarkStep(
          json['from'] as int,
          json['to'] as int,
          Mark.fromJson(json['mark'] as Map<String, dynamic>),
        ),
      'setAttr' => SetAttrStep(
          json['pos'] as int,
          json['key'] as String,
          json['value'],
        ),
      _ => throw FormatException('Unknown step type: "$stepType"'),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StepResult — Result of applying a step
// ─────────────────────────────────────────────────────────────────────────────

/// The result of applying a [Step] to a document.
@immutable
class StepResult {
  const StepResult._(this.doc, this.error);

  /// Creates a successful result.
  const StepResult.ok(DocNode doc) : this._(doc, null);

  /// Creates a failed result.
  const StepResult.fail(String error) : this._(null, error);

  /// The resulting document (null if failed).
  final DocNode? doc;

  /// The error message (null if succeeded).
  final String? error;

  /// Whether the step succeeded.
  bool get isOk => doc != null;

  /// Whether the step failed.
  bool get isFail => error != null;
}
