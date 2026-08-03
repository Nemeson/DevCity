# DevCity Roadmap

**Leitlinie:** Von v1.0-Skeleton zu einer produktiven, rollenbasierten, teamfähigen Agent-Driven-Dev-Umgebung.

Diese Roadmap ist **nicht** verbindlich — sie ist ein Vorschlag, der mit Dir zusammen priorisiert wird. Jede Phase hat einen klaren Mehrwert und ist unabhängig von späteren Phasen lieferbar.

---

## Übersicht

| Phase | Version | Fokus | Schätzung |
|---|---|---|---|
| **1** | v1.1 | Core-Module implementieren (Dry-Run-fähig) | 1–2 Wochen |
| **2** | v1.2 | Multi-Client MCP-Merger + Memory-Setup | 1 Woche |
| **3** | v1.3 | Security-Module + Health-Check | 1 Woche |
| **4** | v1.4 | UX-Polish + Fehlerbehandlung + Linting | 1 Woche |
| **5** | v2.0 | **Rollenbasierte Skill-Profile** | 2–3 Wochen |
| **6** | v3.0 | Erweiterte Optimierungen (siehe unten) | fortlaufend |

**Total bis v2.0:** ~6–8 Wochen (Solo-Entwickler, Teilzeit), kürzer bei Team.

---

## Phase 1 — v1.1: Core-Module implementieren

**Ziel:** `setup.ps1 -DryRun` läuft erfolgreich durch, `setup.ps1` installiert alle 7 Tools auf einer sauberen Windows-Maschine.

### Deliverables

| Modul | Key-Funktionen | Test-Kriterium |
|---|---|---|
| `Prerequisites.psm1` | `Test-Prerequisites`, `Install-Prerequisite`, `Invoke-PrerequisiteCheck` | Erkennt fehlendes Java, installiert via Winget, idempotent |
| `Tools.psm1` | `Install-DevCityTool`, `Install-AllDevCityTools`, `Get-DevCityToolStatus` | 7 Tools werden parallel installiert, Re-Run überspringt vorhandene |
| `Audit.psm1` | `Write-DevCityAuditLog`, `Test-DevCitySecretInLog` | Secret-Pattern-Erkennung fängt `ghp_xxx`, `Bearer xxx`, `AKIA...` ab |

### Optimierungen (eigene Ideen, in v1.1 integriert)

1. **Parallelisierte Tool-Installation** — statt sequenziell 7 Tools nacheinander, mit `Start-Job`/`ForEach-Object -Parallel` installieren. Spart 30–50% Setup-Zeit (NFR 1B < 15 Min).
2. **Cache-Mechanismus für Re-Runs** — `Get-DevCityToolStatus` prüft vor jeder Installation, ob das Tool schon vorhanden ist (Hash-Check der Config). Re-Runs sind No-Ops, außer `-Force`.
3. **Dry-Run mit Diff-Output** — `setup.ps1 -DryRun` zeigt nicht nur "würde X tun", sondern einen echten Diff: "würde `opencode.json` um 4 MCP-Server erweitern (bestehende 2 bleiben)". Das gibt Sicherheit vor dem echten Run.

---

## Phase 2 — v1.2: Multi-Client MCP-Merger + Memory

**Ziel:** MCP-Server werden in OpenCode + Copilot CLI (Default) geschrieben. Memory-Modus (lokal/zentral) ist im Menü wählbar.

### Deliverables

| Modul | Key-Funktionen | Test-Kriterium |
|---|---|---|
| `MCPConfig.psm1` | `Select-DevCityMcpClients`, `Write-DevCityMcpConfig`, `Remove-DevCityMcpConfig` | Multi-Select-Prompt, Deep-Merge erhält User-Einträge, Backup vor Write |
| `Memory.psm1` | `New-DevCityMemory`, `Sync-DevCityMemory`, `Get-DevCityMemoryConfig` | Lokales Memory wird angelegt; zentrales via SSH/SCP synchronisiert |

