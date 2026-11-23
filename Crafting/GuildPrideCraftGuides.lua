-- GuildPride Handwerk: Leveling-Routen 1–300 für WoW Forever
-- Herstellungsberufe nach der Forever-Route von Wowhead (wowhead.com/forever/profession-leveling-guides),
-- eigene Zusammenstellung: je Schritt { von, bis, Rezept-ID (= Zauber-ID), Anzahl, Bauplan-Item, Händler }.
-- Namen, Zutaten und Farben kommen live aus dem Spiel (eigene Sprache, echte Zutaten).
-- Sammelberufe: Gebiete je Stufe (eigene Zusammenstellung).
-- Schlüssel = Skill-Line-ID des Berufs (wie GetProfessionInfo sie liefert).
local ADDON, ns = ...

local G = {}
ns.CraftGuides = G

-- Ränge: ab welcher Stufe man den nächsten lernt (und mit welcher Charakterstufe)
G.RANKS = {
    { max = 75,  learnAt = 1,   level = 5,  de = "Lehrling",   en = "Apprentice" },
    { max = 150, learnAt = 50,  level = 10, de = "Geselle",    en = "Journeyman" },
    { max = 225, learnAt = 125, level = 20, de = "Experte",    en = "Expert" },
    { max = 300, learnAt = 200, level = 35, de = "Fachmann",   en = "Artisan" },
}

G.NAMES = {
    [164] = { de = "Schmiedekunst",      en = "Blacksmithing" },
    [165] = { de = "Lederverarbeitung",  en = "Leatherworking" },
    [171] = { de = "Alchemie",           en = "Alchemy" },
    [197] = { de = "Schneiderei",        en = "Tailoring" },
    [202] = { de = "Ingenieurskunst",    en = "Engineering" },
    [333] = { de = "Verzauberkunst",     en = "Enchanting" },
    [185] = { de = "Kochkunst",          en = "Cooking" },
    [129] = { de = "Erste Hilfe",        en = "First Aid" },
    [186] = { de = "Bergbau",            en = "Mining" },
    [182] = { de = "Kräuterkunde",       en = "Herbalism" },
    [393] = { de = "Kürschnerei",        en = "Skinning" },
    [356] = { de = "Angeln",             en = "Fishing" },
}
G.ORDER = { 164, 165, 171, 197, 202, 333, 185, 129, 186, 182, 393, 356 }
G.GATHER = { [186] = true, [182] = true, [393] = true, [356] = true }

-- Hinweise zu Rängen, die nicht beim normalen Lehrer zu haben sind
G.RANK_NOTES = {
    [185] = { de = "Experte: Buch „Kochbuch für Experten“ (Shandrina / Wulan). Fachmann: Quest „Muschelüberraschung“.",
              en = "Expert: The Expert Cookbook (Shandrina / Wulan). Artisan: quest Clamlette Surprise." },
    [129] = { de = "Experte: Buch „Erste Hilfe für Experten – Gut verbunden“ (Deneb Walker / Balai Lok'Wein). Fachmann: Quest „Triage“.",
              en = "Expert: book Expert First Aid – Under Wraps (Deneb Walker / Balai Lok'Wein). Artisan: quest Triage." },
    [356] = { de = "Experte: Buch beim Angellehrer in Beutebucht (Old Man Heming). Fachmann: Quest von Nat Pagle (Düstermarschen).",
              en = "Expert: book from Old Man Heming in Booty Bay. Artisan: quest from Nat Pagle (Dustwallow Marsh)." },
    [171] = { de = "Ab 270: besondere Lehrer nach einer Questreihe (Allianz: Seltsames Kind in Westfall, Horde: Apotheker Renferrel im Silberwald).",
              en = "From 270: special trainers after a quest line (Alliance: Odd Child in Westfall, Horde: Apothecary Renferrel in Silverpine Forest)." },
    [164] = { de = "Fachmann lernt man nur bei wenigen Lehrern, z. B. Brikk Keencraft in Beutebucht.",
              en = "Artisan is taught by only a few trainers, e.g. Brikk Keencraft in Booty Bay." },
}

