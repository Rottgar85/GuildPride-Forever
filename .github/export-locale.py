# Zeigt Übersetzern, welche Texte einer Sprache noch fehlen (Deutsch -> Englisch als Vorlage):
#   python .github/export-locale.py frFR > frFR.txt
# Eintragen in Core/GuildPrideLocaleMore.lua: ["deutscher Text"] = "Übersetzung",
import re
import sys

if len(sys.argv) != 2:
    sys.exit("Aufruf: python .github/export-locale.py frFR | esES | ruRU")
lang = sys.argv[1]
sys.stdout.reconfigure(encoding="utf-8")
pair = re.compile(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"')
base = dict(pair.findall(open("Core/GuildPrideLocale.lua", encoding="utf-8").read()))
more = open("Core/GuildPrideLocaleMore.lua", encoding="utf-8").read()
part = re.search(r"\nM\." + re.escape(lang) + r" = \{(.*?)\n\}", more, re.S)
if not part:
    sys.exit("Sprache nicht gefunden: " + lang)
done = dict(pair.findall(part.group(1)))
missing = [(de, en) for de, en in base.items() if de not in done]
print("-- %s: %d von %d übersetzt, %d fehlen" % (lang, len(done), len(base), len(missing)))
for de, en in missing:
    print('    ["%s"] = "%s",' % (de, en))
