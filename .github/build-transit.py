"""Erzeugt Travel/GuildPrideTransitData.lua aus Polestars Nav/TravelData.lua.

Übernimmt nur die Fahrpläne der Schiffe, Zeppeline und Luftschiffe (routes und services),
keine Aufzüge, Bahn, Flugpunkte oder Teleporte. Aufruf aus dem Addon-Ordner:

    python .github/build-transit.py [Pfad zu Polestar/Nav/TravelData.lua]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Polestar', 'Nav', 'TravelData.lua')
OUT = os.path.join(HERE, 'Travel', 'GuildPrideTransitData.lua')
KINDS = ('boat', 'zeppelin', 'airship')

lines = open(SRC, encoding='utf-8').read().replace('\r\n', '\n').split('\n')


def block_start(name):
    for i, l in enumerate(lines):
        if l == '\t\t%s = {' % name:
            return i
    raise SystemExit('Block %s nicht gefunden' % name)


ENTRY = re.compile(r'^\t\t\t\["([^"]+)"\] = ')


def entries(start):
    """[(id, [Zeilen])] eines Blocks bis zur schließenden Klammer auf Ebene 2."""
    out, cur = [], None
    for l in lines[start + 1:]:
        if l == '\t\t},':
            break
        m = ENTRY.match(l)
        if m:
            cur = (m.group(1), [l])
            out.append(cur)
        elif cur:
            cur[1].append(l)
    return out


services = [(i, ls) for i, ls in entries(block_start('services'))
            if re.search(r'kind="(%s)"' % '|'.join(KINDS), ls[0])]
used = set()
for _, ls in services:
    used.update(re.findall(r'route="([^"]+)"', ''.join(ls)))
routes = [(i, ls) for i, ls in entries(block_start('routes')) if i in used]
missing = used - {i for i, _ in routes}
if missing:
    raise SystemExit('Routen fehlen: %s' % ', '.join(sorted(missing)))

head = [l for l in lines[:12] if l.startswith('--')]
body = [
    '-- GuildPride: Fahrpläne der Schiffe, Zeppeline und Luftschiffe (für GuildPrideTransit.lua).',
    '-- Erzeugt von .github/build-transit.py aus Polestars Nav/TravelData.lua – nicht von Hand ändern.',
    '-- Herkunft (aus Polestar übernommen):',
] + head + [
    '-- Polestar: Copyright (c) 2026 The Polestar authors (GPL-3.0-only); übernommen für GuildPride Forever.',
    '--',
    '-- routes[id] = { kind, period (ms), fit = Schwellen fürs Mitmessen,',
    '--   stops = { { ankunft, abfahrt (ms im Umlauf), kontinent, wx, wy[, z, wagen] } },',
    '--   frames = { { ankunft, abfahrt, kontinent, wx, wy, sprung[, z] } } }',
    '-- services[id] = { kind, name, ends, areas, board, pre, post, wait, ride, routes = { { route, a = stops, b = stops } } }',
    '',
    'local ADDON, GP = ...',
    'GP.TransitData = {',
    '\troutes = {',
]
for _, ls in routes:
    body += [l[1:] for l in ls]
body += ['\t},', '\tservices = {']
for _, ls in services:
    body += [l[1:] for l in ls]
body += ['\t},', '}', '']

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(body))
print('%d Routen, %d Verbindungen -> %s' % (len(routes), len(services), OUT))
