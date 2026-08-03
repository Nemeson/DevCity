# Contributing to DevCity

Vielen Dank, dass Du zu DevCity beitragen möchtest! Dieses Dokument beschreibt die Konventionen und den Workflow für Beiträge.

---

## Verhaltenskodex

Sei respektvolloll, konstruktiv und inklusiv. Wir folgen dem [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/) in seiner neuesten Version.

---

## Erste Schritte

### Voraussetzungen

- **PowerShell 7+** (für `setup.ps1`)
- **Bash 5+** (für `setup.sh`, optional)
- **Node.js 20+** (für lokale Skript-Tests)
- **Git 2.40+**
- **Python 3.11+** (für codebase-memory-mcp-Tests)
- **Java 17+** (für atlassian-mcp-server-Tests, optional)

### Repository forken & klonen

```powershell
git clone https://github.com/<your-fork>/DevCity.git
cd DevCity
git remote add upstream https://github.com/<origin>/DevCity.git
```

---

## Entwicklungs-Workflow

### 1. Branch anlegen

```powershell
git checkout -b feature/<kurze-beschreibung>
# oder
git checkout -b fix/<issue-nummer>-<kurze-beschreibung>
```

### 2. Änderungen vornehmen

- Folge der Modulstruktur in `modules/`
- Ein Modul pro Thema (`Prerequisites.psm1`, `Tools.psm1`, …)
- Kein Monolith-Code im Hauptskript `setup.ps1`
- PowerShell-Module müssen mit `Export-ModuleMember` exportieren

### 3. Lokal testen

```powershell
# Dry-Run (nur Prerequisite-Check, keine Installation)
.\setup.ps1 -DryRun

# Verbose-Modus (debug-Output)
.\setup.ps1 -Verbose

# Bestimmte Module testen
.\setup.ps1 -OnlyModule Prerequisites,Tools
```

### 4. Commits

Wir verwenden [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Typen:**

- `feat` — neue Funktion
- `fix` — Bugfix
- `docs` — Doku-Änderungen
- `refactor` — Code-Umstrukturierung ohne Verhaltensänderung
- `test` — Tests hinzufügen/ändern
- `chore` — Build, CI, Tooling

**Beispiele:**

```
feat(modules): add HealthCheck.psm1 for Jenkins/Atlassian ping
fix(secrets): handle DPAPI failures gracefully on Windows 10
docs(readme): clarify idempotent re-run behavior
```

### 5. Linting

Vor dem Commit:

```powershell
# PowerShell-Lint
pwsh -Command "Invoke-ScriptAnalyzer -Path . -Recurse"

# Bash-Lint (ShellCheck)
shellcheck setup.sh
```

### 6. Push & PR

```powershell
git push origin feature/<kurze-beschreibung>
```

Erstelle einen PR gegen `main` mit:

- **Klarer Titel** (Conventional Commit-Format)
- **Beschreibung** — was ändert sich, warum, wie getestet
- **Linked Issues** — `Closes #123` oder `Refs #456`
- **Breaking Changes** — explizit kennzeichnen

---

## Konventionen

### Module

Jedes Modul in `modules/` muss:

1. Eine `.psm1`-Datei sein
2. Nur eine Verantwortlichkeit haben (SRP)
3. Mit `<Function-Name>.<Verb>` benannt sein (z.B. `Install-Tools`, `Test-Prerequisites`)
4. `Export-ModuleMember -Function *` am Ende
5. Keine direkten `Write-Host`-Aufrufe — stattdessen `Write-Information` / `Write-Verbose` nutzen
6. Keine Secrets loggen

### Konfiguration

- Tool-Definitionen in `config/tools.json`
- Client-Definitionen in `config/clients.json`
- Prerequisites in `config/prerequisites.json`
- Templates in `templates/*.tpl` (mit Platzhaltern `{{placeholder}}`)

### Sicherheit

- **Niemals** Secrets, Tokens, Passwörter committen
- `.gitignore` schützt `.env`, `*.pem`, `*.key`, `*.token` etc.
- Bei Verdacht auf geleakte Secrets: **sofort** [git-secrets](https://github.com/awslabs/git-secrets) oder `trufflehog` laufen lassen
- Secret-Handling im Skript via `Secrets.psm1` (DPAPI/`.env`)

### Tests

- Unit-Tests für jedes Modul in `tests/<Module>.Tests.ps1`
- Integration-Tests in `tests/integration/` (mit Mock-Servern)
- Kein Test überspringen, bevor ein PR gemerged wird

---

## Issue-Vorlagen

Beim Erstellen eines neuen Issues bitte die passende Vorlage verwenden:

- [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md)
- [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md)
- [Setup-Hilfe](.github/ISSUE_TEMPLATE/setup_help.md)

---

## Release-Prozess

Releases werden als GitHub Releases mit Tags `v<major>.<minor>.<patch>` gepackt:

```
v1.0.0   — Initial Release
v1.1.0   — Feature Release
v1.1.1   — Patch Release
```

Wir folgen [Semantic Versioning](https://semver.org/).

---

## Lizenz

Mit Deinem Beitrag stimmst Du zu, dass Deine Änderungen unter der [MIT-Lizenz](LICENSE) veröffentlicht werden.