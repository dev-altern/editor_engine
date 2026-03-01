import 'dart:convert';

import 'package:meta/meta.dart';

import '../model/fragment.dart';
import '../model/mark.dart';
import '../model/node.dart';
import '../schema/schema.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HtmlSerializer — Document ↔ HTML conversion
// ─────────────────────────────────────────────────────────────────────────────

/// Serializes and deserializes documents to/from HTML.
///
/// Supports all common block types (paragraphs, headings, lists, tables,
/// blockquotes, code blocks, images, dividers) and inline marks (bold, italic,
/// underline, strikethrough, code, links, highlights, colors).
///
/// Example:
/// ```dart
/// final serializer = HtmlSerializer(schema: richSchema);
///
/// // Serialize document to HTML
/// final html = serializer.serialize(doc);
///
/// // Deserialize HTML back to document
/// final doc = serializer.deserialize('<p>Hello <strong>world</strong></p>');
/// ```
@immutable
class HtmlSerializer {
  /// Creates an HTML serializer with an optional [schema] for type-aware
  /// deserialization.
  const HtmlSerializer({this.schema});

  /// The schema for type-aware deserialization.
  final Schema? schema;

  // ── Serialization ───────────────────────────────────────────────────

  /// Serializes a document to an HTML string.
  String serialize(DocNode doc) {
    final buffer = StringBuffer();
    _serializeChildren(doc.content, buffer);
    return buffer.toString();
  }

  /// Serializes a single node to an HTML string.
  String serializeNode(Node node) {
    final buffer = StringBuffer();
    _serializeNode(node, buffer);
    return buffer.toString();
  }

  void _serializeChildren(Fragment content, StringBuffer buffer) {
    content.forEach((node, _, __) => _serializeNode(node, buffer));
  }

  void _serializeNode(Node node, StringBuffer buffer) {
    if (node.isText) {
      _serializeText(node as TextNode, buffer);
      return;
    }

    switch (node.type) {
      case 'doc':
        _serializeChildren(node.content, buffer);

      case 'paragraph':
        buffer.write('<p>');
        _serializeChildren(node.content, buffer);
        buffer.write('</p>');

      case 'heading':
        final level = (node.attrs['level'] as int?) ?? 1;
        final clampedLevel = level.clamp(1, 6);
        buffer.write('<h$clampedLevel>');
        _serializeChildren(node.content, buffer);
        buffer.write('</h$clampedLevel>');

      case 'blockquote':
        buffer.write('<blockquote>');
        _serializeChildren(node.content, buffer);
        buffer.write('</blockquote>');

      case 'code_block':
        final language = node.attrs['language'] as String?;
        buffer.write('<pre><code');
        if (language != null && language.isNotEmpty) {
          buffer.write(' class="language-${_escapeAttr(language)}"');
        }
        buffer.write('>');
        _serializeChildren(node.content, buffer);
        buffer.write('</code></pre>');

      case 'bullet_list':
        buffer.write('<ul>');
        _serializeChildren(node.content, buffer);
        buffer.write('</ul>');

      case 'ordered_list':
        final start = (node.attrs['start'] as int?) ?? 1;
        buffer.write('<ol');
        if (start != 1) {
          buffer.write(' start="$start"');
        }
        buffer.write('>');
        _serializeChildren(node.content, buffer);
        buffer.write('</ol>');

      case 'check_list':
        buffer.write('<ul class="checklist">');
        _serializeChildren(node.content, buffer);
        buffer.write('</ul>');

      case 'list_item':
        buffer.write('<li>');
        _serializeChildren(node.content, buffer);
        buffer.write('</li>');

      case 'check_item':
        final checked = node.attrs['checked'] == true;
        buffer.write(
          '<li class="check-item" data-checked="$checked">',
        );
        _serializeChildren(node.content, buffer);
        buffer.write('</li>');

      case 'table':
        buffer.write('<table>');
        _serializeChildren(node.content, buffer);
        buffer.write('</table>');

      case 'table_row':
        buffer.write('<tr>');
        _serializeChildren(node.content, buffer);
        buffer.write('</tr>');

      case 'table_cell':
        buffer.write('<td');
        final colspan = (node.attrs['colspan'] as int?) ?? 1;
        final rowspan = (node.attrs['rowspan'] as int?) ?? 1;
        if (colspan != 1) {
          buffer.write(' colspan="$colspan"');
        }
        if (rowspan != 1) {
          buffer.write(' rowspan="$rowspan"');
        }
        buffer.write('>');
        _serializeChildren(node.content, buffer);
        buffer.write('</td>');

      case 'horizontal_rule' || 'divider':
        buffer.write('<hr>');

      case 'image':
        buffer.write('<img');
        final src = node.attrs['src'] as String?;
        if (src != null) {
          buffer.write(' src="${_escapeAttr(src)}"');
        }
        final alt = node.attrs['alt'] as String?;
        if (alt != null && alt.isNotEmpty) {
          buffer.write(' alt="${_escapeAttr(alt)}"');
        }
        final title = node.attrs['title'] as String?;
        if (title != null && title.isNotEmpty) {
          buffer.write(' title="${_escapeAttr(title)}"');
        }
        buffer.write('>');

      case 'hard_break':
        buffer.write('<br>');

      case 'callout':
        final icon = node.attrs['icon'] as String?;
        buffer.write('<div class="callout"');
        if (icon != null && icon.isNotEmpty) {
          buffer.write(' data-icon="${_escapeAttr(icon)}"');
        }
        buffer.write('>');
        _serializeChildren(node.content, buffer);
        buffer.write('</div>');

      case 'embed':
        final embedType = node.attrs['embedType'] as String?;
        final data = node.attrs['data'];
        buffer.write('<div class="embed"');
        if (embedType != null) {
          buffer.write(' data-type="${_escapeAttr(embedType)}"');
        }
        if (data != null) {
          buffer.write(' data-embed="${_escapeAttr(jsonEncode(data))}"');
        }
        buffer.write('>');
        _serializeChildren(node.content, buffer);
        buffer.write('</div>');

      case 'inline_widget':
        final widgetNode = node as InlineWidgetNode;
        final widgetAttrs = Map<String, Object?>.from(widgetNode.attrs)
          ..remove('widgetType');
        buffer.write(
          '<span class="inline-widget"'
          ' data-widget-type="${_escapeAttr(widgetNode.widgetType)}"',
        );
        if (widgetAttrs.isNotEmpty) {
          buffer.write(
            ' data-attrs="${_escapeAttr(jsonEncode(widgetAttrs))}"',
          );
        }
        buffer.write('></span>');

      default:
        // Unknown block type — wrap in a div with data-type
        buffer.write('<div data-type="${_escapeAttr(node.type)}">');
        _serializeChildren(node.content, buffer);
        buffer.write('</div>');
    }
  }

