<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# gg do add: standardmäßig nur die genannten Repos

## Motivation

- `gg do add a c` hat bisher auch die Repos zwischen `a` und `c`
  hinzugefügt (`a → b → c`: `b` kam mit)
- Gebraucht werden sie nur, wenn ein Release seine Abhängigen **bricht** —
  ein Major-Sprung, unter 1.0.0 ein Minor-Sprung. Jedes andere Release
  passt in den Caret-Constraint, den `b` schon hat
- Sie trotzdem hinzuzufügen machte Tickets groß: mehr Repos zum Kopieren,
  Lokalisieren, Testen und Veröffentlichen, und ein `gg do add`, das die
  ganze Abhängigkeitshülle abläuft, fetcht und klont, bevor es den Graphen
  baut
- Schlanke Tickets gingen schon mit `--no-transitive` oder `~/.gg_rc`.
  Jetzt sind sie der Standard

## Strategie

- Den Standard aus den Einstellungen nehmen: `GgRc` aus gg_one_core (von
  gg_multi_core re-exportiert) hat jetzt `do.add.transitive = false`
- Jeden Weg zu den Repos dazwischen behalten: `--transitive` für einen
  Lauf, `{"do": {"add": {"transitive": true}}}` in `~/.gg_rc` für jeden
  Lauf, `gg do add transitive for <repo>` genau dann, wenn ein brechendes
  Release sie braucht
- Im Log sagen, warum die Repos dazwischen fehlen
- Die transitive Maschinerie bleibt, wie sie ist; sie läuft nur noch auf
  Wunsch

## Der Befehl

- `--transitive`: `defaultsTo: false`, Hilfe »Also add the repos between
  the ticket repos (off by default; ~/.gg_rc can turn it on)«
- Die Rangfolge bleibt: ein Flag auf der Kommandozeile, dann `~/.gg_rc`,
  dann der eingebaute Standard
- Die Zeile beim Überspringen nennt ihre Quelle:
  - `--no-transitive`, wenn das Flag angegeben wurde
  - `<file>: do.add.transitive = false`, wenn die Datei es setzt
  - sonst `default`:
    `Skip adding transitive repos (default). A breaking release adds them
    later: gg do add transitive for <repo>.`
- Ohne `--transitive` werden weder fehlende Abhängigkeiten in den Ocean
  geklont noch der Abhängigkeitsgraph gebaut — ein einfaches `gg do add`
  ist schneller
- `gg do add transitive [for <repo>…]` und `addReposBetweenWithAddCommand`
  bleiben unverändert: Sie fügen die Repos dazwischen, nach denen gefragt
  wird, immer hinzu
- Jede andere Konstruktion von `AddCommand` ohne Einstellungsleser —
  darunter `WorkspaceRepoHost.addWithAddCommand` — folgt ebenfalls dem
  neuen eingebauten Standard

## Tests

- 21 Tests, die vom transitiven Hinzufügen selbst handeln — die
  Klon-Durchläufe, der Graph, die Repos dazwischen — geben jetzt
  `--transitive` mit
- Neu: Die Repos dazwischen bleiben standardmäßig draußen und die Zeile
  beim Überspringen sagt `default`; `~/.gg_rc` mit `"transitive": true`
  fügt sie hinzu
- Ein Ticket-Ordner ohne Manifest hält den Rückgriff auf den Ordnernamen
  abgedeckt

## Aktualisierte Abhängigkeiten

- gg_one_core: `GgRc.builtInDefaults` lässt `do.add.transitive` aus. Eine
  `~/.gg_rc`, die noch genau das enthält, was ein älteres gg geschrieben
  hat — mit `"transitive": true` —, bekommt die neuen Standards
  hineingeschrieben; eine bearbeitete Datei bleibt. Ohne das käme der neue
  Standard bei niemandem an, der gg schon benutzt hat

## Offene Punkte

- Ein Ticket, das eine brechende Version veröffentlicht, braucht die Repos
  dazwischen weiterhin vor dem Publish: `gg do add transitive for <repo>`
