<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Die CLAUDE-Layer-Dateien in neue Tickets kopieren

## Motivation

- Jedes neue Ticket bekommt die gg-DNA des Workspace-Roots: den verwalteten
  Block der `CLAUDE.md`, die Skills, die Hooks und ihre Settings.
- Seit helix 1.14.0 enthält dieser Block die Anweisungen der DNA-Layer
  nicht mehr selbst. Er importiert sie nur noch, eine Zeile pro Layer:
  `@.claude/CLAUDE_dna_gg.md`.
- Ein Ticket, das nur den Block erhält, würde Dateien importieren, die es
  nicht hat – Claude Code startete dort ohne den gg-Workflow.

## Strategie

- Die Dateien `.claude/CLAUDE_<layer>.md` zusammen mit dem Block kopieren,
  damit jeder Import des Tickets aufgelöst wird.
- Die Layer-Dateien am Namensmuster erkennen statt den Block zu parsen:
  helix schreibt genau eine `CLAUDE_<layer>.md` pro Layer nach `.claude/`.
- Den Root mit dem Build abgleichen: Eine Layer-Datei, die der neue Build
  nicht mehr liefert, wird vor der Übernahme aus dem Root entfernt.
- Alle anderen Dateien in `.claude/` bleiben unangetastet, auch eigene
  Notizen.

## Layer-Dateien ins Ticket kopieren

- `claudeLayerFilesIn(dir)` listet die `CLAUDE_*.md`-Dateien direkt in
  `<dir>/.claude/`, sortiert.
- `copyWorkspaceDna` kopiert sie nach `<ticket>/.claude/`, direkt nachdem
  der Block in die `CLAUDE.md` des Tickets geschrieben wurde.
- Ein Root ohne vollständigen Block kopiert auch keine Layer-Datei: ohne
  Block würde sie niemand importieren.

## Den Root aktuell halten

- `_takeOver` löscht die Layer-Dateien des Roots, die im temporären Build
  fehlen, und kopiert danach wie bisher das `.claude/` des Builds.
- Ein Layer, der aus `dna_gg` herausfällt, bleibt so nicht im Root liegen
  und wird nicht in spätere Tickets kopiert.

## Tests

- Neue Tests decken das Kopieren ins Ticket, den Root ohne Block und einen
  Root ab, dessen Layer-Dateien ein neuer Build ersetzt und aufräumt.
- Der Test zum Commit-Fehler in `do add` stubbte den Process-Runner mit
  `runInShell: true`, was nur unter Windows gilt. Er akzeptiert jetzt jeden
  Wert, damit die Suite auch unter Linux und macOS durchläuft.

## Aktualisierte Abhängigkeiten

- helix ^1.14.0: schreibt die `CLAUDE.md` jedes DNA-Layers nach
  `.claude/CLAUDE_<layer>.md` und lässt den verwalteten Block sie
  importieren. Die neu erzeugte DNA dieses Repos nutzt diese Form ebenfalls.

## Offene Punkte

- Die Marker des verwalteten Blocks sind weiterhin aus helix kopiert statt
  von dort importiert.
