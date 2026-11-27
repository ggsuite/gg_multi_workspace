<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Vom Workspace-Root aus publishen

## Motivation

- `gg do init` schreibt eine CLAUDE.md mit den gg-Befehlen eines
  Ticket-Workspaces.
- Ihre Zeile `gg do publish` brachte Leute dazu, den Publish im
  Ticket-Ordner zu starten.
- Am Ende eines Publish wandert der Ticket-Ordner in den Papierkorb.
  Windows verschiebt keinen Ordner, in dem ein Terminal steht, deshalb
  scheiterte das Aufräumen dort mit „used by another process“.

## Strategie

- Den Publish so zeigen, wie er auf jeder Plattform funktioniert: vom
  Workspace-Root aus, das Ticket per `-i` benannt.
- Begründen, damit es dabei bleibt.

## Befehle in der CLAUDE.md

- Die Zeile lautet jetzt `gg do publish -i <ticket>`, von einem Menschen im
  Workspace-Root auszuführen.
- Ein Satz unter den Befehlen erklärt, dass Windows keinen Ordner
  verschiebt, in dem ein Terminal steht.

## Ergebnis

- Agenten und Menschen, die der erzeugten CLAUDE.md folgen, publishen vom
  Workspace-Root aus, und das Ticket wandert auch unter Windows in den
  Papierkorb.

## Offene Punkte

- Bestehende Workspaces behalten ihre alte CLAUDE.md, bis `gg do init` sie
  neu schreibt.
