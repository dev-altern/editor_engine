import 'package:editor_engine/editor_engine.dart';

DocNode doc(List<Node> blocks) => DocNode.fromBlocks(blocks);

BlockNode para(String text, {List<Mark> marks = const []}) => BlockNode(
  type: 'paragraph',
  inlineContent: true,
  content: Fragment([TextNode(text, marks: marks)]),
);

BlockNode heading(String text, {int level = 1}) => BlockNode(
  type: 'heading',
  attrs: {'level': level},
  inlineContent: true,
  content: Fragment([TextNode(text)]),
);

BlockNode emptyPara() =>
    BlockNode(type: 'paragraph', inlineContent: true, content: Fragment.empty);

BlockNode blockquote(List<Node> blocks) =>
    BlockNode(type: 'blockquote', content: Fragment(blocks));

BlockNode bulletList(List<Node> items) =>
    BlockNode(type: 'bullet_list', content: Fragment(items));

BlockNode listItem(List<Node> blocks) =>
    BlockNode(type: 'list_item', content: Fragment(blocks));
