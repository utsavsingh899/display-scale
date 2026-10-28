#!/bin/bash
# bench.sh: compare GPU power and WindowServer CPU use between two display sizes.
#
#   bench.sh [size A] [size B] [rounds]     (default: 1512x982 2200x1428 3)
#
# For each round and size, it measures two cases:
#   static  nothing on the screen moves
#   motion  the whole screen changes on every frame (screenload)
# The sizes alternate (A, B, A, B, ...), so slow changes in the background load cancel out.
# At the end, the display goes back to the size that it had before.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DM="$HOME/.local/bin/displaymode"
A=${1:-1512x982}
B=${2:-2200x1428}
ROUNDS=${3:-3}
SETTLE=5
MEASURE=15

ORIGINAL=$("$DM" list | awk -F'\t' '$1 == "*" && $3 == "HiDPI" { print $2 }')
trap '"$DM" set "$ORIGINAL" >/dev/null; pkill -f "$HERE/screenload" 2>/dev/null || true' EXIT

ws_pid=$(pgrep -x WindowServer)
# WindowServer CPU time in seconds (ps shows [hh:]mm:ss.ss).
ws_cpu() { ps -o time= -p "$ws_pid" | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'; }

measure() {   # size case
  local t0 t1 gpu
  t0=$(ws_cpu)
  gpu=$("$HERE/powermeter" "$MEASURE")
  t1=$(ws_cpu)
  printf "%s\t%s\t%s\t%s\n" "$1" "$2" "$gpu" "$(awk -v a="$t0" -v b="$t1" -v s="$MEASURE" 'BEGIN { printf "%.1f", (b - a) / s * 100 }')"
}

results=$(mktemp)
echo "size        case    gpu_mW  windowserver_cpu_%"
for (( r = 1; r <= ROUNDS; r++ )); do
  for size in "$A" "$B"; do
    "$DM" set "$size" >/dev/null
    sleep "$SETTLE"
    measure "$size" static | tee -a "$results"
    "$HERE/screenload" $(( MEASURE + 4 )) &
    sleep 3
    measure "$size" motion | tee -a "$results"
    wait
  done
done

echo
echo "Average of $ROUNDS rounds:"
awk -F'\t' '{ k = $1 "\t" $2; gpu[k] += $3; cpu[k] += $4; n[k]++ }
  END { for (k in n) printf "%s\t%.0f mW GPU\t%.1f%% WindowServer CPU\n", k, gpu[k] / n[k], cpu[k] / n[k] }' "$results" | sort
rm -f "$results"
