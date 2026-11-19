"""Erzeugt Travel/GuildPrideFlightData.lua aus Polestars Nav/TravelData.lua.

Übernimmt nur die Flugpunkte (Kontinent, Weltkoordinaten, englischer Name) und die
Direktflüge zwischen ihnen mit den geflogenen Yards. Aufruf aus dem Addon-Ordner:

    python .github/build-flight.py [Pfad zu Polestar/Nav/TravelData.lua]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Polestar', 'Nav', 'TravelData.lua')
OUT = os.path.join(HERE, 'Travel', 'GuildPrideFlightData.lua')

lines = open(SRC, encoding='utf-8').read().replace('\r\n', '\n').split('\n')


def block(name):
    """Zeilen eines Blocks auf Ebene 1 bis zur schließenden Klammer."""
    for i, l in enumerate(lines):
        if l == '\t%s = {' % name:
            out = []
            for m in lines[i + 1:]:
                if m == '\t},':
                    return out
                out.append(m)
    raise SystemExit('Block %s nicht gefunden' % name)


NODE = re.compile(r'^\t\t\{(\d+),(\d+),(-?[\d.]+),(-?[\d.]+),[^,]*,[^,]*,[^,]*,\d+,"([^"\\]*)"')
FLIGHT = re.compile(r'^\t\t(\d+),(\d+),(\d+),$')

nodes = {}
for l in block('taxi'):
    m = NODE.match(l)
    if m:
        nodes[int(m.group(1))] = (m.group(2), m.group(3), m.group(4), m.group(5))
flights = {}
for l in block('flights'):
    m = FLIGHT.match(l)
    if m:
        a, b, yd = int(m.group(1)), int(m.group(2)), int(m.group(3))
        flights.setdefault(a, []).append((b, yd))
if not nodes or not flights:
    raise SystemExit('Keine Flugpunkte oder Flüge gefunden')
missing = sorted({a for a in flights if a not in nodes} | {b for v in flights.values() for b, _ in v if b not in nodes})
if missing:
    raise SystemExit('Flugpunkte fehlen: %s' % ', '.join(map(str, missing)))

head = [l for l in lines[:12] if l.startswith('--')]
body = [
    '-- GuildPride: Flugpunkte und Direktflüge (für GuildPrideFlight.lua).',
    '-- Erzeugt von .github/build-flight.py aus Polestars Nav/TravelData.lua – nicht von Hand ändern.',
    '-- Herkunft (aus Polestar übernommen):',
] + head + [
    '-- Polestar: Copyright (c) 2026 The Polestar authors (GPL-3.0-only); übernommen für GuildPride Forever.',
    '--',
    '-- nodes[id] = { kontinent, wx, wy, englischer Name }',
    '-- flights[von] = { nach, geflogene Yards, nach, Yards, ... } (nur Direktflüge, eine Richtung)',
    '',
    'local ADDON, GP = ...',
    'GP.FlightData = {',
    '\tnodes = {',
]
for i in sorted(nodes):
    c, x, y, name = nodes[i]
    body.append('\t\t[%d] = {%s,%s,%s,"%s"},' % (i, c, x, y, name))
body += ['\t},', '\tflights = {']
for a in sorted(flights):
    body.append('\t\t[%d] = {%s},' % (a, ','.join('%d,%d' % hop for hop in flights[a])))
body += ['\t},', '}', '']

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(body))
print('%d Flugpunkte, %d Flüge -> %s' % (len(nodes), sum(len(v) for v in flights.values()), OUT))
