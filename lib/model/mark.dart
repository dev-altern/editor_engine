import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A mark represents inline formatting or annotation applied to text content.
///
/// Marks are value objects — two marks with the same [type] and [attrs] are
/// considered equal. Marks are immutable; to change a mark's attributes,
/// create a new mark.
///
/// Common marks: bold, italic, underline, strikethrough, code, link, color.
///
/// Marks are inspired by ProseMirror's mark model:
/// - Flat set per text run (not nested spans)
/// - Adjacent text nodes with identical mark sets are always merged
/// - Mark order is canonical (alphabetical by type name)
@immutable
class Mark {
  /// Creates a mark with the given [type] name and optional [attrs].
  const Mark(this.type, [this.attrs = const {}]);

  /// The mark type name (e.g., "bold", "italic", "link").
  final String type;

  /// Attributes for this mark (e.g., {href: "..."} for links).
  ///
  /// All values must be JSON-serializable.
  final Map<String, Object?> attrs;

  /// Whether this mark has any attributes.
  bool get hasAttrs => attrs.isNotEmpty;

  /// Returns a new mark with the same type but different attributes.
  Mark withAttrs(Map<String, Object?> newAttrs) => Mark(type, newAttrs);

  /// Returns a new mark with the given attribute added or updated.
  Mark withAttr(String key, Object? value) =>
      Mark(type, {...attrs, key: value});

  /// Whether this mark is of the given [typeName].
  bool isType(String typeName) => type == typeName;

  /// Serializes this mark to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'type': type,
        if (attrs.isNotEmpty) 'attrs': attrs,
      };

  /// Deserializes a mark from a JSON-compatible map.
  factory Mark.fromJson(Map<String, dynamic> json) => Mark(
        json['type'] as String,
        (json['attrs'] as Map<String, dynamic>?)?.cast<String, Object?>() ??
            const {},
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Mark &&
          type == other.type &&
          const DeepCollectionEquality().equals(attrs, other.attrs);

  @override
  int get hashCode => Object.hash(type, const DeepCollectionEquality().hash(attrs));

  @override
  String toString() =>
      attrs.isEmpty ? 'Mark($type)' : 'Mark($type, $attrs)';

  // ── Common mark constructors ──────────────────────────────────────────

  /// Bold mark.
  static const Mark bold = Mark('bold');

  /// Italic mark.
  static const Mark italic = Mark('italic');

  /// Underline mark.
  static const Mark underline = Mark('underline');

  /// Strikethrough mark.
  static const Mark strikethrough = Mark('strikethrough');

  /// Inline code mark.
  static const Mark code = Mark('code');

  /// Superscript mark.
  static const Mark superscript = Mark('superscript');

  /// Subscript mark.
  static const Mark subscript = Mark('subscript');

  /// Link mark with the given [href].
  static Mark link(String href, {String? title}) => Mark('link', {
        'href': href,
        'title': ?title,
      });

  /// Text color mark.
  static Mark color(String color) => Mark('color', {'color': color});

  /// Background highlight mark.
  static Mark highlight(String color) =>
      Mark('highlight', {'color': color});
}

// ── Mark set utilities ────────────────────────────────────────────────────

/// Extension methods for working with lists of marks as sets.
extension MarkSetExtension on List<Mark> {
  /// Whether this mark set contains a mark of the given [type].
  bool hasMark(String type) => any((m) => m.type == type);

  /// Returns the mark of the given [type], or null if not present.
  Mark? getMark(String type) {
    for (final m in this) {
      if (m.type == type) return m;
    }
    return null;
  }

  /// Returns a new mark set with the given [mark] added.
  ///
  /// If a mark of the same type already exists, it is replaced.
  /// The result is sorted by type name for canonical ordering.
  List<Mark> addMark(Mark mark) {
    final filtered = where((m) => m.type != mark.type).toList();
    // Insert at sorted position (source list is already sorted, filter preserves order)
    var i = 0;
    while (i < filtered.length && filtered[i].type.compareTo(mark.type) < 0) {
      i++;
    }
    filtered.insert(i, mark);
    return List.unmodifiable(filtered);
  }

  /// Returns a new mark set with the mark of the given [type] removed.
  List<Mark> removeMark(String type) =>
      List.unmodifiable(where((m) => m.type != type).toList());

  /// Whether this mark set equals [other] (same marks in same order).
  bool sameMarks(List<Mark> other) =>
      const ListEquality<Mark>().equals(this, other);
}
