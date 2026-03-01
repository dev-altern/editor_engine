import 'package:meta/meta.dart';

import '../model/node.dart';
import 'schema.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ContentExpression — Parsed content expression
// ─────────────────────────────────────────────────────────────────────────────

/// A parsed content expression that can validate a node's children.
///
/// Content expressions define what children a node type can have.
/// They are a simple grammar:
/// - `"block+"` → one or more nodes in the "block" group
/// - `"inline*"` → zero or more inline nodes
/// - `"paragraph heading?"` → a paragraph, optionally followed by a heading
/// - `""` → no content
@immutable
class ContentExpression {
  /// Creates a content expression from a parsed list of elements.
  const ContentExpression(this.elements);

  /// Parses a content expression string.
  ///
  /// Grammar:
  /// - Words are node type names or group names
  /// - `+` means one or more
  /// - `*` means zero or more
  /// - `?` means zero or one
  /// - Spaces separate sequence elements
  /// - `(a | b)` means choice (a or b)
  factory ContentExpression.parse(String expr) {
    if (expr.isEmpty) return const ContentExpression([]);

    // Normalize: remove spaces inside parenthesized groups before splitting
    final normalized = expr.trim().replaceAllMapped(
      RegExp(r'\([^)]+\)'),
      (m) => m.group(0)!.replaceAll(' ', ''),
    );

    final elements = <ContentElement>[];
    final parts = normalized.split(RegExp(r'\s+'));

    for (final part in parts) {
      String name;
      Quantifier quantifier;

      if (part.endsWith('+')) {
        name = part.substring(0, part.length - 1);
        quantifier = Quantifier.oneOrMore;
      } else if (part.endsWith('*')) {
        name = part.substring(0, part.length - 1);
        quantifier = Quantifier.zeroOrMore;
      } else if (part.endsWith('?')) {
        name = part.substring(0, part.length - 1);
        quantifier = Quantifier.zeroOrOne;
      } else {
        name = part;
        quantifier = Quantifier.one;
      }

      // Handle parenthesized choice groups: (a|b)+
      if (name.startsWith('(') && name.endsWith(')')) {
        final choices = name
            .substring(1, name.length - 1)
            .split('|')
            .map((s) => s.trim())
            .toList();
        elements.add(
          ContentElement(choices.first, quantifier, choices: choices),
        );
      } else {
        elements.add(ContentElement(name, quantifier));
      }
    }

    return ContentExpression(elements);
  }

  /// An empty content expression (leaf node).
  static const ContentExpression empty = ContentExpression([]);

  /// The parsed elements.
  final List<ContentElement> elements;

  /// Whether this expression allows no content (leaf).
  bool get isLeaf => elements.isEmpty;

  /// Whether this expression allows inline content.
  bool get allowsInline => elements.any((e) {
    final names = e.isChoice ? e.choices : [e.name];
    return names.any((n) => n == 'inline' || n == 'text');
  });

  /// Whether this expression allows block content.
  bool get allowsBlock => elements.any((e) {
    final names = e.isChoice ? e.choices : [e.name];
    return names.any((n) => n == 'block');
  });

  /// Validates that [children] satisfy this expression.
  ///
  /// Uses the [schema] to resolve group names to concrete types.
  bool validate(List<Node> children, Schema schema) {
    if (isLeaf) return children.isEmpty;

    var childIdx = 0;
    for (final element in elements) {
      var count = 0;

      while (childIdx < children.length) {
        final child = children[childIdx];
        if (_matchesElement(child, element, schema)) {
          count++;
          childIdx++;
          if (element.quantifier == Quantifier.one ||
              element.quantifier == Quantifier.zeroOrOne) {
            break;
          }
        } else {
          break;
        }
      }

      if (count < element.minCount) return false;
    }

    return childIdx == children.length;
  }

  bool _matchesElement(Node node, ContentElement element, Schema schema) {
    final namesToCheck = element.isChoice ? element.choices : [element.name];

    for (final name in namesToCheck) {
      // Direct type match
      if (node.type == name) return true;

      // Group match
      final spec = schema.nodeSpec(node.type);
      if (spec != null && spec.group == name) return true;

      // "inline" matches any inline node
      if (name == 'inline' && node.isInline) return true;

      // "block" matches any block node
      if (name == 'block' && node.isBlock && node.type != 'doc') return true;

      // "text" matches text nodes
      if (name == 'text' && node.isText) return true;
    }

    return false;
  }

  @override
  String toString() => elements.isEmpty
      ? '(empty)'
      : elements.map((e) => e.toString()).join(' ');
}

/// A single element in a content expression.
@immutable
class ContentElement {
  const ContentElement(this.name, this.quantifier, {this.choices = const []});

  /// The type or group name.
  final String name;

  /// The quantifier.
  final Quantifier quantifier;

  /// For choice groups like `(a|b)`, all possible type/group names.
  /// Empty means this is a simple (non-choice) element.
  final List<String> choices;

  /// Whether this is a choice group.
  bool get isChoice => choices.isNotEmpty;

  /// Minimum count required.
  int get minCount {
    switch (quantifier) {
      case Quantifier.one:
        return 1;
      case Quantifier.oneOrMore:
        return 1;
      case Quantifier.zeroOrMore:
        return 0;
      case Quantifier.zeroOrOne:
        return 0;
    }
  }

  @override
  String toString() {
    final suffix = switch (quantifier) {
      Quantifier.one => '',
      Quantifier.oneOrMore => '+',
      Quantifier.zeroOrMore => '*',
      Quantifier.zeroOrOne => '?',
    };
    if (isChoice) return '(${choices.join('|')})$suffix';
    return '$name$suffix';
  }
}

/// Quantifier for content expression elements.
enum Quantifier {
  /// Exactly one.
  one,

  /// One or more.
  oneOrMore,

  /// Zero or more.
  zeroOrMore,

  /// Zero or one.
  zeroOrOne,
}