  void _serializeText(TextNode node, StringBuffer buffer) {
    final text = _escapeHtml(node.text);
    if (node.marks.isEmpty) {
      buffer.write(text);
      return;
    }

    // Open marks
    final openTags = StringBuffer();
    final closeTags = <String>[];

    for (final mark in node.marks) {
      final tags = _markToTags(mark);
      openTags.write(tags.open);
      closeTags.add(tags.close);
    }

    buffer.write(openTags);
    buffer.write(text);

    // Close marks in reverse order
    for (var i = closeTags.length - 1; i >= 0; i--) {
      buffer.write(closeTags[i]);
    }
  }

  ({String open, String close}) _markToTags(Mark mark) {
    switch (mark.type) {
      case 'bold':
        return (open: '<strong>', close: '</strong>');
      case 'italic':
        return (open: '<em>', close: '</em>');
      case 'underline':
        return (open: '<u>', close: '</u>');
      case 'strikethrough':
        return (open: '<s>', close: '</s>');
      case 'code':
        return (open: '<code>', close: '</code>');
      case 'superscript':
        return (open: '<sup>', close: '</sup>');
      case 'subscript':
        return (open: '<sub>', close: '</sub>');
      case 'link':
        final href = mark.attrs['href'] as String? ?? '';
        final title = mark.attrs['title'] as String?;
        final titleAttr = (title != null && title.isNotEmpty)
            ? ' title="${_escapeAttr(title)}"'
            : '';
        return (
          open: '<a href="${_escapeAttr(href)}"$titleAttr>',
          close: '</a>',
        );
      case 'highlight':
        final color = _escapeCss(mark.attrs['color'] as String? ?? 'yellow');
        return (
          open: '<mark style="background-color: $color">',
          close: '</mark>',
        );
      case 'color':
        final color = _escapeCss(mark.attrs['color'] as String? ?? 'inherit');
        return (
          open: '<span style="color: $color">',
          close: '</span>',
        );
      default:
        // Unknown mark — use data attributes
        final attrsJson =
            mark.attrs.isNotEmpty ? jsonEncode(mark.attrs) : null;
        final attrsAttr = attrsJson != null
            ? ' data-attrs="${_escapeAttr(attrsJson)}"'
            : '';
        return (
          open:
              '<span data-mark="${_escapeAttr(mark.type)}"$attrsAttr>',
          close: '</span>',
        );
    }
  }

