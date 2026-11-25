#!/usr/bin/env bash
# The Connect IQ simulator in Docker, on a hidden screen, scriptable. Needed on distributions that no
# longer ship libwebkit2gtk-4.0 (Manjaro, Arch): the image is Ubuntu 22.04, which still has it. It uses the
# SDK and device files already in ~/.Garmin.
#
#   tools/sim.sh image              build the image once (about 1 GB)
#   tools/sim.sh start              start the simulator (container "ciqsim")
#   tools/sim.sh run DEVICE         load bin/Pomodorino.prg (build it first: ./build.sh build DEVICE)
#   tools/sim.sh shot OUT.png       screenshot of the simulator window
#   tools/sim.sh open DEVICE        from the glance into the app
#   tools/sim.sh key KEY            press a key: Return = START, Escape = BACK, Up / Down = UP / DOWN
#   tools/sim.sh tap X Y            tap the screen (window coordinates; 210 220 is about the middle)
#   tools/sim.sh stop               remove the container
set -euo pipefail
cd "$(dirname "$0")/.."
NAME=ciqsim
IMAGE=ciqsim:22.04
SDK='SDK=$(ls -d "$HOME"/.Garmin/ConnectIQ/Sdks/*/bin | sort -V | tail -1)'

case "${1:-}" in
  image)
    docker build -t "$IMAGE" tools/sim ;;
  start)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" --user "$(id -u):$(id -g)" -e HOME="$HOME" -e DISPLAY=:99 \
      -v "$HOME/.Garmin:$HOME/.Garmin" -v "$PWD:/work" -w /work "$IMAGE" \
      bash -c "Xvfb :99 -screen 0 1280x1024x24 >/tmp/xvfb.log 2>&1 & sleep 2; $SDK; \"\$SDK/simulator\" >/tmp/sim.log 2>&1 & sleep infinity" >/dev/null
    sleep 8 ;;
  run)
    docker exec "$NAME" bash -c "$SDK; (\"\$SDK/monkeydo\" /work/bin/Pomodorino.prg ${2:?device} >/tmp/monkeydo.log 2>&1 &)"
    sleep 12 ;;
  shot)
    # The simulator window sits at the top left of the hidden screen; its size depends on the watch. While
    # the app opens a web page (Connect Todoist), a "Webpage Window" covers it:
    # `docker exec ciqsim xdotool search --name Webpage windowunmap`.
    docker exec "$NAME" bash -c 'G=$(timeout 5 xwininfo -root -tree | grep "(\"simulator\" \"Simulator\")" \
        | grep -oE "[0-9]+x[0-9]+\+0\+0" | sort -t x -k1 -n | tail -1); timeout 10 import -window root -crop "$G" /tmp/shot.png'
    docker cp "$NAME:/tmp/shot.png" "${2:?output file}" >/dev/null ;;
  open)
    # From the glance into the app, on touch watches: tap the glance (upper middle of the screen; position
    # from the device profile, plus the window's 25 px menu bar). The simulator's buttons don't open an app
    # from the glance list, so watches without touch can only be checked up to their glance.
    read -r X Y < <(python3 -c "
import json, os
l = json.load(open(os.path.expanduser('~/.Garmin/ConnectIQ/Devices/${2:?device}/simulator.json')))['display']['location']
print(l['x'] + l['width'] // 2, l['y'] + l['height'] * 22 // 100 + 25)")
    docker exec "$NAME" timeout 5 xdotool mousemove "$X" "$Y" click 1
    sleep 4 ;;
  key)
    docker exec "$NAME" timeout 5 xdotool key "${2:?key}"; sleep 1.5 ;;
  tap)
    docker exec "$NAME" timeout 5 xdotool mousemove "${2:?x}" "${3:?y}" click 1; sleep 1.5 ;;
  stop)
    docker rm -f "$NAME" >/dev/null ;;
  *)
    sed -n '2,14p' "$0"; exit 1 ;;
esac
