import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TransactionNoteScreen extends StatefulWidget {
  final int transactionId;
  final String? initialNote;

  const TransactionNoteScreen({
    super.key,
    required this.transactionId,
    this.initialNote,
  });

  @override
  State<TransactionNoteScreen> createState() => _TransactionNoteScreenState();
}

class _TransactionNoteScreenState extends State<TransactionNoteScreen> {
  static const int maxChars = 100;

  late final TextEditingController _controller;
  int _charsRemaining = maxChars;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote ?? '');
    _charsRemaining = maxChars - _controller.text.length;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    setState(() {
      _charsRemaining = maxChars - text.length;
    });
  }

  Future<void> _saveNote() async {
    final walletState = Provider.of<WalletState>(context, listen: false);
    await walletState.saveNote(widget.transactionId, _controller.text);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenSkeleton(
      showBackButton: true,
      title: 'Enter note',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLength: maxChars,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Things like who sent you this and for what?',
              hintStyle: BitcoinTextStyle.body4(Bitcoin.neutral5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Bitcoin.neutral3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Bitcoin.neutral3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Bitcoin.neutral5),
              ),
              counterText: '',
            ),
            style: BitcoinTextStyle.body4(Bitcoin.neutral8),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '$_charsRemaining/$maxChars chars remaining.',
              style: BitcoinTextStyle.body5(Bitcoin.neutral5),
            ),
          ),
        ],
      ),
      footer: SizedBox(
          width: double.infinity,
          child: FooterButton(title: 'Save', onPressed: _saveNote)),
    );
  }
}
