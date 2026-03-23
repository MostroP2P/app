# Nym Identity System (v1 Reference)

> This document describes the pseudonym and avatar system from v1 for chat identity.

## Overview

In Mostro, users never see each other's real pubkeys or identities during chat. Instead, each party is represented by:

1. **Pseudonym (Nym)**: A human-readable "adjective-noun" handle
2. **Avatar**: A colored icon derived from the pubkey

Both are **deterministic** — the same pubkey always produces the same nym and avatar.

## Pseudonym Generation

### Algorithm

```dart
String deterministicHandleFromHexKey(String hexKey) {
  // Parse 32-byte hex pubkey as BigInt
  final pubKeyBigInt = BigInt.parse(hexKey, radix: 16);
  
  // Pick adjective using modulo
  final indexAdjective = pubKeyBigInt % BigInt.from(kAdjectives.length);
  
  // Pick noun using integer division + modulo
  final indexNoun = (pubKeyBigInt ~/ BigInt.from(kAdjectives.length)) 
                    % BigInt.from(kNouns.length);
  
  return '${kAdjectives[indexAdjective.toInt()]}-${kNouns[indexNoun.toInt()]}';
}
```

### Word Lists

#### Adjectives (~46 words)
Bitcoin/Nostr/privacy themed:
- shadowy, orange, nonCustodial, trustless, unbanked, atomic, magic
- hidden, incognito, anonymous, encrypted, ghostly, silent, masked
- stealthy, free, nostalgic, ephemeral, sovereign, unstoppable
- private, censorshipResistant, hush, defiant, subversive
- fiery, subzero, burning, cosmic, mighty, whispering, cyber
- rusty, nihilistic, dark, wicked, spicy, noKYC, discreet
- loose, boosted, starving, hungry, orwellian, bullish, bearish

#### Nouns (~85 words)
Mix of Bitcoin legends, animals, places, and culture:
- wizard, pirate, zap, node, invoice, nipster, nomad, sats
- bull, bear, whale, frog, gorilla, nostrich
- halFinney, hodlonaut, satoshi, nakamoto, samurai, sparrow
- crusader, tinkerer, nostr, pleb, warrior, ecdsa
- monkey, wolf, renegade, minotaur, phoenix, dragon
- fiatjaf, roasbeef (Bitcoin/Nostr personalities)
- berlin, tokyo, buenosAires, caracas, havana, miami, prague
- amsterdam, lugano, seoul, bitcoinBeach (cities)
- carnivore, ape, honeyBadger, mempool
- Venezuelan culture: pana, chamo, catire, arepa, cachapa, tequeño, hallaca, roraima, canaima, turpial, araguaney, cunaguaro, chiguire, mamarracho, cambur

### Examples
- `shadowy-wizard`
- `noKYC-satoshi`
- `anonymous-nostrich`
- `bullish-tequeño`

## Avatar Generation

### Icon Selection

```dart
IconData pickNymIcon(String hexPubKey) {
  final pubKeyBigInt = BigInt.parse(hexPubKey, radix: 16);
  final index = (pubKeyBigInt % BigInt.from(kPossibleIcons.length)).toInt();
  return kPossibleIcons[index];
}
```

### Icon List (~37 icons)
Material icons:
- person, star, favorite, lock, adb, bolt, casino
- visibility, language, face, thumb_up, pets, hotel_class
- anchor, school, public, construction, emoji_emotions
- whatshot, waving_hand, nights_stay, cruelty_free
- outdoor_grill, sports_motorsports, sports_football
- skateboarding, sports_martial_arts, paragliding
- face_6, south_america, face_2, tsunami
- local_shipping, flight, directions_run
- lunch_dining, directions_boat

### Color Selection

```dart
Color pickNymColor(String hexPubKey) {
  final pubKeyBigInt = BigInt.parse(hexPubKey, radix: 16);
  final hue = (pubKeyBigInt % BigInt.from(360)).toInt().toDouble();
  return HSVColor.fromAHSV(1.0, hue, 0.6, 0.8).toColor();
}
```

- Hue: 0-359 (full color wheel)
- Saturation: 0.6 (moderately saturated)
- Value: 0.8 (bright but not blinding)

### Widget Implementation (v2 corrected)

> Note: The v1 implementation had a bug where the icon color matched the background,
> making the icon invisible. The v2 implementation fixes this with proper contrast.

```dart
class NymAvatar extends StatelessWidget {
  final String nym;        // From Rust: "shadowy-wizard"
  final int iconIndex;     // From Rust: index into icon list
  final int colorHue;      // From Rust: 0-359

  const NymAvatar({
    super.key,
    required this.nym,
    required this.iconIndex,
    required this.colorHue,
    this.size = 32.0,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = kPossibleIcons[iconIndex];
    final bgColor = HSVColor.fromAHSV(1.0, colorHue.toDouble(), 0.6, 0.8).toColor();

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bgColor,
      child: Icon(
        icon,
        size: size * 0.6,
        color: Colors.white,  // Always white for contrast
      ),
    );
  }
}
```

