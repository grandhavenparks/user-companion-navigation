import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/tree.dart';

class TreeMarkerWidget extends StatelessWidget {
  const TreeMarkerWidget({
    super.key,
    required this.tree,
    this.isHighlighted = false,
  });

  final Tree tree;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(tree.treeClassification);
    final size = isHighlighted ? 28.0 : 20.0;
    
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isHighlighted 
              ? Colors.yellow 
              : (tree.visited ? Colors.white : color.withOpacity(0.8)),
          width: isHighlighted ? 4 : (tree.visited ? 3 : 2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: isHighlighted ? 6 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        tree.visited ? Icons.check : Icons.place,
        color: Colors.white,
        size: size,
      ),
    );
  }

  static Color _colorFor(TreeClassification c) {
    switch (c) {
      case TreeClassification.environment:
        return AppTheme.environmentColor;
      case TreeClassification.sick:
        return AppTheme.sickColor;
      case TreeClassification.dead:
        return AppTheme.deadColor;
    }
  }
}
