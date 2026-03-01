import '../model/node.dart';
import '../model/fragment.dart';
import '../model/mark.dart';
import '../schema/schema.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JsonSerializer — Document ↔ JSON conversion
// ─────────────────────────────────────────────────────────────────────────────

/// Serializes and deserializes documents to/from JSON.
///
/// The JSON format mirrors ProseMirror's canonical format:
/// ```json
/// {
///   "type": "doc",
///   "content": [
///     {
///       "type": "paragraph",
///       "content": [
///         { "type": "text", "text": "Hello " },
///         { "type": "text", "text": "world", "marks": [{"type": "bold"}] }
///       ]
///     },
///     {
///       "type": "image",
///       "attrs": { "src": "photo.jpg", "alt": "A photo" }
///     }
///   ]
/// }
/// ```
class JsonSerializer {
  const JsonSerializer({this.schema});

  /// The schema for type-aware deserialization.
  final Schema? schema;

  // ── Serialization ───────────────────────────────────────────────────

  /// Serializes a document to a JSON-compatible map.
  Map<String, dynamic> serialize(DocNode doc) => doc.toJson();

  /// Serializes a node to JSON.
  Map<String, dynamic> serializeNode(Node node) => node.toJson();

  /// Serializes a fragment to JSON.
  List<Map<String, dynamic>> serializeFragment(Fragment fragment) =>
      fragment.toJson();

  // ── Deserialization ─────────────────────────────────────────────────

  /// Deserializes a document from JSON.
  DocNode deserialize(Map<String, dynamic> json) {
    if (json['type'] != 'doc') {
      throw FormatException('Expected type "doc", got "${json['type']}"');
    }
    return _deserializeDoc(json);
  }

  /// Deserializes any node from JSON.
  Node deserializeNode(Map<String, dynamic> json) => _nodeFromJson(json);

  DocNode _deserializeDoc(Map<String, dynamic> json) {
    final content = json['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      return DocNode(
        content: Fragment([
          const BlockNode(type: 'paragraph', inlineContent: true),
        ]),
      );
    }

    final children = content
        .cast<Map<String, dynamic>>()
        .map(_nodeFromJson)
        .toList();

    return DocNode(content: Fragment(children));
  }

  Node _nodeFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;

    switch (type) {
      case 'text':
        return _textFromJson(json);
      case 'doc':
        return _deserializeDoc(json);
      case 'inline_widget':
        return InlineWidgetNode.fromJson(json);
      default:
        return _blockFromJson(json);
    }
  }

  TextNode _textFromJson(Map<String, dynamic> json) {
    final text = json['text'] as String;
    final marksList = json['marks'] as List<dynamic>?;
    final marks =
        marksList
            ?.map((m) => Mark.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [];
    return TextNode(text, marks: marks);
  }

  BlockNode _blockFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final attrs =
        (json['attrs'] as Map<String, dynamic>?)?.cast<String, Object?>() ??
        const {};

    final contentList = json['content'] as List<dynamic>?;
    final content = contentList != null
        ? Fragment(
            contentList
                .cast<Map<String, dynamic>>()
                .map(_nodeFromJson)
                .toList(),
          )
        : Fragment.empty;

    // Use schema to determine node flags if available
    final spec = schema?.nodeSpec(type);

    return BlockNode(
      type: type,
      attrs: attrs,
      content: content,
      isLeaf: spec?.isLeaf ?? content.isEmpty,
      isInline: spec?.inline ?? false,
      inlineContent:
          spec?.hasInlineContent ??
          (content.isNotEmpty && content.children.first.isInline),
      isAtom: spec?.atom ?? false,
    );
  }
}