### Optimierungen

4. **Deep-Merge mit Konfliktwarnung** — Wenn ein MCP-Server-Eintrag im Client-Config schon existiert (z.B. User hat eigenen `context7`-Block), warnt DevCity und fragt: überschreiben / überspringen / umbenennen. Kein stillschweigendes Überschreiben.
5. **Memory-Transport-Auto-Detection** — Bei Mode='zentral' versucht DevCity, den besten Transportweg zu erraten (Git-Remote im Repo → `git-remote`; SSH-Host in URL → `ssh-scp`; `\\` in Pfad → `smb`; `http(s)://` → `http-api`). User kann override wählen.
6. **Memory-Initial-Sync im Background-Job** — Erster Sync bei zentralem Memory kann dauern. DevCity startet ihn als Background-Job und zeigt Progress, blockiert aber nicht das Setup-Ende.

---

## Phase 3 — v1.3: Security & Health-Check

**Ziel:** Secrets sind DPAPI/`.env`-gespeichert, Health-Check pingt Jenkins + Atlassian, Rotation-Reminder warnt nach 90 Tagen.

### Deliverables

| Modul | Key-Funktionen | Test-Kriterium |
|---|---|---|
| `Secrets.psm1` | `Get/Set-DevCitySecret`, `Test-DevCitySecretRotation`, `Invoke-DevCitySecretPrompt` | Windows Credential Manager DPAPI, Unix `.env` mit `chmod 600`, Prompt via `Read-Host -AsSecureString` |
| `HealthCheck.psm1` | `Invoke-DevCityHealthCheck`, `Test-DevCityJenkinsHealth`, `Test-DevCityAtlassianHealth`, `Format-DevCityHealthCheckReport` | Endpoint-Ping mit Timeout, klare UI-Tabelle mit ✅/❌, Response-Time |

### Optimierungen

7. **Secret-Rotation-Reminder bei Setup-Start** — Jeder `setup.ps1`-Aufruf prüft, ob Secrets älter als 90 Tage sind, und warnt beim Banner: "⚠️ 2 Secrets älter als 90 Tage: `atlassian_token` (94d), `jenkins_token` (102d). Rotation empfohlen." (NFR 2C).
8. **Health-Check mit Retry + Exponential-Backoff** — Transiente Netzwerkfehler (VPN nicht verbunden, DNS-Hickup) werden 3x mit Backoff (1s, 2s, 4s) retried. Erst bei endgültigem Failure gibt's ❌.
9. **Health-Check-Report als Markdown** — Neben Konsolen-Output wird ein `logs/health-check-YYYYMMDD.md` geschrieben, das in GitHub Issues gepastet werden kann.

---

## Phase 4 — v1.4: UX-Polish + Fehlerbehandlung + Linting

**Ziel:** Setup läuft stabil, Fehlermeldungen sind klarschrittig, Repo ist lint-clean.

### Deliverables

- **Vollständige Try/Catch-Blöcke** in allen Modulen mit klaren Fehlermeldungen (deutsch/englisch)
- **Progress-Bar** für lange Operationen (Tool-Installation, Memory-Sync)
- **Farb-Output** (Erfolg = grün, Warnung = gelb, Fehler = rot) — via `$PSStyle`
- **`Invoke-ScriptAnalyzer` CI-Check** im DevCity-Repo selbst (GitHub Actions)
- **Pester-Tests** für jedes Modul unter `tests/<Module>.Tests.ps1`
- **PowerShell-Lint** wirft keine Warnings mehr

### Optimierungen

