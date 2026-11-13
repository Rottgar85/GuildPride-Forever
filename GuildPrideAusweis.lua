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
    s.disputed = s.disputed or {}  -- [Name] = { by = Name, t = Zeit }: Ausweis angezweifelt
    return s
end

local function Enabled() return GuildPrideDB and GuildPrideDB.ausweisAuto ~= false end

local function ValidCode(a) return type(a) == "string" and a:match("^[0-9a-z]+$") and #a == 14 end

local changedCallbacks = {}
function ns.OnAusweisChanged(fn) changedCallbacks[#changedCallbacks + 1] = fn end
local pending
local function Changed()
    if ns.ClearMainCache then ns.ClearMainCache() end
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
        if type(name) == "string" and not (issecretvalue and (issecretvalue(name) or issecretvalue(rankIndex) or issecretvalue(level))) then
            idx[ns.Normalize(name)] = { rank = rankIndex or 99, level = level or 0 }
        end
    end
    return idx
end

-- Ausweis -> Charaktere (nur wer in der Gilde und nicht umstritten ist)
local function ByCode(roster)
    local s, by = Store(), {}
    for name, e in pairs(s.chars) do
        if roster[name] and not s.disputed[name] then
            by[e.a] = by[e.a] or {}
            table.insert(by[e.a], name)
        end
    end
    return by
end

-- Main bestimmen: gewählter Main > höchster Rang > höchstes Level > am längsten im Rang
local function PickMain(code, names, roster)
    local chosen = Store().mains[code]
    for _, n in ipairs(names) do if n == chosen then return chosen end end
    local best, bestKey
    for _, name in ipairs(names) do
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

-- Name -> Main für die ganze Gilde in einem Durchlauf
-- (Offiziers-Zuordnung > Ausweis > er selbst)
local function MainMap(roster)
    local s, map = Store(), {}
    for code, names in pairs(ByCode(roster)) do
        local main = PickMain(code, names, roster)
        for _, n in ipairs(names) do map[n] = main end
    end
    for name in pairs(roster) do
        local m = s.manual[name]
        if m and roster[m.main] and m.main ~= name then
            -- Ziel selbst ein Twink? Dann gleich zu dessen Main (keine Ketten/Schleifen)
            local target = map[m.main] or m.main
            map[name] = target ~= name and target or name
        elseif not map[name] then
            map[name] = name
        end
    end
    return map
end

-- Zwischenspeicher: Chat und Listen fragen oft; neu rechnen nach Änderungen
-- oder spätestens alle 10 s (Gildenliste kann sich geändert haben)
local mapCache, mapAt = nil, 0
local function CachedMap()
    if not mapCache or GetTime() - mapAt > 10 then
        mapCache, mapAt = MainMap(RosterIndex()), GetTime()
    end
    return mapCache
end

function ns.ClearMainCache() mapCache = nil end

function ns.MainOf(name, roster)
    if not name then return nil end
    if roster then return MainMap(roster)[name] or name end
    return CachedMap()[name] or name
end

-- Gruppen für die Mitgliederliste: { [Main] = { Twink, … } }
function ns.AltGroups()
    local groups = {}
    for name, main in pairs(MainMap(RosterIndex())) do
        groups[main] = groups[main] or {}
        if main ~= name then table.insert(groups[main], name) end
    end
    for _, list in pairs(groups) do table.sort(list) end
    return groups
end

function ns.IsDisputed(name) return Store().disputed[name] ~= nil end

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
local lastAnnounce = 0
local function Announce()
    if not Enabled() or not IsInGuild() or not ns.Queue then return end
    if GetTime() - lastAnnounce < 30 then return end
    lastAnnounce = GetTime()
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
    return ns.IsOfficerRank(my)
end

-- Offizier/Gildenleitung: Twink von Hand zuordnen (main = nil löst die Zuordnung)
function ns.SetAltManual(twink, main)
    if not ns.CanSetAlts() or not twink or twink == main then return false end
    local s, t = Store(), GetServerTime()
    if main then s.manual[twink] = { main = main, by = ns.Me(), t = t } else s.manual[twink] = nil end
    s.disputed[twink] = nil
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
    -- Jemand meldet MEINEN Ausweis mit einem anderen Charakter, während ich online
    -- bin: Ein Battle.net-Konto kann nicht zweimal gleichzeitig spielen, also ist
    -- das gefälscht (der Code wurde abgeschrieben). Anzweifeln und warnen.
    if sender ~= ns.Me() and Enabled() and ValidCode(code) and code == ns.Ausweis() then
        Learn(sender, code, nil)
        s.disputed[sender] = { by = ns.Me(), t = GetServerTime() }
        Changed()
        ns.Queue("AUSX", nil, sender)
        ns.Print((L["|cffff4040Achtung:|r %s gibt sich mit deinem Ausweis als dein Twink aus. Die Gildenleitung sieht das als „umstritten“."]):format(Ambiguate(sender, "guild")))
        return
    end
    Learn(sender, code, main ~= "" and main or nil)
end)

