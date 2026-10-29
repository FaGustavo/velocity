# Velocity 1.2.0 — o que mudou

Código-fonte em `src\` (extraído do `Velocity.exe` 1.1.1). Para gerar o exe:
`powershell -ExecutionPolicy Bypass -File build.ps1` → `Velocity.exe` nesta pasta.

## Correções

1. **Brecha para virar administrador (grave).** O lançador antigo rodava sem privilégio e extraía o app
   em `C:\ProgramData\Velocity\app`, que herda da ProgramData a permissão "Usuários: gravar".
   Como o Velocity carrega como admin todo `.ps1` da pasta `Modules`, qualquer programa sem privilégio
   podia deixar um script ali e ganhar acesso de administrador na próxima vez que o app fosse aberto
   (testado: um usuário comum conseguiu criar arquivo em `Modules`).
   O novo lançador (`launcher\Launcher.cs`) pede admin logo no início, deixa a pasta gravável só por
   SYSTEM/Administradores, troca o dono para Administradores e reextrai os scripts a cada abertura.
2. **"Reverter tudo" desfazia configurações que não eram do Velocity.** Se uma otimização já estava
   ativa antes (ex.: HAGS ligado pelo usuário), não havia backup e o "reverter" gravava o valor
   "padrão" (ex.: desligava o HAGS). Agora o Velocity marca o que ele mesmo aplicou, e "Reverter tudo"
   e "Reverter categoria" só mexem nisso. O botão individual continua funcionando para qualquer item.
3. **Backup podia corromper ou travar.** A gravação agora é atômica (arquivo temporário + troca, com
   `backup.json.bak`). Se o arquivo estiver danificado, usa a cópia anterior e guarda o danificado.
   A trava (mutex) ignorava o tempo esgotado e quebrava se outro processo morresse segurando a trava.
4. **Placa de vídeo errada no painel.** Em PCs com vídeo integrado, aparecia a Intel HD como principal
   e a NVIDIA como "também". Agora a placa dedicada vem primeiro.
5. **Ponto de restauração deixava alteração no registro.** `SystemRestorePointCreationFrequency = 0`
   ficava para sempre; agora o valor original volta depois de criar o ponto.
6. **Spinner gastando CPU/GPU o tempo todo.** A animação de "processando" rodava para sempre, mesmo
   escondida — num otimizador de jogos. Agora só gira enquanto aparece.
7. **Texto começando com `{` quebrava a página** (ex.: um item de inicialização com nome `{GUID}`),
   porque o XAML lê isso como marcação. Corrigido no `ConvertTo-XamlText`.
8. **"Desativar Nagle" sem rede ativa** ficava pendente para sempre e o painel nunca chegava a 100%.
   Agora ela só aparece se houver interface com IP.
9. O relançamento como admin (rodando o `.ps1` direto) não passava `-STA`/`-WindowStyle Hidden`.

Reforço (não era bug confirmado): a limpeza de temporários agora nunca entra em junctions/links.

## Visual no estilo Apple

- Paleta de cores de sistema do macOS, com **modo claro e escuro** seguindo o Windows
  (dá para forçar com `"Theme": "light"` ou `"dark"` no `settings.json`).
- Barra lateral com ícones coloridos por seção, "semáforo" no lugar dos botões da janela,
  cantos arredondados no Windows 11.
- Painel com **anel de progresso** (estilo Atividade) e lista "Seu sistema" no formato dos Ajustes.
- Listas agrupadas com filetes recuados no lugar de cartões soltos; switches estilo iOS (verde).
- Diálogos no formato de alerta do macOS: surgem com escala e desfocam o fundo; ícone por tipo.
- Botões respondem no instante do clique (leve redução de escala), não ao soltar.
- Animações partem do valor atual da tela (podem ser interrompidas) e usam curva de "mola" sem quique.
  Se "Mostrar animações" estiver desligado no Windows, ficam só esmaecimentos curtos.
- Selos de risco só aparecem para risco médio/alto (menos ruído visual).