10. **Fehler-ID-System** — Jeder Fehler hat eine ID (z.B. `DEVCITY-E042: Java-Installation via Winget fehlgeschlagen`). Doku unter `docs/errors.md` listet alle IDs mit Lösungen. Issue-Templates verlangen nach Fehler-ID.
11. **Auto-Resume nach Abbruch** — Wenn `setup.ps1` abbricht, wird ein `setup-state.json` geschrieben. Beim nächsten Aufruf: "Letzter Lauf abgebrochen bei Phase 3. Fortsetzen? (j/n)".
12. **`--Silent`-Modus für CI** — Keine Prompts, nutzt Defaults aus `config/*.json`. Nützlich für Docker-Image-Build, CI/CD-Pipelines, Headless-Server-Setup.
13. **i18n: Deutsch + Englisch** — Strings in `config/strings.de.json` und `config/strings.en.json`. Default = OS-Sprache, override via `-Language en`.

---

## Phase 5 — v2.0: Rollenbasierte Skill-Profile (Dein Vorschlag)

**Ziel:** DevCity erkennt die Rolle des Entwicklers (Frontend/Backend/DevOps/QA/...) und installiert passende Skills + MCP-Server-Konfiguration.

### Konzept

Beim Setup-Prompt:

```
[1/9] Welche Rolle hast Du im Team?
  [x] Frontend Developer
  [ ] Backend Developer
  [ ] DevOps Engineer
  [ ] QA Engineer
  [ ] Security Engineer
  [ ] Data Engineer
  [ ] ML Engineer
  [ ] Tech Lead
  [ ] Full-Stack (alle Skill-Sets)
```

Basierend auf Auswahl installiert DevCity zusätzliche Skills in `~/.claude/skills/` und erweitert die MCP-Client-Configs mit rollenspezifischen MCP-Servern.

### Rollen-Skill-Tabelle (Vorschlag)

| Rolle | Empfohlene Skills (zusätzlich zu superpowers + caveman) | Zusätzliche MCP-Server |
|---|---|---|
| **Frontend Developer** | `react-best-practices`, `frontend-patterns`, `tailwind-patterns`, `frontend-design`, `playwright-skill` | Browser-Tools-MCP (Chrome DevTools) |
| **Backend Developer** | `backend-patterns`, `postgres-patterns`, `api-design`, `prisma-patterns` | Postgres-MCP (optional) |
| **DevOps Engineer** | `docker-patterns`, `github-actions-advanced`, `kubernetes-architect`, `terraform-specialist` | Kubernetes-MCP (optional) |
| **QA Engineer** | `testing-patterns`, `e2e-testing`, `playwright-skill`, `tdd-workflow` | Playwright-MCP |
| **Security Engineer** | `security-review`, `secrets-management`, `threat-modeling-expert` | Secrets-Scanner-MCP |
| **Data Engineer** | `data-engineering-data-pipeline`, `sql-pro`, `polars`, `dbt-transformation-patterns` | DuckDB-MCP (optional) |
| **ML Engineer** | `ml-pipeline-workflow`, `mlops-engineer`, `scikit-learn` | HuggingFace-MCP |
| **Tech Lead** | `architecture`, `code-review-excellence`, `coding-standards`, `mentoring` | — |
| **Full-Stack** | Kombination aus Frontend + Backend | alle optionalen MCPs |

### Implementierung

- Neue Datei: `config/roles.json` mit Skill-Mapping pro Rolle
- Neues Modul: `modules/Roles.psm1` mit `Select-DevCityRole`, `Install-RoleSkills`
- `setup.ps1` bekommt neuen Parameter `-Role <rollen-name>` (nicht-interaktiv)
- Profile können kombiniert werden: `-Role frontend,security` installiert beide Skill-Sets

### Profile-Voreinstellungen (Presets)

- `DevCity -Role frontend` → Frontend-Preset
- `DevCity -Role backend` → Backend-Preset
- `DevCity -Role devops` → DevOps-Preset
- `DevCity -Role fullstack` → Full-Stack-Preset

### Rollen-Spezifische MCP-Client-Configs

Je nach Rolle können MCP-Server-Einträge unterschiedlich sein:

- **Frontend:** Context7 + Browser-Tools-MCP + Codebase-Memory
- **Backend:** Context7 + Postgres-MCP (wenn DB-Projekt) + Codebase-Memory
- **DevOps:** Context7 + Kubernetes-MCP + Jenkins-MCP

