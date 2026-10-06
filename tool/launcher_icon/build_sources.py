#!/usr/bin/env python3
"""Build the launcher icon and splash sources from the mascot disc.

v2 ships the same mascot as the v1 app (MostroP2P/mobile), so on a phone with
both installed the two icons were identical. v2 adds a metallic gold ring
inside the disc's edge; the mascot and the background stay as they are.

`mascot-disc.png` (next to this script) is the v1 artwork without the ring:
the dark disc on a transparent 1024 px square. This script writes:

- `assets/images/launcher-icon.png`: the disc with the ring, still on a
  transparent square (Android legacy icon, adaptive foreground).
- `assets/images/launcher-icon-ios.png`: the same, flattened onto the brand
  background, since iOS forbids an alpha channel in app icons.
- `assets/images/launcher-icon-web.png`: the iOS art at 80 % on that
  background, so Android's maskable crop keeps the bolt's tip and the ring.
- `android/app/src/main/res/drawable-*/splash_logo.png`: the ringed disc at
  160 dp, the launch screen logo below Android 12 (12+ draws the adaptive
  icon itself, at the same size).
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage*.png`: the
  ringed disc at 160 pt, the iOS launch screen logo.
- `linux/packaging/foundation.mostro.app.png`: the ringed disc at 256 px, the
  window icon and the one `install.sh` puts in the icon theme.
- `windows/runner/resources/app_icon.ico`: the ringed disc from 16 to 256 px.
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png`: the iOS
  art on macOS's rounded-square grid, with its drop shadow.

At 16 px the ring blurs into a brown halo (as on `web/favicon.png`), so the
desktop icons drawn that small use the plain disc.

Then regenerate the launcher icons from the first three (see the
`flutter_launcher_icons` block in pubspec.yaml); it has no Linux target and
only a single-size Windows icon, which is why the desktop icons are written
here. Needs only Pillow:

    python3 tool/launcher_icon/build_sources.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).with_name('mascot-disc.png')

SIZE = 1024
# The adaptive icon's background, which the disc's own fill matches.
BRAND_BACKGROUND = (0x1D, 0x21, 0x2C)
# Outer edge 20 px inside the disc, so a launcher's circular mask (which
# trims the adaptive foreground to about 98 % of the disc) never clips it,
# and 34 px wide, enough to read at 48 px; inside sits clear of the ears.
RING_OUTER_RADIUS = 492
RING_WIDTH = 34
# Light top-left to dark, with a highlight back at the bottom-right edge.
GOLD_STOPS = [
    (0.0, (255, 236, 160)),
    (0.35, (233, 190, 80)),
    (0.65, (196, 146, 40)),
    (1.0, (245, 210, 110)),
]
SUPERSAMPLING = 4
WEB_SCALE = 0.8
SPLASH_LOGO_DP = 160
ANDROID_DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
IOS_SCALES = {'': 1, '@2x': 2, '@3x': 3}
# Below this side the ring blurs into a halo; smaller icons use the plain disc.
RINGED_MIN_SIDE = 24
LINUX_ICON_SIDE = 256
WINDOWS_ICON_SIDES = [16, 24, 32, 48, 64, 128, 256]
MACOS_ICON_SIDES = [16, 32, 64, 128, 256, 512, 1024]
# Apple's macOS icon grid on a 1024 px canvas: an 824 px rounded square with
# a 185 px corner radius, and a soft shadow below it.
MACOS_BODY = 824
MACOS_CORNER_RADIUS = 185
MACOS_SHADOW_OFFSET = 12
MACOS_SHADOW_BLUR = 14
MACOS_SHADOW_ALPHA = 0.3


def gold_gradient():
    """A diagonal gold gradient filling the whole square."""
    ramp = []
    for i in range(2 * SIZE - 1):
        t = i / (2 * SIZE - 2)
        for (t0, c0), (t1, c1) in zip(GOLD_STOPS, GOLD_STOPS[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0)
                ramp.append(tuple(round(a + (b - a) * k) for a, b in zip(c0, c1)))
                break
    image = Image.new('RGB', (SIZE, SIZE))
    image.putdata([ramp[x + y] for y in range(SIZE) for x in range(SIZE)])
    return image


def ring_mask():
    """The ring as an antialiased mask, drawn large and scaled down."""
    big = SIZE * SUPERSAMPLING
    centre = big / 2
    outer = RING_OUTER_RADIUS * SUPERSAMPLING
    inner = (RING_OUTER_RADIUS - RING_WIDTH) * SUPERSAMPLING
    mask = Image.new('L', (big, big), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((centre - outer, centre - outer, centre + outer, centre + outer), fill=255)
    draw.ellipse((centre - inner, centre - inner, centre + inner, centre + inner), fill=0)
    return mask.resize((SIZE, SIZE), Image.LANCZOS)


def ringed_disc():
    disc = Image.open(SOURCE).convert('RGBA')
    ring = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ring.paste(gold_gradient(), (0, 0), ring_mask())
    return Image.alpha_composite(disc, ring)


def on_background(image, scale=1.0):
    square = Image.new('RGBA', (SIZE, SIZE), BRAND_BACKGROUND + (255,))
    side = round(SIZE * scale)
    offset = (SIZE - side) // 2
    square.alpha_composite(image.resize((side, side), Image.LANCZOS), (offset, offset))
    return square.convert('RGB')


def save_scaled(image, side, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((side, side), Image.LANCZOS).save(path, optimize=True)


def macos_icon(art):
    """Opaque square art clipped to macOS's rounded square, with its shadow."""
    big = SIZE * SUPERSAMPLING
    body = MACOS_BODY * SUPERSAMPLING
    offset = (big - body) // 2
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (offset, offset, offset + body - 1, offset + body - 1),
        radius=MACOS_CORNER_RADIUS * SUPERSAMPLING,
        fill=255,
    )
    mask = mask.resize((SIZE, SIZE), Image.LANCZOS)

    shadow_alpha = Image.new('L', (SIZE, SIZE), 0)
    shadow_alpha.paste(mask, (0, MACOS_SHADOW_OFFSET))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(MACOS_SHADOW_BLUR))
    shadow_alpha = shadow_alpha.point(lambda a: round(a * MACOS_SHADOW_ALPHA))
    icon = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    icon.putalpha(shadow_alpha)

    inset = (SIZE - MACOS_BODY) // 2
    body_art = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    body_art.paste(art.convert('RGBA').resize((MACOS_BODY, MACOS_BODY), Image.LANCZOS), (inset, inset))
    body_art.putalpha(mask)
    return Image.alpha_composite(icon, body_art)


