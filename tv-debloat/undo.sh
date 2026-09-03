#!/usr/bin/env bash
# Undoes the entire debloat: re-enables every recorded package and restores
# animation scales. Safe to run repeatedly.
set -uo pipefail
DEV="${TV_IP:-192.168.86.245}:${PORT:-5555}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
adb connect "$DEV" >/dev/null 2>&1
grep -vE '^[[:space:]]*(#|$)' "$HERE/kapatilanlar.txt" | tr -d '\r' | while read -r p; do
  adb -s "$DEV" shell pm enable "$p" >/dev/null 2>&1 && echo "re-enabled $p" || echo "FAILED    $p"
done
for k in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb -s "$DEV" shell settings put global "$k" 1.0
done
echo "Animation scales restored to 1.0. Reboot: adb -s $DEV reboot"