-- { von, bis, Rezept, Anzahl, Bauplan-Item (optional), Händler (optional) }
G.STEPS = {
    [164] = {   -- Schmiedekunst
        { 1, 30, 2660, 32 }, { 30, 65, 3320, 42 }, { 65, 75, 2661, 10 }, { 75, 80, 19666, 5 },
        { 80, 90, 2668, 10 }, { 90, 100, 2666, 13 }, { 100, 105, 2674, 5 }, { 105, 110, 2666, 10 },
        { 110, 125, 2668, 15 }, { 125, 129, 8768, 6 }, { 129, 140, 9985, 11 }, { 140, 147, 2672, 17 },
        { 147, 155, 3501, 8 }, { 155, 165, 3506, 12 }, { 165, 183, 3501, 31 }, { 183, 190, 9928, 7 },
        { 190, 200, 7223, 16 }, { 200, 205, 9928, 5 }, { 205, 210, 9931, 5 }, { 210, 215, 9928, 12 },
        { 215, 225, 9959, 10 }, { 225, 235, 16640, 15 }, { 235, 240, 9961, 12 }, { 240, 246, 9968, 17 },
        { 246, 250, 10001, 12 }, { 250, 257, 19669, 10 },
        { 257, 270, 10013, 20, 8030, "Magnus Frostwake" },
        { 270, 275, 1252365, 5, 251468, "Pexmit" },
        { 275, 279, 16969, 4, 12819, "Magnus Frostwake" },
        { 279, 300, 1252365, 24, 251468, "Pexmit" },
    },
    [171] = {   -- Alchemie
        { 1, 12, 1245250, 11 }, { 12, 55, 7183, 43 }, { 55, 65, 2331, 10 }, { 65, 90, 2334, 26 },
        { 90, 120, 3171, 30 }, { 120, 160, 3173, 43 }, { 160, 195, 3452, 38 }, { 195, 205, 11449, 10 },
        { 205, 225, 11448, 20 },
        { 225, 226, 11459, 1, 9303, "Alchemist Pestlezugg" },
        { 226, 240, 11448, 20 }, { 240, 260, 11460, 23 },
        { 260, 270, 17553, 10, 13477, "Ulthir (A) / Algernon (H)" },
        { 270, 300, 1231583, 31 },
    },
    [197] = {   -- Schneiderei
        { 1, 43, 2963, 54 }, { 43, 45, 2385, 2 }, { 45, 70, 8776, 33 }, { 70, 75, 2397, 7 },
        { 75, 81, 2964, 12 }, { 81, 100, 2402, 27 }, { 100, 110, 3839, 10 }, { 110, 125, 3848, 19 },
        { 125, 132, 8760, 7 }, { 132, 139, 6690, 8 }, { 139, 140, 3871, 1 }, { 140, 149, 3865, 11 },
        { 149, 160, 8764, 11 }, { 160, 170, 8770, 10 }, { 170, 180, 12048, 10 }, { 180, 190, 12061, 11 },
        { 190, 205, 12053, 17 }, { 205, 214, 18401, 11 }, { 214, 234, 18402, 21 },
        { 234, 250, 18409, 18, 14472, "Darnall" },
        { 250, 260, 18423, 12, 14488, "Darnall" },
        { 260, 280, 1257487, 25, 254124, "Pexmit" },
        { 280, 285, 23662, 8, 19215, "Meilosh" },
        { 285, 292, 1297120, 7, 275580, "Mishta" },
        { 292, 299, 1297121, 9, 275581, "Mishta" },
        { 299, 300, 1297122, 4, 275582, "Mishta" },
    },
    [165] = {   -- Lederverarbeitung
        { 1, 30, 2881, 32 }, { 30, 45, 2152, 20 }, { 45, 55, 3816, 10 }, { 55, 85, 3756, 35 },
        { 85, 100, 3763, 20 }, { 100, 115, 7135, 15 }, { 115, 118, 2167, 7 }, { 118, 125, 3766, 7 },
        { 125, 135, 3818, 10 }, { 135, 143, 3766, 18 }, { 143, 145, 3818, 12 }, { 145, 155, 3770, 25 },
        { 155, 160, 7151, 5 },
        { 160, 180, 3778, 20, 14635, "Rikqiz" },
        { 180, 185, 7151, 12 },
        { 185, 190, 3778, 7, 14635, "Rikqiz" },
        { 190, 200, 7156, 20 }, { 200, 210, 10487, 20 }, { 210, 225, 10548, 15 }, { 225, 230, 19058, 5 },
        { 230, 240, 10548, 20 },
        { 240, 255, 19049, 15, 15725, "Leonard Porter (A) / Werg Thickblade (H)" },
        { 255, 260, 19048, 6, 15724, "Zannok Hidepiercer" },
        { 260, 270, 19049, 20, 15725, "Leonard Porter (A) / Werg Thickblade (H)" },
        { 270, 300, 19088, 33, 15762, "Zannok Hidepiercer" },
    },
    [202] = {   -- Ingenieurskunst
        { 1, 30, 3918, 32 }, { 30, 50, 3922, 20 }, { 50, 51, 7430, 1 }, { 51, 75, 3923, 29 },
        { 75, 90, 3929, 16 }, { 90, 100, 3931, 15 }, { 100, 105, 3973, 5 }, { 105, 125, 3938, 25 },
        { 125, 135, 3978, 10 }, { 135, 150, 3942, 23 }, { 150, 160, 3953, 12 }, { 160, 175, 3955, 15 },
        { 175, 194, 12585, 51 }, { 194, 195, 12590, 1 }, { 195, 200, 12589, 5 }, { 200, 215, 12591, 18 },
        { 215, 238, 12599, 33 }, { 238, 250, 12619, 15 }, { 250, 260, 19788, 27 },
        { 260, 285, 19791, 25, 16042, "Gearcutter Cogspinner (A) / Sovik (H)" },
        { 285, 300, 19795, 15, 16047, "Xizzer Fizzbolt" },
    },
    [333] = {   -- Verzauberkunst (2–20: grüne Gegenstände entzaubern)
        { 1, 2, 7421, 1 }, { 20, 79, 14293, 59 }, { 79, 90, 7426, 11 }, { 90, 100, 7457, 10 },
        { 100, 101, 7795, 1 }, { 101, 110, 14807, 9 },
        { 110, 135, 13419, 25, 11039, "Dalria (A) / Kulwia (H)" },
        { 135, 155, 13501, 20 }, { 155, 156, 13628, 1 },
        { 156, 185, 13536, 36, 11101, "Dalria (A) / Kulwia (H)" },
        { 185, 200, 13661, 15 }, { 200, 201, 13702, 1 }, { 201, 220, 13661, 26 }, { 220, 225, 13746, 5 },
        { 225, 230, 13815, 5 }, { 230, 235, 13836, 5 }, { 235, 250, 13858, 16 },
        { 250, 265, 25127, 15, 20754, "Lokhtos Darkbargainer" },
        { 265, 294, 20017, 30, 16217, "Mythrin'dir (A) / Daniel Bartlett (H)" },
        { 294, 295, 20051, 1, 16243, "Lorelae Wintersong" },
        { 295, 300, 20015, 5, 16224, "Lorelae Wintersong" },
    },
    [185] = {   -- Kochkunst
        { 1, 50, 7751, 49 },
        { 50, 100, 7753, 51, 6328, "Tharynn Bouden (A) / Naal Mistrunner (H)" },
        { 100, 175, 7755, 120, 6330, "Kilxx" },
        { 175, 225, 20916, 51, 17062, "Kelsey Yance" },
        { 225, 275, 18238, 51, 13939, "Gikkix" },
        { 275, 300, 18246, 25, 13948, "Vivianna (A) / Sheendra Tallgrass (H)" },
    },
    [129] = {   -- Erste Hilfe
        { 1, 40, 3275, 41 }, { 40, 80, 3276, 55 }, { 80, 115, 3277, 48 }, { 115, 150, 3278, 48 },
        { 150, 180, 7928, 41 },
        { 180, 210, 7929, 41, 16112, "Deneb Walker (A) / Balai Lok'Wein (H)" },
        { 210, 240, 10840, 41, 16113, "Deneb Walker (A) / Balai Lok'Wein (H)" },
        { 240, 260, 10841, 24 }, { 260, 290, 18629, 40 }, { 290, 300, 18630, 11 },
    },
}

