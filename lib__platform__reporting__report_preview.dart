import 'package:flutter/material.dart';

import '../../design_system/components/components.dart';
import 'report_dataset.dart';

/// The report as an on-screen table, scrolling sideways when wide.
class ReportPreview extends StatelessWidget {
  const ReportPreview({super.key, required this.data, this.maxRows = 300, this.moreText});

  final ReportDataset data;
  final int maxRows;
  final String? moreText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final scale = data.fontSize < 8 ? 1.6 : 1.4;
    double widthOf(ReportColumn c) => (c.width ?? 160.0 * (c.flex ?? 1.0).clamp(1.0, 3.0).toDouble()) * scale;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface);
    final rows = data.rows.take(maxRows).toList();

    Widget cell(String text, ReportColumn c, {TextStyle? style, Color? fill}) => Container(
          width: widthOf(c),
          color: fill,
          alignment: switch (c.align) {
            ReportAlign.left => Alignment.centerLeft,
            ReportAlign.center => Alignment.center,
            ReportAlign.right => Alignment.centerRight,
          },
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(text, style: style ?? textStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SdCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  color: theme.colorScheme.primary,
                  child: Row(children: [
                    for (final c in data.columns)
                      cell(c.label, c, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onPrimary)),
                  ]),
                ),
                for (final r in rows)
                  if (r.kind == ReportRowKind.group)
                    Container(
                      color: sd.subtleFill,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Text(r.groupTitle ?? '', style: theme.textTheme.titleSmall),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: r.highlight ? sd.absent.withValues(alpha: 0.06) : null,
                        border: Border(bottom: BorderSide(color: sd.border, width: 0.5)),
                      ),
                      child: Row(children: [
                        for (var i = 0; i < data.columns.length; i++)
                          cell(
                            i < r.cells.length ? r.cells[i] : '',
                            data.columns[i],
                            style: r.textColors[i] == null ? null : textStyle?.copyWith(color: Color(r.textColors[i]!)),
                            fill: data.shadedColumns.contains(i) ? sd.subtleFill : null,
                          ),
                      ]),
                    ),
              ],
            ),
          ),
        ),
        if (data.rows.length > maxRows && moreText != null)
          Padding(
            padding: const EdgeInsets.only(top: SdSpace.sm),
            child: Text(moreText!, style: theme.textTheme.bodySmall),
          ),
        for (final n in data.notes)
          Padding(padding: const EdgeInsets.only(top: SdSpace.sm), child: Text(n, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
