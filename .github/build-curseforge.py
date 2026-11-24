# Erzeugt docs/CURSEFORGE.md (Beschreibung zum Einfügen auf CurseForge und Wago) aus README.md:
#   python .github/build-curseforge.py
# So gibt es nur einen Text zu pflegen. Läuft vor jeder Veröffentlichung.
import re

s = open("README.md", encoding="utf-8").read()
version = re.search(r"Version (\d+\.\d+\.\d+)", s).group(1)
en = re.search(r"\n## English\n+(.*?)\n---\n", s, re.S).group(1).strip()
de = re.search(r"\n## Deutsch\n+(.*?)\n### Installation", s, re.S).group(1).strip()
intro, en = en.split("\n\n", 1)
de = re.sub(r"\n\*Version [\d.]+\*\n", "\n", de)
out = [
    "# GuildPride Forever", "", intro, "",
    "*Version %s · Deutsche Beschreibung weiter unten.*" % version, "", "---", "",
    "## 🇬🇧 English", "", en, "", "---", "",
    "## 🇩🇪 Deutsch", "", de, "", "---", "",
    "*Ship timetables based on Polestar and Shortest Path Forever (GPL-3.0). Rare spawn points from ForeverMapNotes / QuestieDB Forever and CMaNGOS classic-db (GPL-3.0). Fonts: DejaVu, Inter (SIL OFL 1.1). Artwork created for GuildPride.*",
]
text = re.sub(r"\n{3,}", "\n\n", "\n".join(out)) + "\n"
open("docs/CURSEFORGE.md", "w", encoding="utf-8", newline="\n").write(text)
print("docs/CURSEFORGE.md: Version %s, %d Zeichen" % (version, len(text)))
