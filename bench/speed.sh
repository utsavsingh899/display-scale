#!/bin/bash
# speed.sh: compare how much GPU work the Mac can do in two display sizes, with the apps that are open now.
#
#   speed.sh [size A] [size B]     (default: 1512x982 2200x1428)
#
# The order is A B B A A B, so the slow rise in temperature affects both sizes equally.
# At the end, the display goes back to the size that it had before.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DM="$HOME/.local/bin/displaymode"
A=${1:-1512x982}
B=${2:-2200x1428}
SETTLE=5
MEASURE=15

ORIGINAL=$("$DM" list | awk -F'\t' '$1 == "*" && $3 == "HiDPI" { print $2 }')
trap '"$DM" set "$ORIGINAL" >/dev/null' EXIT

results=$(mktemp)
power=$(mktemp)
echo "size        gflops  gpu_mW"
for size in "$A" "$B" "$B" "$A" "$A" "$B"; do
  "$DM" set "$size" >/dev/null
  sleep "$SETTLE"
  "$HERE/powermeter" "$MEASURE" > "$power" &
  gflops=$("$HERE/gpuburn" "$MEASURE")
  wait
  printf "%s\t%s\t%s\n" "$size" "$gflops" "$(cat "$power")" | tee -a "$results"
done

echo
echo "Average:"
awk -F'\t' '{ g[$1] += $2; p[$1] += $3; n[$1]++ }
  END { for (k in n) printf "%s\t%.0f GFLOP/s\t%.0f mW GPU\n", k, g[k] / n[k], p[k] / n[k] }' "$results" | sort
rm -f "$results" "$power"
