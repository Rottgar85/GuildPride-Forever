# Erzeugt GuildPrideNewsData.lua (Änderungen im Spiel) aus CHANGELOG.md: python .github/build-news.py
import re
c = open('CHANGELOG.md', encoding='utf-8').read()
secs = re.split(r'\n## ', c)[1:]
def fmt(s):
    s = re.sub(r'\*\*(.+?)\*\*', r'|cffffd100\1|r', s)
    s = re.sub(r'`(.+?)`', r'|cffe6e0da\1|r', s)
    return s
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
L = ['-- GuildPride: Änderungen der letzten Versionen fürs Spiel.', '-- ERZEUGT aus CHANGELOG.md mit: python .github/build-news.py (bei jeder Version neu erzeugen)',
     'local ADDON, ns = ...', 'ns.NEWS = {']
for sec in secs[:6]:
    ver, rest = sec.split('\n', 1)
    def part(tag):
        m = re.search(r'\*\*' + tag + r'\*\*\n(.*?)(?=\n\*\*|\Z)', rest, re.S)
        return [fmt(l[2:].strip()) for l in (m.group(1).strip().split('\n') if m else []) if l.startswith('- ')]
    L.append('    { version = %s,' % q(ver.strip()))
    L.append('      de = { ' + ', '.join(q(x) for x in part('Deutsch')) + ' },')
    L.append('      en = { ' + ', '.join(q(x) for x in part('English')) + ' } },')
L.append('}')
open('Core/GuildPrideNewsData.lua', 'w', encoding='utf-8').write('\n'.join(L) + '\n')
