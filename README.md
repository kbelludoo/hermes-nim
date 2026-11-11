# Hermes Agent — Ultra-Lean Native Edition (Nim + AI Rust Browser)

Uma reescrita completa e de alta performance do **núcleo do Hermes Agent em Nim**, com integração nativa ao **AI-Rust-Browser** (`ai-rust-browser`), projetada para operar com consumo de memória ultra-baixo: **estritamente abaixo do limite de 50 MB de RAM** (típico total do agente + navegador: **~12 a 17 MB**).

---

## 🎯 Por que Nim + AI-Rust-Browser?

No Python original, o Hermes depende de bibliotecas pesadas (`pydantic`, `openai`, `httpx`, `rich`) e do Google Chrome via CDP. O Chrome sozinho consome entre **500 MB e 1.5 GB de RAM**.

Aqui adotamos uma arquitetura 100% compilada e ultra-enxuta:
1. **Hermes Agent Core em Nim**: Compilação nativa com gerenciamento de memória determinístico ORC (`--mm:orc`). Consome apenas **~6 MB de RAM**.
2. **AI-Rust-Browser em Rust**: Navegador headless autônomo sem garbage collector (`crates/ai-go-browser-cli`), com suporte nativo a MCP (Model Context Protocol). Consome apenas **~6 a 11 MB de RAM**.
3. **Pilha Completa de Agente + Browser**: Operando em conjunto, o consumo total fica entre **~12 MB e 17 MB de RAM**, muito abaixo do teto de 50 MB!

---

## 📊 Medições Reais de Memória (Benchmarks no Windows x64)

| Componente / Estado | Limite Requisitado | Memória Real Medida |
| :--- | :---: | :---: |
| **Hermes Nim (Inativo / Prompt)** | < 50.0 MB | **5.78 MB** |
| **Hermes Nim (Operações nativas de código/arquivos)** | < 50.0 MB | **6.11 MB** |
| **AI-Rust-Browser MCP Ativo (Navegação Web)** | < 50.0 MB | **~6.50 MiB** |
| **Hermes Nim + AI-Rust-Browser (Pilha Combinada)** | < 50.0 MB | **~12.75 MB** |

---

## 🛠️ Ferramentas Disponíveis

### 1. Ferramentas Nativas do Agente (Nim — ~0 MB extra):
- **`terminal`**: Executa comandos shell no sistema com timeout e paginação de saída.
- **`read_file`**: Lê arquivos com paginação opcional de linhas (`start_line`, `end_line`).
- **`write_file`**: Cria ou sobrescreve arquivos.
- **`edit_file`**: Substituição exata de strings (patching atômico).
- **`list_directory`**: Lista arquivos, diretórios e tamanhos.
- **`search_files`**: Busca recursiva por nome de arquivo ou conteúdo textual.
- **`fetch_url`**: Download simples de páginas web e conversão de HTML para texto.
- **`memory_save`**: Salva informações de longo prazo em memória persistente.
- **`memory_recall`**: Recupera dados da memória de longo prazo.

### 2. Ferramentas Autônomas de Navegação (AI-Rust-Browser — ~6.5 MiB):
- **`browser_navigate`**: Navega para qualquer URL com extração semântica e suporte a JavaScript.
- **`browser_snapshot`**: Captura snapshot Markdown otimizado com marcadores `#ref:N` para ação.
- **`browser_click`**: Clica em botões e links pelo identificador de referência `#ref:N`.
- **`browser_type`**: Digita textos em campos de formulário e inputs.
- **`browser_search`**: Busca rápida na web através do motor autônomo do Rust Browser.

### 3. Ferramenta Opcional Python (< 12 MB transiente, 0 MB residente):
- **`execute_python`**: Executa scripts Python usando estritamente a stdlib em subprocesso descartável.

---

## 🚀 Como Compilar e Rodar

### 1. Compilação do Hermes Nim:
```cmd
cd hermes_nim
build.bat
```
*(No Linux / macOS: `./build.sh`)*

### 2. Configuração do `.env`:
Crie ou edite o `.env` na raiz ou em `~/.hermes/.env`:
```env
OPENROUTER_API_KEY=sk-or-v1-xxxx
HERMES_MODEL=anthropic/claude-3.5-sonnet

# Ou OpenAI:
# OPENAI_API_KEY=sk-proj-xxxx
# HERMES_MODEL=gpt-4o-mini
```

### 3. Iniciar o Agente:
```cmd
.\bin\hermes.exe
```

---

## 🧪 Suíte de Testes Automatizados

Para rodar todos os testes de integração do Hermes Nim com o AI-Rust-Browser:
```cmd
nim c -r -d:ssl --mm:orc tests/test_core.nim
```
Resultado validado:
```text
[Suite] Hermes Nim Core & Memory Limit Tests
  [Test] Current Resident Memory: 5.84 MB
  [OK] Memory footprint is strictly below 50 MB
  [OK] Memory Store operations
  [OK] Native File Tools (Read, Write, Edit)
  [OK] Native Terminal Execution
  [Test] AI Rust Browser Exe: C:\Users\kbell\Downloads\ai-rust-browser\target\release\ai-go-browser-cli.exe
  [Test] Browser Nav Result: Navigated to https://example.com/ (RSS: ~6.50 MiB)
  [Test] Browser Snapshot Result: # https://example.com/
  [OK] AI Rust Browser MCP Integration (~6-10MB RAM)
  [OK] Tool Registry & OpenAI Schema Generation (15 tools registered)
```
