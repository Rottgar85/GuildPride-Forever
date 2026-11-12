-- GuildPride: Spieler-Ausweis und automatische Twink-Erkennung
--
-- Jeder Spieler mit GuildPride meldet der Gilde für jeden seiner Charaktere
-- denselben Ausweis-Code. So erkennt die Gilde, welche Charaktere zusammen-
-- gehören, egal mit welchem Charakter jemand beitritt.
--
-- Datenschutz (feste Regel): Der BattleTag verlässt nie diesen Client. Er wird
-- hier sofort zusammen mit der Gildenkennung in einen Code umgerechnet; nur der
-- Code wird gesendet und gespeichert. Pro Gilde ergibt sich ein anderer Code.
-- Das ist kein kryptografischer Schutz (wer einen BattleTag schon kennt, kann
-- ihn gegen einen Code prüfen), verhindert aber, dass BattleTags in der Gilde
-- lesbar herumgehen.
--
-- Nachrichten:
--   AUS   ausweis·main·ver   an die Gilde: "dieser Charakter (Absender) gehört zu ausweis"
--   AUSQ  –                  Liste anfordern (nach dem Login)
--   AUSL  Name=a=m;…         Antwort per Flüstern (mehrteilig über ns.Queue)
--   ALT   twink·main·t       Offizier/Gildenleitung ordnet von Hand zu (main leer = lösen)
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"
local PROTO = 1
local OFFICER_MAX_RANK = 1      -- 0 = Gildenleitung, 1 = Offiziere
local NEW_LINK_DAYS = 7         -- so lange gilt eine automatische Verknüpfung als "neu"

---------------------------------------------------------------------
-- Code berechnen (nur Ganzzahlen < 2^53, daher ohne Bit-Operationen)
---------------------------------------------------------------------
local M32 = 4294967296
local function Mix(s, seed, mult)
    local h = seed
    for i = 1, #s do h = (h * mult + s:byte(i) + i) % M32 end
    return h
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Base36(n, len)
    local out = {}
    for i = len, 1, -1 do
        local d = n % 36
        out[i] = DIGITS:sub(d + 1, d + 1)
        n = math.floor(n / 36)
    end
    return table.concat(out)
end

local function MakeCode(text)
    return Base36(Mix(text, 5381, 33), 7) .. Base36(Mix(text, 2166136, 131), 7)
end

-- Der eigene BattleTag, nur lokal; nil, wenn Battle.net ihn nicht liefert
local function MyBattleTag()
    if not BNGetInfo then return nil end
    local ok, _, tag = pcall(BNGetInfo)
    if not ok or type(tag) ~= "string" or tag == "" then return nil end
    if issecretvalue and issecretvalue(tag) then return nil end
    return tag
end

-- Eigener Ausweis für die aktuelle Gilde (nil ohne Gilde)
function ns.Ausweis()
    local gid = ns.GuildId and ns.GuildId()
    if not gid then return nil end
    local secret = MyBattleTag()
    if not secret then
        -- Ohne BattleTag: zufälliger Schlüssel, gilt nur für diesen WoW-Account
        if not GuildPrideDB.ausweisFallback then
            GuildPrideDB.ausweisFallback = ("%08x%08x"):format(math.random(0, 2^31 - 1), math.random(0, 2^31 - 1))
        end
        secret = "fb:" .. GuildPrideDB.ausweisFallback
    end
    return MakeCode(secret .. SEP .. gid)
end

---------------------------------------------------------------------
-- Speicher (je Gilde getrennt)
---------------------------------------------------------------------
local function Store()
    local s = ns.GuildTable("ausweis")
    s.chars = s.chars or {}     -- [Name] = { a = Code, t = zuerst gesehen }
    s.mains = s.mains or {}     -- [Code] = Name des gewählten Mains
    s.manual = s.manual or {}   -- [Twink] = { main = Name, by = Name, t = Zeit }
    return s
end

local function Enabled() return GuildPrideDB and GuildPrideDB.ausweisAuto ~= false end

local function ValidCode(a) return type(a) == "string" and a:match("^[0-9a-z]+$") and #a == 14 end

local changedCallbacks = {}
function ns.OnAusweisChanged(fn) changedCallbacks[#changedCallbacks + 1] = fn end
local pending
local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        for _, fn in ipairs(changedCallbacks) do pcall(fn) end
        if ns.RefreshUI then ns.RefreshUI() end
    end)
end