  // ── Deserialization ─────────────────────────────────────────────────

  /// Deserializes an HTML string into a document node.
  DocNode deserialize(String html) {
    final trimmed = html.trim();
    if (trimmed.isEmpty) {
      return DocNode(content: Fragment([
        const BlockNode(type: 'paragraph', inlineContent: true),
      ]));
    }

    final tokens = _tokenize(trimmed);
    final blocks = _parseTokensToBlocks(tokens);

    if (blocks.isEmpty) {
      return DocNode(content: Fragment([
        const BlockNode(type: 'paragraph', inlineContent: true),
      ]));
    }

    return DocNode(content: Fragment(blocks));
  }

  // ── Tokenizer ─────────────────────────────────────────────────────

  List<_HtmlToken> _tokenize(String html) {
    final tokens = <_HtmlToken>[];
    var pos = 0;

    while (pos < html.length) {
      if (html[pos] == '<') {
        // Find the end of the tag
        final closeIndex = html.indexOf('>', pos);
        if (closeIndex == -1) {
          // Malformed — treat rest as text
          tokens.add(_HtmlToken.text(
            _decodeEntities(html.substring(pos)),
          ));
          break;
        }

        final tagContent = html.substring(pos + 1, closeIndex);

        if (tagContent.startsWith('!--')) {
          // HTML comment — skip
          final commentEnd = html.indexOf('-->', pos);
          if (commentEnd == -1) {
            break;
          }
          pos = commentEnd + 3;
          continue;
        }

        if (tagContent.startsWith('/')) {
          // Closing tag
          final tagName = tagContent
              .substring(1)
              .trim()
              .split(RegExp(r'\s'))
              .first
              .toLowerCase();
          tokens.add(_HtmlToken.closeTag(tagName));
        } else {
          // Opening or self-closing tag
          final selfClosing =
              tagContent.endsWith('/') || _isSelfClosingTag(tagContent);
          final parts = tagContent
              .replaceAll(RegExp(r'/\s*$'), '')
              .split(RegExp(r'\s+'));
          final tagName = parts.first.toLowerCase();
          final attrsString = parts.length > 1
              ? tagContent.substring(tagName.length).trim()
              : '';
          final attrs = _parseAttributes(
            attrsString.replaceAll(RegExp(r'/\s*$'), ''),
          );

          if (selfClosing || _isVoidElement(tagName)) {
            tokens.add(_HtmlToken.selfClosing(tagName, attrs));
          } else {
            tokens.add(_HtmlToken.openTag(tagName, attrs));
          }
        }

        pos = closeIndex + 1;
      } else {
        // Text content — collect until next tag
        final nextTag = html.indexOf('<', pos);
        final textEnd = nextTag == -1 ? html.length : nextTag;
        final text = html.substring(pos, textEnd);
        if (text.isNotEmpty) {
          tokens.add(_HtmlToken.text(_decodeEntities(text)));
        }
        pos = textEnd;
      }
    }

    return tokens;
  }

  bool _isSelfClosingTag(String tagContent) =>
      tagContent.endsWith('/');

  bool _isVoidElement(String tagName) => const {
        'br',
        'hr',
        'img',
        'input',
        'meta',
        'link',
        'area',
        'base',
        'col',
        'embed',
        'source',
        'track',
        'wbr',
      }.contains(tagName);

  Map<String, String> _parseAttributes(String attrString) {
    final attrs = <String, String>{};
    if (attrString.isEmpty) return attrs;

    // Match attr="value", attr='value', or attr=value or standalone attr
    final re = RegExp(
      r'''(\w[\w\-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|(\S+)))?''',
    );

    for (final match in re.allMatches(attrString)) {
      final key = match.group(1)!;
      final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      attrs[key] = _decodeEntities(value);
    }

    return attrs;
  }

  // ── Token-based parser ────────────────────────────────────────────