DevCity generiert rollenspezifische `opencode.json.tpl`-Varianten.

---

## Phase 6 — v3.0: Erweiterte Optimierungen (eigene Ideen)

### 6.1 — Plugin-System für Custom Tools

Aktuell sind 7 Tools hardcodiert (obligatorisch). Für Team-spezifische Tools (z.B. interne MCP-Server, proprietäre Skills) braucht DevCity eine Plugin-Schnittstelle:

- `plugins/`-Verzeichnis im DevCity-Repo
- Jedes Plugin ist ein JSON-File mit Tool-Definition (analog `config/tools.json`)
- `setup.ps1 -Plugins plugins/mein-tool.json` installiert zusätzliche Tools

### 6.2 — Self-Update-Mechanismus

- `setup.ps1 -SelfUpdate` pulled das neueste DevCity vom Git-Remote
- Versions-Check beim Start: "DevCity v1.4.2 verfügbar (Du hast v1.3.0). Update empfohlen."
- Safety: Vor Self-Update Snapshot erzeugen

### 6.3 — Web-UI (optional)

Für nicht-CLI-affine Nutzer: kleines Web-Dashboard

- `setup.ps1 -WebUI` startet lokalen HTTP-Server (Pode oder Polaris)
- Browser-UI mit Checkboxen, Multi-Selects, Live-Progress
- Selbe Logik wie CLI, nur andere Frontend
- Nützlich für Windows-Nutzer, die PowerShell nicht mögen

### 6.4 — SBOM-Generierung (Software Bill of Materials)

- DevCity erzeugt nach Setup eine `sbom.json` (CycloneDX-Format)
- Listet alle installierten Tools + Versionen
- Für Security-Audits, Compliance, Enterprise-Nutzung
- Optional: Upload zu Dependency-Track

### 6.5 — Version-Pinning (Lockfile)

- `devcity.lock.json` pinnst alle Tool-Versionen (z.B. `opencode-ai@1.2.3`, `context7@0.4.1`)
- Repo-Commit des Lockfiles = reproduzierbare Setups
- `setup.ps1 -UseLockFile` installiert genau diese Versionen
- Ohne LockFile: `@latest` (wie bisher)

### 6.6 — Telemetry (opt-in, anonym)

- Freiwillige, anonyme Telemetry: welche Tools werden installiert, wie lange dauert Setup, welche Rollen am häufigsten
- Hilft Feature-Priorisierung
- Opt-in (Default: opt-out), transparent dokumentiert
- Datenpunkte werden vor Senden geprüft (keine Secrets, keine Pfade)

### 6.7 — Multi-Language-Skill-Support

Aktuell: Skills in `~/.claude/skills/` sind Claude-spezifisch. Für Copilot CLI, Codex etc. gibt es andere Skill-Formate.

- DevCity erkennt das Skill-Format pro Client (Claude: `SKILL.md`, Codex: `AGENTS.md`, Gemini: `GEMINI.md`)
- Konvertiert Skills automatisch zwischen Formaten
- Ein Skill-Source → Multi-Client-Skills

### 6.8 — Setup-Dry-Run-Report als Markdown

- `setup.ps1 -DryRun -OutputFormat markdown` schreibt `dry-run-report.md`
- Zeigt alle geplanten Aktionen, Diffs zu bestehenden Configs, Estimated-Time
- Kann in PRs gepostet werden ("Was würde dieses DevCity-Update ändern?")

### 6.9 — CI/CD-Pipeline für DevCity selbst

- GitHub Actions Workflow: `.github/workflows/test-setup.yml`
- Testet `setup.ps1 -DryRun` auf Windows/macOS/Linux (Matrix-Build)
- Lint mit `Invoke-ScriptAnalyzer` + `shellcheck`
- Pester-Tests laufen automatisch bei PRs

### 6.10 — Auto-Dependency-Update-PRs

