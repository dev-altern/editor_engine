import 'package:meta/meta.dart';

import '../transform/step_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MarkerBehavior — How marker boundaries respond to edits
// ─────────────────────────────────────────────────────────────────────────────

/// How a marker's boundaries respond to insertions at boundary positions.
///
/// When text is inserted exactly at a marker's `from` or `to` position,
/// the behavior determines whether the marker expands to include the
/// new text or stays fixed.
enum MarkerBehavior {
  /// Insertions at boundaries do NOT expand the marker.
  /// Use for: completed comment threads, resolved diagnostics.
  exclusive,

  /// Insertions at the start expand the marker; end stays tight.
  /// Use for: active text highlights, selection-like ranges.
  startInclusive,

  /// Insertions at the end expand the marker; start stays tight.
  /// Use for: typing at the end of a highlighted word.
  endInclusive,

  /// Insertions at either boundary expand the marker.
  /// Use for: active comment ranges where typing at edges should be included.
  inclusive,
}

// ─────────────────────────────────────────────────────────────────────────────
// Marker — A tracked range in the document
// ─────────────────────────────────────────────────────────────────────────────

/// A tracked range in the document that survives edits.
///
/// Markers are used for comments, highlights, diagnostics, bookmarks,
/// collaborator cursors, and any feature that needs a persistent range.
///
/// Unlike [Decoration]s (which are ephemeral view-layer annotations),
/// markers are part of the editor state and survive across transactions.
/// They are identified by a unique [id] and automatically update their
/// positions as the document is edited.
///
/// ```dart
/// final marker = Marker(
///   id: 'comment-1',
///   from: 10,
///   to: 25,
///   type: 'comment',
///   attrs: {'threadId': 'abc123'},
///   behavior: MarkerBehavior.exclusive,
/// );
/// ```
@immutable
class Marker {
  /// Creates a marker.
  const Marker({
    required this.id,
    required this.from,
    required this.to,
    required this.type,
    this.attrs = const {},
    this.behavior = MarkerBehavior.exclusive,
  });

  /// Unique identifier for this marker (survives edits and serialization).
  final String id;

  /// Start position (inclusive).
  final int from;

  /// End position (exclusive).
  final int to;

  /// Marker type name (e.g., "comment", "diagnostic", "highlight").
  final String type;

  /// Arbitrary metadata (e.g., threadId, severity, color).
  final Map<String, Object?> attrs;

  /// How boundary edits affect this marker's range.
  final MarkerBehavior behavior;

  /// Maps this marker through a [Mapping], returning the updated marker
  /// or `null` if the entire range was deleted.
  Marker? mapThrough(Mapping mapping) {
    final int fromAssoc;
    final int toAssoc;

    switch (behavior) {
      case MarkerBehavior.exclusive:
        fromAssoc = 1;
        toAssoc = -1;
      case MarkerBehavior.startInclusive:
        fromAssoc = -1;
        toAssoc = -1;
      case MarkerBehavior.endInclusive:
        fromAssoc = 1;
        toAssoc = 1;
      case MarkerBehavior.inclusive:
        fromAssoc = -1;
        toAssoc = 1;
    }

    final newFrom = mapping.map(from, assoc: fromAssoc);
    final newTo = mapping.map(to, assoc: toAssoc);

    // Range collapsed — marker was fully deleted.
    if (newFrom >= newTo) return null;

    if (newFrom == from && newTo == to) return this;
    return Marker(
      id: id,
      from: newFrom,
      to: newTo,
      type: type,
      attrs: attrs,
      behavior: behavior,
    );
  }

  /// Returns a copy with updated fields.
  Marker copyWith({
    int? from,
    int? to,
    String? type,
    Map<String, Object?>? attrs,
    MarkerBehavior? behavior,
  }) => Marker(
    id: id,
    from: from ?? this.from,
    to: to ?? this.to,
    type: type ?? this.type,
    attrs: attrs ?? this.attrs,
    behavior: behavior ?? this.behavior,
  );

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'type': type,
    if (attrs.isNotEmpty) 'attrs': attrs,
    if (behavior != MarkerBehavior.exclusive) 'behavior': behavior.name,
  };

  /// Deserializes from JSON.
  factory Marker.fromJson(Map<String, dynamic> json) => Marker(
    id: json['id'] as String,
    from: json['from'] as int,
    to: json['to'] as int,
    type: json['type'] as String,
    attrs: json['attrs'] != null
        ? Map<String, Object?>.from(json['attrs'] as Map)
        : const {},
    behavior: json['behavior'] != null
        ? MarkerBehavior.values.byName(json['behavior'] as String)
        : MarkerBehavior.exclusive,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Marker &&
          id == other.id &&
          from == other.from &&
          to == other.to &&
          type == other.type &&
          behavior == other.behavior &&
          _mapsEqual(attrs, other.attrs);

  @override
  int get hashCode => Object.hash(id, from, to, type, behavior);

  @override
  String toString() {
    final extra = <String>[];
    if (attrs.isNotEmpty) extra.add('attrs: $attrs');
    if (behavior != MarkerBehavior.exclusive)
      extra.add('behavior: ${behavior.name}');
    final suffix = extra.isEmpty ? '' : ', ${extra.join(', ')}';
    return 'Marker($id, $from..$to, $type$suffix)';
  }
}

bool _mapsEqual(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
