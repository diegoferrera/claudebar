#!/bin/bash
# Recompila o ClaudeBar, reassina o .app (mantém ícone/notificações) e reinicia.
set -e
cd "$(dirname "$0")"
# primeira vez: monta o pacote ClaudeBar.app a partir de resources/
if [ ! -f ClaudeBar.app/Contents/Info.plist ]; then
  mkdir -p ClaudeBar.app/Contents/MacOS ClaudeBar.app/Contents/Resources
  cp resources/Info.plist ClaudeBar.app/Contents/
  cp resources/AppIcon.icns ClaudeBar.app/Contents/Resources/
fi
cp widget.js ClaudeBar.app/Contents/Resources/  # o app copia o widget daqui para o iCloud
swiftc -O -target "$(uname -m)-apple-macos13.0" src/*.swift -o ClaudeBar.app/Contents/MacOS/ClaudeBar
codesign --force -s - ClaudeBar.app
launchctl kickstart -k gui/$(id -u)/com.$(whoami).claudebar 2>/dev/null || true
