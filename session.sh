#!/bin/bash
# Hook do Claude Code -> ClaudeBar.
# uso: session.sh start | prompt | tool | notify | stop | end   (estado da sessão)
#      session.sh guard                                          (PreToolUse: pastas proibidas do agente)
# estado em ~/.claude/menubar/sessions/<session_id>.json; agentes em ~/.claude/menubar/agents.json
base="$HOME/.claude/menubar"; dir="$base/sessions"; agents="$base/agents.json"; mkdir -p "$dir" "$base/delivered"
jq=$(command -v jq || echo /opt/homebrew/bin/jq)
input=$(cat)
sid=$(printf '%s' "$input" | $jq -r '.session_id // empty'); [ -z "$sid" ] && exit 0
cwd=$(printf '%s' "$input" | $jq -r '.cwd // ""')
f="$dir/$sid.json"

# agente do painel para este terminal: primeiro pelo id do terminal do Maestri, depois pela pasta
agent() {
  [ -f "$agents" ] || return
  $jq -c --arg t "${MAESTRI_TERMINAL_ID:-}" --arg c "$cwd" \
    '(.agents // []) as $a | ((if $t != "" then [$a[] | select(.terminal == $t)] else [] end) + [$a[] | select(.cwd == $c)]) | .[0] // empty' "$agents"
}

write() { # state message prompt
  # processo do claude dono desta sessão (para o app saber se ainda está aberta)
  pid=$PPID
  for _ in 1 2 3 4; do
    [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "claude" ] && break
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' '); [ -z "$pid" ] && break
  done
  prev_prompt=$([ -f "$f" ] && $jq -r '.prompt // ""' "$f" 2>/dev/null)
  since=$([ -f "$f" ] && [ "$($jq -r '.state' "$f" 2>/dev/null)" = "$1" ] && $jq -r '.since' "$f" || date +%s)
  printf '%s' "$input" | $jq -c --arg s "$1" --arg m "$2" --arg p "${3:-$prev_prompt}" --argjson pid "${pid:-0}" \
    --argjson since "$since" --arg term "${MAESTRI_TERMINAL_ID:-}" \
    '{session_id, cwd, state: $s, message: $m, prompt: $p, pid: $pid, since: $since, updated: now|floor, terminal: $term}' > "$f.tmp" && mv "$f.tmp" "$f"
}

deny() { # motivo
  $jq -cn --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

case "$1" in
  start)  write idle "" "" ;;
  prompt) write working "" "$(printf '%s' "$input" | $jq -r '.prompt // ""' | tr '\n' ' ' | cut -c1-120)"
          # recado deixado no painel: entra como contexto nesta mensagem, uma vez só
          ag=$(agent)
          note=$(printf '%s' "$ag" | $jq -r '.note // ""' 2>/dev/null); nid=$(printf '%s' "$ag" | $jq -r '.noteId // ""' 2>/dev/null)
          if [ -n "$note" ] && [ -n "$nid" ] && [ ! -f "$base/delivered/$nid" ]; then
            touch "$base/delivered/$nid"
            $jq -cn --arg n "$note" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit",
              additionalContext: ("Recado deixado no painel do ClaudeBar para este terminal (vale para esta conversa): " + $n)}}'
          fi ;;
  tool)   # sessão já aberta antes do hook, ou permissão aprovada: volta a "trabalhando"
          { [ ! -f "$f" ] || [ "$($jq -r '.state' "$f")" != "working" ]; } && write working "" ;;
  notify) type=$(printf '%s' "$input" | $jq -r '.notification_type // ""')
          msg=$(printf '%s' "$input" | $jq -r '.message // ""')
          if [ "$type" = "permission_prompt" ] || printf '%s' "$msg" | grep -qi permission; then write waiting "$msg"; fi ;;
  stop)   write idle "" ;;
  end)    rm -f "$f" ;;
  guard)  ag=$(agent); [ -z "$ag" ] && exit 0
          name=$(printf '%s' "$ag" | $jq -r '.name')
          tool=$(printf '%s' "$input" | $jq -r '.tool_name // ""')
          while IFS= read -r b; do
            [ -z "$b" ] && continue
            why="Bloqueado pelo ClaudeBar: o agente \"$name\" não pode alterar arquivos em $b (regra do painel Agentes). Não tente contornar; peça ao usuário se precisar."
            case "$tool" in
              Edit|Write|MultiEdit|NotebookEdit)
                p=$(printf '%s' "$input" | $jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')
                case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
                case "$p/" in "$b"/*) deny "$why" ;; esac ;;
              Bash)
                cmd=$(printf '%s' "$input" | $jq -r '.tool_input.command // ""')
                if [[ "$cmd" == *"$b"* ]] && printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(rm|mv|cp|touch|mkdir|tee|rclone|rsync|ln|chmod|truncate)([[:space:]]|$)|sed[[:space:]]+-i|>'; then
                  deny "$why"
                fi ;;
            esac
          done < <(printf '%s' "$ag" | $jq -r '.blocked[]?') ;;
esac
exit 0
