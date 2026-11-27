<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Klonen auf einem neuen Rechner

## Motivation

- Auf einem neuen Rechner scheiterte `gg do add` beim ersten Azure-DevOps-
  Repo mit einem rätselhaften Fehler: `PathNotFoundException: Directory
  listing failed, path = '…\.ocean\<org>\<repo>\.git\objects\pack\*'`.
- Der eigentliche Grund lag dahinter verborgen: ssh kannte den Host noch
  nicht (»Host key verification failed«). Entwickler mussten erst ein Repo
  von Hand klonen und mit yes bestätigen, bevor gg funktionierte.
- Ein erster Clone soll sich selbst erklären und, wo es sicher ist, sich
  selbst helfen.

## Strategie

- Das Aufräumen nach einem gescheiterten Clone harmlos machen, damit der
  Entwickler immer den git-Fehler sieht.
- Einem unbekannten Host direkt im Lauf vertrauen können, mit Fingerprint
  und dem Vergleich mit dem veröffentlichten.
- Jedes andere ssh-Problem mit dem nächsten Schritt erklären statt mit
  einem rohen git-Fehler.
- Für alles, was ssh selbst betrifft, `SshHostKeys` aus gg_git verwenden.

## Aufräumen nach einem gescheiterten Clone

- `do add` klont bis zu vier Repos parallel. Das Aufräumen eines
  gescheiterten Clones durchsuchte den ganzen neuen Org-Ordner – auch die
  Ordner von Clones, die git gerade befüllte oder entfernte. Ein Ordner
  verschwand beim Auflisten, und diese Exception ersetzte den Clone-Fehler.
- Jetzt wird nur der Zielordner durchsucht; seine Elternordner werden
  einzeln gelöscht, solange sie leer sind, und nie durchsucht.
- Ein Ordner, der sich nicht auflisten oder löschen lässt, bleibt liegen:
  Ein Rest ersetzt nie den Clone-Fehler.

## Einem unbekannten Host vertrauen

- Scheitert der Clone, weil der Host unbekannt ist, liest `GitHandler` den
  Key, den der Host zeigt, und gibt seinen Fingerprint aus – und ob er zum
  Fingerprint passt, den GitHub oder Azure DevOps veröffentlicht.
- Er fragt, ob der Key in `~/.ssh/known_hosts` soll, und klont bei Ja neu.
  Ja ist nur vorausgewählt, wenn der Fingerprint passt.
- Ein Key, der vom veröffentlichten Fingerprint abweicht, wird ohne Frage
  abgelehnt: Wer aus Gewohnheit Ja antwortet, darf nicht den Key eines
  Angreifers speichern.
- Die Antwort gilt pro Host und Lauf. Parallele Clones eines Hosts warten
  auf die eine Frage; Dialoge verschiedener Hosts kommen nacheinander. Ein
  Host, dessen Key nicht gelesen werden konnte, wird erneut angeboten.
- Was beim Angebot schiefgeht, wird gemeldet und ersetzt nie den
  Clone-Fehler.

## ssh-Probleme erklären

- Ohne Terminal, nach einem Nein, bei geändertem Host-Key oder abgelehntem
  ssh-Key wirft der Clone `SshSetupException`: den git-Fehler plus den
  nächsten Schritt aus `SshHostKeys.setupHint`.
- `addRepositoryHelper` behält diese Exception über die Ausweich-
  Organisationen hinweg, überspringt die Organisationen auf demselben Host
  und wirft sie statt »Repository not found«.
- `do add` zeigt sie ohne die allgemeine Vermutung »vermutlich dein
  SSH-Key oder das Netzwerk«.

## Aktualisierte Abhängigkeiten

- gg_git: `SshHostKeys` – ordnet ssh-Fehler ein, liest und prüft Host-Keys,
  speichert vertraute und sagt, was als Nächstes zu tun ist.

## Offene Punkte

- `remoteExists` und die Fetches von `RepoFreshness` zeigen weiterhin den
  rohen ssh-Fehler.
