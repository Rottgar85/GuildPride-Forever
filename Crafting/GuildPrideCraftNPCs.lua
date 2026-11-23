-- GuildPride Handwerk: Lehrer und Händler auf der Karte
-- Wählst du im Handwerk-Fenster einen Beruf, zeigt die Weltkarte dessen Lehrer (deine Fraktion
-- und neutrale) – und Bauplan-Händler, sobald GuildPride ihren Standort kennt. „Auf Karte“
-- öffnet die Karte beim passenden Lehrer und setzt einen Wegpunkt.
-- Lehrer-Standorte: Wowhead (Classic), eigene Zusammenstellung { npcID, Fraktion (A/H/N), Karte, x, y, Name, Titel }.
-- Händler: gelernt im Spiel – wer einen Händler anspricht, der einen Bauplan aus dem Guide
-- verkauft, merkt sich dessen Standort (GuildPrideDB.craftNPCSeen[Name] = { map, x, y, line }).
-- Schalter: craftNPCMap
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local N = {}
ns.CraftNPC = N

N.TRAINERS = {
    [129] = {
        { 3181, "A", 1437, 10.8, 61.2, "Fremal Doohickey", "First Aid Trainer" },
        { 2327, "A", 1453, 42.4, 26.8, "Shaina Fuller", "First Aid Trainer" },
        { 3373, "H", 1454, 34, 84.4, "Arnok", "First Aid Trainer" },
        { 2798, "H", 1456, 29.4, 21.4, "Pand Stonebinder", "First Aid Trainer" },
        { 2329, "A", 1429, 43.4, 65.6, "Michelle Belle", "Physician" },
        { 4211, "A", 1457, 51.4, 12.6, "Dannelor", "First Aid Trainer" },
        { 5150, "A", 1455, 54.8, 58.4, "Nissa Firestone", "First Aid Trainer" },
        { 4591, "H", 1458, 73.4, 55.4, "Mary Edras", "First Aid Trainer" },
        { 2326, "A", 1426, 47.2, 52.4, "Thamner Pol", "Physician" },
        { 5759, "H", 1420, 61.8, 52.8, "Nurse Neela", "First Aid Trainer" },
        { 5943, "H", 1411, 54, 42, "Rawrk", "First Aid Trainer" },
        { 6094, "A", 1438, 55.2, 56.8, "Byancie", "First Aid Trainer" },
        { 5939, "H", 1412, 46.8, 60.8, "Vira Younghoof", "First Aid Trainer" },
    },
    [164] = {
        { 1383, "H", 1454, 79.2, 22.4, "Snarl", "Expert Blacksmith" },
        { 514, "A", 1429, 41.6, 65.6, "Smith Argus", "Journeyman Blacksmith" },
        { 2998, "H", 1456, 38.8, 54, "Karn Stonehoof", "Expert Blacksmith" },
        { 957, "A", 1453, 57.2, 16.4, "Dane Lindgren", "Journeyman Blacksmith" },
        { 3174, "H", 1411, 52, 40.6, "Dwukk", "Journeyman Blacksmith" },
        { 1241, "A", 1426, 45.2, 52, "Tognus Flintfire", "Journeyman Blacksmith" },
        { 2836, "N", 1434, 29, 75.4, "Brikk Keencraft", "Master Blacksmith" },
        { 3355, "H", 1454, 82.2, 23, "Saru Steelfury", "Artisan Blacksmith" },
        { 3557, "H", 1421, 43.2, 41, "Guillaume Sorouy", "Journeyman Blacksmith" },
        { 3136, "A", 1431, 73.8, 48.6, "Clarise Gnarltree", "Expert Blacksmith" },
        { 3478, "H", 1413, 51.2, 28.8, "Traugh", "Expert Blacksmith" },
        { 4605, "H", 1458, 60, 28.4, "Basil Frye", "Journeyman Blacksmith" },
        { 4258, "A", 1455, 51.4, 42.2, "Bengus Deepforge", "Artisan Blacksmith" },
        { 4596, "H", 1458, 61.2, 29.2, "James Van Brunt", "Expert Blacksmith" },
        { 5511, "A", 1453, 56.4, 15.4, "Therum Deepforge", "Expert Blacksmith" },
        { 10276, "A", 1455, 51.2, 43.2, "Rotgath Stonebeard", "Expert Blacksmith" },
        { 6299, "A", 1439, 38.2, 41, "Delfrum Flintbeard", "Journeyman Blacksmith" },
        { 10266, "H", 1454, 80.4, 23.4, "Ug'thok", "Journeyman Blacksmith" },
        { 5164, "A", 1455, 49.4, 43, "Grumnus Steelshaper", "Armor Crafter" },
        { 10278, "H", 1456, 39, 57.8, "Thrag Stonehoof", "Journeyman Blacksmith" },
        { 7230, "H", 1454, 80.2, 23.2, "Shayis Steelfury", "Armor Crafter" },
        { 7231, "H", 1454, 81.8, 18.6, "Kelgruk Bloodaxe", "Weapon Crafter" },
        { 11177, "H", 1454, 79.8, 23.4, "Okothos Ironrager", "Armorsmith" },
        { 7232, "A", 1453, 51.4, 12.4, "Borgus Steelhand", "Weapon Crafter" },
        { 11146, "A", 1455, 49.4, 44.8, "Ironus Coldsteel", "Special Weapon Crafter" },
        { 10277, "A", 1455, 51.2, 42.8, "Groum Stonebeard", "Journeyman Blacksmith" },
        { 11178, "H", 1454, 79.4, 23.4, "Borgosh Corebender", "Weaponsmith" },
    },
    [165] = {
        { 223, "H", 1458, 70.4, 58.4, "Dan Golthas", "Journeyman Leatherworker" },
        { 1632, "A", 1429, 46.4, 62.2, "Adele Fielder", "Journeyman Leatherworker" },
        { 1385, "H", 1434, 31.6, 28.8, "Brawn", "Expert Leatherworker" },
        { 3008, "H", 1456, 42.2, 43.2, "Mak", "Journeyman Leatherworker" },
        { 3069, "H", 1412, 45.4, 57.8, "Chaw Stronghide", "Journeyman Leatherworker" },
        { 3007, "H", 1456, 41.6, 42.4, "Una", "Artisan Leatherworker" },
        { 3365, "H", 1454, 62.8, 44.4, "Karolek", "Expert Leatherworker" },
        { 1466, "A", 1455, 39, 32.4, "Gretta Finespindle", "Journeyman Leatherworker" },
        { 3605, "A", 1438, 41.8, 49.4, "Nadyia Maneweaver", "Journeyman Leatherworker" },
        { 3549, "H", 1420, 65.4, 60, "Shelene Rhobart", "Journeyman Leatherworker" },
        { 3703, "H", 1413, 44.8, 59.4, "Krulmoo Fullmoon", "Expert Leatherworker" },
        { 5127, "A", 1455, 39.4, 33.8, "Fimble Finespindle", "Expert Leatherworker" },
        { 3967, "A", 1440, 35.8, 52, "Aayndia Floralwind", "Expert Leatherworker" },
        { 4212, "A", 1457, 64.4, 21.4, "Telonis", "Artisan Leatherworker" },
        { 4588, "H", 1458, 70.2, 57.4, "Arthur Moore", "Expert Leatherworker" },
        { 5564, "A", 1453, 67.2, 49.4, "Simon Tanner", "Expert Leatherworker" },
        { 5811, "H", 1454, 63, 45, "Kamari", "Journeyman Leatherworker" },
        { 11098, "H", 1444, 74.4, 43, "Hahrana Ironhide", "Master Leatherworker" },
        { 11097, "A", 1425, 13.4, 43.4, "Drakk Stonehand", "Master Leatherworking Trainer" },
        { 7866, "A", 1447, 37.4, 65.4, "Peter Galen", "Master Dragonscale Leatherworker" },
        { 11083, "A", 1457, 64.2, 21.6, "Darianna", "Journeyman Leatherworker" },
        { 8153, "H", 1443, 55.2, 56.2, "Narv Hidecrafter", "Expert Leathercrafter" },
        { 11081, "A", 1457, 64.4, 21.4, "Faldron", "Expert Leatherworker" },
        { 11084, "H", 1456, 42.4, 43, "Tarn", "Expert Leatherworker" },
        { 11096, "A", 1453, 67.4, 49.4, "Randal Worth", "Journeyman Leatherworker" },
        { 7871, "H", 1434, 36.4, 34, "Se'Jib", "Master Tribal Leatherworker" },
        { 7868, "A", 1427, 63.2, 75.4, "Sarah Tanner", "Master Elemental Leatherworker" },
        { 7870, "A", 1444, 89.4, 46.4, "Caryssia Moonhunter", "Tribal Leatherworking Trainer" },
        { 7867, "H", 1418, 62.4, 57.4, "Thorkaf Dragoneye", "Master Dragonscale Leatherworker" },
        { 7869, "H", 1417, 28.2, 45, "Brumn Winterhoof", "Master Elemental Leatherworker" },
    },
    [171] = {
        { 1215, "A", 1429, 39.8, 48.4, "Alchemist Mallory", "Journeyman Alchemist" },
        { 1386, "H", 1435, 48.2, 55.4, "Rogvar", "Master Alchemist" },
        { 2837, "N", 1434, 28, 78, "Jaxin Chong", "Expert Alchemist" },
        { 3009, "H", 1456, 46.8, 33.4, "Bena Winterhoof", "Expert Alchemist" },
        { 3184, "H", 1411, 55.4, 74, "Miao'zan", "Journeyman Alchemist" },
        { 2391, "H", 1424, 61.4, 19.2, "Serge Hinott", "Expert Alchemist" },
        { 1246, "A", 1455, 66.4, 55.2, "Vosur Brakthel", "Journeyman Alchemist" },
        { 1470, "A", 1432, 37, 49.2, "Ghak Healtouch", "Journeyman Alchemist" },
        { 3603, "A", 1438, 57.6, 60.6, "Cyndra Kindwhisper", "Journeyman Alchemist" },
        { 3347, "H", 1454, 56.4, 33.2, "Yelmak", "Expert Alchemist" },
        { 4611, "H", 1458, 47.4, 73, "Doctor Herbert Halsey", "Artisan Alchemist" },
        { 3964, "A", 1440, 50.8, 67, "Kylanna", "Expert Alchemist" },
        { 7948, "A", 1444, 32.4, 43.8, "Kylanna Windwhisper", "Master Alchemist" },
        { 4609, "H", 1458, 51.2, 75, "Doctor Marsh", "Expert Alchemist" },
        { 5499, "A", 1453, 46.4, 79.4, "Lilyssia Nightbreeze", "Expert Alchemist" },
        { 5177, "A", 1455, 66.4, 55.2, "Tally Berryfizz", "Expert Alchemist" },
        { 4900, "A", 1445, 64, 47.6, "Alchemist Narett", "Expert Alchemist" },
        { 4160, "A", 1457, 55, 23.4, "Ainethil", "Artisan Alchemist" },
        { 11041, "A", 1457, 55.2, 22.4, "Milla Fairancora", "Journeyman Alchemist" },
        { 5500, "A", 1453, 46.4, 79, "Tel'Athir", "Journeyman Alchemist" },
        { 11044, "H", 1458, 45.8, 73.2, "Doctor Martin Felben", "Journeyman Alchemist Trainer" },
        { 2132, "H", 1420, 59.4, 52.2, "Carolai Anise", "Journeyman Alchemist" },
        { 11042, "A", 1457, 55.6, 23.4, "Sylvanna Forestmoon", "Expert Alchemist" },
        { 11047, "H", 1456, 46.8, 34.2, "Kray", "Journeyman Alchemist" },
        { 11046, "H", 1454, 55.8, 33.2, "Whuut", "Journeyman Alchemist" },
    },
    [182] = {
        { 812, "A", 1433, 21.4, 45.6, "Alma Jainrose", "Herbalism Trainer" },
        { 908, "N", 1434, 27.6, 77.8, "Flora Silverwind", "Superior Herbalist" },
        { 1218, "A", 1429, 39.8, 48.4, "Herbalist Pomeroy", "Herbalism Trainer" },
        { 1473, "A", 1432, 36.4, 48.4, "Kali Healtouch", "Herbalist" },
        { 3013, "H", 1456, 49.8, 39.8, "Komin Winterhoof", "Herbalism Trainer" },
        { 3404, "H", 1454, 55.4, 39.4, "Jandi", "Herbalism Trainer" },
        { 2856, "H", 1434, 32.2, 27.4, "Angrun", "Superior Herbalist" },
        { 2114, "H", 1420, 59.8, 52, "Faruza", "Apprentice Herbalist" },
        { 2390, "H", 1424, 61.6, 19.4, "Aranae Venomblood", "Herbalist" },
        { 1458, "A", 1437, 8, 55.8, "Telurinon Moonshadow", "Herbalism Trainer" },
        { 3185, "H", 1411, 55.4, 75, "Mishiki", "Herbalist" },
        { 3965, "A", 1440, 50.4, 67, "Cylania Rootstalker", "Herbalist" },
        { 4898, "A", 1445, 64, 47.6, "Brant Jasperbloom", "Herbalist" },
        { 4614, "H", 1458, 54.2, 49.4, "Martha Alliestar", "Herbalism Trainer" },
        { 4204, "A", 1457, 48, 68.4, "Firodren Mooncaller", "Herbalism Trainer" },
        { 5502, "A", 1453, 15, 49.4, "Shylamiir", "Herbalism Trainer" },
        { 12025, "N", 1450, 45.4, 47, "Malvor", "Herbalist" },
        { 5137, "A", 1455, 55.4, 58.8, "Reyna Stonebranch", "Herbalism Trainer" },
        { 8146, "H", 1444, 76, 43.4, "Ruw", "Herbalism Trainer" },
        { 5566, "A", 1453, 44.4, 77.8, "Tannysa", "Herbalism Trainer" },
        { 3604, "A", 1438, 57.4, 60.6, "Malorne Bladeleaf", "Herbalist" },
    },
    [185] = {
        { 1382, "H", 1434, 31.4, 28, "Mudduk", "Superior Cook" },
        { 4210, "A", 1457, 49, 21.2, "Alegorn", "Cooking Trainer" },
        { 3087, "A", 1433, 22.8, 43.4, "Crystal Boughman", "Cooking Trainer" },
        { 1355, "A", 1426, 68.4, 54.4, "Cook Ghilm", "Cooking Trainer" },
        { 3026, "H", 1456, 51, 52.8, "Aska Mistrunner", "Cooking Trainer" },
        { 1699, "A", 1426, 47.6, 52.4, "Gremlock Pilsnor", "Cooking Trainer" },
        { 3067, "H", 1412, 45.4, 58, "Pyall Silentstride", "Cook" },
        { 1430, "A", 1429, 44.2, 66, "Tomas", "Cook" },
        { 3399, "H", 1454, 57.4, 53.4, "Zamja", "Cooking Trainer" },
        { 4552, "H", 1458, 62.2, 44.4, "Eunice Burch", "Cooking Trainer" },
        { 5482, "A", 1453, 75.4, 37.2, "Stephen Ryback", "Cooking Trainer" },
        { 2818, "H", 1417, 74, 33.8, "Slagg", "Superior Butcher" },
        { 5159, "A", 1455, 60, 36.8, "Daryl Riknussun", "Cooking Trainer" },
        { 6286, "A", 1438, 57, 61.2, "Zarrin", "Cook" },
        { 8306, "H", 1413, 55.2, 31.8, "Duhng", "Cook" },
    },
    [186] = {
        { 1681, "A", 1432, 37, 47.8, "Brock Stoneseeker", "Mining Trainer" },
        { 1701, "A", 1426, 69.2, 55.4, "Dank Drizzlecut", "Mining Trainer" },
        { 3001, "H", 1456, 34.4, 57.4, "Brek Stonehoof", "Mining Trainer" },
        { 3175, "H", 1411, 51.8, 40.8, "Krunn", "Miner" },
        { 3137, "A", 1431, 74, 49.4, "Matt Johnson", "Mining Trainer" },
        { 3357, "H", 1454, 73, 26.4, "Makaru", "Mining Trainer" },
        { 3555, "H", 1421, 43.4, 40.4, "Johan Focht", "Miner" },
        { 4254, "A", 1455, 50.2, 26, "Geofram Bouldertoe", "Mining Trainer" },
        { 4598, "H", 1458, 55.8, 36, "Brom Killian", "Mining Trainer" },
        { 5513, "A", 1453, 51, 17.2, "Gelman Stonehand", "Mining Trainer" },
        { 5392, "A", 1426, 50, 50.4, "Yarr Hammerstone", "Mining Trainer" },
        { 6297, "A", 1439, 38.2, 41, "Kurdram Stonehammer", "Mining Trainer" },
        { 8128, "N", 1446, 51, 28, "Pikkle", "Miner" },
    },
    [197] = {
        { 1703, "A", 1455, 43.4, 28.2, "Uthrar Threx", "Journeyman Tailor" },
        { 1346, "A", 1453, 43.2, 73.4, "Georgio Bolero", "Artisan Tailor" },
        { 2399, "H", 1424, 63.4, 20.8, "Daryl Stack", "Master Tailor" },
        { 1300, "A", 1453, 43.4, 73.8, "Lawrence Schneider", "Journeyman Tailor" },
        { 1103, "A", 1429, 79.2, 69, "Eldrin", "Journeyman Tailor" },
        { 3004, "H", 1456, 43.8, 44.4, "Tepa", "Expert Tailor" },
        { 2627, "N", 1434, 28.6, 76.8, "Grarnik Goodstitch", "Expert Tailor" },
        { 3523, "H", 1420, 52.4, 55.6, "Bowen Brisboise", "Journeyman Tailor" },
        { 2855, "H", 1454, 62.8, 49.4, "Snang", "Journeyman Tailor" },
        { 3484, "H", 1413, 52.2, 31.6, "Kil'hala", "Journeyman Tailor" },
        { 3363, "H", 1454, 63.4, 50, "Magar", "Expert Tailor" },
        { 5567, "A", 1453, 42, 76.2, "Sellandus", "Expert Tailor" },
        { 4576, "H", 1458, 70.4, 30.4, "Josef Gregorian", "Artisan Tailor" },
        { 3704, "H", 1413, 44.8, 59.4, "Mahani", "Expert Tailor" },
        { 4159, "A", 1457, 62.4, 22.4, "Me'lynn", "Expert Tailor" },
        { 5153, "A", 1455, 43.2, 28.4, "Jormund Stonebrow", "Expert Tailor" },
        { 11052, "A", 1445, 66.2, 51.6, "Timothy Worthington", "Master Tailor" },
        { 4193, "A", 1439, 38.2, 40.4, "Grondal Moonbreeze", "Journeyman Tailor" },
        { 11051, "H", 1456, 43.4, 43.6, "Vhan", "Journeyman Tailor" },
        { 4578, "H", 1458, 85.8, 22.6, "Josephine Lister", "Master Shadoweave Tailor" },
        { 11049, "H", 1458, 70.2, 30.2, "Rhiannon Davis", "Expert Tailor" },
        { 11050, "A", 1457, 63.4, 21.4, "Trianna", "Journeyman Tailor" },
        { 9584, "A", 1453, 26.4, 77.4, "Jalane Ayrole", "Master Shadoweave Tailor" },
        { 11048, "H", 1458, 70.2, 29.6, "Victor Ward", "Journeyman Tailor" },
    },
    [202] = {
        { 3412, "H", 1454, 75.8, 25.2, "Nogg", "Expert Engineer" },
        { 1676, "A", 1431, 77.4, 48.4, "Finbus Geargrind", "Expert Engineer" },
        { 2857, "H", 1454, 75.4, 24.6, "Thund", "Journeyman Engineer" },
        { 5174, "A", 1455, 68.2, 43.4, "Springspindle Fizzlegear", "Artisan Engineer" },
        { 3494, "N", 1413, 62.6, 36.2, "Tinkerwiz", "Journeyman Engineer" },
        { 1702, "A", 1426, 50.2, 50.4, "Bronk Guzzlegear", "Journeyman Engineer" },
        { 3290, "A", 1432, 45.8, 13.4, "Deek Fizzlebizz", "Journeyman Engineer" },
        { 11028, "A", 1455, 67.8, 43.4, "Jemma Quikswitch", "Journeyman Engineer" },
        { 8736, "N", 1446, 52.2, 27.6, "Buzzek Bracketswing", "Master Engineer" },
        { 4586, "H", 1458, 75.2, 72.4, "Graham Van Talen", "Journeyman Engineer" },
        { 11026, "A", 1453, 54.6, 8, "Sprite Jumpsprocket", "Journeyman Engineer" },
        { 10993, "H", 1412, 61.8, 31.4, "Twizwick Sprocketgrind", "Journeyman Engineer" },
        { 11017, "H", 1454, 76, 25, "Roxxik", "Artisan Engineer" },
        { 5518, "A", 1453, 54.8, 7.8, "Lilliam Sparkspindle", "Expert Engineer" },
        { 11029, "A", 1455, 67.4, 43.2, "Trixie Quikswitch", "Expert Engineer" },
        { 11025, "H", 1411, 52.2, 40.8, "Mukdrak", "Journeyman Engineer" },
        { 11031, "H", 1458, 76, 73.4, "Franklin Lloyd", "Expert Engineer" },
        { 11037, "A", 1439, 38.2, 41, "Jenna Lemkenilli", "Journeyman Engineer" },
        { 8738, "N", 1413, 62.6, 36.2, "Vazario Linkgrease", "Master Goblin Engineer" },
        { 7944, "A", 1455, 69.4, 50.4, "Tinkmaster Overspark", "Master Gnome Engineer" },
        { 8126, "N", 1446, 52.4, 27.2, "Nixx Sprocketspring", "Master Goblin Engineer" },
        { 7406, "N", 1434, 28.2, 76.2, "Oglethorpe Obnoticus", "Master Gnome Engineer" },
    },
    [333] = {
        { 3011, "H", 1456, 45, 38, "Teg Dawnstrider", "Expert Enchanter" },
        { 1317, "A", 1453, 43, 64.4, "Lucan Cordell", "Expert Enchanter" },
        { 3345, "H", 1454, 53.8, 38.4, "Godan", "Expert Enchanter" },
        { 5157, "A", 1455, 60, 45.4, "Gimble Thistlefuzz", "Expert Enchanter" },
        { 7949, "A", 1444, 31.4, 44.2, "Xylinnia Starshine", "Expert Enchanter" },
        { 4213, "A", 1457, 58.4, 13.2, "Taladan", "Expert Enchanter" },
        { 4616, "H", 1458, 62.2, 61.6, "Lavinia Crowe", "Expert Enchanter" },
        { 5695, "H", 1420, 61.6, 51.6, "Vance Undergloom", "Journeyman Enchanter" },
        { 3606, "A", 1438, 36.8, 34.2, "Alanna Raveneye", "Journeyman Enchanter" },
        { 11065, "A", 1455, 60.4, 44.4, "Thonys Pillarstone", "Journeyman Enchanter" },
        { 11066, "H", 1454, 53.4, 38.2, "Jhag", "Journeyman Enchanter" },
        { 11067, "H", 1458, 62.2, 60.4, "Malcomb Wynn", "Journeyman Enchanter" },
        { 11070, "A", 1457, 58.6, 14, "Lalina Summermoon", "Journeyman Enchanter" },
        { 11071, "H", 1456, 44.4, 38.8, "Mot Dawnstrider", "Journeyman Enchanter" },
        { 11068, "A", 1453, 43.2, 63.8, "Betty Quin", "Journeyman Enchanter" },
        { 11072, "A", 1429, 64.8, 70.4, "Kitta Firewind", "Artisan Enchanter" },
        { 11074, "H", 1442, 49.2, 57.2, "Hgarth", "Artisan Enchanter" },
    },
    [356] = {
        { 1651, "A", 1429, 47.4, 62.2, "Lee Brown", "Fisherman" },
        { 2834, "N", 1434, 27.4, 77, "Myizz Luckycatch", "Superior Fisherman" },
        { 1680, "A", 1433, 26.4, 50.4, "Matthew Hooper", "Fishing Trainer" },
        { 2367, "A", 1424, 50.6, 61, "Donald Rabonne", "Fisherman" },
        { 1700, "A", 1426, 35.4, 40.2, "Paxton Ganter", "Fisherman" },
        { 3028, "H", 1456, 56, 46.8, "Kah Mistrunner", "Fishing Trainer" },
        { 1683, "A", 1432, 40.4, 39.4, "Warg Deepwater", "Fisherman" },
        { 3332, "H", 1454, 69.4, 29.2, "Lumak", "Fishing Trainer" },
        { 4156, "A", 1457, 47.4, 56.6, "Astaia", "Fishing Trainer" },
        { 3607, "A", 1438, 55.8, 93.4, "Androl Oakhand", "Fisherman" },
        { 3179, "A", 1437, 8, 58.4, "Harold Riggs", "Fishing Trainer" },
        { 5493, "A", 1453, 45.8, 58.2, "Arnold Leland", "Fishing Trainer" },
        { 5690, "H", 1420, 67.2, 51, "Clyde Kellen", "Fisherman" },
        { 5161, "A", 1455, 48.2, 6.6, "Grimnur Stonebrand", "Fishing Trainer" },
        { 4573, "H", 1458, 80.8, 31.2, "Armand Cromwell", "Fishing Trainer" },
        { 7946, "A", 1444, 32.2, 41.6, "Brannock", "Fisherman" },
        { 5938, "H", 1412, 44.4, 60.4, "Uthan Stillwater", "Fisherman" },
        { 5941, "H", 1411, 53.2, 81.4, "Lau'Tiki", "Fisherman" },
        { 12032, "H", 1443, 22.6, 72.4, "Lui'Mala", "Fisherman" },
        { 14740, "H", 1425, 80.2, 81.4, "Katoom the Angler", "Fishing Trainer & Supplies" },
        { 12961, "H", 1440, 10.8, 33.4, "Kil'Hiwana", "Fisherman" },
    },
    [393] = {
        { 6287, "A", 1438, 42, 50, "Radnaal Maneweaver", "Skinner" },
        { 1292, "A", 1453, 67.8, 49, "Maris Granger", "Skinning Trainer" },
        { 6288, "A", 1440, 50, 67.2, "Jayla", "Skinner" },
        { 6289, "H", 1420, 65.4, 60, "Rand Rhobart", "Skinner" },
        { 6306, "A", 1429, 46.2, 62.2, "Helene Peltskinner", "Skinner" },
        { 6292, "A", 1457, 64.2, 21.8, "Eladriel", "Skinning Trainer" },
        { 6290, "H", 1412, 45.4, 57.8, "Yonn Deepcut", "Skinner" },
        { 6291, "A", 1455, 39.4, 32.4, "Balthus Stoneflayer", "Skinning Trainer" },
        { 7088, "H", 1454, 63.2, 45.2, "Thuwd", "Skinning Trainer" },
        { 6295, "A", 1433, 88.8, 71, "Wilma Ranthal", "Skinning Trainer" },
        { 6387, "H", 1413, 45, 59, "Dranh", "Skinner" },
        { 7089, "H", 1456, 44.4, 42.4, "Mooranta", "Skinning Trainer" },
        { 7087, "H", 1458, 70.4, 59.2, "Killian Hagey", "Skinning Trainer" },
        { 8144, "H", 1444, 74.4, 43, "Kulleg Stonehorn", "Skinning Trainer" },
        { 12030, "H", 1443, 23.2, 69.8, "Malux", "Skinning Trainer" },
    },
}