-- Anzweiflung: nur von einem Charakter, der selbst länger mit diesem Ausweis
-- bekannt ist als der angezweifelte (ein Fälscher kommt immer später dazu)
ns.On("AUSX", function(payload, sender)
    if not ns.IsGuildMember(sender) then return end
    local target = ns.Clean(payload, 60)
    local s = Store()
    local mine, theirs = s.chars[sender], s.chars[target]
    if not (mine and theirs) or mine.a ~= theirs.a or target == sender then return end
    if (mine.t or 0) > (theirs.t or 0) then return end
    if s.manual[target] then return end   -- von Hand bestätigt: Offiziere entscheiden
    s.disputed[target] = { by = sender, t = GetServerTime() }
    Changed()
end)

-- Antworten: nicht alle, sonst bekäme der Fragende Dutzende Listen. Etwa drei
-- zufällige Mitglieder antworten (Offiziere immer, ihre Liste zählt sofort).
-- Listen gehen in Stücken: eine Nachricht darf höchstens 20 Teile haben.
local CHUNK = 3000
ns.On("AUSQ", function(_, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    local users = 0
    for _ in pairs(ns.AddonUsers or {}) do users = users + 1 end
    if not ns.CanSetAlts() and math.random() > 3 / math.max(users, 1) then return end
    C_Timer.After(2 + math.random() * 6, function()
        local roster, s = RosterIndex(), Store()
        local buf, len = {}, 0
        local function flush()
            if #buf > 0 then ns.Queue("AUSL", sender, table.concat(buf, ";")) end
            buf, len = {}, 0
        end
        for name, e in pairs(s.chars) do
            if roster[name] and not s.disputed[name] then
                local item = ("%s=%s=%s"):format(name, e.a, s.mains[e.a] or "")
                if len + #item + 1 > CHUNK then flush() end
                buf[#buf + 1] = item
                len = len + #item + 1
            end
        end
        flush()
    end)
end)

-- Liste von anderen: nur übernehmen, was wir noch nicht kennen (eigene Meldungen
-- der Spieler über AUS haben immer Vorrang)
-- Fremde Listen sind nur Hörensagen: Ein Eintrag zählt erst, wenn ihn ein
-- Offizier oder zwei verschiedene Mitglieder gleich melden. So kann ein
-- einzelnes manipuliertes Addon keine Spieler ohne GuildPride falsch zuordnen.
local heard, heardCount = {}, 0   -- ["Name=Code"] = { [Absender] = true }
ns.On("AUSL", function(payload, sender)
    if not ns.IsGuildMember(sender) then return end
    local trusted = ns.IsOfficerName(sender)
    local s, roster, n = Store(), RosterIndex(), 0
    for entry in payload:gmatch("[^;]+") do
        n = n + 1
        if n > 1000 then break end
        local name, code, main = entry:match("^([^=]+)=([^=]+)=(.*)$")
        name = name and ns.Clean(name, 60)
        if name and name ~= sender and roster[name] and not s.chars[name] and ValidCode(code) then
            local key = name .. "=" .. code
            local seen = heard[key]
            if not seen and heardCount < 5000 then seen = {}; heard[key] = seen; heardCount = heardCount + 1 end
            if seen then seen[sender] = true end
            local count = 0
            for _ in pairs(seen or {}) do count = count + 1 end
            if trusted or count >= 2 then
                Learn(name, code, nil)
                main = ns.Clean(main, 60)
                if main ~= "" and not s.mains[code] then s.mains[code] = main end
            end
        end
    end
end)

-- Von Hand: nur von Gildenleitung und Offizieren, neuere Änderung gewinnt
ns.On("ALT", function(payload, sender)
    if not ns.IsOfficerName(sender) then return end
    local twink, main, t = strsplit(SEP, payload)
    twink, main, t = ns.Clean(twink, 60), ns.Clean(main, 60), ns.Stamp(t)
    if twink == "" or twink == main then return end
    local s = Store()
    local cur = s.manual[twink]
    if cur and (cur.t or 0) > t then return end
    if main == "" then s.manual[twink] = nil else s.manual[twink] = { main = main, by = sender, t = t } end
    s.disputed[twink] = nil
    Changed()
end)

---------------------------------------------------------------------
-- Aufräumen: wer nicht mehr in der Gilde ist, fliegt raus
---------------------------------------------------------------------
local function Cleanup()
    if not IsInGuild() or GetNumGuildMembers() == 0 then return end
    -- Liefert der Client Offline-Mitglieder nicht mit, sähe jeder Offline-Spieler
    -- wie ausgetreten aus: dann nichts löschen
    if GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then return end
    local roster, s = RosterIndex(), Store()
    if next(roster) == nil then return end
    for name in pairs(s.chars) do if not roster[name] then s.chars[name] = nil end end
    for name in pairs(s.manual) do if not roster[name] then s.manual[name] = nil end end
    for name in pairs(s.disputed) do if not roster[name] then s.disputed[name] = nil end end
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
