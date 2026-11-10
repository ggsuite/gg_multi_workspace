<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# ReadSettings aus gg_multi_core verwenden

## Motivation

- `gg do add` liest `~/.gg_rc`, um `--[no-]transitive` vorzubelegen
  (`do.add.transitive`). Die Lesefunktion wird übergeben: `AddCommand`
  bekommt sie als `readSettings`, und ohne sie gelten die eingebauten
  Voreinstellungen. Kein Test liest oder schreibt so die echte Datei.
- Für dieses Argument deklarierte das Paket in
  `lib/src/commands/do/add.dart` einen eigenen Funktionstyp:
  `typedef ReadSettings = GgRc Function({required GgLog ggLog});`
- Die Bibliothek exportiert diese Datei, der Typ war also Teil der
  öffentlichen API. Ein anderes Paket deklarierte den identischen Typ
  unter demselben Namen. Für Dart sind das zwei verschiedene
  Deklarationen, und eine Bibliothek, die beide exportierte, ließ sich
  nicht mehr kompilieren:
  `'ReadSettings' is exported from both …`
- Der Typ beschreibt, wie `GgRc` geladen wird. Er gehört deshalb zu
  gg_multi_core, wo `GgRc` liegt.

## Strategie

- Das `ReadSettings` verwenden, das gg_multi_core jetzt neben `GgRc`
  deklariert
- Die eigene Deklaration löschen
- Den Namen für die Nutzer dieses Pakets erhalten: Die Bibliothek
  exportiert den aus gg_multi_core weiter, so wie sie es mit
  `OrganizationRepoLists` schon tut
- Kein Verhalten ändern

## Realisierung 1: der Typ

- `add.dart` hat seinen Typ verloren. Es importiert bereits
  `package:gg_multi_core/gg_multi_core.dart`, das den Typ liefert. So
  behalten `AddCommand(readSettings: …)`, das Feld `_readSettings` und die
  Rückfallfunktion `_builtInSettings` ihren Typ
- Die Tests importieren gg_multi_core bereits und mussten nicht geändert
  werden

## Realisierung 2: der Export

- `lib/gg_multi_workspace.dart` ergänzt den Namen im bestehenden
  Weiter-Export:

  ```dart
  // Moved to gg_multi_core; still exported for the users of this package.
  export 'package:gg_multi_core/gg_multi_core.dart'
      show OrganizationRepoLists, ReadSettings;
  ```

- Code, der `ReadSettings` aus diesem Paket importiert, kompiliert weiter
- Eine Bibliothek, die dieses Paket zusammen mit einem anderen exportiert,
  das denselben Typ weiter exportiert, kompiliert ebenfalls: Beide Namen
  zeigen jetzt auf dieselbe Deklaration

## Aktualisierte Abhängigkeiten

- gg_multi_core `^4.18.0`: die erste Version, die `ReadSettings`
  deklariert

## Ergebnis

- Gleiches Verhalten, gleiche öffentliche Namen, eine Deklaration des Typs
- Veröffentlicht als Patch-Version

## Offene Punkte

- Keine
