import 'dart:convert' show jsonEncode, jsonDecode;

import 'package:meta/meta.dart';

import '../model/fragment.dart';
import '../model/mark.dart';
import '../model/node.dart';
import '../schema/schema.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MarkdownSerializer — Document ↔ Markdown conversion
// ─────────────────────────────────────────────────────────────────────────────

/// Serializes and deserializes documents to/from Markdown.
///
/// Supports standard Markdown plus common extensions:
/// - GitHub-flavored Markdown tables
/// - Task lists (`- [x]` / `- [ ]`)
/// - Strikethrough (`~~text~~`)
/// - Fenced code blocks with language hints
///
/// Example:
/// ```dart
/// final serializer = MarkdownSerializer(schema: richSchema);
///
/// // Serialize document to Markdown
/// final md = serializer.serialize(doc);
///
/// // Deserialize Markdown back to document
/// final doc = serializer.deserialize('# Hello\n\nSome **bold** text.');
/// ```
@immutable
class MarkdownSerializer {
  /// Creates a Markdown serializer with an optional [schema] for type-aware
  /// deserialization.
  const MarkdownSerializer({this.schema});

  /// The schema for type-aware deserialization.
  final Schema? schema;

  // ── Serialization ───────────────────────────────────────────────────

  /// Serializes a document to a Markdown string.
  String serialize(DocNode doc) {
    final buffer = StringBuffer();
    _serializeBlocks(doc.content, buffer, prefix: '');
    // Remove trailing newlines to produce clean output
    return buffer.toString().trimRight();
  }

  void _serializeBlocks(
    Fragment content,
    StringBuffer buffer, {
    required String prefix,
    bool skipTrailingNewline = false,
  }) {
    final count = content.childCount;
    content.forEach((node, _, index) {
      _serializeBlock(node, buffer, prefix: prefix);
      // Add blank line between blocks (except after the last one)
      if (!skipTrailingNewline && index < count - 1) {
        buffer.writeln();
      }
    });
  }

  void _serializeBlock(
    Node node,
    StringBuffer buffer, {
    required String prefix,
  }) {
    switch (node.type) {
      case 'doc':
        _serializeBlocks(node.content, buffer, prefix: prefix);

      case 'paragraph':
        buffer.write(prefix);
        _serializeInline(node.content, buffer);
        buffer.writeln();

      case 'heading':
        final level = ((node.attrs['level'] as int?) ?? 1).clamp(1, 6);
        buffer.write(prefix);
        buffer.write('#' * level);
        buffer.write(' ');
        _serializeInline(node.content, buffer);
        buffer.writeln();

      case 'blockquote':
        final innerBuffer = StringBuffer();
        _serializeBlocks(node.content, innerBuffer, prefix: '');
        final lines = innerBuffer.toString().split('\n');
        // Remove trailing empty line from inner blocks
        final trimmedLines = lines.endsWith('') && lines.length > 1
            ? lines.sublist(0, lines.length - 1)
            : lines;
        for (final line in trimmedLines) {
          buffer.write(prefix);
          if (line.isEmpty) {
            buffer.writeln('>');
          } else {
            buffer.writeln('> $line');
          }
        }

      case 'code_block':
        final language = node.attrs['language'] as String? ?? '';
        buffer.write(prefix);
        buffer.write('```');
        if (language.isNotEmpty) {
          buffer.write(language);
        }
        buffer.writeln();
        final text = node.textContent;
        for (final line in text.split('\n')) {
          buffer.write(prefix);
          buffer.writeln(line);
        }
        buffer.write(prefix);
        buffer.writeln('```');

      case 'bullet_list':
        _serializeListItems(
          node.content,
          buffer,
          prefix: prefix,
          marker: (index) => '- ',
        );

      case 'ordered_list':
        final start = (node.attrs['start'] as int?) ?? 1;
        _serializeListItems(
          node.content,
          buffer,
          prefix: prefix,
          marker: (index) => '${start + index}. ',
        );

      case 'check_list':
        _serializeCheckListItems(node.content, buffer, prefix: prefix);

      case 'list_item':
        // Should not be reached directly — handled by list serialization
        _serializeBlocks(node.content, buffer, prefix: prefix);

      case 'horizontal_rule' || 'divider':
        buffer.write(prefix);
        buffer.writeln('---');

      case 'image':
        final src = node.attrs['src'] as String? ?? '';
        final alt = (node.attrs['alt'] as String? ?? '').replaceAll(']', r'\]');
        final title = node.attrs['title'] as String? ?? '';
        buffer.write(prefix);
        buffer.write('![$alt]($src');
        if (title.isNotEmpty) {
          buffer.write(' "${title.replaceAll('"', '\\"')}"');
        }
        buffer.write(')');
        buffer.writeln();

      case 'hard_break':
        buffer.writeln('  ');

      case 'table':
        _serializeTable(node, buffer, prefix: prefix);

      default:
        // Unknown block — just output text content
        final text = node.textContent;
        if (text.isNotEmpty) {
          buffer.write(prefix);
          buffer.writeln(text);
        }
    }
  }