local function Opt() return not (type(GuildPrideDB) == "table" and GuildPrideDB.craftNPCMap == false) end
local function Seen()
    if type(GuildPrideDB) ~= "table" then return {} end
    GuildPrideDB.craftNPCSeen = type(GuildPrideDB.craftNPCSeen) == "table" and GuildPrideDB.craftNPCSeen or {}
    return GuildPrideDB.craftNPCSeen
end
N.Seen = Seen

local function MyFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Horde" and "H" or (f == "Alliance" and "A" or nil)
end

-- Rang im Titel (für „bester Lehrer“): Master/Artisan vor Expert vor Journeyman
local function TitleRank(tag)
    tag = tostring(tag or ""):lower()
    if tag:find("master") or tag:find("artisan") or tag:find("superior") then return 3 end
    if tag:find("expert") then return 2 end
    if tag:find("journeyman") then return 1 end
    return 0
end
N.TitleRank = TitleRank

-- Händler aus den Guides für einen Beruf: { [Name] = true } (für das Lernen im Spiel)
function N.GuideVendors(line)
    local out = {}
    for _, s in ipairs(G.STEPS[line] or {}) do
        if s[6] then
            for name in s[6]:gmatch("[^/]+") do out[strtrim((name:gsub("%(%a%)", "")))] = true end
        end
    end
    return out