local function Learn(name, code, main)
    if not ValidCode(code) then return end
    local s = Store()
    local e = s.chars[name]
    if not e or e.a ~= code then
        s.chars[name] = { a = code, t = GetServerTime() }
        Changed()
    end
    if main and main ~= "" and main ~= s.mains[code] then
        s.mains[code] = main
        Changed()
    end
end

---------------------------------------------------------------------
-- Abfragen
---------------------------------------------------------------------
-- Gildenliste einmal lesen: Rang, Level je Name
local function RosterIndex()
    local idx = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, level = GetGuildRosterInfo(i)
        if name then idx[ns.Normalize(name)] = { rank = rankIndex or 99, level = level or 0 } end
    end
    return idx
end

-- Alle Charaktere mit demselben Ausweis (nur wer in der Gilde ist)
local function SameCode(code, roster)
    local list = {}
    for name, e in pairs(Store().chars) do
        if e.a == code and roster[name] then list[#list + 1] = name end
    end
    return list
end

-- Main bestimmen: gewählter Main > höchster Rang > höchstes Level > am längsten im Rang
local function PickMain(code, roster)
    local s = Store()
    local chosen = s.mains[code]
    if chosen and roster[chosen] and s.chars[chosen] and s.chars[chosen].a == code then return chosen end
    local best, bestKey
    for _, name in ipairs(SameCode(code, roster)) do
        local r = roster[name]
        local since = ns.RankSince and ns.RankSince(name) or GetServerTime()
        local key = { r.rank, -r.level, since, name }
        local better = not bestKey
        if not better then
            for i = 1, 4 do
                if key[i] ~= bestKey[i] then better = key[i] < bestKey[i]; break end
            end
        end
        if better then best, bestKey = name, key end
    end
    return best
end

-- Main zu einem Charakter: Offiziers-Zuordnung > Ausweis > er selbst
function ns.MainOf(name, roster)
    if not name then return nil end
    roster = roster or RosterIndex()
    local s = Store()
    local m = s.manual[name]
    if m and roster[m.main] then return m.main end
    local e = s.chars[name]
    if e then return PickMain(e.a, roster) or name end
    return name
end

-- Twinks eines Mains (ohne den Main selbst)
function ns.AltsOf(main, roster)
    roster = roster or RosterIndex()
    local alts = {}
    for name in pairs(roster) do
        if name ~= main and ns.MainOf(name, roster) == main then alts[#alts + 1] = name end
    end
    table.sort(alts)
    return alts
end

-- Gruppen für die Mitgliederliste: { [Main] = { Twink, … } }, ein Durchlauf
function ns.AltGroups()
    local roster = RosterIndex()
    local groups = {}
    for name in pairs(roster) do
        local main = ns.MainOf(name, roster)
        groups[main] = groups[main] or {}
        if main ~= name then table.insert(groups[main], name) end
    end
    for _, list in pairs(groups) do table.sort(list) end
    return groups
end

-- Automatisch verknüpft und noch neu? (Hinweis für Offiziere)
function ns.IsNewLink(name)
    local e = Store().chars[name]
    return e and not Store().manual[name] and GetServerTime() - (e.t or 0) < NEW_LINK_DAYS * 86400 or false
end

-- Gehört der Charakter zu meinem Ausweis?
function ns.IsMyChar(name)
    local code = ns.Ausweis()
    local e = code and Store().chars[name]
    return e ~= nil and e.a == code
end

function ns.IsManualAlt(name) return Store().manual[name] ~= nil end

---------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------
local function Announce()
    if not Enabled() or not IsInGuild() or not ns.Queue then return end
    local code = ns.Ausweis()
    if not code then return end
    local me = ns.Me()
    local main = Store().mains[code] or ""
    Learn(me, code, main ~= "" and main or nil)
    ns.Queue("AUS", nil, code, main, PROTO)
end

-- Eigenen Main festlegen (nur eigene Charaktere mit demselben Ausweis)
function ns.SetMyMain(name)
    local code = ns.Ausweis()
    if not code then return false end
    local e = Store().chars[name]
    if not e or e.a ~= code then return false end
    Store().mains[code] = name
    Changed()
    Announce()
    return true
end

function ns.CanSetAlts()
    local _, _, my = GetGuildInfo("player")
    return my ~= nil and my <= OFFICER_MAX_RANK
end

-- Offizier/Gildenleitung: Twink von Hand zuordnen (main = nil löst die Zuordnung)
function ns.SetAltManual(twink, main)
    if not ns.CanSetAlts() or not twink or twink == main then return false end
    local s, t = Store(), GetServerTime()
    if main then s.manual[twink] = { main = main, by = ns.Me(), t = t } else s.manual[twink] = nil end
    Changed()
    ns.Queue("ALT", nil, twink, main or "", t)
    return true
end
function ns.ClearAltManual(twink) return ns.SetAltManual(twink, nil) end

---------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------
-- Ein Charakter kann nur sich selbst einem Ausweis zuordnen
ns.On("AUS", function(payload, sender)
    if not ns.IsGuildMember(sender) then return end
    local code, main = strsplit(SEP, payload)
    main = ns.Clean(main, 60)
    -- Der Main muss zum selben Ausweis gehören, sonst nur den Code übernehmen
    local s = Store()
    if main ~= "" and main ~= sender and not (s.chars[main] and s.chars[main].a == code) then main = nil end
    Learn(sender, code, main ~= "" and main or nil)
end)

ns.On("AUSQ", function(_, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    C_Timer.After(2 + math.random() * 6, function()
        local parts, roster = {}, RosterIndex()
        local s = Store()
        for name, e in pairs(s.chars) do
            if roster[name] then parts[#parts + 1] = ("%s=%s=%s"):format(name, e.a, s.mains[e.a] or "") end
        end
        if #parts > 0 then ns.Queue("AUSL", sender, table.concat(parts, ";")) end
    end)
end)

-- Liste von anderen: nur übernehmen, was wir noch nicht kennen (eigene Meldungen
-- der Spieler über AUS haben immer Vorrang)
ns.On("AUSL", function(payload, sender)
    if not ns.IsGuildMember(sender) then return end
    local s, roster, n = Store(), RosterIndex(), 0
    for entry in payload:gmatch("[^;]+") do
        n = n + 1
        if n > 1000 then break end
        local name, code, main = entry:match("^([^=]+)=([^=]+)=(.*)$")
        name = name and ns.Clean(name, 60)
        if name and roster[name] and not s.chars[name] and ValidCode(code) then
            Learn(name, code, nil)
            main = ns.Clean(main, 60)
            if main ~= "" and not s.mains[code] then s.mains[code] = main end
        end
    end
end)

-- Von Hand: nur von Gildenleitung und Offizieren, neuere Änderung gewinnt
ns.On("ALT", function(payload, sender)
    local rank = ns.RankIndexOf and ns.RankIndexOf(sender)
    if not rank or rank > OFFICER_MAX_RANK then return end
    local twink, main, t = strsplit(SEP, payload)
    twink, main, t = ns.Clean(twink, 60), ns.Clean(main, 60), ns.Stamp(t)
    if twink == "" or twink == main then return end
    local s = Store()
    local cur = s.manual[twink]
    if cur and (cur.t or 0) > t then return end
    if main == "" then s.manual[twink] = nil else s.manual[twink] = { main = main, by = sender, t = t } end
    Changed()
end)

---------------------------------------------------------------------
-- Aufräumen: wer nicht mehr in der Gilde ist, fliegt raus
---------------------------------------------------------------------
local function Cleanup()
    if not IsInGuild() or GetNumGuildMembers() == 0 then return end
    local roster, s = RosterIndex(), Store()
    for name in pairs(s.chars) do if not roster[name] then s.chars[name] = nil end end
    for name in pairs(s.manual) do if not roster[name] then s.manual[name] = nil end end
    local used = {}
    for _, e in pairs(s.chars) do used[e.a] = true end
    for code in pairs(s.mains) do if not used[code] then s.mains[code] = nil end end
end

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------
local started, lastClean = false, 0
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
pcall(f.RegisterEvent, f, "PLAYER_GUILD_UPDATE")
f:SetScript("OnEvent", function(_, event, isLogin, isReload)
    if not GuildPrideDB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if not (isLogin or isReload) or started then return end
        started = true
        -- nach dem Kanalbeitritt und den übrigen Startanfragen
        C_Timer.After(25, function()
            Announce()
            if IsInGuild() and ns.Queue then ns.Queue("AUSQ", nil, PROTO) end
        end)
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- frisch beigetreten: gleich melden
        if started and IsInGuild() then C_Timer.After(5, Announce) end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if GetTime() - lastClean > 60 then lastClean = GetTime(); Cleanup() end
    end
end)

-- /gp ausweis: nur den Code zeigen, nie den BattleTag
ns.AusweisCommand = function()
    local code = ns.Ausweis()
    ns.Print(code and (L["Ausweis: |cffffd100%s|r"]):format(code) or L["Kein Ausweis (keine Gilde)."])
end