def for_side(ringed, plain, side):
    """The ringed image, or the plain one where the ring would only blur."""
    image = ringed if side >= RINGED_MIN_SIDE else plain
    return image.resize((side, side), Image.LANCZOS)


def write_desktop_icons(disc, ios):
    plain = Image.open(SOURCE).convert('RGBA')

    linux = ROOT / 'linux' / 'packaging' / 'foundation.mostro.app.png'
    save_scaled(disc, LINUX_ICON_SIDE, linux)

    windows = [for_side(disc, plain, side) for side in WINDOWS_ICON_SIDES]
    windows[-1].save(
        ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico',
        format='ICO',
        sizes=[(side, side) for side in WINDOWS_ICON_SIDES],
        append_images=windows[:-1],
    )

    appicon = ROOT / 'macos' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    ringed_mac = macos_icon(ios)
    plain_mac = macos_icon(on_background(plain))
    for side in MACOS_ICON_SIDES:
        for_side(ringed_mac, plain_mac, side).save(appicon / f'app_icon_{side}.png', optimize=True)


def main():
    disc = ringed_disc()
    images = ROOT / 'assets' / 'images'
    disc.save(images / 'launcher-icon.png', optimize=True)
    ios = on_background(disc)
    ios.save(images / 'launcher-icon-ios.png', optimize=True)
    on_background(ios.convert('RGBA'), WEB_SCALE).save(images / 'launcher-icon-web.png', optimize=True)

    res = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
    for density, factor in ANDROID_DENSITIES.items():
        side = round(SPLASH_LOGO_DP * factor)
        save_scaled(disc, side, res / f'drawable-{density}' / 'splash_logo.png')

    launch = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'LaunchImage.imageset'
    for suffix, factor in IOS_SCALES.items():
        save_scaled(disc, SPLASH_LOGO_DP * factor, launch / f'LaunchImage{suffix}.png')

    write_desktop_icons(disc, ios)


if __name__ == '__main__':
    main()
