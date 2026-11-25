-- GuildPride Handwerk: Sammeln (Bergbau, Kräuterkunde)
--   • Eigene Sammelpunkte: jedes Vorkommen/Kraut, das du abbaust, wird gemerkt und auf der
--     Weltkarte gezeigt – gefärbt nach deiner Fertigkeit (rot: noch nicht, orange/gelb/grün:
--     Punkte möglich, grau: keine Punkte mehr). Gespeichert: GuildPrideDB.craftNodes[Karte] = { { x, y, item, t } }
--   • Hinweise: „Kupfer gibt dir keine Punkte mehr – ab jetzt Zinn“ und eine Erinnerung,
--     wenn Mineraliensuche / Kräutersuche aus ist
-- Schalter: craftNodes (Karte), craftHints (Hinweise)
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local Ga = {}
ns.CraftGather = Ga

local MAX_NODES = 3000

-- Erz/Kraut → { Beruf, Mindeststufe }
Ga.NODES = {
    [2770] = { 186, 1 }, [2771] = { 186, 65 }, [2775] = { 186, 75 }, [2772] = { 186, 125 }, [2776] = { 186, 155 },
    [3858] = { 186, 175 }, [7911] = { 186, 230 }, [10620] = { 186, 245 },
    [2447] = { 182, 1 }, [765] = { 182, 1 }, [2449] = { 182, 15 }, [785] = { 182, 50 }, [2450] = { 182, 70 },
    [2452] = { 182, 70 }, [3820] = { 182, 85 }, [2453] = { 182, 100 }, [3355] = { 182, 115 }, [3369] = { 182, 120 },
    [3356] = { 182, 125 }, [3357] = { 182, 150 }, [3818] = { 182, 160 }, [3821] = { 182, 170 }, [3358] = { 182, 185 },
    [3819] = { 182, 195 }, [4625] = { 182, 205 }, [8831] = { 182, 210 }, [8836] = { 182, 220 }, [8838] = { 182, 230 },
    [8839] = { 182, 235 }, [8845] = { 182, 245 }, [8846] = { 182, 250 }, [13464] = { 182, 260 }, [13463] = { 182, 270 },
    [13465] = { 182, 280 }, [13466] = { 182, 285 }, [13467] = { 182, 290 },
}

local function Opt(key) return not (type(GuildPrideDB) == "table" and GuildPrideDB[key] == false) end
local function Nodes()
    if type(GuildPrideDB) ~= "table" then return {} end
    GuildPrideDB.craftNodes = type(GuildPrideDB.craftNodes) == "table" and GuildPrideDB.craftNodes or {}
    return GuildPrideDB.craftNodes
end
Ga.Nodes = Nodes

-- Farbe für deine Fertigkeit: rot unter der Mindeststufe, dann orange (+25), gelb (+50), grün (+100), grau
function Ga.Color(req, skill)
    if not skill or skill < req then return "red" end
    if skill < req + 25 then return "orange" end
    if skill < req + 50 then return "yellow" end
    if skill < req + 100 then return "green" end
    return "gray"
end
local RGB = { red = { 1, 0.2, 0.2 }, orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, gray = { 0.5, 0.5, 0.5 } }