  void _serializeListItems(
    Fragment content,
    StringBuffer buffer, {
    required String prefix,
    required String Function(int index) marker,
  }) {
    content.forEach((item, _, index) {
      final markerStr = marker(index);
      final indent = ' ' * markerStr.length;

      // Serialize the item's children
      if (item.content.childCount == 0) {
        buffer.write(prefix);
        buffer.writeln(markerStr);
        return;
      }

      var first = true;
      item.content.forEach((child, _, __) {
        if (first) {
          buffer.write(prefix);
          buffer.write(markerStr);
          final firstBuffer = StringBuffer();
          _serializeBlock(child, firstBuffer, prefix: '');
          buffer.write(firstBuffer.toString().trimRight());
          buffer.writeln();
          first = false;
        } else {
          buffer.writeln();
          _serializeBlock(child, buffer, prefix: '$prefix$indent');
        }
      });
    });
  }

  void _serializeCheckListItems(
    Fragment content,
    StringBuffer buffer, {
    required String prefix,
  }) {
    content.forEach((item, _, index) {
      final checked = item.attrs['checked'] == true;
      final checkbox = checked ? '- [x] ' : '- [ ] ';

      if (item.content.childCount == 0) {
        buffer.write(prefix);
        buffer.writeln(checkbox);
        return;
      }

      var first = true;
      item.content.forEach((child, _, __) {
        if (first) {
          buffer.write(prefix);
          buffer.write(checkbox);
          final firstBuffer = StringBuffer();
          _serializeBlock(child, firstBuffer, prefix: '');
          buffer.write(firstBuffer.toString().trimRight());
          buffer.writeln();
          first = false;
        } else {
          buffer.writeln();
          _serializeBlock(child, buffer, prefix: '$prefix      ');
        }
      });
    });
  }

  void _serializeTable(
    Node table,
    StringBuffer buffer, {
    required String prefix,
  }) {
    // Collect all rows
    final rows = <List<String>>[];
    table.content.forEach((row, _, __) {
      final cells = <String>[];
      row.content.forEach((cell, _, __) {
        final cellBuffer = StringBuffer();
        _serializeInline(
          cell.content.childCount > 0 &&
                  cell.content.child(0).content.isNotEmpty
              ? cell.content.child(0).content
              : cell.content,
          cellBuffer,
        );
        cells.add(cellBuffer.toString().trim());
      });
      rows.add(cells);
    });

    if (rows.isEmpty) return;

    // Calculate column widths
    final colCount = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    final colWidths = List<int>.filled(colCount, 3);
    for (final row in rows) {
      for (var i = 0; i < row.length; i++) {
        if (row[i].length > colWidths[i]) {
          colWidths[i] = row[i].length;
        }
      }
    }

    // Write header row
    if (rows.isNotEmpty) {
      buffer.write(prefix);
      buffer.write('|');
      for (var i = 0; i < colCount; i++) {
        final cell = i < rows[0].length ? rows[0][i] : '';
        buffer.write(' ${cell.padRight(colWidths[i])} |');
      }
      buffer.writeln();

      // Write separator
      buffer.write(prefix);
      buffer.write('|');
      for (var i = 0; i < colCount; i++) {
        buffer.write(' ${'-' * colWidths[i]} |');
      }
      buffer.writeln();

      // Write data rows
      for (var r = 1; r < rows.length; r++) {
        buffer.write(prefix);
        buffer.write('|');
        for (var i = 0; i < colCount; i++) {
          final cell = i < rows[r].length ? rows[r][i] : '';
          buffer.write(' ${cell.padRight(colWidths[i])} |');
        }
        buffer.writeln();
      }
    }
  }

  // ── Inline serialization ──────────────────────────────────────────

