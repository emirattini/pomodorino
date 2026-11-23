#!/usr/bin/env bash
# Regenerates every bitmap font in resources/fonts from the TTFs.
set -euo pipefail
cd "$(dirname "$0")/.."
MK="python3 -I tools/make_font.py"
O=resources/fonts
NOTO=/usr/share/fonts/noto
TF=tools/fonts
DIGITS="0123456789:"
UPPER="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 /:·."
LOWER="abcdefghijklmnopqrstuvwxyz0123456789 /:=_·."
MIXED="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /:·."

rm -f $O/*.fnt $O/*.png
# 1 Ember
$MK $NOTO/NotoSans-CondensedLight.ttf $O/timer_ember --digit 56
# 2 Drain
$MK $TF/BebasNeue-Regular.ttf $O/timer_drain --digit 70
$MK $TF/BebasNeue-Regular.ttf $O/label_drain --em 28 --chars "$UPPER"
# 3 Mono
$MK $TF/JetBrainsMono-VF.ttf $O/timer_mono --digit 50 --var Light
$MK $TF/JetBrainsMono-VF.ttf $O/label_mono --em 17 --var Regular --chars "$LOWER"
# 4 Liquid
$MK $TF/Outfit-VF.ttf $O/timer_liquid --digit 60 --var ExtraLight
$MK $TF/Outfit-VF.ttf $O/small_liquid --em 16 --var Regular --chars "$UPPER"
# 5 Classic
$MK $TF/PlayfairDisplay-VF.ttf $O/timer_classic --digit 46 --var Regular
$MK $TF/PlayfairDisplay-VF.ttf $O/label_classic --em 30 --var Regular --chars "$MIXED"
$MK $TF/PlayfairDisplay-VF.ttf $O/small_classic --em 17 --var Regular --chars "$MIXED"
