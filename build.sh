#!/usr/bin/env bash
# Usage: ./build.sh [build|sim|release] [device]   (default: build fr165)
set -euo pipefail
cd "$(dirname "$0")"

CMD="${1:-build}"
DEVICE="${2:-fr165}"
SDK_BIN="$(ls -d "$HOME"/.Garmin/ConnectIQ/Sdks/*/bin 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$SDK_BIN" ] || { echo "Connect IQ SDK not found. Install it with the SDK Manager (see README)."; exit 1; }
export PATH="$SDK_BIN:$PATH"

if [ ! -f developer_key.der ]; then
    echo "Generating developer key..."
    openssl genrsa -out developer_key.pem 4096
    openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
fi

mkdir -p bin
case "$CMD" in
    build)
        monkeyc -d "$DEVICE" -f monkey.jungle -o bin/Pomodorino.prg -y developer_key.der -w
        echo "Built bin/Pomodorino.prg" ;;
    sim)
        monkeyc -d "$DEVICE" -f monkey.jungle -o bin/Pomodorino.prg -y developer_key.der -w
        pgrep -f simulator >/dev/null || { connectiq & sleep 4; }
        monkeydo bin/Pomodorino.prg "$DEVICE" ;;
    release)
        monkeyc -e -f monkey.jungle -o bin/Pomodorino.iq -y developer_key.der -r
        echo "Built bin/Pomodorino.iq" ;;
    *) echo "Unknown command: $CMD"; exit 1 ;;
esac