## Privacy Considerations

1. **No real identity exposure**: Users never see actual pubkeys in the UI
2. **Deterministic but not reversible**: Given a nym, you cannot derive the pubkey
3. **Collision possible**: With ~46 adjectives × ~85 nouns = ~3,910 combinations, collisions can occur across many users. This is acceptable since nyms are only used for visual distinction within a single trade, not for authentication.
4. **Trade-key-based**: Nyms are derived from trade keys, not identity keys. In privacy mode, each trade uses a different key, so the same user gets different nyms across trades.

## v2 Implementation Notes

### Rust Side (All Deterministic Logic)

All nym generation **must** be in Rust for cross-platform consistency:

```rust
// rust/src/api/nym.rs

#[frb]
pub struct NymIdentity {
    pub pseudonym: String,    // "shadowy-wizard"
    pub icon_index: u8,       // Index into icon list (0-36)
    pub color_hue: u16,       // HSV hue (0-359)
}

#[frb]
pub fn generate_nym(pubkey_hex: String) -> NymIdentity {
    let pubkey_bigint = BigUint::parse_bytes(pubkey_hex.as_bytes(), 16)
        .unwrap_or_default();
    
    let adj_index = (&pubkey_bigint % ADJECTIVES.len()).to_usize().unwrap();
    let noun_index = ((&pubkey_bigint / ADJECTIVES.len()) % NOUNS.len())
        .to_usize().unwrap();
    let icon_index = (&pubkey_bigint % ICONS.len()).to_u8().unwrap();
    let color_hue = (&pubkey_bigint % 360u32).to_u16().unwrap();
    
    NymIdentity {
        pseudonym: format!("{}-{}", ADJECTIVES[adj_index], NOUNS[noun_index]),
        icon_index,
        color_hue,
    }
}
```

Exposed via flutter_rust_bridge:
- `generateNym(pubkeyHex: String) -> NymIdentity`

### Dart Side (Rendering Only)

Dart only handles widget rendering — receives all values from Rust:

```dart
// lib/src/widgets/nym_avatar.dart

class NymAvatar extends StatelessWidget {
  final NymIdentity identity;  // From Rust
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = kPossibleIcons[identity.iconIndex];
    final bgColor = HSVColor.fromAHSV(
      1.0, 
      identity.colorHue.toDouble(), 
      0.6, 
      0.8,
    ).toColor();

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bgColor,
      child: Icon(icon, size: size * 0.6, color: Colors.white),
    );
  }
}
```

### Why All Logic in Rust?

1. **Cross-platform consistency**: Same pubkey produces identical nym on iOS, Android, Web, Desktop
2. **Single source of truth**: Word lists and algorithm defined once
3. **Testable**: Rust unit tests verify determinism
4. **No divergence risk**: Dart and Rust can't produce different results

### Testing

#### Rust Unit Tests
```rust
#[test]
fn test_nym_determinism() {
    let pubkey = "a1b2c3..."; // Known test pubkey
    let nym1 = generate_nym(pubkey.to_string());
    let nym2 = generate_nym(pubkey.to_string());
    assert_eq!(nym1.pseudonym, nym2.pseudonym);
    assert_eq!(nym1.icon_index, nym2.icon_index);
    assert_eq!(nym1.color_hue, nym2.color_hue);
}

#[test]
fn test_known_nym_values() {
    // Regression test with known pubkey -> known nym
    let pubkey = "0000...0001";
    let nym = generate_nym(pubkey.to_string());
    assert_eq!(nym.pseudonym, "shadowy-wizard"); // Expected value
    assert_eq!(nym.icon_index, 1);
    assert_eq!(nym.color_hue, 1);
}
```

#### Flutter Widget Tests
```dart
testWidgets('NymAvatar renders correctly', (tester) async {
  final identity = NymIdentity(
    pseudonym: 'test-nym',
    iconIndex: 0,
    colorHue: 180,
  );
  
  await tester.pumpWidget(
    MaterialApp(home: NymAvatar(identity: identity, size: 48)),
  );
  
  expect(find.byType(CircleAvatar), findsOneWidget);
  expect(find.byType(Icon), findsOneWidget);
});
```

#### Visual Regression (Golden Tests)
```dart
testWidgets('NymAvatar golden test', (tester) async {
  // Test multiple hues and icons for visual consistency
  await expectLater(
    find.byType(NymAvatar),
    matchesGoldenFile('goldens/nym_avatar_hue_0.png'),
  );
});
```
