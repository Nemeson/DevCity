# DevCity

**Interaktives Installations- und Konfigurationsskript für eine Agent-Driven-Development-Umgebung.**

DevCity bündelt 7 Tools in einem reproduzierbaren, idempotenten Setup und macht sie über MCP (Model Context Protocol) für OpenCode, Copilot CLI, Claude Desktop, Codex, Gemini und Antigravity nutzbar.

---

## Was ist DevCity?

DevCity ist ein **Hybrid-Setup-Skript** (PowerShell 7 + Bash-Wrapper), das eine vollständige Agent-Driven-Development-Umgebung aufsetzt:

| Tool | Rolle | Obligatorisch |
|---|---|:---:|
| [obra/superpowers](https://github.com/obra/superpowers) | Skill-Bundle (Brainstorming, TDD, Debugging, …) | ✅ |
| [opencode-ai](https://www.npmjs.com/package/opencode-ai) | Multi-Client-Runtime für Claude/Codex/Gemini/Antigravity | ✅ |
| [upstash/context7](https://github.com/upstash/context7) | MCP-Server für aktuelle Library-/Framework-Docs | ✅ |
| [atlassian/atlassian-mcp-server](https://github.com/atlassian/atlassian-mcp-server) | MCP für Jira/Confluence (verbindet zu vorhandenem Atlassian-Server) | ✅ |
| [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | Persistentes Knowledge-Graph-Memory | ✅ |
| [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | Skill für komprimierten Agent-Output (Token-Savings) | ✅ |
| [jenkinsci/mcp-server-plugin](https://github.com/jenkinsci/mcp-server-plugin) | MCP für Jenkins (Client-Only, Server bereits vorhanden) | ✅ |

Alle Tools sind **obligatorisch** — das Skript bricht ab, wenn ein Tool abgewählt wird. Das stellt eine konsistente Umgebung sicher.

---

## Features

- **Interaktive Setup-Prompts** — Memory-Modus (lokal/zentral), Client-Auswahl, Remote-URLs, Tokens
- **Multi-Client MCP-Konfiguration** — OpenCode (Default), Copilot CLI, Claude Desktop, Codex, Gemini, Antigravity via Multi-Select
- **Memory-Store** — wählbar zwischen lokal (`./memory/`) oder zentral (Jenkins/Atlassian-Server)
- **Transportwege** — SSH/SCP, Git-Remote, SMB, HTTP-API je nach Speicherort
- **Health-Check** — prüft nur Remote-Server (Jenkins + Atlassian), nicht lokale Tools
- **Prerequisite-Prüfung + optionale Auto-Installation** — Winget (Windows), Brew (macOS), Apt/Scoop (Linux)
- **Secret-Management** — Windows Credential Manager (DPAPI) / `.env` mit `chmod 600` auf Unix
- **Transaktional** — Snapshot vorab, Rollback bei kritischen Fehlern
- **Audit-Log** — jede Aktion wird geloggt (ohne Secret-Werte)
- **Idempotent** — Skript kann mehrfach laufen ohne Duplikate
- **Cross-Plattform** — Windows (PowerShell 7), macOS, Linux (Bash-Wrapper)

---

## Schnellstart

### Windows (PowerShell 7+)

```powershell
git clone https://github.com/<your-org>/DevCity.git
cd DevCity
.\setup.ps1
```

### macOS / Linux (Bash)

```bash
git clone https://github.com/<your-org>/DevCity.git
cd DevCity
chmod +x setup.sh
./setup.sh
```

> Der Bash-Wrapper ruft intern `pwsh setup.ps1` auf, falls PowerShell Core installiert ist. Andernfalls läuft ein natives Bash-Äquivalent.

---

## Setup-Ablauf

1. **Prerequisite-Check** — Node, Python, Git, Java, Maven prüfen, ggf. Auto-Installations-Prompt
2. **Snapshot** — Backup relevanter Configs (`opencode.json`, `.env`, MCP-Configs) vor dem Setup
3. **Tool-Installation** — alle 7 Tools werden installiert (obligatorisch)
4. **Memory-Setup** — Prompt: lokal vs. zentral; bei zentral: Transportweg (SSH/Git/SMB/HTTP) wählen
5. **MCP-Client-Konfiguration** — Multi-Select: welche Clients sollen MCP-Server bekommen
6. **Secret-Store** — Tokens/Keys für Jenkins, Atlassian, Git-Remote abfragen und sicher speichern
7. **Health-Check** — Remote-Server (Jenkins, Atlassian) pingen
8. **Audit-Log** — Setup-Verlauf wird unter `logs/setup-audit-YYYYMMDD-HHMMSS.log` gespeichert

---

## Projektstruktur

```
DevCity/
├── setup.ps1                    # Haupt-Einstieg (PowerShell 7)
├── setup.sh                     # Bash-Wrapper für Unix
├── config/
│   ├── tools.json               # Tool-Definitionen (Name, Install-Command, MCP-Block)
│   ├── clients.json             # MCP-Client-Definitionen
│   └── prerequisites.json       # Java/Node/Python/Git/Maven-Versionen
├── modules/
│   ├── Prerequisites.psm1       # Prüfung + Auto-Install
│   ├── Tools.psm1               # Tool-Installation (7 Tools)
│   ├── Memory.psm1              # Lokal/Zentral-Menü, Snapshot, Restore
│   ├── MCPConfig.psm1           # Multi-Client MCP-Config-Merger
│   ├── Secrets.psm1             # DPAPI/`.env`-Credential-Store
│   ├── Audit.psm1                # Audit-Log (keine Secret-Werte)
│   ├── Snapshot.psm1             # Pre-Setup-Snapshot + Rollback
│   └── HealthCheck.psm1         # Remote-Server-Ping
├── templates/
│   ├── opencode.json.tpl
│   ├── copilot-cli.json.tpl
│   ├── claude-desktop.json.tpl
│   ├── .gitignore.tpl
│   ├── README.md.tpl
│   ├── CONTRIBUTING.md.tpl
│   ├── LICENSE.tpl
│   └── .github/ISSUE_TEMPLATE/
├── backups/                     # Snapshots (gitignored)
├── logs/                        # Audit-Logs (gitignored)
├── memory/                      # Lokales Memory (sensible Inhalte gitignored)
├── .gitignore
├── README.md
├── LICENSE
└── CONTRIBUTING.md
```

---

## NFRs (Nicht-funktionale Anforderungen)

| NFR | Ziel |
|---|---|
| Performance | < 15 Min für Standard-Setup |
| Sicherheit | DPAPI/`.env` + Audit-Log (keine Secret-Werte) |
| Zuverlässigkeit | Transaktional: Snapshot vorab, Rollback bei Fehler |
| Wartbarkeit | Open-Source-reif: README, LICENSE, CONTRIBUTING, ISSUE-Template |
| Plattform | Windows + macOS + Linux (volle Cross-Plattform) |

---

## Konfiguration

Die Setup-Prompts werden im interaktiven Modus ausgeführt. Alle relevanten Konfigurationen werden in `config/` abgelegt und können vorab editiert werden:

- `config/tools.json` — Tool-Definitionen (Installationsart, MCP-Block, Obligat-Flag)
- `config/clients.json` — MCP-Client-Pfade und Config-Formate
- `config/prerequisites.json` — Java/Node/Python/Git/Maven-Versionen pro Tool

---

## Re-Run & Rollback

Das Skript ist **idempotent** — ein erneuter Lauf überschreibt keine User-Einträge, sondern mergt sie. Bei kritischen Fehlern:

```powershell
# Snapshot anzeigen
.\setup.ps1 -ListSnapshots

# Rollback auf Snapshot
.\setup.ps1 -Rollback backups\snapshot-20260803-150000.zip
```

---

## Mitwirken

Siehe [CONTRIBUTING.md](CONTRIBUTING.md). Issues und PRs willkommen.

---

## Lizenz

MIT — siehe [LICENSE](LICENSE).

---

## Danksagung

DevCity bündelt Arbeiten folgender Open-Source-Projekte:

- [obra/superpowers](https://github.com/obra/superpowers)
- [sst/opencode](https://github.com/sst/opencode) (opencode-ai)
- [upstash/context7](https://github.com/upstash/context7)
- [atlassian/atlassian-mcp-server](https://github.com/atlassian/atlassian-mcp-server)
- [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)
- [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)
- [jenkinsci/mcp-server-plugin](https://github.com/jenkinsci/mcp-server-plugin)

Ohne diese Projekte wäre DevCity nicht möglich.