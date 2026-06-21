import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/data/enums/amount_display_unit.dart';
import 'package:danawallet/widgets/skeletons/screen_skeleton.dart';
import 'package:danawallet/widgets/buttons/footer/footer_button.dart';
import 'package:flutter/material.dart';

class ChangeAmountDisplayScreen extends StatefulWidget {
  final AmountDisplayUnit currentUnit;
  final ValueSetter<AmountDisplayUnit> onConfirm;

  const ChangeAmountDisplayScreen(
      {super.key, required this.currentUnit, required this.onConfirm});

  @override
  State<ChangeAmountDisplayScreen> createState() =>
      _ChangeAmountDisplayScreenState();
}

class _ChangeAmountDisplayScreenState extends State<ChangeAmountDisplayScreen> {
  AmountDisplayUnit? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentUnit;
  }

  @override
  Widget build(BuildContext context) {
    final body = RadioGroup<AmountDisplayUnit>(
        groupValue: _selected,
        onChanged: (AmountDisplayUnit? value) {
          setState(() {
            _selected = value;
          });
        },
        child: ListView.separated(
          separatorBuilder: (context, index) => const Divider(),
          itemCount: AmountDisplayUnit.values.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(AmountDisplayUnit.values[index].displayNameLabel(),
                style: BitcoinTextStyle.body3(Bitcoin.black)),
            leading: Radio<AmountDisplayUnit>(
              value: AmountDisplayUnit.values[index],
            ),
            onTap: () {
              setState(() {
                _selected = AmountDisplayUnit.values[index];
              });
            },
          ),
        ));

    final footer = FooterButton(
        title: 'Confirm', onPressed: () => widget.onConfirm(_selected!));

    return ScreenSkeleton(
        title: 'Choose amount display',
        body: body,
        showBackButton: true,
        footer: footer);
  }
}