-- Besondere Schritte ohne Rezept (Verzauberkunst 2–20)
G.EXTRA = {
    [333] = { { 2, 20, de = "Grüne Gegenstände entzaubern", en = "Disenchant green items" } },
}

-- Sammelberufe: { von, bis, de = Text, en = Text }
G.GATHER_STEPS = {
    [186] = {
        { 1, 65, de = "Kupfer: Wald von Elwynn, Dun Morogh, Durotar, Tirisfal, Dunkelküste", en = "Copper: Elwynn Forest, Dun Morogh, Durotar, Tirisfal Glades, Darkshore" },
        { 65, 125, de = "Zinn und Silber: Rotkammgebirge, Brachland, Eschental, Steinkrallengebirge", en = "Tin and silver: Redridge Mountains, The Barrens, Ashenvale, Stonetalon Mountains" },
        { 125, 175, de = "Eisen und Gold: Arathihochland, Desolace, Schlingendorntal, Tausend Nadeln", en = "Iron and gold: Arathi Highlands, Desolace, Stranglethorn Vale, Thousand Needles" },
        { 175, 245, de = "Mithril und Echtsilber: Hinterland, Tanaris, Ödland, Sengende Schlucht", en = "Mithril and truesilver: The Hinterlands, Tanaris, Badlands, Searing Gorge" },
        { 245, 300, de = "Thorium: Krater von Un'Goro, Winterquell, Brennende Steppe, Östliche Pestländer", en = "Thorium: Un'Goro Crater, Winterspring, Burning Steppes, Eastern Plaguelands" },
    },
    [182] = {
        { 1, 70, de = "Friedensblume, Silberblatt, Erdwurzel: Startgebiete", en = "Peacebloom, silverleaf, earthroot: starting zones" },
        { 70, 115, de = "Maguskönigskraut, Wilddornrose, Beulengras: Westfall, Brachland, Dunkelküste", en = "Mageroyal, briarthorn, bruiseweed: Westfall, The Barrens, Darkshore" },
        { 115, 170, de = "Wildstahlblume, Königsblut, Lebenswurz: Arathihochland, Steinkrallengebirge, Sumpfland", en = "Wild steelbloom, kingsblood, liferoot: Arathi Highlands, Stonetalon Mountains, Wetlands" },
        { 170, 205, de = "Blassblatt, Golddorn, Khadgars Schnurrbart: Schlingendorntal, Sümpfe des Elends", en = "Fadeleaf, goldthorn, Khadgar's whisker: Stranglethorn Vale, Swamp of Sorrows" },
        { 205, 230, de = "Feuerblüte, Lila Lotus, Sonnengras: Tanaris, Sengende Schlucht, Feralas", en = "Firebloom, purple lotus, sungrass: Tanaris, Searing Gorge, Feralas" },
        { 230, 270, de = "Sonnengras, Gromsblut, Goldener Sansam: Feralas, Teufelswald, Azshara", en = "Sungrass, gromsblood, golden sansam: Feralas, Felwood, Azshara" },
        { 270, 300, de = "Traumblatt, Bergsilbersalbei, Pestblüte: Un'Goro, Winterquell, Östliche Pestländer", en = "Dreamfoil, mountain silversage, plaguebloom: Un'Goro, Winterspring, Eastern Plaguelands" },
    },
    [393] = {
        { 1, 75, de = "Tiere der Stufe 1–15: Startgebiete, Westfall, Brachland", en = "Beasts of level 1–15: starting zones, Westfall, The Barrens" },
        { 75, 150, de = "Tiere der Stufe 15–30: Rotkammgebirge, Sumpfland, Eschental, Tausend Nadeln", en = "Beasts of level 15–30: Redridge, Wetlands, Ashenvale, Thousand Needles" },
        { 150, 225, de = "Tiere der Stufe 30–45: Arathihochland, Schlingendorntal, Feralas, Tanaris", en = "Beasts of level 30–45: Arathi Highlands, Stranglethorn Vale, Feralas, Tanaris" },
        { 225, 300, de = "Tiere der Stufe 45–60: Un'Goro, Winterquell, Silithus, Brennende Steppe", en = "Beasts of level 45–60: Un'Goro, Winterspring, Silithus, Burning Steppes" },
    },
    [356] = {
        { 1, 75, de = "Startgebiete: jedes Wasser", en = "Starting zones: any water" },
        { 75, 150, de = "Westfall, Brachland, Rotkammgebirge, Dunkelküste", en = "Westfall, The Barrens, Redridge Mountains, Darkshore" },
        { 150, 225, de = "Schlingendorntal, Desolace, Düstermarschen, Arathihochland", en = "Stranglethorn Vale, Desolace, Dustwallow Marsh, Arathi Highlands" },
        { 225, 300, de = "Tanaris, Feralas, Azshara, Hinterland (Fischen in Schwärmen geht schneller)", en = "Tanaris, Feralas, Azshara, The Hinterlands (fishing pools is faster)" },
    },
}

