import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/repositories/transaction_notes_repository.dart';
import 'package:flutter/material.dart';

class TransactionNoteScreen extends StatefulWidget {
  final String txid;
  final String? initialNote;

  const TransactionNoteScreen({
    super.key,
    required this.txid,
    this.initialNote,
  });

  @override
  State<TransactionNoteScreen> createState() => _TransactionNoteScreenState();
}

class _TransactionNoteScreenState extends State<TransactionNoteScreen> {
  static const int maxChars = 100;
  
  late final TextEditingController _controller;
  final _notesRepository = TransactionNotesRepository.instance;
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
    // Auto-save
    _notesRepository.saveNote(widget.txid, text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context, _controller.text),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, color: Bitcoin.neutral8),
                    Text(
                      'Back to transaction',
                      style: BitcoinTextStyle.body4(Bitcoin.neutral8),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                'Enter note',
                style: BitcoinTextStyle.body3(Bitcoin.neutral8),
              ),
              const SizedBox(height: 16),
              // Text field
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
                  counterText: '', // Hide default counter
                ),
                style: BitcoinTextStyle.body4(Bitcoin.neutral8),
              ),
              const SizedBox(height: 8),
              // Auto-save indicator
              Center(
                child: Text(
                  'Auto-saved. $_charsRemaining/$maxChars chars remaining.',
                  style: BitcoinTextStyle.body5(Bitcoin.neutral5),
                ),
              ),
              const SizedBox(height: 24),
              // Save button
              SizedBox(
                width: double.infinity,
                child: BitcoinButtonFilled(
                  body: Text('Save', style: BitcoinTextStyle.body4(Bitcoin.white)),
                  onPressed: () => Navigator.pop(context, _controller.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