  void _serializeInline(Fragment content, StringBuffer buffer) {
    content.forEach((node, _, __) {
      if (node.isText) {
        _serializeTextNode(node as TextNode, buffer);
      } else if (node.type == 'hard_break') {
        buffer.write('  \n');
      } else if (node.type == 'image') {
        final src = node.attrs['src'] as String? ?? '';
        final alt = node.attrs['alt'] as String? ?? '';
        final title = node.attrs['title'] as String? ?? '';
        buffer.write('![$alt]($src');
        if (title.isNotEmpty) {
          buffer.write(' "$title"');
        }
        buffer.write(')');
      } else if (node is InlineWidgetNode) {
        // Encode inline widgets as HTML comments for lossless round-trip.
        // Sanitize to prevent --> from breaking the comment.
        final attrsJson = jsonEncode(node.attrs).replaceAll('-->', '--&gt;');
        final safeType = node.widgetType.replaceAll('-->', '--&gt;');
        buffer.write('<!-- widget:$safeType $attrsJson -->');
      } else {
        // Other inline nodes — just output text
        buffer.write(node.textContent);
      }
    });
  }

  void _serializeTextNode(TextNode node, StringBuffer buffer) {
    var text = node.text;
    if (node.marks.isEmpty) {
      buffer.write(text);
      return;
    }

    // Apply marks — build wrapping strings
    var prefix = '';
    var suffix = '';

    for (final mark in node.marks) {
      final wrapper = _markToMarkdown(mark, text);
      prefix = '$prefix${wrapper.prefix}';
      suffix = '${wrapper.suffix}$suffix';
      if (wrapper.transformedText != null) {
        text = wrapper.transformedText!;
      }
    }

    buffer.write('$prefix$text$suffix');
  }

  ({String prefix, String suffix, String? transformedText}) _markToMarkdown(
    Mark mark,
    String text,
  ) {
    switch (mark.type) {
      case 'bold':
        return (prefix: '**', suffix: '**', transformedText: null);
      case 'italic':
        return (prefix: '*', suffix: '*', transformedText: null);
      case 'strikethrough':
        return (prefix: '~~', suffix: '~~', transformedText: null);
      case 'code':
        return (prefix: '`', suffix: '`', transformedText: null);
      case 'link':
        final href = (mark.attrs['href'] as String? ?? '')
            .replaceAll(r'\', r'\\')
            .replaceAll('(', '%28')
            .replaceAll(')', '%29');
        final title = mark.attrs['title'] as String?;
        final titlePart = (title != null && title.isNotEmpty)
            ? ' "${title.replaceAll('"', '\\"')}"'
            : '';
        return (
          prefix: '[',
          suffix: ']($href$titlePart)',
          transformedText: null,
        );
      default:
        // No markdown equivalent — just output the text
        return (prefix: '', suffix: '', transformedText: null);
    }
  }

  // ── Deserialization ─────────────────────────────────────────────────

  /// Deserializes a Markdown string into a document node.
  DocNode deserialize(String markdown) {
    if (markdown.trim().isEmpty) {
      return DocNode(
        content: Fragment([
          const BlockNode(type: 'paragraph', inlineContent: true),
        ]),
      );
    }

    final lines = markdown.split('\n');
    final blocks = _parseLines(lines);

    if (blocks.isEmpty) {
      return DocNode(
        content: Fragment([
          const BlockNode(type: 'paragraph', inlineContent: true),
        ]),
      );
    }

    return DocNode(content: Fragment(blocks));
  }

  List<Node> _parseLines(List<String> lines) {
    final blocks = <Node>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // Blank line — skip
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Horizontal rule: ---, ***, ___
      if (_isHorizontalRule(line)) {
        blocks.add(const BlockNode(type: 'horizontal_rule', isLeaf: true));
        i++;
        continue;
      }

      // Heading: # through ######
      final headingMatch = _headingRe.firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final text = headingMatch.group(2)!;
        blocks.add(
          BlockNode(
            type: 'heading',
            attrs: {'level': level},
            content: Fragment(_parseInlineMarkdown(text)),
            inlineContent: true,
          ),
        );
        i++;
        continue;
      }

      // Fenced code block: ```
      if (line.trimLeft().startsWith('```')) {
        final result = _parseFencedCodeBlock(lines, i);
        blocks.add(result.node);
        i = result.nextIndex;
        continue;
      }

      // Blockquote: >
      if (line.trimLeft().startsWith('>')) {
        final result = _parseBlockquote(lines, i);
        blocks.add(result.node);
        i = result.nextIndex;
        continue;
      }

      // Indented code block (4 spaces or tab)
      if (line.startsWith('    ') || line.startsWith('\t')) {
        final result = _parseIndentedCodeBlock(lines, i);
        blocks.add(result.node);
        i = result.nextIndex;
        continue;
      }

      // Task list item: - [x] or - [ ] or * [x] or * [ ]
      if (_isTaskListItem(line)) {
        final result = _parseTaskList(lines, i);
        blocks.add(result.node);
        i = result.nextIndex;
        continue;
      }

      // Unordered list: - or *
      if (_isUnorderedListItem(line)) {
        final result = _parseUnorderedList(lines, i);
        blocks.add(result.node);
        i = result.nextIndex;
        continue;
      }

      // Ordered list: 1.
      if (_isOrderedListItem(line)) {
        final result = _parseOrderedList(lines, i);
        blocks.add(result.node);
        i = result.nextIndex;
        continue;
      }

      // Image on its own line: ![alt](url)
      final imageMatch = _blockImageRe.firstMatch(line);
      if (imageMatch != null) {
        final attrs = <String, Object?>{
          'src': imageMatch.group(2)!,
          'alt': imageMatch.group(1)!,
        };
        final title = imageMatch.group(3);
        if (title != null) {
          attrs['title'] = title;
        }
        blocks.add(
          BlockNode(type: 'image', attrs: attrs, isLeaf: true, isAtom: true),
        );
        i++;
        continue;
      }

      // Paragraph: collect lines until blank line or block-level construct
      final result = _parseParagraph(lines, i);
      blocks.add(result.node);
      i = result.nextIndex;
    }

