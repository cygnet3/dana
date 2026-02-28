import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ScanDetailsScreen extends StatelessWidget {
  const ScanDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scanProgress = Provider.of<ScanProgressNotifier>(context);

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
            // Progress bar
            Row(
              children: [
                Text(
                  'Scanning: ${(scanProgress.progress * 100.0).toStringAsFixed(1)}%',
                  style: BitcoinTextStyle.body4(Bitcoin.neutral7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Bitcoin.blue),
                      backgroundColor: Bitcoin.neutral4,
                      value: scanProgress.progress,
                      minHeight: 8.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Scan status
            _buildStatusBadge(scanProgress.scanning),
            const SizedBox(height: 24),

            // Block info cards
            _buildInfoRow(
              'Start block',
              scanProgress.start.toString(),
              Icons.first_page,
            ),
            const Divider(height: 1),
            _buildInfoRow(
              'Current block',
              scanProgress.current.toString(),
              Icons.sync,
            ),
            const Divider(height: 1),
            _buildInfoRow(
              'End block (tip)',
              scanProgress.end.toString(),
              Icons.last_page,
            ),
            const Divider(height: 1),
            _buildInfoRow(
              'Outputs found',
              scanProgress.outputsFound.toString(),
              Icons.output,
            ),

            const SizedBox(height: 24),

            // Blocks remaining
            if (scanProgress.scanning) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Bitcoin.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Bitcoin.blue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      '${scanProgress.end - scanProgress.current}',
                      style: BitcoinTextStyle.body1(Bitcoin.blue)
                          .apply(fontSizeDelta: 4, fontWeightDelta: 2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'blocks remaining',
                      style: BitcoinTextStyle.body4(Bitcoin.neutral7),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool scanning) {
    final color = scanning ? Bitcoin.green : Bitcoin.neutral6;
    final label = scanning ? 'Scanning' : 'Idle';

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

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: Bitcoin.neutral6, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: BitcoinTextStyle.body4(Bitcoin.neutral7)),
          ),
          Text(
            value,
            style: BitcoinTextStyle.body3(Bitcoin.neutral8)
                .apply(fontWeightDelta: 1),
          ),
        ],
      ),
    );
  }
}
