#!/bin/bash
# Bilanciamento: N partite IA contro IA per scenario, vittorie per lato e durata media.
# uso: tools/bilancio.sh "scenario1 scenario2" N
G=/home/claude/godot/Godot_v4.7-stable_linux.x86_64
SC=${1:-"rabaul coral_battaglia coral_giorni coral_campagna salomone_battaglia salomone_campagna santacruz_battaglia santacruz_campagna guadalcanal midway wake"}
N=${2:-8}
mkdir -p /tmp/bil
for sc in $SC; do
  for s in $(seq 1 $N); do
    echo "$sc $s"
  done
done | xargs -P 8 -n 2 sh -c 'timeout 600 '"$G"' --headless --path . -s tests/sim.gd -- $0 $1 > /tmp/bil/$0_$1.txt 2>&1'
for sc in $SC; do
  a=0; j=0; p=0; t=0; err=0
  for s in $(seq 1 $N); do
    f=/tmp/bil/${sc}_$s.txt
    grep -q "SCRIPT ERROR" $f && err=$((err+1))
    w=$(grep -o '"vincitore": "[AJ]*"' $f | head -1 | grep -o '[AJ]"' | tr -d '"')
    case "$w" in A) a=$((a+1));; J) j=$((j+1));; *) p=$((p+1));; esac
    tt=$(grep -oE '^\[T[0-9]+' $f | tail -1 | tr -d '[T')
    t=$((t+${tt:-0}))
  done
  echo "$sc: Alleati $a  Giappone $j  pari $p  turni medi $((t/N))  errori $err"
done
