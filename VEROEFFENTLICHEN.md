# GuildPride Forever veröffentlichen

GitHub baut die ZIP automatisch und lädt sie zu CurseForge (und auf Wunsch zu Wago) hoch.
Diese Datei und der Ordner `.github` landen nicht in der ZIP.

## Schon eingerichtet

- GitHub-Repository: https://github.com/Rottgar85/GuildPride-Forever
- CurseForge-Projekt-ID in `GuildPrideForever.toc`: `## X-Curse-Project-ID: 1788777`
- GitHub-Secret `CF_API_KEY` (Repository → Settings → Secrets and variables → Actions)

Für Wago zusätzlich: `## X-Wago-ID: abcdef12` in die `.toc` und das Secret `WAGO_API_TOKEN`
(addons.wago.io → Account → API Keys). Das GitHub-Token ist automatisch vorhanden.

## Lua-Code lokal prüfen (luacheck)

- `luacheck.exe` (v1.2.0, github.com/lunarmodules/luacheck/releases) liegt in `.tools/` – nicht im Git, nicht in der ZIP
- Von Hand: `.\.tools\luacheck.exe . --no-color`
- Automatisch vor jedem `git push` über `.githooks/pre-push`; bei Fehlern wird der Push abgebrochen.
  Einmal pro Klon einschalten: `git config core.hooksPath .githooks`

## Neue Version veröffentlichen

1. In `GuildPrideForever.toc` die `## Version:` erhöhen und in `CHANGELOG.md` eintragen, was neu ist.
2. Änderungen hochladen (commit und push). GitHub prüft dabei den Lua-Code (Check).
3. Einen Tag mit der Version setzen und hochladen, zum Beispiel:
   `git tag v1.15.1` und dann `git push origin v1.15.1`
4. Unter „Actions“ im Repository siehst du, wie die ZIP gebaut und hochgeladen wird.
   Die fertige ZIP liegt danach auch unter „Releases“.

## Ohne GitHub: ZIP von Hand hochladen

Auf curseforge.com → Projekt 1788777 → „Upload File“ die fertige ZIP wählen,
als Spielversion nur WoW Forever (1.60.1) angeben, Release-Typ „Release“ und den Abschnitt der neuen
Version aus `CHANGELOG.md` als Changelog einfügen.
