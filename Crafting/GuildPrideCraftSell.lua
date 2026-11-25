-- GuildPride Handwerk: Verkaufs-Berater (nur im Item-Tooltip)
-- Für jedes Item: Händler, Auktionshaus oder behalten?
--   • Behalten: dein Tracker oder dein Berufs-Guide braucht es noch, Quest-Gegenstände
--   • Händler: graue Sachen, seelengebundene Sachen, und alles, wo das AH nach 5 % Gebühr
--     kaum mehr bringt (weniger als 20 % und 5 Silber mehr)
--   • Auktionshaus: GuildPride-Preis nach Gebühr deutlich über dem Händlerpreis
--   • Im AH nachsehen: grün oder besser, handelbar, aber noch kein Preis bekannt
-- Die zwei Zeilen hängt GuildPrideCraftTips.lua an den Tooltip. Schalter: craftSell
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
    if not id then return nil end
    local name, _, quality, _, _, _, _, _, _, _, sell, classID, _, bindType = ns.ItemInfo(id)
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
-- Tooltip: eine klare Empfehlung, darunter Preise und Unterschied
--   GuildPride                                        AUKTIONSHAUS
--   Händler 1s · Auktionshaus 47s 50c (nach Gebühr) · +46s 50c
---------------------------------------------------------------------
local WORD = { ah = "AUKTIONSHAUS", vendor = "HÄNDLER", check = "IM AUKTIONSHAUS NACHSEHEN", keep = "BEHALTEN" }
local COLOR = { ah = "|cff40ff40", vendor = "|cffffd100", check = "|cff66ccff", keep = "|cffff9933" }
local ICON = { ah = "INV_Hammer_15", vendor = "INV_Misc_Coin_02", check = "INV_Misc_Spyglass_02", keep = "INV_Misc_Bag_10" }
S.WORD, S.COLOR = WORD, COLOR

-- Angelegt oder besser als dein Teil? Dann nicht zum Verkauf raten
local function KeepReason(id, link)
    local worn = C_Item and C_Item.IsEquippedItem
    if worn then
        local ok, v = pcall(worn, id)
        if ok and v == true then return L["angelegt"] end
    end
    local Cmp = ns.Scales and ns.Scales.Compare
    if link and Cmp and Cmp.Verdict then
        local ok, v = pcall(Cmp.Verdict, link)
        if ok and v == "up" then return L["besser als dein angelegtes Teil"] end
    end
end

-- Empfehlung samt „behalten“ für Angelegtes, Besseres und Unverkäufliches
function S.Final(id, count, bound, link)
    local a = S.Advice(id, count, bound)
    if not a then return nil end
    local why = KeepReason(id, link)
    if why then a.verdict, a.reason = "keep", why
    elseif a.verdict == "none" then a.verdict, a.reason = "keep", L["kein Verkaufswert"] end
    return a
end

-- Farbmarke in den Taschen (Schalter bagMarks, ab Werk aus): "keep", "vendor", "ah", "check" oder nil.
-- Kurz gemerkt, weil jede Taschenänderung alle Plätze neu zeichnet.
S.MARK = { keep = { 1, 0.6, 0.2 }, vendor = { 1, 0.82, 0 }, ah = { 0.25, 1, 0.25 }, check = { 0.4, 0.8, 1 } }
local marks, marksAt = {}, 0
function S.BagMark(link)
    if not (type(GuildPrideDB) == "table" and GuildPrideDB.bagMarks == true) then return nil end
    if (issecretvalue and issecretvalue(link)) or type(link) ~= "string" then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    if GetTime() - marksAt > 10 then marks, marksAt = {}, GetTime() end
    local v = marks[link]
    if v == nil then
        local bags, bank = Craft.Count(id)
        local a = S.Final(id, math.max(1, bags + bank), false, link)
        v = a and a.verdict or false
        marks[link] = v
    end
    return v or nil
end

-- bound: steht im Tooltip „Seelengebunden“? Rückgabe: Kopf (farbig), Zeile darunter (oder nil)
function S.TooltipLines(id, bound, link)
    -- mit deinem ganzen Bestand rechnen: braucht der Guide 3 und du hast 10, ist der Rest frei
    local bags, bank = Craft.Count(id)
    local f = S.ItemFacts(id)
    if not f then return nil end
    local a = S.Final(id, math.max(1, bags + bank), bound, link)
    if not a then return nil end
    local money = ns.AH and ns.AH.Money or tostring
    local head = ("|TInterface\\Icons\\%s:14:14:0:0:64:64:5:59:5:59|t "):format(ICON[a.verdict]) .. COLOR[a.verdict] .. L[WORD[a.verdict]] .. "|r"
    local parts = {}
    if a.keep > 0 and a.sell > 0 then parts[#parts + 1] = (L["%d behalten"]):format(a.keep) end
    if f.vendor > 0 then parts[#parts + 1] = L["Händler"] .. " " .. money(f.vendor) end
    local tradable = not bound and f.bindType ~= 1 and f.bindType ~= 4 and f.classID ~= 12
    if f.ah and tradable then
        local net = math.floor(f.ah * AH_CUT)
        parts[#parts + 1] = (L["Auktionshaus %s (nach Gebühr)"]):format(money(net))
        local diff = net - f.vendor
        if f.vendor > 0 and diff > 0 then
            parts[#parts + 1] = a.verdict == "ah" and ("|cff40ff40+" .. money(diff) .. "|r") or ("|cffffd100" .. (L["nur +%s"]):format(money(diff)) .. "|r")
        elseif diff < 0 then
            parts[#parts + 1] = "|cffff6060-" .. money(-diff) .. "|r"
        end
    end
    if a.reason then parts[#parts + 1] = "|cffaaaaaa" .. a.reason .. "|r" end
    return head, #parts > 0 and table.concat(parts, " · ") or nil
end