  List<Node> _parseTokensToBlocks(List<_HtmlToken> tokens) {
    final context = _ParseContext(tokens);
    final blocks = <Node>[];

    while (context.pos < context.tokens.length) {
      final token = context.current;

      if (token.type == _TokenType.text) {
        final text = token.text!;
        context.advance();
        if (text.trim().isNotEmpty) {
          // Bare text — wrap in paragraph
          blocks.add(BlockNode(
            type: 'paragraph',
            content: Fragment([TextNode(text)]),
            inlineContent: true,
          ));
        }
        continue;
      }

      if (token.type == _TokenType.closeTag) {
        // Unexpected close tag — skip
        context.advance();
        continue;
      }

      if (token.type == _TokenType.selfClosing) {
        final node = _parseSelfClosing(token);
        if (node != null) {
          blocks.add(node);
        }
        context.advance();
        continue;
      }

      // Open tag — parse the element
      final node = _parseElement(context);
      if (node != null) {
        blocks.add(node);
      }
    }

    return blocks;
  }

  Node? _parseSelfClosing(_HtmlToken token) {
    switch (token.tagName) {
      case 'br':
        return const BlockNode(
          type: 'hard_break',
          isLeaf: true,
          isInline: true,
        );
      case 'hr':
        return const BlockNode(type: 'horizontal_rule', isLeaf: true);
      case 'img':
        final attrs = <String, Object?>{};
        if (token.attrs.containsKey('src')) {
          attrs['src'] = token.attrs['src'];
        }
        if (token.attrs.containsKey('alt')) {
          attrs['alt'] = token.attrs['alt'];
        }
        if (token.attrs.containsKey('title')) {
          attrs['title'] = token.attrs['title'];
        }
        return BlockNode(
          type: 'image',
          attrs: attrs,
          isLeaf: true,
          isAtom: true,
        );
      default:
        return null;
    }
  }

  Node? _parseElement(_ParseContext context) {
    final openToken = context.current;
    context.advance();

    final tagName = openToken.tagName!;
    final attrs = openToken.attrs;

    // Collect inner content tokens until matching close tag
    final innerTokens = <_HtmlToken>[];
    var depth = 1;
    while (context.pos < context.tokens.length && depth > 0) {
      final token = context.current;
      if (token.type == _TokenType.openTag && token.tagName == tagName) {
        depth++;
      } else if (token.type == _TokenType.closeTag &&
          token.tagName == tagName) {
        depth--;
        if (depth == 0) {
          context.advance();
          break;
        }
      }
      innerTokens.add(token);
      context.advance();
    }

    return _buildNode(tagName, attrs, innerTokens);
  }

