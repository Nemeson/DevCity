# DevCity Memory

Lokales Verzeichnis für **projektspezifisches Memory** — gespeist von `codebase-memory-mcp`.

---

## Was wird hier gespeichert?

| Typ | Datei/Verzeichnis | Beschreibung |
|---|---|---|
| **Knowledge-Graph** | `codebase-graph.json` | Strukturierte Codebasis-Erinnerung (von codebase-memory-mcp verwaltet) |
| **Session-Memory** | `sessions/` | Kontext aus vergangenen Agent-Driven-Sessions |
| **Decisions** | `decisions/` | Architekturentscheidungen, die der Agent getroffen hat |
| **Snapshots** | `snapshots/` | Memory-Interne Snapshots (nicht zu verwechseln mit `backups/`) |
| **Config** | `devcity-memory.json` | Konfiguration des Memory-Stores (lokal/zentral, Transportweg) |

---

## Lokal vs. Zentral

Beim Setup hast Du gewählt:

- **lokal** → dieses Verzeichnis, NICHT ins Git-Repo gepusht (`.gitignore` schützt es)
- **zentral** → Memory wird mit dem Jenkins/Atlassian-Server synchronisiert; dieses Verzeichnis ist ein lokaler Cache

Konfiguration steht in `devcity-memory.json`.

---

## `.gitignore`-Verhalten

```
memory/*
!memory/README.md
!memory/.gitkeep
```

→ Die README und der `.gitkeep` sind im Repo, alle anderen Inhalte lokal.

---

## Sync (nur bei Mode='zentral')

```powershell
# Push: lokal → zentral
.\setup.ps1 -OnlyModule 4  # Memory-Modul aufrufen (Stub)
# TODO: Sync-DevCityMemory -Direction push

# Pull: zentral → lokal
# TODO: Sync-DevCityMemory -Direction pull
```

---

## Reset / Clean

```powershell
# Memory löschen (mit Snapshot-Backup)
.\setup.ps1 -OnlyModule 4 -Force
# TODO: Remove-DevCityMemory -Force
```

**Achtung:** Löschen ist destruktiv. Snapshot wird vorher automatisch erzeugt (NFR 3C).

---

## NFRs

- **Sicherheit:** Memory kann sensible Inhalte (Code-Snippets, Kommentare) enthalten. Darum `gitignored`.
- **Performance:** Lokales Memory ist schnell. Zentrales Memory via SSH/SCP ist langsamer, aber team-sync.
- **Wartbarkeit:** `devcity-memory.json` dokumentiert die Config.

---

## Nutzung mit codebase-memory-mcp

Der `codebase-memory-mcp`-Server wird vom DevCity-Setup in Deinen MCP-Client geschrieben (OpenCode/Copilot CLI/etc.). Seine Environment-Variable `MEMORY_STORE_PATH` zeigt auf dieses Verzeichnis.

Sobald der Agent läuft, schreibt er Memory-Einträge hier hinein. Beim nächsten Start liest er sie wieder und hat den Kontext.