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
  final VoidCallback? onLongPressAdd;
  final VoidCallback? onCountTap;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool hasSubRows;
  final bool collapsed;
  final int multiplier;

  const ObservationRow({
    super.key,
    required this.taxon,
    required this.displayCount,
    required this.ownCount,
    required this.isChild,
    required this.onIncrement,
    required this.onDecrement,
    this.onLongPressAdd,
    this.onCountTap,
    this.onTap,
    this.onLongPress,
    this.hasSubRows = false,
    this.collapsed = false,
    this.multiplier = 1,
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
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.only(left: isChild ? 32.0 : 0.0, right: 12.0),
        child: SizedBox(
        height: isChild ? 52 : 64,
        child: Row(
          children: [
            // Green dot or collapse chevron.
            SizedBox(
              width: 20,
              child: Center(
                child: hasSubRows
                    ? Icon(
                        collapsed
                            ? Icons.expand_more
                            : Icons.expand_less,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : Container(
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
            TallyCounter(
              count: displayCount,
              onIncrement: onIncrement,
              onDecrement: onDecrement,
              onLongPressAdd: onLongPressAdd,
              onCountTap: onCountTap,
              small: isChild,
              multiplier: multiplier,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Shared counter widget used by both main observation rows and sub-rows.
class TallyCounter extends StatelessWidget {
  final int count;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback? onLongPressAdd;
  final VoidCallback? onCountTap;
  final bool small;
  final int multiplier;

  const TallyCounter({
    super.key,
    required this.count,
    required this.onIncrement,
    required this.onDecrement,
    this.onLongPressAdd,
    this.onCountTap,
    this.small = false,
    this.multiplier = 1,
  });

  @override
  Widget build(BuildContext context) {
    final plusSize = small ? 40.0 : 48.0;
    final minusSize = small ? 32.0 : 36.0;
    final fontSize = small ? 16.0 : 20.0;
    final decrementEnabled = count > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Multiplier label (hidden when x1).
        if (multiplier > 1)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'x$multiplier',
              style: TextStyle(
                fontSize: small ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1565C0),
              ),
            ),
          ),
        // − button: smaller red circle
        SizedBox(
          width: minusSize,
          height: minusSize,
          child: Material(
            color: decrementEnabled
                ? const Color(0xFFD32F2F)
                : Colors.grey.shade300,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: decrementEnabled ? onDecrement : null,
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(
                  Icons.remove,
                  size: small ? 16 : 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: small ? 36 : 40,
          child: InkWell(
            onTap: onCountTap,
            borderRadius: BorderRadius.circular(4),
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
        ),
        // + button: larger green circle
        SizedBox(
          width: plusSize,
          height: plusSize,
          child: Material(
            color: const Color(0xFF388E3C),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onIncrement,
              onLongPress: onLongPressAdd,
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: small ? 20 : 26,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
