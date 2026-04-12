import 'package:flutter/material.dart';

import '../models/taxon.dart';
import '../utils/string_utils.dart';
import 'badge_chips.dart';

/// A single row in Aktuell lista.
///
/// [displayCount] — the number shown on the counter (for parents: total
/// across all children; for children: own count).
/// [ownCount] — this taxon's own count, used to determine the green dot.
/// [isChild] — true for Underart / Artkomplex / Kollektivtaxon rows.
class ObservationRow extends StatelessWidget {
  final Taxon taxon;
  final int displayCount;
  final int ownCount;
  final bool isChild;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback? onTap;

  const ObservationRow({
    super.key,
    required this.taxon,
    required this.displayCount,
    required this.ownCount,
    required this.isChild,
    required this.onIncrement,
    required this.onDecrement,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = isChild
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500);
    final sciStyle = theme.textTheme.bodySmall?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: isChild ? 32.0 : 0.0),
        child: SizedBox(
        height: isChild ? 52 : 64,
        child: Row(
          children: [
            // Green dot — visible when this taxon's own count > 0.
            SizedBox(
              width: 20,
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ownCount > 0
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
              ),
            ),

            // Swedish name, scientific name, badges.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(taxon.swedishName.sentenceCase, style: nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (!isChild)
                      Text(taxon.scientificName, style: sciStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    BadgeChips(taxon: taxon),
                  ],
                ),
              ),
            ),

            // Counter: − count +
            _Counter(
              count: displayCount,
              onIncrement: onIncrement,
              onDecrement: onDecrement,
              small: isChild,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final int count;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool small;

  const _Counter({
    required this.count,
    required this.onIncrement,
    required this.onDecrement,
    required this.small,
  });

  @override
  Widget build(BuildContext context) {
    final size = small ? 40.0 : 48.0;
    final fontSize = small ? 16.0 : 20.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: IconButton(
            onPressed: count > 0 ? onDecrement : null,
            icon: const Icon(Icons.remove),
            iconSize: small ? 18 : 22,
            padding: EdgeInsets.zero,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(
          width: size,
          height: size,
          child: IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.add),
            iconSize: small ? 18 : 22,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
