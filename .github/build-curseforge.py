# Erzeugt docs/CURSEFORGE.md (Beschreibung zum Einfügen auf CurseForge und Wago) aus README.md:
#   python .github/build-curseforge.py
# So gibt es nur einen Text zu pflegen. Läuft vor jeder Veröffentlichung. Gekürzt: von jedem Punkt
# der erste Satz, ohne Befehlsliste; das Ausführliche steht auf GitHub.
import re

s = open("README.md", encoding="utf-8").read()
version = re.search(r"Version (\d+\.\d+\.\d+)", s).group(1)
en = re.search(r"\n## English\n+(.*?)\n---\n", s, re.S).group(1).strip()
de = re.search(r"\n## Deutsch\n+(.*?)\n### Installation", s, re.S).group(1).strip()


def short(text):
    out = []
    for part in re.split(r"(?m)^(?=### )", text):
        head = part.split("\n", 1)[0]
        if re.match(r"### (Commands|Befehle|Feedback)", head):
            continue
        full = re.match(r"### (NEW|NEU|Security|Sicherheit)", head)
        lines = []
        for line in part.rstrip().split("\n"):
            if line.startswith("- ") and not full:
                # erster Satz (Punkte nach Ziffern und in "z. B." zählen nicht als Satzende)
                m = re.match(r"(.*?[^\d\s.][.!?]\**)(?= +[A-ZÄÖÜ*`„])", line)
                if m and not re.search(r"\b(z|B|e|g|bzw|ca)\.$", m.group(1)):
                    line = m.group(1)
            lines.append(line)
        out.append("\n".join(lines))
    return "\n\n".join(x.strip() for x in out if x.strip())


intro, en = en.split("\n\n", 1)
en, de = short(en), short(de)
MORE_EN = "*All commands: `/gp help` in game. Full description: https://github.com/Rottgar85/GuildPride-Forever*"
MORE_DE = "*Alle Befehle: `/gp hilfe` im Spiel. Ausführlich: https://github.com/Rottgar85/GuildPride-Forever*"
de = re.sub(r"\n\*Version [\d.]+\*\n", "\n", de)
out = [
    "# GuildPride Forever", "", intro, "",
    "*Version %s · Deutsche Beschreibung weiter unten.*" % version, "", "---", "",
    "## 🇬🇧 English", "", en, "", MORE_EN, "", "---", "",
    "## 🇩🇪 Deutsch", "", de, "", MORE_DE, "", "---", "",
    "*Ship timetables based on Polestar and Shortest Path Forever (GPL-3.0). Rare spawn points from ForeverMapNotes / QuestieDB Forever and CMaNGOS classic-db (GPL-3.0). Fonts: DejaVu, Inter (SIL OFL 1.1). Artwork created for GuildPride.*",
]
text = re.sub(r"\n{3,}", "\n\n", "\n".join(out)) + "\n"
open("docs/CURSEFORGE.md", "w", encoding="utf-8", newline="\n").write(text)
print("docs/CURSEFORGE.md: Version %s, %d Zeichen" % (version, len(text)))