-- Vorkommen merken (doppelte in der Nähe zusammenfassen)
function Ga.Record(map, x, y, item)
    if not (map and x and y and Ga.NODES[item]) then return false end
    local list = Nodes()[map] or {}
    Nodes()[map] = list
    for _, n in ipairs(list) do
        if n[3] == item and math.abs(n[1] - x) < 0.006 and math.abs(n[2] - y) < 0.006 then
            n[4] = GetServerTime()
            return false
        end
    end
    local total = 0
    for _, l in pairs(Nodes()) do total = total + #l end
    if total >= MAX_NODES then return false end
    list[#list + 1] = { math.floor(x * 10000) / 10000, math.floor(y * 10000) / 10000, item, GetServerTime() }
    return true
end

---------------------------------------------------------------------
-- Hinweise: Vorkommen grau → nächste Stufe
---------------------------------------------------------------------
local hinted = {}
function Ga.NextTier(line, skill)
    local best
    for item, n in pairs(Ga.NODES) do
        if n[1] == line and n[2] <= (skill or 0) and Ga.Color(n[2], skill) ~= "gray" then
            if not best or n[2] > Ga.NODES[best][2] then best = item end
        end
    end
    return best
end

function Ga.GrayHint(item, skill)
    local n = Ga.NODES[item]
    if not n or Ga.Color(n[2], skill) ~= "gray" then return nil end
    local nxt = Ga.NextTier(n[1], skill)
    return (L["%s gibt dir keine Punkte mehr – ab jetzt %s."]):format(Craft.ItemName(item), nxt and Craft.ItemName(nxt) or "?")
end

-- Suche (Mineralien/Kräuter) an?
local FIND = { [186] = 2580, [182] = 2383 }
local function TrackingActive(spell)
    local name = Craft.RecipeName(spell)
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local info = C_Minimap.GetTrackingInfo(i)
            local n, active = info, nil
            if type(info) == "table" then n, active = info.name, info.active end
            if n == name then return active and true or false end
        end
        return nil
    end
    if GetTrackingTexture and C_Spell and C_Spell.GetSpellTexture then
        return GetTrackingTexture() == C_Spell.GetSpellTexture(spell)
    end
    return nil
end

local reminded = {}
local function CheckTracking()
    if not Opt("craftHints") or (IsResting and IsResting()) or (IsInInstance and IsInInstance()) then return end
    for line, spell in pairs(FIND) do
        if Craft.Skill(line) and not reminded[line] and TrackingActive(spell) == false then
            reminded[line] = true
            ns.Print((L["Tipp: %s ist aus – so siehst du keine Vorkommen auf der Minimap."]):format(Craft.RecipeName(spell)))
        end
    end
end

---------------------------------------------------------------------
-- Beute: Sammelpunkt merken, Hinweis geben
---------------------------------------------------------------------
local function OnLoot()
    if IsFishingLoot and IsFishingLoot() then return end
    local n = GetNumLootItems and GetNumLootItems() or 0
    for i = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(i)
        local item = link and tonumber(link:match("item:(%d+)"))
        local node = item and Ga.NODES[item]
        if node then
            local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition(map, "player")
            if pos and Opt("craftNodes") then
                local x, y = pos:GetXY()
                Ga.Record(map, x, y, item)
            end
            local skill = Craft.Skill(node[1])
            local hint = Opt("craftHints") and not hinted[item] and Ga.GrayHint(item, skill)
            if hint then hinted[item] = true; ns.Print(hint) end
            return
        end
    end
end
Ga.OnLoot = OnLoot

---------------------------------------------------------------------
-- Karte
---------------------------------------------------------------------
if ns.AddMapSource then
    ns.AddMapSource(function(shown)
        local list = {}
        if not (Opt("craftNodes") and shown) then return list end
        local Translate = ns.Zettel and ns.Zettel.Translate
        for map, nodes in pairs(Nodes()) do
            if map == shown or Translate then
                for _, n in ipairs(nodes) do
                    local info = Ga.NODES[n[3]]
                    local skill = info and Craft.Skill(info[1])
                    if skill then
                        local x, y = n[1], n[2]
                        if map ~= shown then x, y = Translate(map, x, y, shown) end
                        if x then
                            local c = Ga.Color(info[2], skill)
                            list[#list + 1] = { x = x, y = y, tex = Craft.ItemIcon(n[3]), size = 12, ring = true,
                                color = nil, alpha = c == "gray" and 0.5 or 1,
                                enter = function(pin)
                                    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
                                    GameTooltip:AddLine(Craft.ItemName(n[3]), RGB[c][1], RGB[c][2], RGB[c][3])
                                    GameTooltip:AddLine((L["%s ab %d · deine Fertigkeit %d"]):format(G.Name(info[1]), info[2], skill), 1, 1, 1)
                                    GameTooltip:Show()
                                end }
                        end
                    end
                end
            end
        end
        return list
    end)
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "LOOT_OPENED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
    if event == "LOOT_OPENED" then ns.Try(OnLoot)
    else C_Timer.After(15, function() ns.Try(CheckTracking) end) end
end)
