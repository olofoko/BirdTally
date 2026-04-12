import 'package:flutter/material.dart';

import '../models/taxon.dart';

/// Displays compact conservation-status badges for a taxon.
/// Renders nothing if the taxon has no applicable badges.
class BadgeChips extends StatelessWidget {
  final Taxon taxon;
  final double fontSize;

  const BadgeChips({super.key, required this.taxon, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (taxon.hasRedListBadge) {
      final label = taxon.redListCategory!.replaceAll('°', '°'); // keep as-is
      chips.add(_badge(label, _redListColor(taxon.redListCategory!)));
    }
    if (taxon.isBirdsDirective) {
      chips.add(_badge('FD I', Colors.blue.shade700));
    }
    if (taxon.isForestryPriority) {
      chips.add(_badge('Skog', Colors.brown.shade600));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: chips,
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color, width: 0.8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Color _redListColor(String category) {
    return switch (category.replaceAll('°', '')) {
      'CR' || 'CR°' => Colors.red.shade800,
      'EN' => Colors.red.shade600,
      'VU' => Colors.orange.shade700,
      'NT' || 'NT°' => Colors.amber.shade700,
      'DD' => Colors.grey.shade600,
      'RE' => Colors.purple.shade700,
      'NE' || 'NA' => Colors.grey.shade500,
      'LC' => Colors.green.shade600,
      _ => Colors.green.shade700,
    };
  }
}
