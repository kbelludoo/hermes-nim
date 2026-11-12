# Hermes Agent — Ultra-Lean Native Edition (Nim + MBVM-DB + AI-Rust-Browser)

Reescrita completa e de alta performance do **Hermes Agent em Nim**, com integração nativa ao **MBVM-DB** (motor de grafo de código e slicing inteligente com -93% de tokens) e ao **AI-Rust-Browser** (navegador headless MCP).

Projetado especificamente para operar com consumo de memória ultra-baixo: **estritamente abaixo do limite de 50 MB de RAM** (típico: **~5.8 MB a 12.3 MB**).

---

## 🏛️ Destaques da Arquitetura

1. **MBVM-DB no lugar de bancos genéricos**:
   - Ao invés de carregar dezenas de milhares de tokens de arquivos brutos, o agente usa o **MBVM-DB** (`mbvm-db.exe`) para extrair fatias subgrafo exatas em torno de símbolos (`mbvm_slice`, `mbvm_slice_budget`).
   - Redução de contexto de **mais de 90% dos tokens**, permitindo que modelos trabalhem mais rápido e com muito mais precisão.
2. **AI-Rust-Browser Integrado via MCP**:
   - Automação web real sem o consumo de 1 GB do Google Chrome. O motor em Rust opera em **~6.5 MiB de RAM**.
3. **Persistência de Sessões (`--resume`)**:
   - Salva todo o histórico de mensagens e ferramentas por sessão (`~/.hermes/sessions/`). Permite retomar conversas anteriores (`hermes --resume last` ou `hermes --resume <id>`).
4. **Sistema de Habilidades (Skills / `SKILL.md`)**:
   - Escaneia e injeta automaticamente instruções de habilidades especializadas (`skills_list`, `skill_view`).
5. **Agendador de Tarefas em Segundo Plano (Cron Jobs)**:
   - Permite agendar tarefas periódicas em minutos/horas (`cron_add`, `cron_list`, `cron_remove`).
6. **Modo de Segurança e Aprovação Humana (YOLO mode)**:
   - Pausa e solicita confirmação antes de rodar comandos destrutivos no terminal (`rm -rf`, `del /f`, `git reset --hard`), a menos que a flag `--yolo` esteja ativa.
7. **Subagentes / Delegação de Tarefas**:
   - Ferramenta `delegate_task` que executa subtarefas em um agente isolado em background, retornando apenas o relatório final sem poluir a conversa principal.
8. **Gateway do Telegram 24/7**:
   - Bot pessoal para conversar de qualquer lugar pelo celular com streaming de ferramentas ao vivo.

---

## 📊 Medições Reais de Memória (Benchmarks no Windows x64)

| Componente / Modo | Limite Requisitado | Memória Real Medida |
| :--- | :---: | :---: |
| **Hermes Nim Core (25 Ferramentas Ativas)** | < 50.0 MB | **5.79 MB** |
| **AI-Rust-Browser MCP (Navegação Headless)** | < 50.0 MB | **~6.50 MiB** |
| **Pilha Completa (Hermes + Browser + MBVM)** | < 50.0 MB | **~12.34 MB** |
| **Original Python + Chrome + Heavy SQLite** | < 50.0 MB | **650+ MB** |

---

## 🛠️ As 25 Ferramentas Integradas

### 1. Ferramentas do MBVM-DB (Grafo de Código & Slicing):
- **`mbvm_slice`**: Extrai subgrafo inteligente em torno de um símbolo (função, struct, interface) com -93% de tokens.
- **`mbvm_slice_budget`**: Extrai fatia de código com teto estrito de tokens e penalização de ruído.
- **`mbvm_inspect`**: Inspeciona arquivos, símbolos e status do arquivo binário `.mbvmdb`.
- **`mbvm_build`**: Indexa um diretório ou repositório inteiro em formato `.mbvmdb`.

### 2. Ferramentas do AI-Rust-Browser (Navegação Web):
- **`browser_navigate`**: Abre qualquer URL com renderização semântica.
- **`browser_snapshot`**: Captura a página em Markdown otimizado com marcadores `#ref:N`.
- **`browser_click`**: Clica em botões e links pelo identificador de referência.
- **`browser_type`**: Digita textos em campos de formulário e inputs.
- **`browser_search`**: Busca rápida na web pelo motor do Rust Browser.

### 3. Ferramentas Nativas do Sistema:
- **`terminal`**: Executa comandos shell no sistema (com proteção de aprovação/segurança).
- **`read_file`**: Lê arquivos com suporte a paginação de linhas.
- **`write_file`**: Cria ou sobrescreve arquivos.
- **`edit_file`**: Substituição atômica de strings (patching de código).
- **`list_directory`**: Lista arquivos, diretórios e tamanhos.
- **`search_files`**: Busca recursiva por nome ou conteúdo textual.
- **`fetch_url`**: Download simples de páginas web com extração de texto.
- **`memory_save`**: Salva informações de longo prazo em memória persistente.
- **`memory_recall`**: Recupera dados da memória de longo prazo.

### 4. Habilidades, Agendamento e Subagentes:
- **`skills_list`**: Lista todas as habilidades (`SKILL.md`) disponíveis.
- **`skill_view`**: Exibe o conteúdo completo e instruções de uma habilidade.
- **`cron_add`**: Agenda uma instrução periódica em segundo plano.
- **`cron_list`**: Lista tarefas cron ativas.
- **`cron_remove`**: Remove uma tarefa cron agendada.
- **`delegate_task`**: Dispara um subagente isolado para tarefas complexas.
- **`execute_python`**: Executa código Python via micro-worker transiente (0 MB residente).

---

## 🚀 Como Usar

### 1. Modo Interativo (REPL):
```cmd
.\bin\hermes.exe
```

Comandos Slash disponíveis no terminal:
- `/stats` — Medição de RAM e consumo de tokens.
- `/skills` — Lista habilidades instaladas.
- `/sessions` — Lista sessões anteriores salvas.
- `/cron` — Exibe tarefas recorrentes ativas.
- `/mbvm` — Inspeciona o status do MBVM-DB.
- `/yolo` — Alterna o modo de segurança de comandos.
- `/tools` — Lista todas as 25 ferramentas registradas.
- `/model <nome>` — Troca de modelo de IA.
- `/clear` — Limpa o contexto da conversa.

### 2. Retomar Conversa Anterior (`--resume`):
```cmd
.\bin\hermes.exe --resume last
```

### 3. Listar Sessões Salvas:
```cmd
.\bin\hermes.exe --list-sessions
```

### 4. Modo Telegram Gateway (24/7):
```cmd
.\bin\hermes.exe --telegram
```

### 5. Modo YOLO (Sem pedir confirmação para comandos):
```cmd
.\bin\hermes.exe --yolo
```
