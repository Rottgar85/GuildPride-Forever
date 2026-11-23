-- GuildPride Handwerk: Woher kommt ein Material? (eigene Zusammenstellung, nur die gängigen)
-- Im Item-Tooltip als „Herkunft: …“ (GuildPrideCraftExtras.lua).
local ADDON, ns = ...

local M = {}
ns.CraftMats = M

-- Texte je Herkunft
local TEXT = {
    copper   = { de = "Kupfervorkommen (Bergbau 1+)", en = "Copper veins (Mining 1+)" },
    tin      = { de = "Zinnvorkommen (Bergbau 65+)", en = "Tin veins (Mining 65+)" },
    silver   = { de = "Silbervorkommen (Bergbau 75+)", en = "Silver veins (Mining 75+)" },
    iron     = { de = "Eisenvorkommen (Bergbau 125+)", en = "Iron veins (Mining 125+)" },
    gold     = { de = "Goldvorkommen (Bergbau 155+)", en = "Gold veins (Mining 155+)" },
    mithril  = { de = "Mithrilvorkommen (Bergbau 175+)", en = "Mithril veins (Mining 175+)" },
    truesil  = { de = "Echtsilbervorkommen (Bergbau 230+)", en = "Truesilver veins (Mining 230+)" },
    thorium  = { de = "Thoriumvorkommen (Bergbau 245+)", en = "Thorium veins (Mining 245+)" },
    smelt    = { de = "Erz schmelzen (Bergbau)", en = "Smelt ore (Mining)" },
    smeltAlloy = { de = "Legierung schmelzen (Bergbau, aus zwei Erzen)", en = "Smelt alloy (Mining, from two ores)" },
    linen    = { de = "Humanoide Stufe 5–15", en = "Humanoids level 5–15" },
    wool     = { de = "Humanoide Stufe 15–25", en = "Humanoids level 15–25" },
    silk     = { de = "Humanoide Stufe 25–40", en = "Humanoids level 25–40" },
    mageweave = { de = "Humanoide Stufe 35–50", en = "Humanoids level 35–50" },
    runecloth = { de = "Humanoide Stufe 50–60", en = "Humanoids level 50–60" },
    felcloth = { de = "Dämonen und Satyrn (Teufelswald, Azshara)", en = "Demons and satyrs (Felwood, Azshara)" },
    bolt     = { de = "Schneiderei aus Stoff", en = "Tailoring from cloth" },
    skin1    = { de = "Kürschnerei: Tiere Stufe 1–20", en = "Skinning: beasts level 1–20" },
    skin2    = { de = "Kürschnerei: Tiere Stufe 20–30", en = "Skinning: beasts level 20–30" },
    skin3    = { de = "Kürschnerei: Tiere Stufe 30–40", en = "Skinning: beasts level 30–40" },
    skin4    = { de = "Kürschnerei: Tiere Stufe 40–50", en = "Skinning: beasts level 40–50" },
    skin5    = { de = "Kürschnerei: Tiere Stufe 50–60", en = "Skinning: beasts level 50–60" },
    scale    = { de = "Kürschnerei: Skorpide (Silithus, Brennende Steppe)", en = "Skinning: scorpids (Silithus, Burning Steppes)" },
    herb     = { de = "Kräuterkunde", en = "Herbalism" },
    dust     = { de = "Entzaubern (grüne Rüstung und Waffen)", en = "Disenchanting (green armor and weapons)" },
    shard    = { de = "Entzaubern (blaue Gegenstände)", en = "Disenchanting (blue items)" },
    vendor   = { de = "Händler für Handwerkswaren", en = "Trade goods vendor" },
    cook     = { de = "Kochbedarf beim Händler", en = "Cooking supplies vendor" },
    fish     = { de = "Angeln", en = "Fishing" },
    meat     = { de = "Tiere (Beute)", en = "Beasts (loot)" },
    element  = { de = "Elementare (Beute)", en = "Elementals (loot)" },
    gem      = { de = "Bergbau (Edelstein aus Vorkommen)", en = "Mining (gem from veins)" },
}

