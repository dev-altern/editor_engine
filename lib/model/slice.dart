import 'package:meta/meta.dart';

import 'fragment.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Slice — A fragment with open/close depths (for cut/paste)
// ─────────────────────────────────────────────────────────────────────────────

/// A slice of document content with open depths at each side.
///
/// When you cut a range from a document, the result is a slice.
/// The [openStart] and [openEnd] indicate how many nodes are "open"
/// (partially included) on each side. This is needed for proper paste
/// behavior — pasting into an existing paragraph should merge inline
/// content, not insert a new paragraph.
@immutable
class Slice {
  /// Creates a slice with the given content and open depths.
  const Slice(this.content, this.openStart, this.openEnd);

  /// An empty slice.
  static const Slice empty = Slice(Fragment.empty, 0, 0);

  /// The sliced content.
  final Fragment content;

  /// How many levels are open at the start.
  final int openStart;

  /// How many levels are open at the end.
  final int openEnd;

  /// The total size of the slice content.
  int get size => content.size;

  /// Whether this is an empty slice.
  bool get isEmpty => content.isEmpty;

  /// Whether this slice has content.
  bool get isNotEmpty => content.isNotEmpty;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'content': content.toJson(),
    if (openStart > 0) 'openStart': openStart,
    if (openEnd > 0) 'openEnd': openEnd,
  };

  factory Slice.fromJson(Map<String, dynamic> json) => Slice(
    Fragment.fromJson(json['content'] as List<dynamic>),
    json['openStart'] as int? ?? 0,
    json['openEnd'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Slice &&
          content == other.content &&
          openStart == other.openStart &&
          openEnd == other.openEnd;

  @override
  int get hashCode => Object.hash(content, openStart, openEnd);

  @override
  String toString() => 'Slice($content, $openStart, $openEnd)';
}
