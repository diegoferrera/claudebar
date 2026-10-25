#!/bin/bash
# Regenera os prints de docs/ no modo demonstração (dados de exemplo, nada do seu Mac).
set -e
cd "$(dirname "$0")/.."
bin=ClaudeBar.app/Contents/MacOS/ClaudeBar; f="$(mktemp -u)"
shot() {  # shot <arquivo> VAR=valor
  rm -f "$f"; env CLAUDEBAR_DEMO=1 CLAUDEBAR_SHOT="$f" "$2" "$bin" & pid=$!
  end=$((SECONDS + 15)); until [ -s "$f" ] || [ $SECONDS -ge $end ]; do :; done
  screencapture -x -l"$(cat "$f")" "docs/$1.png"; kill $pid; wait $pid 2>/dev/null || true
}
for p in overview sessions agents settings; do shot $p CLAUDEBAR_PANE=$p; done
shot menu CLAUDEBAR_MENU=1
rm -f "$f"
