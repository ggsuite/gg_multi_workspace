<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Nur auflösen, was do add verändert

## Motivation

- `gg do add` lokalisierte am Ende jedes Laufs das ganze Ticket und rief in
  jedem Ticket-Repo `pub upgrade` auf. `pub upgrade` fragt beim Remote
  jeder git-Abhängigkeit nach neuen Tags: eine ssh-Verbindung pro
  git-Abhängigkeit und Repo.
- Einzeln hinzugefügt kosteten N Repos N·(N+1)/2 Upgrades. In einem Ticket,
  dessen Pakete sich per git referenzieren, waren das Minuten pro Repo.
- Dazu lief in jedem kopierten Repo ein `pub get`, kurz bevor die
  Lokalisierung es erneut auflöste – vier Kopien parallel, auf denselben
  git-Mirrors des pub-Caches.

## Strategie

- Mit `pub get` auflösen. Es behält die Lock-Datei und holt nur einen
  gesperrten Commit, der im pub-Cache fehlt. Upgraden bleibt Aufgabe von
  `gg do push`.
- Nur die Repos auflösen, die es brauchen, nicht jedes Ticket-Repo.
- Einmal pro Repo installieren: die Kopie installiert nichts.
- Der Lauf heilt sich weiter selbst: Was ein früherer Lauf unaufgelöst
  ließ, löst der nächste auf.

## Die Repos, die ein Lauf auflöst

- Die in diesem Lauf kopierten Repos – sie wurden im Ticket nie
  aufgelöst.
- Die Repos, die ein neues Repo aus dem Takt bringt: ein neues
  Geschwister-Repo ändert ihre Overrides. Ein von der Flach-Migration
  verschobenes Repo zählt auch, sein Override-Pfad hat sich geändert.
- Die Repos, deren Abhängigkeiten nie installiert wurden oder deren
  Auflösung einen Pfad-Override ignoriert – ein gescheiterter oder
  abgebrochener früherer Lauf.
- Alle anderen Ticket-Repos behalten ihre Auflösung. Der abschließende
  `#gg:`-Commit erfasst weiter jedes Repo, damit die von gg geschriebenen
  Konfigurationsdateien committet bleiben.

## Installationen

- `_copyRepoToTicket` kopiert nur und checkt den Ticket-Branch aus.
- Die abschließende Lokalisierung installiert die kopierten Repos. Mit
  `--no-localize` installiert `do add` sie nacheinander.
- Ein gescheitertes `pub get` oder `npm install` erscheint auch ohne
  `--verbose`: das Repo baut nicht, bis es behoben ist.

## Ergebnis

- Gemessen mit drei Repos und pub.dev-Abhängigkeiten: ein Aufruf sank von
  250 s auf 142 s, drei Einzelaufrufe von 394 s auf 221 s – beide Läufe
  des neuen Codes kompilierten gg noch aus dem Quellcode, etwa 40 s pro
  Aufruf.
- Die Lock-Dateien ändern sich bei `do add` nicht mehr, kein `#gg:`-Commit
  enthält mehr Upgrade-Rauschen.

## Aktualisierte Abhängigkeiten

- gg_multi_core: `TicketLocalizer.outOfSync` nennt die Repos mit nicht
  lokalisierten Referenzen, `repoDependenciesOutdated` die, die neu
  installiert werden müssen.

## Offene Punkte

- `do commit`, `do push` und `do localize` prüfen veraltete
  Abhängigkeiten noch nicht; sie lokalisieren nur die Repos, die aus dem
  Takt sind.
