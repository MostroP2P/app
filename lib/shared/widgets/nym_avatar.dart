import 'package:flutter/material.dart';

/// Deterministic pseudonymous avatar derived from a Nostr public key.
///
/// Renders a colored circle background (HSV hue from [colorHue]) with a
/// white icon selected by [iconIndex] (0–36).
///
/// **Rendering contract (FR-011c)**: The icon is ALWAYS white regardless of
/// the hue value — v1 had a bug where the icon color matched the background,
/// making it invisible.
class NymAvatar extends StatelessWidget {
  const NymAvatar({
    super.key,
    required this.iconIndex,
    required this.colorHue,
    this.size = 40,
  }) : assert(iconIndex >= 0 && iconIndex <= 36, 'iconIndex must be 0–36'),
       assert(colorHue >= 0 && colorHue <= 359, 'colorHue must be 0–359');

  /// Icon selector (0–36), derived from NymIdentity.icon_index.
  final int iconIndex;

  /// HSV hue (0–359) for the avatar background circle.
  final int colorHue;

  /// Diameter of the avatar circle.
  final double size;

  @override
  Widget build(BuildContext context) {
    final bgColor = HSVColor.fromAHSV(1.0, colorHue.toDouble(), 0.65, 0.70)
        .toColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          _kNymIcons[iconIndex],
          // Icon is ALWAYS white — FR-011c rendering contract.
          color: Colors.white,
          size: size * 0.55,
          semanticLabel: 'Avatar icon',
        ),
      ),
    );
  }
}

/// 37 icon entries (index 0–36). Must not be reordered — the mapping is
/// derived deterministically from public keys.
const List<IconData> _kNymIcons = [
  Icons.pets,                   // 0
  Icons.forest,                 // 1
  Icons.waves,                  // 2
  Icons.bolt,                   // 3
  Icons.wb_sunny_outlined,      // 4
  Icons.nightlight_round,       // 5
  Icons.star_border,            // 6
  Icons.diamond_outlined,       // 7
  Icons.sailing,                // 8
  Icons.terrain,                // 9
  Icons.local_fire_department,  // 10
  Icons.ac_unit,                // 11
  Icons.spa,                    // 12
  Icons.rocket_launch,          // 13
  Icons.anchor,                 // 14
  Icons.whatshot,               // 15
  Icons.filter_vintage,         // 16
  Icons.emoji_nature,           // 17
  Icons.catching_pokemon,       // 18
  Icons.cruelty_free,           // 19
  Icons.brightness_5,           // 20
  Icons.cloud_outlined,         // 21
  Icons.water_drop,             // 22
  Icons.local_florist,          // 23
  Icons.eco,                    // 24
  Icons.dark_mode_outlined,     // 25
  Icons.lens_blur,              // 26
  Icons.tornado,                // 27
  Icons.thunderstorm_outlined,  // 28
  Icons.flare,                  // 29
  Icons.ac_unit_outlined,       // 30
  Icons.circle_outlined,        // 31
  Icons.hexagon_outlined,       // 32
  Icons.pentagon_outlined,      // 33
  Icons.change_history,         // 34
  Icons.grade,                  // 35
  Icons.auto_awesome,           // 36
];
