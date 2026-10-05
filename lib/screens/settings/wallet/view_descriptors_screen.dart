import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ViewDescriptorsScreen extends StatelessWidget {
  final String encodedWatchOnly;
  final String encodedFull;
  final String twoKeyWatchOnly;
  final String twoKeyFull;

  const ViewDescriptorsScreen({
    super.key,
    required this.encodedWatchOnly,
    required this.encodedFull,
    required this.twoKeyWatchOnly,
    required this.twoKeyFull,
  });

  void _copyToClipboard(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 1),
        content: Text('Copied to clipboard'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final descriptors = [
      _DescriptorEntry(
        title: 'Encoded (watch-only)',
        value: encodedWatchOnly,
      ),
      _DescriptorEntry(
        title: 'Encoded (full)',
        value: encodedFull,
      ),
      _DescriptorEntry(
        title: 'Two-key (watch-only)',
        value: twoKeyWatchOnly,
      ),
      _DescriptorEntry(
        title: 'Two-key (full)',
        value: twoKeyFull,
      ),
    ];

    return ScreenSkeleton(
      showBackButton: true,
      title: 'Descriptors',
      body: ListView.separated(
        itemCount: descriptors.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final entry = descriptors[index];
          return _DescriptorCard(
            title: entry.title,
            value: entry.value,
            onCopy: () => _copyToClipboard(context, entry.value),
          );
        },
      ),
    );
  }
}

class _DescriptorEntry {
  final String title;
  final String value;

  _DescriptorEntry({required this.title, required this.value});
}

class _DescriptorCard extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onCopy;

  const _DescriptorCard({
    required this.title,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Bitcoin.neutral2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: BitcoinTextStyle.body4(Bitcoin.neutral8),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                color: Bitcoin.neutral6,
                onPressed: onCopy,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            value,
            style: BitcoinTextStyle.body5(Bitcoin.neutral7).copyWith(
              fontFamily: 'Inter',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
