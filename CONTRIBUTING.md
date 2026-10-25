# Como colaborar

Sugestões, correções e melhorias são bem-vindas.

- **Achou um problema ou tem uma ideia?** Abra uma [issue](https://github.com/diegoferrera/claudebar/issues) dizendo o que aconteceu, a versão do macOS e, se der, um print.
- **Quer mandar código?** Faça um fork, crie um branch, recompile com `./build.sh` para conferir que o app abre e funciona, e abra um pull request explicando o que mudou e por quê.

## Combinados do projeto

- **Leve em primeiro lugar.** O app fica aberto o dia todo: nada de ler os históricos do Claude Code, timers curtos ou consultas frequentes à API (ela devolve 429 se for chamada demais).
- **macOS 13.** O código compila só com as Command Line Tools (sem Xcode), então evite APIs do macOS 14 ou mais novo.
- **Visual nativo.** Menu e painel seguem o jeito dos menus do sistema (Bateria, Wi-Fi) e do Ajustes do Sistema.
- **Nada pessoal no código.** Sem caminhos, nomes ou contas fixos; use `$HOME`, `whoami` e afins.

## Prints e testes sem dados reais

`CLAUDEBAR_DEMO=1 ClaudeBar.app/Contents/MacOS/ClaudeBar` abre o app com dados de exemplo, sem ler nem gravar nada em `~/.claude` e sem consultar a API. `./tools/screenshots.sh` usa esse modo para refazer os prints de `docs/`.

Issues e pull requests em inglês também são bem-vindos.
