import 'package:auto_size_text/auto_size_text.dart';
import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

class ViewDescriptorsScreen extends StatefulWidget {
  final String encodedWatchOnly;
  final String? encodedFull;
  final String twoKeyWatchOnly;
  final String? twoKeyFull;
  final DateTime? birthday;

  const ViewDescriptorsScreen({
    super.key,
    required this.encodedWatchOnly,
    required this.encodedFull,
    required this.twoKeyWatchOnly,
    required this.twoKeyFull,
    this.birthday,
  });

  @override
  State<ViewDescriptorsScreen> createState() => _ViewDescriptorsScreenState();
}

class _ViewDescriptorsScreenState extends State<ViewDescriptorsScreen> {
  bool _encoded = false;

  void _copyToClipboard(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('Copied $label descriptor'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchOnly =
        _encoded ? widget.encodedWatchOnly : widget.twoKeyWatchOnly;
    final full = _encoded ? widget.encodedFull : widget.twoKeyFull;

    final title = AutoSizeText(
      "These are your wallet descriptors",
      style: BitcoinTextStyle.title2(Colors.black)
          .copyWith(height: 1.8, fontFamily: 'Inter'),
      textAlign: TextAlign.center,
      maxLines: 2,
    );

    final text = AutoSizeText(
      "You can recover this wallet by using a full descriptor.",
      style: BitcoinTextStyle.body3(Bitcoin.neutral7).copyWith(
        fontFamily: 'Inter',
      ),
      textAlign: TextAlign.center,
      maxLines: 3,
    );

    final birthday = widget.birthday;
    Widget? birthdayText;
    if (birthday != null) {
      final locale = Localizations.localeOf(context);
      final birthdayDateString =
          DateFormat('d MMM yyyy', locale.toString()).format(birthday);
      birthdayText = AutoSizeText(
        "Wallet birthday: $birthdayDateString",
        style: BitcoinTextStyle.body3(Bitcoin.neutral1Dark).copyWith(
          fontFamily: 'Inter',
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
      );
    }

    return ScreenSkeleton(
      showBackButton: true,
      body: Column(
        children: [
          title,
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: Adaptive.h(3),
              horizontal: Adaptive.w(2),
            ),
            child: text,
          ),
          if (birthdayText != null)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: Adaptive.h(1),
                horizontal: Adaptive.w(2),
              ),
              child: birthdayText,
            ),
          const SizedBox(height: 24),
          _DescriptorCard(
            title: 'Full',
            onCopy: full == null
                ? null
                : () => _copyToClipboard(context, full, 'full'),
          ),
          const SizedBox(height: 16),
          _DescriptorCard(
            title: 'Watch-only',
            onCopy: () => _copyToClipboard(context, watchOnly, 'watch-only'),
          ),
          const Spacer(),
          _EncodedToggle(
            encoded: _encoded,
            onChanged: (encoded) => setState(() => _encoded = encoded),
          ),
        ],
      ),
    );
  }
}

class _EncodedToggle extends StatelessWidget {
  final bool encoded;
  final ValueChanged<bool> onChanged;

  const _EncodedToggle({
    required this.encoded,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ToggleLabel(
          label: 'Two-key',
          selected: !encoded,
          onTap: () => onChanged(false),
        ),
        Transform.scale(
          scale: 0.7,
          child: Switch(
            value: encoded,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            thumbColor: WidgetStateProperty.all(Bitcoin.neutral6),
            trackColor: WidgetStateProperty.all(Bitcoin.neutral3),
          ),
        ),
        _ToggleLabel(
          label: 'Encoded',
          selected: encoded,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _ToggleLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: BitcoinTextStyle.body5(
          selected ? Bitcoin.neutral8 : Bitcoin.neutral5,
        ).copyWith(fontFamily: 'Inter'),
      ),
    );
  }
}

class _DescriptorCard extends StatelessWidget {
  final String title;
  final VoidCallback? onCopy;

  const _DescriptorCard({
    required this.title,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Bitcoin.neutral2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: BitcoinTextStyle.body4(Bitcoin.neutral8),
            ),
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
    );
  }
}
