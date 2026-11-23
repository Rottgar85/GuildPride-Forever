-- GuildPride Handwerk: Verkaufs-Berater (nur im Item-Tooltip)
-- Für jedes Item: Händler, Auktionshaus oder behalten?
--   • Behalten: dein Tracker oder dein Berufs-Guide braucht es noch, Quest-Gegenstände
--   • Händler: graue Sachen, seelengebundene Sachen, und alles, wo das AH nach 5 % Gebühr
--     kaum mehr bringt (weniger als 20 % und 5 Silber mehr)
--   • Auktionshaus: GuildPride-Preis nach Gebühr deutlich über dem Händlerpreis
--   • Im AH nachsehen: grün oder besser, handelbar, aber noch kein Preis bekannt
-- Die Zeile hängt GuildPrideCraftTips.lua an den Tooltip. Schalter: craftSell
local ADDON, ns = ...
local L = ns.L
local Craft = ns.Craft

local S = {}
ns.CraftSell = S

local AH_CUT = 0.95          -- 5 % Auktionshaus-Gebühr
local AH_FACTOR = 1.2        -- AH muss mind. 20 % mehr bringen …
local AH_MIN_GAIN = 500      -- … und mind. 5 Silber mehr (ganze Menge), sonst lohnt der Weg nicht

local function Opt() return not (type(GuildPrideDB) == "table" and GuildPrideDB.craftSell == false) end
S.Opt = Opt

-- Preise je Stück: Händler (Verkaufspreis), AH (GuildPride-Preis), Qualität, Klasse, Bindung
function S.ItemFacts(id)
    if not (id and GetItemInfo) then return nil end
    local name, _, quality, _, _, _, _, _, _, _, sell, classID, _, bindType = GetItemInfo(id)
    if not name then return nil end
    local AH = ns.AH
    local ah = AH and AH.PriceFor and AH.Key and AH.PriceFor(AH.Key(id))
    return { vendor = tonumber(sell) or 0, ah = tonumber(ah), quality = tonumber(quality) or 1,
        classID = tonumber(classID), bindType = tonumber(bindType) or 0 }
end

-- Wie viel davon brauchst du noch? (Tracker + Guide), mit Grund
function S.Need(id)
    local need, why = 0, nil
    local T = ns.CraftTrack
    local t = T and T.Needs and T.Needs()[id] or 0
    if t > 0 then need, why = t, L["Tracker"] end
    local X = ns.CraftExtras
    local g = X and X.GuideNeed and X.GuideNeed(id) or 0
    if g > need then need, why = g, L["Guide"] end
    return need, why
end

-- Empfehlung für count Stück. bound = in der Tasche seelengebunden.
-- Rückgabe: { verdict = "keep"|"ah"|"vendor"|"check"|"none", keep, sell, vendor, ah, reason }
--   vendor/ah = Erlös für die verkaufbare Menge (ah nach Gebühr)
function S.Advice(id, count, bound)
    count = math.max(1, tonumber(count) or 1)
    local f = S.ItemFacts(id)
    if not f then return nil end
    local r = { keep = 0, sell = count, vendor = 0, ah = nil }
    if f.classID == 12 then
        r.verdict, r.keep, r.sell, r.reason = "keep", count, 0, L["Quest-Gegenstand"]
        return r
    end
    local need, why = S.Need(id)
    if need > 0 then
        r.keep = math.min(count, need)
        r.sell = count - r.keep
        r.reason = (L["%s braucht noch %d"]):format(why, need)
        if r.sell == 0 then r.verdict = "keep"; return r end
    end
    local n = r.sell
    r.vendor = f.vendor * n
    local tradable = not bound and f.bindType ~= 1 and f.bindType ~= 4
    if tradable and f.ah then r.ah = math.floor(f.ah * AH_CUT * n + 0.5) end
    if f.vendor <= 0 and not r.ah then
        r.verdict = "none"
    elseif f.quality == 0 then
        r.verdict = "vendor"; r.reason = r.reason or L["Schrott"]
    elseif not tradable then
        r.verdict = "vendor"; r.reason = r.reason or L["gebunden – nicht im AH"]
    elseif r.ah then
        if r.ah > r.vendor * AH_FACTOR and r.ah - r.vendor >= AH_MIN_GAIN then
            r.verdict = "ah"
        else
            r.verdict = "vendor"; r.reason = r.reason or L["AH bringt kaum mehr"]
        end
    elseif f.quality >= 2 then
        r.verdict = "check"; r.reason = r.reason or L["noch kein AH-Preis – im AH nachsehen"]
        -- Waffen/Rüstung: Verzauberer unter deinen Charakteren? Dann ist Entzaubern eine Option
        if f.classID == 2 or f.classID == 4 then
            for name, e in pairs(Craft.Chars()) do
                if type(e) == "table" and e.profs and e.profs[333] then
                    r.reason = r.reason .. " · " .. (L["Entzaubern: %s"]):format(name)
                    break
                end
            end
        end
    else
        r.verdict = "vendor"
    end
    return r
end

---------------------------------------------------------------------
-- Tooltip-Zeile („Verkaufen: AH 1g 20s · Händler 15s“)
---------------------------------------------------------------------
local WORD = { ah = "Auktionshaus", vendor = "Händler", check = "im AH nachsehen", keep = "Behalten" }
local COLOR = { ah = "|cff40ff40", vendor = "|cffffd100", check = "|cff66ccff", keep = "|cffff9933" }
S.WORD, S.COLOR = WORD, COLOR

function S.TooltipText(id)
    -- mit deinem ganzen Bestand rechnen: braucht der Guide 3 und du hast 10, ist der Rest frei
    local bags, bank = Craft.Count(id)
    local a = S.Advice(id, math.max(1, bags + bank))
    if not a or a.verdict == "none" then return nil end
    local money = ns.AH and ns.AH.Money or tostring
    local f = S.ItemFacts(id)
    local parts = { COLOR[a.verdict] .. L[WORD[a.verdict]] .. "|r" }
    if a.keep > 0 and a.sell > 0 then parts[#parts + 1] = (L["%d behalten"]):format(a.keep) end
    if f.vendor > 0 then parts[#parts + 1] = L["Händler"] .. " " .. money(f.vendor) end
    if f.ah then parts[#parts + 1] = L["AH"] .. " " .. money(f.ah) end
    if a.reason then parts[#parts + 1] = "|cffaaaaaa" .. a.reason .. "|r" end
    return table.concat(parts, " · ")
end
