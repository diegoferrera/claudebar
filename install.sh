#!/bin/bash
# Instala o ClaudeBar: compila, abre no login (LaunchAgent) e registra os hooks do Claude Code.
set -e
cd "$(dirname "$0")"
dir="$(pwd)"
label="com.$(whoami).claudebar"
command -v jq >/dev/null || { echo "Precisa do jq: brew install jq"; exit 1; }

./build.sh

# abrir ao iniciar o Mac
plist="$HOME/Library/LaunchAgents/$label.plist"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$dir/ClaudeBar.app/Contents/MacOS/ClaudeBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>LowPriorityIO</key><true/>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"

# hooks do Claude Code (em ~/.claude/settings.local.json; faz backup antes)
s="$HOME/.claude/settings.local.json"; mkdir -p "$HOME/.claude"; [ -f "$s" ] || echo '{}' > "$s"
cp "$s" "$s.bak-claudebar"
h="$dir/session.sh"
jq --arg h "$h" '
  # acrescenta os hooks do ClaudeBar sem apagar os que já existem (e sem duplicar)
  def add($ev; $entry): .hooks[$ev] = ((.hooks[$ev] // []) | map(select((tostring | contains("session.sh")) | not))) + [$entry];
  def cmd($m): {hooks: [{type: "command", command: ($h + " " + $m)}]};
  add("SessionStart"; cmd("start")) | add("UserPromptSubmit"; cmd("prompt")) | add("PostToolUse"; cmd("tool"))
  | add("Notification"; cmd("notify")) | add("Stop"; cmd("stop")) | add("SessionEnd"; cmd("end"))
  | add("PreToolUse"; cmd("guard") + {matcher: "Edit|Write|MultiEdit|NotebookEdit|Bash"})
' "$s.bak-claudebar" > "$s"
echo "Pronto. O ✳ aparece na barra de menus; as sessões entram a partir da próxima mensagem em cada terminal."
