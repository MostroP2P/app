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

### Widget Implementation

```dart
class NymAvatar extends StatelessWidget {
  final String pubkeyHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = pickNymIcon(pubkeyHex);
    final color = pickNymColor(pubkeyHex);

    return CircleAvatar(
      radius: size - 8,
      backgroundColor: color,
      child: CircleAvatar(
        child: Icon(
          icon,
          size: size,
          color: color,
        ),
      ),
    );
  }
}
```

## Privacy Considerations

1. **No real identity exposure**: Users never see actual pubkeys in the UI
2. **Deterministic but not reversible**: Given a nym, you cannot derive the pubkey
3. **Collision possible**: With ~46 adjectives × ~85 nouns = ~3,910 combinations, collisions can occur across many users. This is acceptable since nyms are only used for visual distinction within a single trade, not for authentication.
4. **Trade-key based**: Nyms are derived from trade keys, not identity keys. In privacy mode, each trade uses a different key, so the same user gets different nyms across trades.

## v2 Implementation Notes

### Rust Side
The nym generation should be implemented in Rust for consistency:
- Word lists defined as static arrays
- Same algorithm as v1 (BigInt modulo)
- Exposed via flutter_rust_bridge

### Dart Side
Only the avatar widget needs Dart implementation:
- Receives the generated nym string from Rust
- Handles icon/color selection (can also be in Rust if preferred)
- Renders the CircleAvatar widget

### Testing
- Test that same pubkey always produces same nym
- Test that different pubkeys produce different nyms (probabilistically)
- Visual regression tests for avatar rendering
