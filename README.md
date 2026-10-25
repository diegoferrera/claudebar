# ClaudeBar

App de barra de menus para macOS que mostra o uso do plano Claude (sessão de 5 h e semana) sem precisar abrir o Claude, e acompanha as sessões do Claude Code abertas no Mac.

- **Barra de menus:** ✳ com a % da sessão e da semana, em verde, laranja ou vermelho. Pisca quando um terminal pede permissão.
- **Menu:** limites do plano com horário de reset e a lista de sessões (trabalhando, pedindo permissão, terminou).
- **Painel** (abra o app ou ⌘, no menu):
  - Visão geral com gráfico do uso e previsão de quando o limite acaba.
  - Sessões abertas, com aviso quando dois terminais estão na mesma pasta.
  - Agentes: dê um nome a cada terminal, proíba pastas (o hook bloqueia edição nelas) e deixe recados que o agente recebe na próxima mensagem.
  - Ajustes: cores, o que aparece na barra, notificações, abrir ao iniciar.
- **Notificações** quando uma sessão termina ou pede permissão.
- **Widget de iPhone** pelo app [Scriptable](https://scriptable.app), lendo um arquivo que o Mac grava no iCloud Drive.

Leve: consulta o uso a cada 2 minutos, não lê os históricos do Claude Code e monta o menu só quando é aberto.

## Requisitos

- macOS 13 ou mais novo (Apple Silicon ou Intel)
- Claude Code logado com uma conta Pro/Max (o app usa o login guardado no Keychain)
- Xcode Command Line Tools (`xcode-select --install`) e `jq` (`brew install jq`)

## Instalar

```bash
git clone https://github.com/diegoferrera/claudebar.git
cd claudebar
./install.sh
```

O `install.sh` compila o app, faz ele abrir ao iniciar o Mac e acrescenta os hooks do ClaudeBar em `~/.claude/settings.local.json` (com backup em `settings.local.json.bak-claudebar`; hooks que já existem continuam lá).

Depois de mudar o código, recompile com `./build.sh`.

### Widget do iPhone

1. Ligue o iCloud Drive no Mac e instale o Scriptable no iPhone.
2. Com o app rodando, o arquivo `Claude.js` aparece na pasta do Scriptable.
3. No iPhone, adicione um widget do Scriptable e escolha o script **Claude**.

## Como funciona

- O uso vem de `api.anthropic.com/api/oauth/usage` (endpoint não documentado, o mesmo da tela "Seu uso"), com o token do Claude Code lido do Keychain. Se a API limitar as consultas (429), o app espera mais antes de tentar de novo e mostra o último valor.
- `session.sh` é chamado pelos hooks do Claude Code e grava o estado de cada sessão em `~/.claude/menubar/sessions/`.
- No `PreToolUse`, `session.sh guard` nega edições nas pastas proibidas do agente.
- Os terminais são reconhecidos pelo id do Maestri quando existe; senão, pela pasta.

## Estrutura

```
src/Core.swift        dados: uso, sessões, histórico, agentes, ajustes, widget
src/MenuViews.swift   menu da barra
src/PanelViews.swift  janela do painel
src/main.swift        app, timers, barra de menus
session.sh            hooks do Claude Code
widget.js             widget do Scriptable
tools/icon.swift      gera o ícone
resources/            Info.plist e ícone do app
```

## Colaborar

Veja [CONTRIBUTING.md](CONTRIBUTING.md). Licença [MIT](LICENSE): pode usar, modificar e distribuir.

> Projeto independente, sem ligação com a Anthropic. Usa um endpoint não documentado que pode mudar a qualquer momento.