-- Zutaten je Herstellung für die Guide-Rezepte (aus den Wowhead-Forever-Guides), damit die
-- Anleitung und die Einkaufsliste auch ohne geöffnetes Berufsfenster funktionieren.
-- Was das Spiel live liefert (Berufsfenster), hat Vorrang.
G.REAGENTS = {
    [7751] = { { 6291, 1 } },
    [7753] = { { 6289, 1 } },
    [7755] = { { 6308, 1 } },
    [20916] = { { 8365, 1 } },
    [18238] = { { 4603, 1 } },
    [18246] = { { 13893, 1 }, { 2692, 1 }, { 3713, 1 } },
    [3275] = { { 2589, 1 } },
    [3276] = { { 2589, 2 } },
    [3277] = { { 2592, 1 } },
    [3278] = { { 2592, 2 } },
    [7928] = { { 4306, 1 } },
    [7929] = { { 4306, 2 } },
    [10840] = { { 4338, 1 } },
    [10841] = { { 4338, 2 } },
    [18629] = { { 14047, 1 } },
    [18630] = { { 14047, 2 } },
    [2660] = { { 2835, 1 } },
    [3320] = { { 2835, 2 } },
    [2661] = { { 2840, 6 } },
    [19666] = { { 2842, 1 }, { 3470, 1 } },
    [2668] = { { 2841, 6 } },
    [2666] = { { 2840, 10 } },
    [2674] = { { 2838, 1 } },
    [8768] = { { 3575, 1 } },
    [9985] = { { 2841, 8 }, { 3466, 1 }, { 2319, 1 } },
    [2672] = { { 2841, 5 }, { 3478, 2 } },
    [3501] = { { 3575, 6 }, { 2605, 1 } },
    [3506] = { { 3575, 8 }, { 3486, 1 }, { 2605, 1 } },
    [9928] = { { 3860, 6 }, { 4338, 4 } },
    [7223] = { { 3859, 5 }, { 3486, 2 } },
    [9931] = { { 3860, 12 } },
    [9959] = { { 3860, 16 } },
    [16640] = { { 12365, 1 } },
    [9961] = { { 3860, 10 }, { 4338, 6 } },
    [9968] = { { 3860, 14 }, { 4304, 4 } },
    [10001] = { { 3860, 16 }, { 7971, 1 }, { 1210, 4 }, { 7966, 1 }, { 4304, 2 } },
    [19669] = { { 12360, 1 }, { 12644, 1 } },
    [10013] = { { 3860, 12 }, { 6037, 6 }, { 7910, 2 }, { 7966, 1 }, { 4304, 2 } },
    [1252365] = { { 12359, 30 }, { 7082, 4 }, { 249726, 10 }, { 8170, 4 } },
    [16969] = { { 12359, 20 }, { 12799, 2 }, { 12644, 2 }, { 8170, 4 } },
    [1245250] = { { 765, 1 }, { 3371, 1 } },
    [7183] = { { 765, 1 }, { 2447, 1 }, { 3371, 1 } },
    [2331] = { { 785, 1 }, { 2447, 1 }, { 3371, 1 } },
    [2334] = { { 2449, 2 }, { 2447, 1 }, { 3371, 1 } },
    [3171] = { { 785, 1 }, { 2450, 2 }, { 3371, 1 } },
    [3173] = { { 785, 1 }, { 3820, 1 }, { 3371, 1 } },
    [3452] = { { 3820, 1 }, { 3356, 1 }, { 3372, 1 } },
    [11449] = { { 3820, 1 }, { 3821, 1 }, { 3372, 1 } },
    [11448] = { { 3358, 1 }, { 3821, 1 }, { 3372, 1 } },
    [11459] = { { 3575, 4 }, { 9262, 1 }, { 8831, 4 }, { 4625, 4 } },
    [11460] = { { 8836, 1 }, { 8925, 1 } },
    [17553] = { { 8838, 2 }, { 8839, 2 }, { 8925, 1 } },
    [1231583] = { { 8925, 1 }, { 13466, 1 }, { 730, 1 } },
    [2963] = { { 2589, 2 } },
    [2385] = { { 2996, 1 }, { 2320, 1 } },
    [8776] = { { 2996, 1 }, { 2320, 1 } },
    [2397] = { { 2996, 2 }, { 2320, 3 } },
    [2964] = { { 2592, 3 } },
    [2402] = { { 2997, 1 }, { 2321, 1 } },
    [3839] = { { 4306, 4 } },
    [3848] = { { 2997, 3 }, { 2321, 2 } },
    [8760] = { { 4305, 2 }, { 6260, 2 }, { 2321, 1 } },
    [6690] = { { 4305, 2 }, { 2321, 2 }, { 3182, 2 } },
    [3871] = { { 4305, 3 }, { 2324, 2 }, { 2321, 1 } },
    [3865] = { { 4338, 5 } },
    [8764] = { { 4305, 3 }, { 7067, 1 }, { 2321, 2 } },
    [8770] = { { 4339, 2 }, { 7067, 2 }, { 7070, 2 }, { 7068, 2 }, { 7069, 2 }, { 4291, 2 } },
    [12048] = { { 4339, 2 }, { 4291, 3 } },
    [12061] = { { 4339, 1 }, { 6261, 1 }, { 8343, 1 } },
    [12053] = { { 4339, 2 }, { 8343, 2 } },
    [18401] = { { 14047, 5 } },
    [18402] = { { 14048, 3 }, { 14341, 1 } },
    [18409] = { { 14048, 4 }, { 14227, 1 }, { 14341, 1 } },
    [18423] = { { 14048, 4 }, { 14227, 2 }, { 8170, 4 }, { 14341, 1 } },
    [1257487] = { { 14048, 5 }, { 14227, 1 }, { 14341, 1 } },
    [23662] = { { 14048, 8 }, { 7076, 3 }, { 12803, 3 }, { 14227, 2 } },
    [1297120] = { { 14048, 4 }, { 14343, 1 }, { 7082, 3 }, { 14341, 6 } },
    [1297121] = { { 14048, 6 }, { 14343, 1 }, { 7082, 3 }, { 14341, 6 } },
    [1297122] = { { 14048, 5 }, { 14343, 1 }, { 7082, 3 }, { 14341, 6 } },
    [2881] = { { 2934, 3 } },
    [2152] = { { 2318, 1 } },
    [3816] = { { 783, 1 }, { 4289, 1 } },
    [3756] = { { 2318, 3 }, { 2320, 2 } },
    [3763] = { { 2318, 6 }, { 2320, 2 } },
    [7135] = { { 2319, 12 }, { 4340, 1 }, { 2321, 1 } },
    [2167] = { { 2319, 4 }, { 2321, 2 }, { 4340, 1 } },
    [3766] = { { 4246, 1 }, { 4233, 1 }, { 2321, 2 }, { 4340, 1 } },
    [3818] = { { 4235, 1 }, { 4289, 3 } },
    [3770] = { { 2319, 4 }, { 4233, 2 }, { 3389, 2 }, { 3182, 2 }, { 2321, 2 } },
    [7151] = { { 4234, 8 }, { 4236, 1 }, { 2321, 2 } },
    [3778] = { { 4236, 4 }, { 5500, 2 }, { 1529, 2 }, { 3864, 1 }, { 2321, 1 } },
    [7156] = { { 4234, 4 }, { 4236, 1 }, { 4291, 1 } },
    [10487] = { { 4304, 5 }, { 4291, 1 } },
    [10548] = { { 4304, 14 }, { 4291, 4 } },
    [19058] = { { 8170, 5 } },
    [19049] = { { 8170, 8 }, { 2325, 1 }, { 14341, 1 } },
    [19048] = { { 8170, 4 }, { 15408, 4 }, { 14341, 1 } },
    [19088] = { { 8170, 8 }, { 15408, 12 }, { 15407, 1 }, { 14341, 1 } },
    [3918] = { { 2835, 1 } },
    [3922] = { { 2840, 1 } },
    [7430] = { { 2840, 6 } },
    [3923] = { { 2840, 1 }, { 4359, 1 }, { 4357, 2 }, { 2589, 1 } },
    [3929] = { { 2836, 1 } },
    [3931] = { { 4364, 3 }, { 2589, 1 } },
    [3973] = { { 2842, 1 } },
    [3938] = { { 2841, 2 }, { 2880, 1 } },
    [3978] = { { 4371, 1 }, { 1206, 1 } },
    [3942] = { { 2841, 2 }, { 2592, 1 } },
    [3953] = { { 2841, 2 }, { 2319, 1 }, { 2592, 1 } },
    [3955] = { { 4382, 1 }, { 4375, 1 }, { 4377, 2 }, { 2592, 2 } },
    [12585] = { { 7912, 2 } },
    [12590] = { { 3859, 4 } },
    [12589] = { { 3860, 3 } },
    [12591] = { { 3860, 1 }, { 4338, 1 }, { 10505, 1 } },
    [12599] = { { 3860, 3 } },
    [12619] = { { 10561, 2 }, { 10560, 1 }, { 10505, 2 } },
    [19788] = { { 12365, 2 } },
    [19791] = { { 12359, 3 }, { 14047, 1 } },
    [19795] = { { 12359, 6 } },
    [7421] = { { 6217, 1 }, { 247786, 1 } },
    [14293] = { { 4470, 1 }, { 10938, 1 } },
    [7426] = { { 10938, 1 } },
    [7457] = { { 10940, 2 } },
    [7795] = { { 6338, 1 }, { 10940, 3 }, { 10938, 4 }, { 1210, 1 } },
    [14807] = { { 4470, 1 }, { 10938, 2 } },
    [13419] = { { 10998, 1 } },
    [13501] = { { 11083, 1 } },
    [13628] = { { 11128, 1 }, { 5500, 1 }, { 11082, 1 }, { 11083, 1 } },
    [13536] = { { 11083, 1 } },
    [13661] = { { 11137, 1 } },
    [13702] = { { 11144, 1 }, { 7971, 1 }, { 11135, 1 }, { 11137, 1 } },
    [13746] = { { 11137, 1 } },
    [13815] = { { 11137, 1 } },
    [13836] = { { 11137, 2 } },
    [13858] = { { 11137, 3 } },
    [25127] = { { 11176, 1 }, { 8831, 1 }, { 8925, 1 } },
    [20017] = { { 11176, 6 } },
    [20051] = { { 16206, 1 }, { 13926, 1 }, { 16204, 10 }, { 16203, 4 }, { 14343, 4 }, { 14344, 2 } },
    [20015] = { { 16204, 8 } },
}