    return blocks;
  }

  // ── Block parsers ─────────────────────────────────────────────────

  bool _isHorizontalRule(String line) {
    final trimmed = line.trim();
    if (trimmed.length < 3) return false;
    // Must be only -, *, or _ (with optional spaces)
    final stripped = trimmed.replaceAll(' ', '');
    if (stripped.isEmpty) return false;
    final char = stripped[0];
    if (char != '-' && char != '*' && char != '_') return false;
    return stripped.split('').every((c) => c == char);
  }

  ({Node node, int nextIndex}) _parseFencedCodeBlock(
    List<String> lines,
    int start,
  ) {
    final openLine = lines[start].trimLeft();
    final fence = openLine.startsWith('```') ? '```' : '~~~';
    final language = openLine.substring(fence.length).trim();

    final codeLines = <String>[];
    var i = start + 1;

    while (i < lines.length) {
      if (lines[i].trimLeft().startsWith(fence)) {
        i++;
        break;
      }
      codeLines.add(lines[i]);
      i++;
    }

    final code = codeLines.join('\n');
    final attrs = <String, Object?>{};
    if (language.isNotEmpty) {
      attrs['language'] = language;
    }

    return (
      node: BlockNode(
        type: 'code_block',
        attrs: attrs,
        content: code.isNotEmpty ? Fragment([TextNode(code)]) : Fragment.empty,
      ),
      nextIndex: i,
    );
  }

  ({Node node, int nextIndex}) _parseBlockquote(List<String> lines, int start) {
    final quotedLines = <String>[];
    var i = start;

    while (i < lines.length) {
      final line = lines[i];
      if (line.trimLeft().startsWith('>')) {
        // Remove the leading > and optional space
        final content = line.trimLeft().replaceFirst(_blockquoteContentRe, '');
        quotedLines.add(content);
        i++;
      } else if (line.trim().isEmpty && quotedLines.isNotEmpty) {
        // Check if next non-empty line continues the quote
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) {
          j++;
        }
        if (j < lines.length && lines[j].trimLeft().startsWith('>')) {
          quotedLines.add('');
          i++;
        } else {
          break;
        }
      } else {
        break;
      }
    }

    final innerBlocks = _parseLines(quotedLines);
    final content = innerBlocks.isNotEmpty
        ? Fragment(innerBlocks)
        : Fragment([const BlockNode(type: 'paragraph', inlineContent: true)]);

    return (
      node: BlockNode(type: 'blockquote', content: content),
      nextIndex: i,
    );
  }

  ({Node node, int nextIndex}) _parseIndentedCodeBlock(
    List<String> lines,
    int start,
  ) {
    final codeLines = <String>[];
    var i = start;

    while (i < lines.length) {
      final line = lines[i];
      if (line.startsWith('    ')) {
        codeLines.add(line.substring(4));
        i++;
      } else if (line.startsWith('\t')) {
        codeLines.add(line.substring(1));
        i++;
      } else if (line.trim().isEmpty) {
        codeLines.add('');
        i++;
      } else {
        break;
      }
    }

    // Remove trailing empty lines
    while (codeLines.isNotEmpty && codeLines.last.isEmpty) {
      codeLines.removeLast();
    }

    final code = codeLines.join('\n');
    return (
      node: BlockNode(
        type: 'code_block',
        content: code.isNotEmpty ? Fragment([TextNode(code)]) : Fragment.empty,
      ),
      nextIndex: i,
    );
  }

  bool _isTaskListItem(String line) {
    final trimmed = line.trimLeft();
    return _taskItemRe.hasMatch(trimmed);
  }

  bool _isUnorderedListItem(String line) {
    final trimmed = line.trimLeft();
    return _unorderedItemRe.hasMatch(trimmed) && !_isTaskListItem(line);
  }

  bool _isOrderedListItem(String line) {
    final trimmed = line.trimLeft();
    return _orderedItemRe.hasMatch(trimmed);
  }

  ({Node node, int nextIndex}) _parseTaskList(List<String> lines, int start) {
    final items = <Node>[];
    var i = start;

    while (i < lines.length) {
      final line = lines[i];
      if (!_isTaskListItem(line)) break;

      final match = _taskItemFullRe.firstMatch(line.trimLeft());
      if (match == null) break;

      final checked = match.group(1)!.toLowerCase() == 'x';
      final text = match.group(2)!;

      items.add(
        BlockNode(
          type: 'check_item',
          attrs: {'checked': checked},
          content: Fragment([
            BlockNode(
              type: 'paragraph',
              content: Fragment(_parseInlineMarkdown(text)),
              inlineContent: true,
            ),
          ]),
        ),
      );
      i++;
    }

    return (
      node: BlockNode(type: 'check_list', content: Fragment(items)),
      nextIndex: i,
    );
  }

  Node _buildListItem(String text) => BlockNode(
    type: 'list_item',
    content: Fragment([
      BlockNode(
        type: 'paragraph',
        content: Fragment(_parseInlineMarkdown(text)),
        inlineContent: true,
      ),
    ]),
  );

  ({Node node, int nextIndex}) _parseUnorderedList(
    List<String> lines,
    int start,
  ) {
    final items = <Node>[];
    var i = start;
    // Accumulate text for the current item (supports continuation lines).
    var currentItemText = '';

    while (i < lines.length) {
      final line = lines[i];
      if (_isUnorderedListItem(line)) {
        // Flush previous item if any.
        if (currentItemText.isNotEmpty || items.isNotEmpty) {
          if (currentItemText.isNotEmpty) {
            items.add(_buildListItem(currentItemText));
          }
        }
        currentItemText = line.trimLeft().replaceFirst(_unorderedItemRe, '');
        i++;
      } else if (items.isNotEmpty || currentItemText.isNotEmpty) {
        // Continuation line or blank line within the list.
        if (line.trim().isEmpty || _isIndentedContinuation(line)) {
          if (currentItemText.isNotEmpty && line.trim().isNotEmpty) {
            // Append continuation text (strip leading indent).
            currentItemText += ' ${line.trimLeft()}';
          }
          i++;
        } else {
          break;
        }
      } else {
        break;
      }
    }

    // Flush final item.
    if (currentItemText.isNotEmpty) {
      items.add(_buildListItem(currentItemText));
    }

    return (
      node: BlockNode(type: 'bullet_list', content: Fragment(items)),
      nextIndex: i,
    );
  }

  ({Node node, int nextIndex}) _parseOrderedList(
    List<String> lines,
    int start,
  ) {
    final items = <Node>[];
    var i = start;
    int? startNum;
    var currentItemText = '';

    while (i < lines.length) {
      final line = lines[i];
      if (_isOrderedListItem(line)) {
        // Flush previous item.
        if (currentItemText.isNotEmpty) {
          items.add(_buildListItem(currentItemText));
        }

        final match = _orderedItemFullRe.firstMatch(line.trimLeft());
        if (match == null) break;

        startNum ??= int.parse(match.group(1)!);
        currentItemText = match.group(2)!;
        i++;
      } else if (items.isNotEmpty || currentItemText.isNotEmpty) {
        if (line.trim().isEmpty || _isIndentedContinuation(line)) {
          if (currentItemText.isNotEmpty && line.trim().isNotEmpty) {
            currentItemText += ' ${line.trimLeft()}';
          }
          i++;
        } else {
          break;
        }
      } else {
        break;
      }
    }

    // Flush final item.
    if (currentItemText.isNotEmpty) {
      items.add(_buildListItem(currentItemText));
    }

    return (
      node: BlockNode(
        type: 'ordered_list',
        attrs: {'start': startNum ?? 1},
        content: Fragment(items),
      ),
      nextIndex: i,
    );
  }

  bool _isIndentedContinuation(String line) =>
      line.startsWith('  ') || line.startsWith('\t');

  ({Node node, int nextIndex}) _parseParagraph(List<String> lines, int start) {
    final paragraphLines = <String>[];
    var i = start;

    while (i < lines.length) {
      final line = lines[i];

      // Stop at blank line
      if (line.trim().isEmpty) break;

      // Stop at block-level constructs
      if (_isHorizontalRule(line)) break;
      if (_headingBreakRe.hasMatch(line)) break;
      if (line.trimLeft().startsWith('```')) break;
      if (line.trimLeft().startsWith('>')) break;
      if (_isUnorderedListItem(line)) break;
      if (_isOrderedListItem(line)) break;
      if (_isTaskListItem(line)) break;

      paragraphLines.add(line);
      i++;
    }

    final text = paragraphLines.join('\n');
    return (
      node: BlockNode(
        type: 'paragraph',
        content: Fragment(_parseInlineMarkdown(text)),
        inlineContent: true,
      ),
      nextIndex: i,
    );
  }

  // ── Precompiled patterns ────────────────────────────────────────

  static final _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _blockImageRe = RegExp(
    r'^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)\s*$',
  );
  static final _blockquoteContentRe = RegExp(r'^>\s?');
  static final _taskItemRe = RegExp(r'^[-*]\s+\[([ xX])\]\s');
  static final _taskItemFullRe = RegExp(r'^[-*]\s+\[([ xX])\]\s(.*)$');
  static final _unorderedItemRe = RegExp(r'^[-*]\s');
  static final _orderedItemRe = RegExp(r'^\d+\.\s');
  static final _orderedItemFullRe = RegExp(r'^(\d+)\.\s(.*)$');
  static final _headingBreakRe = RegExp(r'^#{1,6}\s');
  static final _inlineImageRe = RegExp(
    r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)',
  );
  static final _inlineLinkRe = RegExp(
    r'\[([^\]]+)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)',
  );
  static final _inlineBoldRe = RegExp(r'\*\*(.+?)\*\*');
  static final _inlineItalicRe = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final _inlineStrikeRe = RegExp(r'~~(.+?)~~');
  static final _inlineCodeRe = RegExp(r'`([^`]+)`');
  static final _inlineWidgetRe = RegExp(r'<!-- widget:([^\s]+) ({.*}) -->');

  // ── Inline Markdown parsing ───────────────────────────────────────

  List<Node> _parseInlineMarkdown(String text) {
    if (text.isEmpty) return [];

    final nodes = <Node>[];
    _parseInlineRecursive(text, const [], nodes);
    return nodes;
  }

  void _parseInlineRecursive(String text, List<Mark> marks, List<Node> nodes) {
    if (text.isEmpty) return;

    // Find the earliest inline pattern
    _InlineMatch? earliest;

    // Image: ![alt](url "title")
    final imageMatch = _inlineImageRe.firstMatch(text);
    if (imageMatch != null) {
      earliest = _choosEarliest(
        earliest,
        _InlineMatch(
          imageMatch.start,
          imageMatch.end,
          'image',
          match: imageMatch,
        ),
      );
    }

    // Link: [text](url "title")
    final linkMatch = _inlineLinkRe.firstMatch(text);
    if (linkMatch != null) {
      earliest = _choosEarliest(
        earliest,
        _InlineMatch(linkMatch.start, linkMatch.end, 'link', match: linkMatch),
      );
    }

    // Bold: **text**
    final boldMatch = _inlineBoldRe.firstMatch(text);
    if (boldMatch != null) {
      earliest = _choosEarliest(
        earliest,
        _InlineMatch(boldMatch.start, boldMatch.end, 'bold', match: boldMatch),
      );
    }

    // Italic: *text*
    final italicMatch = _inlineItalicRe.firstMatch(text);
    if (italicMatch != null) {
      earliest = _choosEarliest(
        earliest,
        _InlineMatch(
          italicMatch.start,
          italicMatch.end,
          'italic',
          match: italicMatch,
        ),
      );
    }

    // Strikethrough: ~~text~~
    final strikeMatch = _inlineStrikeRe.firstMatch(text);
    if (strikeMatch != null) {
      earliest = _choosEarliest(
        earliest,
        _InlineMatch(
          strikeMatch.start,
          strikeMatch.end,
          'strikethrough',
          match: strikeMatch,
        ),
      );
    }

    // Inline code: `text`
    final codeMatch = _inlineCodeRe.firstMatch(text);
    if (codeMatch != null) {
      earliest = _choosEarliest(
        earliest,
        _InlineMatch(codeMatch.start, codeMatch.end, 'code', match: codeMatch),
      );
    }

    // Inline widget comment: <!-- widget:type {"key":"value"} -->
    final widgetMatch = _inlineWidgetRe.firstMatch(text);
    if (widgetMatch != null) {
      earliest = _choosEarliest(
        earliest,
        _InlineMatch(
          widgetMatch.start,
          widgetMatch.end,
          'widget',
          match: widgetMatch,
        ),
      );
    }

    if (earliest == null) {
      // No patterns found — emit as plain text
      if (text.isNotEmpty) {
        nodes.add(TextNode(text, marks: marks));
      }
      return;
    }

    // Emit text before the match
    if (earliest.start > 0) {
      nodes.add(TextNode(text.substring(0, earliest.start), marks: marks));
    }

    // Handle the match
    switch (earliest.type) {
      case 'image':
        final m = earliest.match!;
        final attrs = <String, Object?>{'src': m.group(2)!, 'alt': m.group(1)!};
        final title = m.group(3);
        if (title != null) {
          attrs['title'] = title;
        }
        nodes.add(
          BlockNode(type: 'image', attrs: attrs, isLeaf: true, isAtom: true),
        );

      case 'link':
        final m = earliest.match!;
        final linkText = m.group(1)!;
        final href = m.group(2)!;
        final title = m.group(3);
        final linkMark = Mark.link(href, title: title);
        final newMarks = [...marks, linkMark];
        _parseInlineRecursive(linkText, newMarks, nodes);

      case 'bold':
        final m = earliest.match!;
        final innerText = m.group(1)!;
        final newMarks = [...marks, Mark.bold];
        _parseInlineRecursive(innerText, newMarks, nodes);

      case 'italic':
        final m = earliest.match!;
        final innerText = m.group(1)!;
        final newMarks = [...marks, Mark.italic];
        _parseInlineRecursive(innerText, newMarks, nodes);

      case 'strikethrough':
        final m = earliest.match!;
        final innerText = m.group(1)!;
        final newMarks = [...marks, Mark.strikethrough];
        _parseInlineRecursive(innerText, newMarks, nodes);

      case 'code':
        final m = earliest.match!;
        final codeText = m.group(1)!;
        final newMarks = [...marks, Mark.code];
        nodes.add(TextNode(codeText, marks: newMarks));

      case 'widget':
        final m = earliest.match!;
        final widgetType = m.group(1)!.replaceAll('--&gt;', '-->');
        final attrsJson = m.group(2)!.replaceAll('--&gt;', '-->');
        final attrs = (jsonDecode(attrsJson) as Map<String, dynamic>)
            .cast<String, Object?>();
        nodes.add(InlineWidgetNode(widgetType: widgetType, attrs: attrs));
    }

    // Parse the rest
    if (earliest.end < text.length) {
      _parseInlineRecursive(text.substring(earliest.end), marks, nodes);
    }
  }

  _InlineMatch? _choosEarliest(_InlineMatch? current, _InlineMatch candidate) {
    if (current == null) return candidate;
    if (candidate.start < current.start) return candidate;
    return current;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal types
// ─────────────────────────────────────────────────────────────────────────────

class _InlineMatch {
  const _InlineMatch(this.start, this.end, this.type, {this.match});

  final int start;
  final int end;
  final String type;
  final RegExpMatch? match;
}

/// Extension to check if a list of strings ends with an empty string.
extension on List<String> {
  bool endsWith(String value) => isNotEmpty && last == value;
}
