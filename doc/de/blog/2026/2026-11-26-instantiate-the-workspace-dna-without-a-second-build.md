<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Die Workspace-DNA ohne zweiten Build instanziieren

## Motivation

- `gg do init workspace` legt den Ocean an und stellt die gg-DNA in den
  Workspace-Root: die Skills und den verwalteten Block der `CLAUDE.md`.
  `gg do create ticket` aktualisiert diese DNA auf demselben Weg.
- Beides endete mit „Could not instantiate dna_gg: … git rev-parse
  --show-prefix failed … not a git repository“. Ein neuer Workspace bekam
  gar keine DNA, ein bestehender blieb auf seinem Stand.
- Ein Workspace bekommt eine abgespeckte DNA: nur `.claude/` und den Block,
  kein `doc/`, `scripts/` oder `.github/`. Der Fehler kam von dieser
  Abspeckung.

## Strategie

- Den scheiternden Schritt finden, indem die helix-Befehle von Hand
  laufen, einmal mit der vollständigen und einmal mit der abgespeckten DNA.
- Den Schritt entfernen, statt seinen Fehler zu umgehen: Er hatte nichts
  mehr zu tun.
- Die Abspeckung genau so lassen, wie sie ist.
- Den Ersatz für helix in den Tests so arbeiten lassen wie helix, damit der
  Schritt nicht unbemerkt zurückkommt.

## Zwei Schritte statt drei

- Die DNA wurde in einem temporären Ordner mit `gg dna init`,
  `gg dna add dna_gg --workspace` und `gg dna build --workspace`
  instanziiert.
- `add` baut direkt nach dem Installieren des Layers. Im Workspace-Modus
  entfernt es danach das `dna/`-Gerüst: Ein Workspace wird jedes Mal neu
  aufgesetzt, für ein späteres Update wird nichts festgehalten.
- Der `build` danach fand deshalb keinen Layer. Mit der vollständigen DNA
  bleibt das Gerüst, und derselbe Aufruf läuft durch.
- `instantiateWorkspaceDna` führt jetzt nur noch `init` und `add` aus. Was
  im Workspace landet, ist dasselbe wie vorher.

## Ein Skill als Link

- Bevor die neuen Skills kopiert werden, werden die Skill-Ordner der
  früheren DNA aus `.claude/skills/` entfernt.
- Ein Skill, den der Workspace als Link hält, wurde als Datei gelöscht.
  Unter macOS und Linux folgt das dem Link und scheitert, bei einem Link
  auf einen Ordner ebenso wie bei einem Link ins Leere. Die Instanziierung
  endete mit demselben „Could not instantiate dna_gg“.
- Der Link wird jetzt als Link entfernt. Sein Ziel bleibt unberührt.

## Tests

- Der Ersatz für die helix-Befehle schreibt Block und Skills im `add` und
  entfernt `dna/`, wie helix es tut. Ein `build` danach wirft den Fehler,
  den helix außerhalb eines Git-Repositories meldet.
- Ein Test benennt die Regel: kein `build` nach `add`.
- Die Skill-Tests decken eine Datei, einen Link ins Leere und einen Link
  auf einen Ordner ab, dessen Inhalt bleibt.
- Von Hand gegen helix 1.18.0 und dna_gg 1.9.1 geprüft: ein leerer Ordner,
  ein Workspace mit eigenem Text in der `CLAUDE.md` und eigenen Skills
  sowie ein temporärer Ordner innerhalb eines Git-Repositories.

## Aktualisierte Abhängigkeiten

- helix 1.14.0 → 1.18.0, die Constraint lautet `^1.18.0`.
- Seit helix 1.16.0 gehört ein vorhandener verwalteter `CLAUDE.md`-Block
  der DNA, auch wenn ihn kein Layer füllt. Ein Build ohne Layer will ihn
  leeren und scheitert außerhalb eines Git-Repositories an der Datei, die
  er überschreiben müsste. Bis 1.15 tat dieser Build stillschweigend
  nichts.
- helix 1.15.0 brachte `checkDna`, das der platzierte DNA-Check
  `test/dna/dna_test.dart` aufruft.

## Offene Punkte

- Ein installiertes gg bekommt den Fix mit `dart pub global activate gg`.
- Ein Workspace, dessen DNA nicht aktualisiert werden konnte, holt mit dem
  nächsten `gg do create ticket` oder `gg do init workspace` auf.
- `gg dna build --workspace`, von Hand in einem Ordner ohne `dna/`
  ausgeführt, leert den Block weiterhin. Innerhalb eines Git-Repositories
  tut helix das ohne ein Wort.
- `doc/guides/install-guide/install-gg-workspace-guide.md` nennt noch drei
  Schritte. Die Datei ist generiert und folgt mit dem nächsten DNA-Upgrade.