- Dependabot für `package.json` (falls DevCity Node-Abhängigkeiten bekommt)
- Renovate für `config/prerequisites.json` (Java/Node-Versionen updaten)
- Auto-PR: "chore(deps): update Node.js LTS 20 → 22"

### 6.11 — Documentation Site (VitePress)

- `docs/`-Verzeichnis mit VitePress-Site
- Schnellstart, Rollen-Guide, Troubleshooting, API-Reference der Module
- Deployment via GitHub Pages
- Für Open-Source-Nutzerschaft

### 6.12 — Rollback-Chaining

Aktuell: Snapshot vor Setup, Rollback auf einen Snapshot.

Erweiterung:

- `setup.ps1 -History` zeigt alle Setups als Timeline
- `setup.ps1 -RollbackTo "v1.4.0-Setup"` springt zu einem beliebigen Punkt
- Git-Branches für Setup-Stände (experimentell)

---

## Priorisierung (MoSCoW)

| Idee | Phase | Must | Should | Could | Won't (v1) |
|---|---|:---:|:---:|:---:|:---:|
| Parallelisierte Installation | 1 | ✅ | | | |
| Cache für Re-Runs | 1 | ✅ | | | |
| Dry-Run mit Diff | 1 | ✅ | | | |
| Multi-Client MCP-Merger | 2 | ✅ | | | |
| Memory lokal/zentral | 2 | ✅ | | | |
| DPAPI/`.env`-Secrets | 3 | ✅ | | | |
| Health-Check Remote | 3 | ✅ | | | |
| Rotation-Reminder | 3 | | ✅ | | |
| Retry mit Backoff | 3 | | ✅ | | |
| Fehler-ID-System | 4 | | ✅ | | |
| Auto-Resume | 4 | | ✅ | | |
| `--Silent`-Modus | 4 | | ✅ | | |
| i18n DE/EN | 4 | | ✅ | | |
| **Rollenbasierte Skills** | **5** | | | **✅ (v2.0)** | |
| Plugin-System | 6 | | | ✅ | |
| Self-Update | 6 | | | ✅ | |
| Web-UI | 6 | | | | ✅ (low prio) |
| SBOM-Generierung | 6 | | | ✅ | |
| Version-Pinning | 6 | | | ✅ | |
| Telemetry | 6 | | | | ✅ (privacy) |
| Multi-Language-Skill-Support | 6 | | | ✅ | |
| Dry-Run-Report Markdown | 6 | | | ✅ | |
| CI/CD-Pipeline DevCity | 6 | | ✅ | | |
| Dependabot/Renovate | 6 | | ✅ | | |
| VitePress-Doku | 6 | | | ✅ | |
| Rollback-Chaining | 6 | | | | ✅ (overkill) |

---

## Abhängigkeiten zwischen Phasen

```
v1.0 (Skeleton) ──► v1.1 (Core-Module) ──► v1.2 (MCP+Memory) ──► v1.3 (Security+Health)
                                                                   │
                                                                   ▼
                                                                v1.4 (UX+Polish)
                                                                   │
                                                                   ▼
                                                                v2.0 (Rollen-Skills)
                                                                   │
                                                                   ▼
                                                                v3.0 (Plugins, Self-Update, ...)
```

- **v2.0 braucht v1.4** — Rollen-Skills brauchen stabile UX, Multi-Client-Merger, Security
- **v3.0 ist unabhängig** — Ideen können parallel zu v2.x umgesetzt werden

---

## Empfehlung für die nächsten Schritte

1. **Sofort:** Phase 1 starten — `Prerequisites.psm1` implementieren + `Audit.psm1` mit Secret-Pattern-Erkennung
2. **Nächste Woche:** Phase 2 — MCP-Config-Merger ist der größte UX-Gewinn
3. **Nach v1.4:** Entscheidung über Rollen-Skills (v2.0) — ob wir das angehen wollen

Was meinst Du? Welche Phase soll ich angehen?