  Node? _buildNode(
    String tagName,
    Map<String, String> attrs,
    List<_HtmlToken> innerTokens,
  ) {
    switch (tagName) {
      case 'p':
        final inlines = _parseInlineTokens(innerTokens);
        return BlockNode(
          type: 'paragraph',
          content: Fragment(inlines),
          inlineContent: true,
        );

      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(tagName.substring(1));
        final inlines = _parseInlineTokens(innerTokens);
        return BlockNode(
          type: 'heading',
          attrs: {'level': level},
          content: Fragment(inlines),
          inlineContent: true,
        );

      case 'blockquote':
        final blocks = _parseTokensToBlocks(innerTokens);
        if (blocks.isEmpty) {
          return BlockNode(
            type: 'blockquote',
            content: Fragment([
              const BlockNode(type: 'paragraph', inlineContent: true),
            ]),
          );
        }
        return BlockNode(
          type: 'blockquote',
          content: Fragment(blocks),
        );

      case 'pre':
        // Look for <code> inside
        final text = _extractTextFromTokens(innerTokens);
        return BlockNode(
          type: 'code_block',
          content:
              text.isNotEmpty ? Fragment([TextNode(text)]) : Fragment.empty,
        );

      case 'ul':
        // Check for checklist class
        if (attrs['class'] == 'checklist') {
          final items = _parseListItems(innerTokens, isCheckList: true);
          return BlockNode(
            type: 'check_list',
            content: Fragment(items),
          );
        }
        final items = _parseListItems(innerTokens);
        return BlockNode(
          type: 'bullet_list',
          content: Fragment(items),
        );

      case 'ol':
        final start = int.tryParse(attrs['start'] ?? '1') ?? 1;
        final items = _parseListItems(innerTokens);
        return BlockNode(
          type: 'ordered_list',
          attrs: {'start': start},
          content: Fragment(items),
        );

      case 'li':
        final nodeAttrs = <String, Object?>{};
        String nodeType = 'list_item';

        if (attrs['class']?.contains('check-item') == true) {
          nodeType = 'check_item';
          nodeAttrs['checked'] = attrs['data-checked'] == 'true';
        }

        // Try to parse as blocks first, then wrap inline content
        final blocks = _parseTokensToBlocks(innerTokens);
        if (blocks.isNotEmpty) {
          return BlockNode(
            type: nodeType,
            attrs: nodeAttrs,
            content: Fragment(blocks),
          );
        }

        // Inline content — wrap in paragraph
        final inlines = _parseInlineTokens(innerTokens);
        return BlockNode(
          type: nodeType,
          attrs: nodeAttrs,
          content: Fragment([
            BlockNode(
              type: 'paragraph',
              content: Fragment(inlines),
              inlineContent: true,
            ),
          ]),
        );

      case 'table':
        final rows = _parseTableRows(innerTokens);
        return BlockNode(
          type: 'table',
          content: Fragment(rows),
        );

      case 'tr':
        final cells = _parseTableCells(innerTokens);
        return BlockNode(
          type: 'table_row',
          content: Fragment(cells),
        );

      case 'td' || 'th':
        final colspan = int.tryParse(attrs['colspan'] ?? '1') ?? 1;
        final rowspan = int.tryParse(attrs['rowspan'] ?? '1') ?? 1;
        final blocks = _parseTokensToBlocks(innerTokens);
        final content = blocks.isNotEmpty
            ? blocks
            : [
                BlockNode(
                  type: 'paragraph',
                  content: Fragment(_parseInlineTokens(innerTokens)),
                  inlineContent: true,
                ),
              ];
        return BlockNode(
          type: 'table_cell',
          attrs: {'colspan': colspan, 'rowspan': rowspan},
          content: Fragment(content),
        );

      case 'div':
        // Check for special div types
        if (attrs['class'] == 'callout') {
          final blocks = _parseTokensToBlocks(innerTokens);
          return BlockNode(
            type: 'callout',
            attrs: {
              'icon': attrs['data-icon'] ?? '',
            },
            content: blocks.isNotEmpty
                ? Fragment(blocks)
                : Fragment([
                    const BlockNode(
                      type: 'paragraph',
                      inlineContent: true,
                    ),
                  ]),
          );
        }
        if (attrs['class'] == 'embed') {
          final embedType = attrs['data-type'] ?? '';
          final dataJson = attrs['data-embed'];
          final data = dataJson != null
              ? jsonDecode(dataJson) as Map<String, dynamic>
              : <String, dynamic>{};
          return BlockNode(
            type: 'embed',
            attrs: {
              'embedType': embedType,
              'data': data,
            },
            isLeaf: true,
            isAtom: true,
          );
        }
        if (attrs.containsKey('data-type')) {
          // Reconstruct unknown block type
          final blocks = _parseTokensToBlocks(innerTokens);
          return BlockNode(
            type: attrs['data-type']!,
            content: blocks.isNotEmpty ? Fragment(blocks) : Fragment.empty,
          );
        }
        // Generic div — parse as container
        final blocks = _parseTokensToBlocks(innerTokens);
        if (blocks.isNotEmpty) {
          return blocks.length == 1 ? blocks.first : null;
        }
        final inlines = _parseInlineTokens(innerTokens);
        if (inlines.isNotEmpty) {
          return BlockNode(
            type: 'paragraph',
            content: Fragment(inlines),
            inlineContent: true,
          );
        }
        return null;

      default:
        // Treat as inline if it's a known inline tag, otherwise block
        if (_isInlineTag(tagName)) {
          // Shouldn't normally reach here at block level, but handle
          // gracefully by wrapping in a paragraph
          final inlines = _parseInlineElement(
            tagName,
            attrs,
            innerTokens,
          );
          if (inlines.isNotEmpty) {
            return BlockNode(
              type: 'paragraph',
              content: Fragment(inlines),
              inlineContent: true,
            );
          }
          return null;
        }
        // Unknown block — parse children as blocks
        final blocks = _parseTokensToBlocks(innerTokens);
        if (blocks.isNotEmpty) {
          return blocks.length == 1
              ? blocks.first
              : BlockNode(
                  type: 'paragraph',
                  content: Fragment(blocks),
                );
        }
        return null;
    }
  }

  // ── Inline parsing ────────────────────────────────────────────────

