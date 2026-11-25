#!/usr/bin/env bash
# Regenerates every bitmap font from the TTFs: one set per screen size.
#   resources/fonts/                     390 px (Forerunner 165): the reference sizes below
#   resources-round-<W>x<W>/fonts/       the same fonts scaled to a W-pixel round screen
# Connect IQ picks the folder that matches the device's screen (resource qualifiers).
set -euo pipefail
cd "$(dirname "$0")/.."
MK="python3 -I tools/make_font.py"
NOTO=/usr/share/fonts/noto
TF=tools/fonts
DIGITS="0123456789:"
UPPER="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 /:·."
LOWER="abcdefghijklmnopqrstuvwxyz0123456789 /:=_·."
MIXED="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /:·."

REF=390           # the screen the sizes below were drawn for
SIZES="240 260 280 360 416 454"  # other round screens: Fenix 7S/7/7X, FR 265S, FR 265 / epix, FR 965 / Fenix 8
MIN_EM=12         # labels never smaller than this, so they stay readable on small screens

# px REF_SIZE WIDTH [MIN]: REF_SIZE scaled from a REF-pixel screen to a WIDTH-pixel one.
px() { python3 -c "print(max(${3:-1}, round($1 * $2 / $REF)))"; }

# fonts OUT_DIR WIDTH
fonts() {
    local O=$1 W=$2
    mkdir -p "$O"
    rm -f "$O"/*.fnt "$O"/*.png
    # 1 Ember
    $MK $NOTO/NotoSans-CondensedLight.ttf $O/timer_ember --digit "$(px 56 $W)"
    # 2 Drain
    $MK $TF/BebasNeue-Regular.ttf $O/timer_drain --digit "$(px 70 $W)"
    $MK $TF/BebasNeue-Regular.ttf $O/label_drain --em "$(px 28 $W $MIN_EM)" --chars "$UPPER"
    # 3 Mono
    $MK $TF/JetBrainsMono-VF.ttf $O/timer_mono --digit "$(px 50 $W)" --var Light
    $MK $TF/JetBrainsMono-VF.ttf $O/label_mono --em "$(px 17 $W $MIN_EM)" --var Regular --chars "$LOWER"
    # 4 Liquid
    $MK $TF/Outfit-VF.ttf $O/timer_liquid --digit "$(px 60 $W)" --var ExtraLight
    $MK $TF/Outfit-VF.ttf $O/small_liquid --em "$(px 16 $W $MIN_EM)" --var Regular --chars "$UPPER"
    # 5 Classic
    $MK $TF/PlayfairDisplay-VF.ttf $O/timer_classic --digit "$(px 46 $W)" --var Regular
    $MK $TF/PlayfairDisplay-VF.ttf $O/label_classic --em "$(px 30 $W $MIN_EM)" --var Regular --chars "$MIXED"
    $MK $TF/PlayfairDisplay-VF.ttf $O/small_classic --em "$(px 17 $W $MIN_EM)" --var Regular --chars "$MIXED"
}

fonts resources/fonts $REF
for W in $SIZES; do
    fonts "resources-round-${W}x${W}/fonts" "$W"
    cp resources/fonts/fonts.xml "resources-round-${W}x${W}/fonts/fonts.xml"
done
