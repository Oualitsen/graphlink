class TreeNode {
  final String value;
  final List<TreeNode> _children = [];
  TreeNode? parent;
  TreeNode({required this.value, this.parent});

  TreeNode addChild(String value) {
    var child = TreeNode(value: value, parent: this);
    _children.add(child);
    return child;
  }

  bool contains(String value) {
    TreeNode? par = this;
    while (par != null) {
      if (par.value == value) {
        return true;
      }
      par = par.parent;
    }
    return false;
  }

  List<String> getParents() {
    var result = <String>[];
    TreeNode? par = this;
    while (par != null) {
      result.add(par.value);
      par = par.parent;
    }
    return result;
  }

  List<String> getAllValues([bool skipRoot = false]) {
    var result = <String>[];
    if (!skipRoot) {
      result.add(value);
    }
    for (var child in _children) {
      result.addAll(child.getAllValues());
    }

    return result;
  }
}
