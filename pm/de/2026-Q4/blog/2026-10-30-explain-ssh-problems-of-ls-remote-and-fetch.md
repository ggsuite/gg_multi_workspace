<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# ssh-Probleme bei ls-remote und fetch erklären

## Motivation

- Ein Clone erklärt ein ssh-Problem bereits und bietet an, einem
  unbekannten Host zu vertrauen. Die anderen git-Netzbefehle der
  Workspace-Kommandos taten das nicht.
- `remoteExists` entscheidet, welche Organisationen ein Repository
  besitzen. Scheiterte ssh, antwortete es »nein« – das Repository wirkte
  fehlend, und der Lauf riet eine Organisation, ohne den Grund zu nennen.
- Die Fetches von `do add` meldeten den rohen git-Fehler, einmal pro Aufruf
  und Repository.

## Strategie

- `remoteExists` wie einen Clone behandeln: den unbekannten Host zum
  Vertrauen anbieten und git erneut fragen.
- Jedes andere ssh-Problem mit dem nächsten Schritt aus
  `SshHostKeys.setupHint` von gg_git erklären – einmal pro Host, egal wie
  viele Aufrufe scheitern.

## remoteExists

- Ein unbekannter Host bekommt denselben Dialog wie bei einem Clone:
  Fingerprint, Vergleich mit dem veröffentlichten, die Frage. Nach einem Ja
  läuft `ls-remote` erneut.
- Ist ssh für den Host nicht eingerichtet, bleibt die Antwort false, aber
  der nächste Schritt wird einmal pro Host und Lauf ausgegeben.
- Ein Repository, das wirklich nicht existiert, meldet wie bisher nichts.

## Die git-Aufrufe von do add

- `do add` fetcht jedes Ocean-Repository, das es in ein Ticket kopiert:
  `fetch`, `fetch --tags`, `fetch --prune --tags`.
- Scheitert einer davon an ssh, wird der nächste Schritt einmal pro Host
  ausgegeben, mit der URL aus dem `origin` des Repositorys.

## Aktualisierte Abhängigkeiten

- gg_git: `Fetch` erklärt ssh-Probleme in seinem Fehler, der so auch
  `RepoFreshness` und jeden anderen Aufrufer erreicht.

## Offene Punkte

- Keine.
