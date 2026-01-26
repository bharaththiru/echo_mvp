import 'package:flutter/material.dart';

import '../app/theme.dart';

class ReportReasonOption {
  const ReportReasonOption(this.id, this.label);

  final String id;
  final String label;
}

const List<ReportReasonOption> reportReasonOptions = [
  ReportReasonOption('harassment_hate', 'Harassment or hate'),
  ReportReasonOption('sexual', 'Sexual content'),
  ReportReasonOption('self_harm', 'Self-harm'),
  ReportReasonOption('threats_violence', 'Threats or violence'),
  ReportReasonOption('spam', 'Spam'),
  ReportReasonOption('other', 'Other'),
];

Future<String?> showReportReasonSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: EchoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report this clip', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'This will hide the clip for you.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: EchoColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: reportReasonOptions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final option = reportReasonOptions[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(
                          color: EchoColors.borderSubtle,
                        ),
                      ),
                      tileColor: EchoColors.muted,
                      title: Text(option.label),
                      onTap: () => Navigator.of(context).pop(option.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