  List<Node> _parseInlineTokens(List<_HtmlToken> tokens) {
    return _parseInlineTokensWithMarks(tokens, const []);
  }

  List<Node> _parseInlineTokensWithMarks(
    List<_HtmlToken> tokens,
    List<Mark> inheritedMarks,
  ) {
    final nodes = <Node>[];
    final context = _ParseContext(tokens);

    while (context.pos < context.tokens.length) {
      final token = context.current;

      if (token.type == _TokenType.text) {
        final text = token.text!;
        context.advance();
        if (text.isNotEmpty) {
          nodes.add(TextNode(text, marks: inheritedMarks));
        }
        continue;
      }

      if (token.type == _TokenType.closeTag) {
        // Unexpected close — skip
        context.advance();
        continue;
      }

      if (token.type == _TokenType.selfClosing) {
        final node = _parseSelfClosing(token);
        if (node != null) {
          nodes.add(node);
        }
        context.advance();
        continue;
      }

      // Open tag
      final tagName = token.tagName!;
      final attrs = token.attrs;
      context.advance();

      // Collect tokens until matching close
      final innerTokens = <_HtmlToken>[];
      var depth = 1;
      while (context.pos < context.tokens.length && depth > 0) {
        final t = context.current;
        if (t.type == _TokenType.openTag && t.tagName == tagName) {
          depth++;
        } else if (t.type == _TokenType.closeTag && t.tagName == tagName) {
          depth--;
          if (depth == 0) {
            context.advance();
            break;
          }
        }
        innerTokens.add(t);
        context.advance();
      }

      final inlineNodes =
          _parseInlineElement(tagName, attrs, innerTokens, inheritedMarks);
      nodes.addAll(inlineNodes);
    }

    return nodes;
  }

  List<Node> _parseInlineElement(
    String tagName,
    Map<String, String> attrs,
    List<_HtmlToken> innerTokens, [
    List<Mark> inheritedMarks = const [],
  ]) {
    Mark? mark;

    switch (tagName) {
      case 'strong' || 'b':
        mark = Mark.bold;
      case 'em' || 'i':
        mark = Mark.italic;
      case 'u':
        mark = Mark.underline;
      case 's' || 'del' || 'strike':
        mark = Mark.strikethrough;
      case 'code':
        mark = Mark.code;
      case 'sup':
        mark = Mark.superscript;
      case 'sub':
        mark = Mark.subscript;
      case 'a':
        final href = attrs['href'] ?? '';
        final title = attrs['title'];
        mark = Mark.link(href, title: title);
      case 'mark':
        final style = attrs['style'] ?? '';
        final colorMatch =
            RegExp(r'background-color:\s*([^;]+)').firstMatch(style);
        final color = colorMatch?.group(1)?.trim() ?? 'yellow';
        mark = Mark.highlight(color);
      case 'span':
        // Check for special span types
        if (attrs.containsKey('data-mark')) {
          final markType = attrs['data-mark']!;
          final dataAttrs = attrs['data-attrs'];
          final markAttrs = dataAttrs != null
              ? (jsonDecode(dataAttrs) as Map<String, dynamic>)
                  .cast<String, Object?>()
              : const <String, Object?>{};
          mark = Mark(markType, markAttrs);
        } else if (attrs['class'] == 'inline-widget') {
          final widgetType = attrs['data-widget-type'] ?? '';
          final dataAttrs = attrs['data-attrs'];
          final widgetAttrs = dataAttrs != null
              ? (jsonDecode(dataAttrs) as Map<String, dynamic>)
                  .cast<String, Object?>()
              : <String, Object?>{};
          return [
            InlineWidgetNode(
              widgetType: widgetType,
              attrs: widgetAttrs,
              marks: inheritedMarks,
            ),
          ];
        } else {
          // Check for color style
          final style = attrs['style'] ?? '';
          final colorMatch =
              RegExp(r'(?:^|;)\s*color:\s*([^;]+)').firstMatch(style);
          if (colorMatch != null) {
            mark = Mark.color(colorMatch.group(1)!.trim());
          }
        }
      default:
        // Unknown inline tag — just parse children with current marks
        return _parseInlineTokensWithMarks(innerTokens, inheritedMarks);
    }

    if (mark != null) {
      final newMarks = [...inheritedMarks, mark];
      return _parseInlineTokensWithMarks(innerTokens, newMarks);
    }

    return _parseInlineTokensWithMarks(innerTokens, inheritedMarks);
  }

