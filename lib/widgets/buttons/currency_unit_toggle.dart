import 'package:bitcoin_ui/bitcoin_ui.dart';
import 'package:danawallet/constants.dart';
import 'package:flutter/material.dart';

class CurrencyUnitToggle extends StatelessWidget {
  final bool isFiatSelected;
  final String fiatSymbol;
  final bool enabled;
  final VoidCallback? onTap;

  const CurrencyUnitToggle({
    super.key,
    required this.isFiatSelected,
    required this.fiatSymbol,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(6.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border:
                    Border.all(color: Bitcoin.neutral7.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5.0),
                child: IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _side(
                        selected: !isFiatSelected,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(btcSymbol, style: _textStyle(!isFiatSelected)),
                            const SizedBox(width: 4.0),
                            Text(
                              satSymbol,
                              style: _textStyle(!isFiatSelected)
                                  .copyWith(fontFamily: satFontFamily),
                            ),
                          ],
                        ),
                      ),
                      VerticalDivider(
                        width: 1.0,
                        thickness: 1.0,
                        color: Bitcoin.neutral7.withValues(alpha: 0.35),
                      ),
                      _side(
                        selected: isFiatSelected,
                        child:
                            Text(fiatSymbol, style: _textStyle(isFiatSelected)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _textStyle(bool selected) {
    return BitcoinTextStyle.body3(
      selected ? Bitcoin.black : Bitcoin.neutral7,
    ).copyWith(
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    );
  }

  Widget _side({required bool selected, required Widget child}) {
    return Container(
      color: selected
          ? Bitcoin.orange.withValues(alpha: 0.12)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: child,
    );
  }
}