end

-- Alle NPCs eines Berufs für deine Fraktion: { { name, tag, map, x, y (0–1), kind = "trainer"/"vendor" } }
function N.ForLine(line, faction)
    faction = faction or MyFaction()
    local out = {}
    for _, t in ipairs(N.TRAINERS[line] or {}) do
        if t[2] == "N" or not faction or t[2] == faction then
            out[#out + 1] = { id = t[1], name = t[6], tag = t[7], map = t[3], x = t[4] / 100, y = t[5] / 100,
                              kind = "trainer", rank = TitleRank(t[7]) }
        end
    end
    local vendors = N.GuideVendors(line)
    for name, v in pairs(Seen()) do
        if vendors[name] or v.line == line then
            out[#out + 1] = { name = name, tag = L["Bauplan-Händler"], map = v.map, x = v.x, y = v.y, kind = "vendor", rank = 0 }
        end
    end
    return out
end

-- Bester Lehrer: gleiche Karte wie du zuerst, sonst höchster Rang
function N.Best(line)
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local best
    for _, n in ipairs(N.ForLine(line)) do
        if n.kind == "trainer" then
            local score = (n.map == here and 10 or 0) + n.rank
            if not best or score > best.score then best = { n = n, score = score } end
        end
    end
    return best and best.n
end

---------------------------------------------------------------------
-- Karte
---------------------------------------------------------------------
N.line = nil
function N.SetLine(line)
    N.line = line
    if ns.RefreshMapPins then ns.RefreshMapPins(true) end
end

local TRAINER_TEX = "Interface\\Minimap\\Tracking\\Profession"
local VENDOR_TEX = "Interface\\Minimap\\Tracking\\Banker"

local function PinEnter(pin, n)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(n.name, 1, 0.82, 0)
    GameTooltip:AddLine(n.tag or "", 1, 1, 1)
    GameTooltip:AddLine(("%s  (%.1f, %.1f)"):format(G.Name(N.line or 0), n.x * 100, n.y * 100), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

if ns.AddMapSource then
    ns.AddMapSource(function(shown)
        local list = {}
        if not (Opt() and N.line and shown) then return list end
        local Translate = ns.Zettel and ns.Zettel.Translate
        for _, n in ipairs(N.ForLine(N.line)) do
            local x, y
            if n.map == shown then x, y = n.x, n.y elseif Translate then x, y = Translate(n.map, n.x, n.y, shown) end
            if x then
                list[#list + 1] = { x = x, y = y, tex = n.kind == "vendor" and VENDOR_TEX or TRAINER_TEX, size = 16,
                    color = n.kind == "vendor" and { 0.6, 0.85, 1 } or nil, alpha = 1,
                    enter = function(pin) PinEnter(pin, n) end }
            end
        end
        return list
    end)
end

-- Karte beim besten Lehrer öffnen und Wegpunkt setzen (TomTom, sonst Spiel-Wegpunkt)
function N.ShowOnMap(line)
    N.SetLine(line)
    local n = N.Best(line)
    if not n then ns.Print(L["Für diesen Beruf kennt GuildPride keinen Lehrer deiner Fraktion."]); return false end
    if TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, n.map, n.x, n.y, { title = n.name .. " (" .. (n.tag or "") .. ")" })
    elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(n.map, n.x, n.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    end
    if WorldMapFrame then
        if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, n.map) end
    end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(n.map)
    ns.Print((L["Lehrer: %s (%s) – %s %.1f, %.1f"]):format(n.name, n.tag or "", info and info.name or "?", n.x * 100, n.y * 100))
    return true
end

---------------------------------------------------------------------
-- Händler-Standorte im Spiel lernen
---------------------------------------------------------------------
function N.Learn()
    local name = UnitName and UnitName("npc")
    if not name then return end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    -- Gehört der Händler zu einem Guide? (Name, oder er verkauft einen Guide-Bauplan)
    local line
    for l in pairs(G.STEPS) do
        if N.GuideVendors(l)[name] then line = l; break end
    end
    if not line and ns.CraftVendor then
        local offer = ns.CraftVendor.Offer()
        for l, steps in pairs(G.STEPS) do
            for _, s in ipairs(steps) do if s[5] and offer[s[5]] then line = l; break end end
            if line then break end
        end
    end
    if line then Seen()[name] = { map = map, x = x, y = y, line = line, t = GetServerTime() } end
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "MERCHANT_SHOW")
ev:SetScript("OnEvent", function() C_Timer.After(0.5, function() pcall(N.Learn) end) end)