-- itemID → Herkunft (Schlüssel in TEXT, bei Kräutern mit Stufe)
local SRC = {
    -- Steine und Erze
    [2835] = "copper", [2770] = "copper", [2836] = "tin", [2771] = "tin", [2775] = "silver",
    [2838] = "iron", [2772] = "iron", [2776] = "gold", [7912] = "mithril", [3858] = "mithril",
    [7911] = "truesil", [12365] = "thorium", [10620] = "thorium",
    -- Barren
    [2840] = "smelt", [3576] = "smelt", [2842] = "smelt", [3575] = "smelt", [3577] = "smelt",
    [3860] = "smelt", [6037] = "smelt", [12359] = "smelt", [2841] = "smeltAlloy", [3859] = "smeltAlloy",
    -- Stoff
    [2589] = "linen", [2592] = "wool", [4306] = "silk", [4338] = "mageweave", [14047] = "runecloth", [14256] = "felcloth",
    [2996] = "bolt", [2997] = "bolt", [4305] = "bolt", [4339] = "bolt", [14048] = "bolt",
    -- Leder und Bälge
    [2934] = "skin1", [2318] = "skin1", [783] = "skin1", [2319] = "skin2", [4232] = "skin2",
    [4234] = "skin3", [4235] = "skin3", [4304] = "skin4", [8169] = "skin4", [8170] = "skin5", [8171] = "skin5",
    [15408] = "scale", [15407] = "skin5",
    -- Kräuter
    [2447] = "herb:1", [765] = "herb:1", [2449] = "herb:15", [785] = "herb:50", [2450] = "herb:70",
    [2453] = "herb:100", [2452] = "herb:70", [3820] = "herb:85", [3355] = "herb:115", [3369] = "herb:120",
    [3356] = "herb:125", [3357] = "herb:150", [3818] = "herb:160", [3821] = "herb:170", [3358] = "herb:185",
    [3819] = "herb:195", [4625] = "herb:205", [8831] = "herb:210", [8836] = "herb:220", [8838] = "herb:230",
    [8839] = "herb:235", [8845] = "herb:245", [8846] = "herb:250", [13464] = "herb:260", [13463] = "herb:270",
    [13465] = "herb:280", [13466] = "herb:285", [13467] = "herb:290",
    -- Verzaubern
    [10940] = "dust", [11083] = "dust", [11137] = "dust", [11176] = "dust", [16204] = "dust",
    [10938] = "dust", [10939] = "dust", [10998] = "dust", [11082] = "dust", [11134] = "dust", [11135] = "dust",
    [11174] = "dust", [11175] = "dust", [16202] = "dust", [16203] = "dust",
    [10978] = "shard", [11084] = "shard", [11138] = "shard", [11139] = "shard", [11177] = "shard",
    [11178] = "shard", [14343] = "shard", [14344] = "shard",
    -- Händlerwaren
    [2320] = "vendor", [2321] = "vendor", [4291] = "vendor", [8343] = "vendor", [14341] = "vendor",
    [2324] = "vendor", [2604] = "vendor", [2605] = "vendor", [6260] = "vendor", [6261] = "vendor",
    [4340] = "vendor", [4289] = "vendor", [3371] = "vendor", [3372] = "vendor", [8925] = "vendor",
    [18256] = "vendor", [2880] = "vendor", [3466] = "vendor", [4470] = "vendor", [6217] = "vendor",
    [4399] = "vendor", [4400] = "vendor", [10290] = "vendor", [2325] = "vendor", [3857] = "vendor",
    [2678] = "cook", [2692] = "cook", [3713] = "cook", [159] = "cook", [30817] = "cook",
    -- Fisch und Fleisch
    [6291] = "fish", [6289] = "fish", [6308] = "fish", [8365] = "fish", [4603] = "fish", [13893] = "fish",
    [769] = "meat", [2672] = "meat", [3173] = "meat", [5503] = "meat",
    -- Elementares
    [7067] = "element", [7068] = "element", [7069] = "element", [7070] = "element",
    [7075] = "element", [7076] = "element", [7077] = "element", [7078] = "element", [7079] = "element",
    [7080] = "element", [7081] = "element", [7082] = "element", [12803] = "element", [12808] = "element",
    -- Edelsteine
    [774] = "gem", [818] = "gem", [1210] = "gem", [1206] = "gem", [1705] = "gem", [1529] = "gem",
    [3864] = "gem", [7909] = "gem", [7910] = "gem", [12361] = "gem", [12799] = "gem", [12800] = "gem",
}

local function Lang(t) return ns.IS_GERMAN and t.de or t.en end

-- Herkunft als Text oder nil
function M.Origin(itemID)
    local key = SRC[tonumber(itemID) or 0]
    if not key then return nil end
    local base, level = key:match("^(%a+):(%d+)$")
    if base then
        return Lang(TEXT[base]) .. " " .. level .. "+"
    end
    return TEXT[key] and Lang(TEXT[key]) or nil
end

M.SRC = SRC
