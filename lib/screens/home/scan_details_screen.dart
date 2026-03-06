import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const int _blocksPerDay = 144;

/// Estimate the date of a block height given a reference tip height and today's date.
DateTime _estimateBlockDate(int blockHeight, int tipHeight) {
  final blocksAgo = tipHeight - blockHeight;
  final daysAgo = blocksAgo ~/ _blocksPerDay;
  return DateTime.now().subtract(Duration(days: daysAgo));
}

/// Format a DateTime as YYYY-MM-DD.
String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class ScanDetailsScreen extends StatelessWidget {
  const ScanDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scanProgress = Provider.of<ScanProgressNotifier>(context);
    final chainState = Provider.of<ChainState>(context);
    final tip = chainState.available ? chainState.tip : scanProgress.end;

    final bool rescanEnabled =
        !scanProgress.scanning && scanProgress.paused;

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Text(
          'Scan Details',
          style: BitcoinTextStyle.body2(Bitcoin.neutral8)
              .apply(fontWeightDelta: 2),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Start / end labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tip > 0
                          ? _formatDate(
                              _estimateBlockDate(scanProgress.start, tip))
                          : scanProgress.start.toString(),
                      style: BitcoinTextStyle.body4(Bitcoin.neutral8)
                          .apply(fontWeightDelta: 1),
                    ),
                    Text(
                      'block ${scanProgress.start}',
                      style: BitcoinTextStyle.body5(Bitcoin.neutral6),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(DateTime.now()),
                      style: BitcoinTextStyle.body4(Bitcoin.neutral8)
                          .apply(fontWeightDelta: 1),
                    ),
                    Text(
                      'block ${scanProgress.end} · now',
                      style: BitcoinTextStyle.body5(Bitcoin.neutral6),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Bitcoin.blue),
                backgroundColor: Bitcoin.neutral4,
                value: scanProgress.progress,
                minHeight: 8.0,
              ),
            ),
            const SizedBox(height: 8),

            // Blocks remaining + time estimate (below bar)
            if (scanProgress.scanning || scanProgress.paused) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${scanProgress.end - scanProgress.current} blocks remaining',
                    style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                  ),
                  if (scanProgress.estimatedTimeRemaining != null) ...[
                    Text(
                      '  ·  ',
                      style: BitcoinTextStyle.body5(Bitcoin.neutral6),
                    ),
                    Text(
                      scanProgress.estimatedTimeRemaining!,
                      style: BitcoinTextStyle.body5(Bitcoin.neutral7),
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Outputs found
            _buildInfoRow(
              'Outputs found',
              scanProgress.outputsFound.toString(),
              Icons.output,
            ),

            const Spacer(),

            // Bottom controls
            // Status badge
            Row(
              children: [
                _buildStatusBadge(scanProgress.scanning, scanProgress.paused),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons row
            Row(
              children: [
                if (scanProgress.scanning)
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.pause,
                      label: 'Pause',
                      onTap: () => scanProgress.pause(),
                    ),
                  ),
                if (!scanProgress.scanning && scanProgress.paused)
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.play_arrow,
                      label: 'Resume',
                      onTap: () => scanProgress.resume(),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.history,
                    label: 'Rescan from date',
                    onTap: rescanEnabled
                        ? () => _openRescanDatePicker(context)
                        : null,
                    enabled: rescanEnabled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openRescanDatePicker(BuildContext context) async {
    final selectedDate = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(
        builder: (context) => const _RescanDatePickerScreen(),
      ),
    );

    if (selectedDate != null) {
      // TODO: implement rescan logic with selectedDate
    }
  }

  Widget _buildStatusBadge(bool scanning, bool paused) {
    final Color color;
    final String label;

    if (scanning) {
      color = Bitcoin.green;
      label = 'Scanning';
    } else if (paused) {
      color = Bitcoin.orange;
      label = 'Paused';
    } else {
      color = Bitcoin.neutral6;
      label = 'Idle';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: BitcoinTextStyle.body4(color)),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    final color = enabled ? Bitcoin.blue : Bitcoin.neutral5;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: (enabled ? Bitcoin.blue : Bitcoin.neutral5)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: (enabled ? Bitcoin.blue : Bitcoin.neutral5)
                  .withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: BitcoinTextStyle.body4(color)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon,
      {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: Bitcoin.neutral6, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: BitcoinTextStyle.body4(Bitcoin.neutral7)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: BitcoinTextStyle.body3(Bitcoin.neutral8)
                    .apply(fontWeightDelta: 1),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: BitcoinTextStyle.body5(Bitcoin.neutral6),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Date picker screen for choosing a rescan date.
class _RescanDatePickerScreen extends StatefulWidget {
  const _RescanDatePickerScreen();

  @override
  State<_RescanDatePickerScreen> createState() =>
      _RescanDatePickerScreenState();
}

class _RescanDatePickerScreenState extends State<_RescanDatePickerScreen> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _selectedDate = DateTime.utc(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Text(
          'Rescan from date',
          style: BitcoinTextStyle.body2(Bitcoin.neutral8)
              .apply(fontWeightDelta: 2),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          children: [
            Text(
              'Choose a date to rescan from. All transactions after this date will be re-scanned.',
              style: BitcoinTextStyle.body3(Bitcoin.neutral7),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: CalendarDatePicker(
                  initialDate: _selectedDate,
                  firstDate: minimumAllowedBirthday,
                  lastDate: DateTime.now().toUtc(),
                  currentDate: DateTime.now().toUtc(),
                  onDateChanged: (date) {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: BitcoinButtonFilled(
                tintColor: danaBlue,
                body: Text(
                  'Rescan from ${_formatDate(_selectedDate)}',
                  style: BitcoinTextStyle.body3(Bitcoin.white),
                ),
                cornerRadius: 6,
                onPressed: () => Navigator.of(context).pop(_selectedDate),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