  bool _isInlineTag(String tagName) => const {
        'strong',
        'b',
        'em',
        'i',
        'u',
        's',
        'del',
        'strike',
        'code',
        'sup',
        'sub',
        'a',
        'mark',
        'span',
        'br',
      }.contains(tagName);

  // ── List and table helpers ────────────────────────────────────────

  List<Node> _parseListItems(
    List<_HtmlToken> tokens, {
    bool isCheckList = false,
  }) {
    // Parse tokens and extract only <li> elements
    final items = <Node>[];
    final context = _ParseContext(tokens);

    while (context.pos < context.tokens.length) {
      final token = context.current;

      if (token.type == _TokenType.openTag &&
          token.tagName == 'li') {
        final node = _parseElement(context);
        if (node != null) {
          items.add(node);
        }
      } else {
        context.advance();
      }
    }

    return items;
  }

  List<Node> _parseTableRows(List<_HtmlToken> tokens) {
    final rows = <Node>[];
    final context = _ParseContext(tokens);

    while (context.pos < context.tokens.length) {
      final token = context.current;

      if (token.type == _TokenType.openTag) {
        if (token.tagName == 'tr') {
          final node = _parseElement(context);
          if (node != null) {
            rows.add(node);
          }
        } else if (token.tagName == 'thead' ||
            token.tagName == 'tbody' ||
            token.tagName == 'tfoot') {
          // Skip wrapper tags, descend into content
          context.advance();
        } else {
          context.advance();
        }
      } else if (token.type == _TokenType.closeTag &&
          (token.tagName == 'thead' ||
              token.tagName == 'tbody' ||
              token.tagName == 'tfoot')) {
        context.advance();
      } else {
        context.advance();
      }
    }

    return rows;
  }

  List<Node> _parseTableCells(List<_HtmlToken> tokens) {
    final cells = <Node>[];
    final context = _ParseContext(tokens);

    while (context.pos < context.tokens.length) {
      final token = context.current;

      if (token.type == _TokenType.openTag &&
          (token.tagName == 'td' || token.tagName == 'th')) {
        final node = _parseElement(context);
        if (node != null) {
          cells.add(node);
        }
      } else {
        context.advance();
      }
    }

    return cells;
  }

  /// Extracts plain text from a sequence of tokens (for code blocks).
  String _extractTextFromTokens(List<_HtmlToken> tokens) {
    final buffer = StringBuffer();
    for (final token in tokens) {
      if (token.type == _TokenType.text) {
        buffer.write(token.text);
      }
      // Skip tags inside <pre><code>
    }
    return buffer.toString();
  }

  // ── HTML escaping / entity handling ───────────────────────────────

  static String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _escapeAttr(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// Sanitizes a value for use inside a CSS property.
  ///
  /// Strips characters that could break out of the property value context
  /// (semicolons, braces, parentheses, quotes, backslashes, angle brackets).
  static String _escapeCss(String value) =>
      value.replaceAll(RegExp(r'[;\{\}\(\)<>"\x27\\]'), '');

  static String _decodeEntities(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', '\u00A0');
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal tokenizer types
// ─────────────────────────────────────────────────────────────────────────────

enum _TokenType { openTag, closeTag, selfClosing, text }

class _HtmlToken {
  const _HtmlToken._({
    required this.type,
    this.tagName,
    this.attrs = const {},
    this.text,
  });

  factory _HtmlToken.openTag(String tagName, Map<String, String> attrs) =>
      _HtmlToken._(type: _TokenType.openTag, tagName: tagName, attrs: attrs);

  factory _HtmlToken.closeTag(String tagName) =>
      _HtmlToken._(type: _TokenType.closeTag, tagName: tagName);

  factory _HtmlToken.selfClosing(
    String tagName,
    Map<String, String> attrs,
  ) =>
      _HtmlToken._(
        type: _TokenType.selfClosing,
        tagName: tagName,
        attrs: attrs,
      );

  factory _HtmlToken.text(String text) =>
      _HtmlToken._(type: _TokenType.text, text: text);

  final _TokenType type;
  final String? tagName;
  final Map<String, String> attrs;
  final String? text;
}

class _ParseContext {
  _ParseContext(this.tokens);

  final List<_HtmlToken> tokens;
  int pos = 0;

  _HtmlToken get current => tokens[pos];

  void advance() => pos++;
}
