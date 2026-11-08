import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

/// The symbol shown beside a currency code: its flag for a fiat, a neutral
/// coin for a pegged code, stablecoin or bitcoin on another network
/// (DS-TYP-9). Nothing for a code the catalogue lacks.
///
/// [size] is the font size a flag is drawn at; the coin is sized to sit on
/// the same line. The flag inherits the theme's flags fallback (DS-TYP-8);
/// the coin is painted, so it never reaches a font.
class CurrencyMark extends ConsumerWidget {
  const CurrencyMark({super.key, required this.code, required this.size});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flag = ref.watch(currencyFlagsProvider)[code];
    if (flag != null) return Text(flag, style: TextStyle(fontSize: size));
    final peg = ref.watch(currencyPegsProvider)[code];
    if (peg == null) return const SizedBox.shrink();
    return StablecoinCoin(peg: peg, size: size);
  }
}

/// [CurrencyMark] followed by [gap] — or nothing at all for a code without a
/// mark, so the text after it never sits behind an empty gap.
class CurrencyMarkGap extends ConsumerWidget {
  const CurrencyMarkGap({
    super.key,
    required this.code,
    required this.size,
    required this.gap,
  });

  final String code;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMark =
        ref.watch(currencyFlagsProvider).containsKey(code) ||
        ref.watch(currencyPegsProvider).containsKey(code);
    if (!hasMark) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsetsDirectional.only(end: gap),
      child: CurrencyMark(code: code, size: size),
    );
  }
}

/// The sign a peg is written with, inside the coin: its fiat's, or bitcoin's
/// for bitcoin on another network (#907).
String pegSign(String peg) => switch (peg.toUpperCase()) {
  'BTC' => '₿',
  'USD' => r'$',
  'EUR' => '€',
  'GBP' => '£',
  'JPY' => '¥',
  _ => peg.toUpperCase().substring(0, 1),
};

/// A ring carrying its peg's sign: the neutral mark of a pegged code. No
/// issuer logo (a trademark), no emoji (an OS font).
class StablecoinCoin extends StatelessWidget {
  const StablecoinCoin({super.key, required this.peg, required this.size});

  final String peg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    // A flag glyph is wider than its font size; the coin matches that box.
    final box = size * 1.2;
    return Semantics(
      label: peg,
      child: CustomPaint(
        size: Size.square(box),
        painter: _CoinPainter(
          ring: book.textSecondary,
          fill: book.inset,
          ink: book.textStrong,
          sign: pegSign(peg),
          box: box,
        ),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter({
    required this.ring,
    required this.fill,
    required this.ink,
    required this.sign,
    required this.box,
  });

  final Color ring;
  final Color fill;
  final Color ink;
  final String sign;
  final double box;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = (box / 12).clamp(1.0, 2.0);
    final radius = box / 2 - stroke / 2;
    canvas.drawCircle(centre, radius, Paint()..color = fill);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final text = TextPainter(
      text: TextSpan(
        text: sign,
        style: TextStyle(
          fontFamily: AppFonts.figures,
          fontWeight: FontWeight.w700,
          fontSize: box * 0.62,
          color: ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - text.size.center(Offset.zero));
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.ring != ring ||
      old.fill != fill ||
      old.ink != ink ||
      old.sign != sign ||
      old.box != box;
}