local function Lang(t) return t and (ns.IS_GERMAN and t.de or t.en) or "" end
G.Lang = Lang

function G.Name(line) return Lang(G.NAMES[line]) end

-- Rang zur Höchststufe und der nächste, der zu lernen ist
function G.Rank(max)
    max = tonumber(max) or 0
    for i, r in ipairs(G.RANKS) do
        if max <= r.max then return r, G.RANKS[i + 1] end
    end
    return G.RANKS[#G.RANKS], nil
end

-- Alle Schritte eines Berufs, sortiert (Rezepte, Sonderschritte, Sammeln)
-- Ergebnis: { { from, to, spell, count, pattern, vendor, text, gather } }
function G.Steps(line)
    local out = {}
    for _, s in ipairs(G.STEPS[line] or {}) do
        out[#out + 1] = { from = s[1], to = s[2], spell = s[3], count = s[4], pattern = s[5], vendor = s[6] }
    end
    for _, s in ipairs(G.EXTRA[line] or {}) do
        out[#out + 1] = { from = s[1], to = s[2], text = Lang(s) }
    end
    for _, s in ipairs(G.GATHER_STEPS[line] or {}) do
        out[#out + 1] = { from = s[1], to = s[2], text = Lang(s), gather = true }
    end
    table.sort(out, function(a, b) return a.from < b.from end)
    return out
end

-- Index des Schritts für diese Stufe (der erste, dessen Ende über der Stufe liegt)
function G.CurrentIndex(steps, skill)
    skill = tonumber(skill) or 0
    for i, s in ipairs(steps) do
        if skill < s.to then return i end
    end
    return nil   -- fertig (300)
end

-- Wie viele Herstellungen noch (grob): Anteil des Schritts, der noch fehlt
function G.Remaining(step, skill)
    if not step.count then return nil end
    skill = tonumber(skill) or 0
    if skill <= step.from then return step.count end
    if skill >= step.to then return 0 end
    return math.max(1, math.ceil(step.count * (step.to - skill) / (step.to - step.from)))
end
