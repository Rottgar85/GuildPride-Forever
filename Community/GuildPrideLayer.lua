-- GuildPride: Layer wechseln mit Hilfe anderer GuildPride-Spieler (serverweit)
--
-- Ablauf:
--  1. "Layer wechseln" fragt im offenen GuildPride-Kanal: LYQ (Spielversion, Karte, eigener Layer)
--  2. Wer hilft (Einstellung an), in derselben Zone auf einem ANDEREN Layer steht und
--     einladen kann, antwortet per Flüstern: LYA (Karte, Layer)
--  3. Nach ein paar Sekunden wird ein Helfer gewählt und gebeten: LYR (Flüstern)
--  4. Der Helfer bekommt eine Abfrage mit "Einladen" (Klick = Einladung)
--  5. Nach dem Beitritt wechselt das Spiel den Layer. Sobald eine Kreatur in der Nähe
--     den neuen Layer verrät, verlässt das Addon die Gruppe wieder.
--
-- Der Layer steckt in der GUID von Kreaturen ("Creature-0-Server-Instanz-ZONE-npc-spawn").
-- Die Zahl gilt nur innerhalb einer Zone; verglichen wird daher nur bei gleicher Karte.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local Layer = { id = nil, map = nil }
ns.Layer = Layer

---------------------------------------------------------------------
-- Eigenen Layer erkennen
---------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function MapId()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

local function Observe(unit)
    if IsInInstance() or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if type(guid) ~= "string" or Secret(guid) then return end
    local kind, _, _, _, zoneUID = strsplit("-", guid)
    if (kind ~= "Creature" and kind ~= "Vehicle") or not zoneUID or zoneUID == "" or zoneUID == "0" then return end
    -- Begleiter und Wächter von Spielern verraten nichts Verlässliches
    if UnitPlayerControlled and UnitPlayerControlled(unit) then return end
    local map, changed = MapId(), Layer.id ~= zoneUID
    Layer.id, Layer.map, Layer.at = zoneUID, map, GetTime()
    -- Schiffs-Zähler: Entstehungszeit der Kreatur, daraus der Start dieses Layers
    if map and ns.Transit and ns.Transit.SawCreature then ns.Transit.SawCreature(guid, map .. "." .. zoneUID) end
    if changed and Layer.OnChange then Layer.OnChange() end
    if changed and Layer.Share then Layer.Share() end
end

-- Weitere Quellen für den Layer, ohne dass man etwas anvisieren muss:
-- weiches Ziel (Interaktion, Gegner, Freund), NPC im Gespräch (Händler, Flugmeister, Quest)
local SOFT = { PLAYER_SOFT_INTERACT_CHANGED = "softinteract", PLAYER_SOFT_ENEMY_CHANGED = "softenemy",
               PLAYER_SOFT_FRIEND_CHANGED = "softfriend" }
local NPC_EVENTS = { GOSSIP_SHOW = true, MERCHANT_SHOW = true, QUEST_DETAIL = true, QUEST_GREETING = true,
                     QUEST_PROGRESS = true, TAXIMAP_OPENED = true, BANKFRAME_OPENED = true, TRAINER_SHOW = true }

-- Layer noch unbekannt: sichtbare Namensplaketten und Ziele der Gruppe durchsehen
local function Scan()
    if Layer.id or IsInInstance() then return end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) then Observe(u); if Layer.id then return end end
    end
    for i = 1, 4 do
        local u = "party" .. i .. "target"
        if UnitExists(u) then Observe(u); if Layer.id then return end end
    end
    for _, u in pairs(SOFT) do if UnitExists(u) then Observe(u) end end
end
Layer._Scan = Scan   -- für Tests
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, Scan) end

local watch = CreateFrame("Frame")
ns.RegisterEvents(watch, "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PARTY_INVITE_REQUEST",
    "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED",
    "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_DETAIL", "QUEST_GREETING", "QUEST_PROGRESS", "TAXIMAP_OPENED",
    "BANKFRAME_OPENED", "TRAINER_SHOW")
watch:SetScript("OnEvent", function(_, event, unit)
    if SOFT[event] then Observe(SOFT[event])
    elseif NPC_EVENTS[event] then Observe("npc")
    elseif event == "PARTY_INVITE_REQUEST" then
        if Layer.OnInvite then Layer.OnInvite(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then Observe("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then Observe("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then Observe(unit)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if Layer.OnGroup then Layer.OnGroup() end
    else
        -- neue Zone: alte Layer-Zahl gilt dort nicht mehr
        Layer.id, Layer.map = nil, nil
        if C_Timer and C_Timer.After then C_Timer.After(2, Scan) end
        -- der Gilde die neue Zone melden (Layer noch unbekannt)
        C_Timer.After(3, function() if Layer.Share then Layer.Share() end end)
    end
end)

function Layer.Text()
    if not Layer.id then return L["unbekannt"] end
    return Layer.id
end

---------------------------------------------------------------------
-- Layer der Gildenmitglieder (über die Gilde: LYG = Zone + Layer, LYGQ = Abfrage)
---------------------------------------------------------------------
Layer.guild = {}   -- ["Name"] = { map, id, t }
local GUILD_MAX_AGE = 15 * 60   -- ältere Meldungen gelten als veraltet (offline, ausgeloggt)

local function MyShare()
    local map = MapId() or 0
    return map, (Layer.map == map and Layer.id) or ""
end

local lastShared, lastShareAt, sharePending = nil, 0, false
function Layer.Share(force)
    if Layer.SharePublic then Layer.SharePublic() end
    if not ns.IS_FOREVER or not IsInGuild() or not ns.QueueLatest then return end
    local map, id = MyShare()
    local key = map .. ":" .. id
    if not force and key == lastShared then return end
    -- höchstens alle 10 s senden; den letzten Stand dann nachholen
    local wait = 10 - (GetTime() - lastShareAt)
    if wait > 0 then
        if not sharePending then
            sharePending = true
            C_Timer.After(wait + 0.1, function() sharePending = false; Layer.Share(force) end)
        end
        return
    end
    lastShared, lastShareAt = key, GetTime()
    ns.QueueLatest("LYG", nil, ns.CLIENT_TAG, map, id, GetServerTime())
end

ns.On("LYG", function(payload, sender)
    if sender == ns.Me() then return end
    local tag, map, id = strsplit(SEP, payload or "")
    if tag ~= ns.CLIENT_TAG then return end
    map = tonumber(map)
    if map and (map <= 0 or map > 999999) then map = nil end
    -- die Layer-Zahl ist immer eine Ziffernfolge (Teil der Kreatur-GUID)
    if type(id) ~= "string" or not id:match("^%d+$") or #id > 10 then id = nil end
    Layer.guild[sender] = { map = map, id = id, t = GetTime() }
    if Layer.RefreshList then Layer.RefreshList() end
end)

ns.On("LYGQ", function(_, sender)
    if sender == ns.Me() then return end
    C_Timer.After(0.3 + math.random() * 2, function()
        local map, id = MyShare()
        ns.QueueLatest("LYG", sender, ns.CLIENT_TAG, map, id, GetServerTime())
    end)
end)

local lastGuildAsk = 0
function Layer.AskGuild()
    if not ns.IS_FOREVER or not IsInGuild() or not ns.QueueLatest then return end
    if GetTime() - lastGuildAsk < 30 then return end
    lastGuildAsk = GetTime()
    ns.QueueLatest("LYGQ", nil, GetServerTime())
    Layer.Share(true)
end

-- Gildenmitglieder mit bekanntem Stand, aktuelle zuerst: gleiche Zone, dann Name
function Layer.GuildList()
    local list, now, myMap = {}, GetTime(), MapId()
    for name, e in pairs(Layer.guild) do
        if now - e.t <= GUILD_MAX_AGE then
            list[#list + 1] = { name = name, map = e.map, id = e.id, here = e.map ~= nil and e.map == myMap }
        else
            Layer.guild[name] = nil
        end
    end
    table.sort(list, function(a, b)
        if a.here ~= b.here then return a.here end
        return a.name < b.name
    end)
    return list
end

-- Zähler: wie oft geholfen, wie oft bedankt, wie oft selbst gewechselt
function Layer.Stats()
    if not GuildPrideDB then return { helped = 0, thanks = 0, switched = 0 } end
    local s = GuildPrideDB.layerStats
    if type(s) ~= "table" then s = {}; GuildPrideDB.layerStats = s end
    s.helped, s.thanks, s.switched = tonumber(s.helped) or 0, tonumber(s.thanks) or 0, tonumber(s.switched) or 0
    return s
end
function Layer.StatsText()
    local s = Layer.Stats()
    return (L["Du hast %d-mal beim Layer-Wechsel geholfen (%d Dankeschöns) und %d-mal selbst gewechselt."])
        :format(s.helped, s.thanks, s.switched)
end

---------------------------------------------------------------------
-- Nachrichten (offener Kanal + Flüstern, auch von Nicht-Mitgliedern)
---------------------------------------------------------------------
local function Available()
    -- Layer-Wechsel gehört zur Gruppensuche: nur mit „Serverweite Gruppensuche“ an
    return ns.IS_FOREVER and ns.PublicLFGOn and ns.PublicLFGOn() and ns.PublicChannelId and ns.PublicChannelId()
        and not ns.PUBLIC_VIA_CHAT
end

local function Send(kind, to, ...)
    if to then ns.QueuePublicTo(to, kind, ...) else ns.Queue(kind, "@PUBLIC", ...) end
end

---------------------------------------------------------------------
-- Serverweit: alle mit GuildPride im offenen Kanal melden Zone + Layer
-- im offenen Kanal (LYS). LYP fragt alle; geantwortet wird öffentlich und
-- höchstens einmal pro Minute, eine Antwort reicht für alle Fragenden.
---------------------------------------------------------------------
Layer.public = {}   -- ["Name"] = { map, id, t }
local PUBLIC_MAX = 400
local publicCount = 0

-- Alle im serverweiten GuildPride-Kanal teilen (abschalten: /gp server)
local function SharesPublic()
    return Available() and GuildPrideDB and GuildPrideDB.publicLFG and not IsInInstance()
end

local lastPubKey, lastPubAt, pubPending = nil, 0, false
function Layer.SharePublic(force)
    if not SharesPublic() then return end
    local map, id = MyShare()
    local key = map .. ":" .. id
    if not force and key == lastPubKey then return end
    -- höchstens alle 30 s; den letzten Stand dann nachholen
    local wait = 30 - (GetTime() - lastPubAt)
    if wait > 0 then
        if not pubPending then
            pubPending = true
            C_Timer.After(wait + 0.1, function() pubPending = false; Layer.SharePublic(force) end)
        end
        return
    end
    lastPubKey, lastPubAt = key, GetTime()
    Send("LYS", nil, ns.CLIENT_TAG, map, id)
end

local function StorePublic(sender, map, id)
    if type(sender) ~= "string" or Secret(sender) or #sender > 60 or sender:find("|", 1, true) then return end
    map = tonumber(map)
    if map and (map <= 0 or map > 999999) then map = nil end
    if type(id) ~= "string" or not id:match("^%d+$") or #id > 10 then id = nil end
    if not Layer.public[sender] then
        if publicCount >= PUBLIC_MAX then return end
        publicCount = publicCount + 1
    end
    Layer.public[sender] = { map = map, id = id, t = GetTime() }
    if Layer.RefreshList then Layer.RefreshList() end
end
Layer.StorePublic = StorePublic

local lastPubAnswer, lastPubAsk = 0, 0
local function AnswerPublic()
    if GetTime() - lastPubAnswer < 60 then return end
    lastPubAnswer = GetTime()
    C_Timer.After(1 + math.random() * 9, function() Layer.SharePublic(true) end)
end
Layer.AnswerPublic = AnswerPublic

-- Gilde und Server fragen (Liste öffnen / Aktualisieren)
local lastVerAsk = 0
function Layer.AskAll()
    Layer.AskGuild()
    -- Wer in der Gilde hat überhaupt GuildPride? (Versionsabfrage, alle antworten)
    if IsInGuild() and ns.VERSION and GetTime() - lastVerAsk > 120 then
        lastVerAsk = GetTime()
        ns.Queue("VER", nil, ns.VERSION, "")
    end
    if not Available() or GetTime() - lastPubAsk < 60 then return end
    lastPubAsk = GetTime()
    Send("LYP", nil, ns.CLIENT_TAG)
    Layer.SharePublic(true)
end

-- Gilde + Server zusammen: gleiche Zone zuerst, dann Gilde, dann Name
function Layer.AllList()
    local list, seen, now, myMap = {}, {}, GetTime(), MapId()
    for _, e in ipairs(Layer.GuildList()) do
        e.guild = true
        seen[e.name] = true
        list[#list + 1] = e
    end
    -- Gildenmitglieder mit GuildPride (aus der Versionsabfrage), die online sind,
    -- aber (noch) keinen Layer melden – z. B. ältere Versionen ohne Layer-Teilen
    if ns.Versions and GetNumGuildMembers then
        for i = 1, GetNumGuildMembers() do
            local rname, _, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
            local full = rname and (ns.FullName and ns.FullName(rname) or rname)
            local v = full and ns.Versions[full]
            if online and v and not seen[full] and full ~= ns.Me() then
                seen[full] = true
                local a, b = v:match("^(%d+)%.(%d+)")
                local old = tonumber(a) < 2 or (tonumber(a) == 2 and tonumber(b) < 17)
                list[#list + 1] = { name = full, guild = true, here = false,
                    zoneText = type(zone) == "string" and zone or nil, old = old and v or nil }
            end
        end
    end
    for name, e in pairs(Layer.public) do
        if now - e.t > GUILD_MAX_AGE then
            Layer.public[name] = nil
            publicCount = publicCount - 1
        elseif not seen[name] and name ~= ns.Me() then
            local guild = ns.IsGuildMember and ns.IsGuildMember(name) or false
            list[#list + 1] = { name = name, map = e.map, id = e.id, guild = guild,
                here = e.map ~= nil and e.map == myMap }
        end
    end
    table.sort(list, function(a, b)
        if a.here ~= b.here then return a.here end
        if a.guild ~= b.guild then return a.guild end
        return a.name < b.name
    end)
    return list
end

-- Laufende Anfrage (ich will wechseln)
local req          -- { started, map, from, offers = { [name] = layer }, asked, joinedAt }
-- Wem ich als Helfer geantwortet habe: [Name] = Zeit
local answered = {}
-- Wen ich als Helfer eingeladen habe: [Name] = Zeit (für den Dank)
local invited = {}
local lastAsk = 0

local function Reset(msg)
    if msg then ns.Print(msg) end
    req = nil
end

local function CanHelp()
    if not (GuildPrideDB and GuildPrideDB.layerHelp) or not Layer.id or InCombatLockdown() or IsInInstance() then return false end
    if Layer.map ~= MapId() then return false end
    if IsInGroup() then
        if not UnitIsGroupLeader("player") then return false end
        if GetNumGroupMembers() >= (IsInRaid() and 40 or 5) then return false end
    end
    return true
end

StaticPopupDialogs["GUILDPRIDE_LAYER_INVITE"] = {
    text = L["%s (GuildPride) möchte auf deinen Layer wechseln. Einladen? Die Person verlässt die Gruppe danach von selbst."],
    button1 = L["Einladen"], button2 = L["Nein"],
    OnAccept = function(_, name)
        local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if invite then invite(Ambiguate(name, "none")) end
        invited[name] = GetTime()
        local s = Layer.Stats(); s.helped = s.helped + 1
    end,
    timeout = 30, whileDead = true, hideOnEscape = true,
}

-- Automatisch einladen bzw. annehmen. Sperrt WoW das (ADDON_ACTION_BLOCKED kommt
-- noch während des Aufrufs), fällt das Addon für diese Sitzung auf einen Klick zurück.
local trying, gotBlocked = false, false
local noAuto = {}   -- ["invite"] / ["accept"] = true: in dieser Sitzung gesperrt
local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:SetScript("OnEvent", function(_, _, addon) if trying and addon == ADDON then gotBlocked = true end end)
local function Try(key, fn, ...)
    if noAuto[key] or not fn then return false end
    trying, gotBlocked = true, false
    local ok = pcall(fn, ...)
    trying = false
    if not ok or gotBlocked then noAuto[key] = true; return false end
    return true
end
local InviteFn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit

function ns.OnLayerMessage(message, sender, whisper)
    if not ns.IS_FOREVER or sender == ns.Me() then return end
    local kind, value = message:match("^(LY%u):(.*)$")
    if not kind then return end
    local f = { strsplit(SEP, value) }
    if f[1] ~= ns.CLIENT_TAG then return end
    local map = tonumber(f[2])

    if kind == "LYQ" and not whisper then
        -- Jemand sucht einen anderen Layer: nur antworten, wenn ich wirklich helfen kann
        if not CanHelp() or map ~= Layer.map or (f[3] ~= "" and f[3] == Layer.id) then return end
        -- Wunsch-Layer (gezielter Wechsel): nur antworten, wer genau dort steht
        if f[4] and f[4] ~= "" and f[4] ~= Layer.id then return end
        if (answered[sender] or 0) > GetTime() - 30 then return end
        answered[sender] = GetTime()
        C_Timer.After(0.5 + math.random() * 2.5, function()
            if CanHelp() then Send("LYA", sender, ns.CLIENT_TAG, Layer.map, Layer.id) end
        end)
    elseif kind == "LYS" and not whisper then
        StorePublic(sender, f[2], f[3])
    elseif kind == "LYP" and not whisper then
        if SharesPublic() then AnswerPublic() end
    elseif kind == "LYA" and whisper then
        if not req or req.asked or map ~= req.map then return end
        local layer = f[3]
        if layer == "" or layer == req.from then return end
        if req.want and layer ~= req.want then return end
        req.offers[sender] = layer
    elseif kind == "LYR" and whisper then
        -- Bitte um Einladung: nur, wenn ich dem Fragenden vorher angeboten habe
        if (answered[sender] or 0) < GetTime() - 90 or not CanHelp() then return end
        answered[sender] = nil
        local short = Ambiguate(sender, "none")
        if Try("invite", InviteFn, short) then
            invited[sender] = GetTime()
            local s = Layer.Stats(); s.helped = s.helped + 1
            ns.Print((L["Layer-Hilfe: %s automatisch eingeladen – die Person wechselt auf deinen Layer und verlässt die Gruppe danach von selbst."]):format(short))
        else
            -- WoW lässt das automatische Einladen nicht zu: ein Klick genügt
            StaticPopup_Show("GUILDPRIDE_LAYER_INVITE", short, nil, sender)
            if GuildPrideDB.sound then PlaySound(SOUNDKIT.TELL_MESSAGE) end
        end
    elseif kind == "LYT" and whisper then
        -- Dank nach erfolgreichem Wechsel: nur von jemandem, den ich eingeladen habe
        if (invited[sender] or 0) < GetTime() - 600 then return end
        invited[sender] = nil
        local s = Layer.Stats(); s.thanks = s.thanks + 1
        ns.Print((L["%s hat dank dir den Layer gewechselt und bedankt sich! (%d Dankeschöns bisher)"]):format(Ambiguate(sender, "none"), s.thanks))
    end
end

---------------------------------------------------------------------
-- Anfrage stellen
---------------------------------------------------------------------
local function PickHelper()
    if not req then return end
    req.asked = true
    -- Ein Layer, der sich vom eigenen unterscheidet; bei mehreren Helfern zufällig
    local names = {}
    for name in pairs(req.offers) do names[#names + 1] = name end
    if #names == 0 then
        return Reset(req.want and (L["Layer wechseln: Auf Layer %s kann gerade niemand mit GuildPride helfen. Später noch einmal versuchen."]):format(req.want)
            or L["Layer wechseln: Niemand mit GuildPride in dieser Zone kann gerade helfen. Später noch einmal versuchen."])
    end
    local layers = {}
    for _, layer in pairs(req.offers) do layers[layer] = true end
    local count = 0
    for _ in pairs(layers) do count = count + 1 end
    local helper = names[math.random(#names)]
    req.helper, req.target = helper, req.offers[helper]
    Send("LYR", helper, ns.CLIENT_TAG, req.map)
    ns.Print((L["Layer wechseln: %d Helfer auf %d anderen Layer(n) gefunden. %s lädt dich ein, der Rest läuft automatisch."])
        :format(#names, count, Ambiguate(helper, "none")))
    C_Timer.After(45, function()
        if req and not req.joinedAt then
            Reset(L["Layer wechseln: Keine Einladung angenommen – abgebrochen. Einfach noch einmal versuchen."])
        end
    end)
end

-- Ein Klick schaltet alles frei: serverweiter GuildPride-Kanal + anderen helfen.
-- Gibt true zurück, wenn der Kanal schon bereit ist (sonst dauert der Beitritt ein paar Sekunden).
function Layer.EnableAll()
    if not GuildPrideDB then return false end
    if not GuildPrideDB.publicLFG then
        GuildPrideDB.publicLFG = true
        if ns.PublicLFGChanged then ns.PublicLFGChanged() end
    end
    GuildPrideDB.layerHelp = true
    if ns.RefreshUI then ns.RefreshUI() end
    if ns.LayerUpdateDisplay then ns.LayerUpdateDisplay() end
    return Available() and true or false
end

function Layer.HelpActive()
    return GuildPrideDB and GuildPrideDB.layerHelp and Available() and true or false
end

-- want: gewünschter Layer (gezielt zu einem Mitglied oder Rare), sonst irgendein anderer
function Layer.Request(retried, want)
    if want == "" then want = nil end
    if not ns.IS_FOREVER then ns.Print(L["Layer wechseln gibt es nur in WoW Forever."]); return end
    if not Available() then
        -- Kanal aus: automatisch einschalten und nach dem Beitritt noch einmal versuchen
        if not retried and not ns.PUBLIC_VIA_CHAT then
            Layer.EnableAll()
            ns.Print(L["Serverweiter GuildPride-Kanal wird eingeschaltet – Layer wechseln startet gleich …"])
            C_Timer.After(6, function() Layer.Request(true, want) end)
            return
        end
        ns.Print(L["Layer wechseln braucht den serverweiten GuildPride-Kanal: Einstellungen > Serverweite Gruppensuche einschalten."])
        return
    end
    if IsInInstance() then ns.Print(L["In einer Instanz gibt es keine Layer."]); return end
    if IsInGroup() then ns.Print(L["Zum Layer-Wechsel bitte zuerst die Gruppe verlassen."]); return end
    if req then ns.Print(L["Layer wechseln läuft schon …"]); return end
    if GetTime() - lastAsk < 20 then ns.Print(L["Bitte kurz warten, bevor du erneut fragst."]); return end
    local map = MapId()
    if not map then return end
    local from = (Layer.map == map) and Layer.id or nil
    if want and want == from then ns.Print((L["Du bist schon auf Layer %s."]):format(want)); return end
    lastAsk = GetTime()
    req = { started = GetTime(), map = map, from = from, want = want, offers = {} }
    Send("LYQ", nil, ns.CLIENT_TAG, map, from or "", want or "")
    ns.Print(from and (L["Layer wechseln: Suche Helfer (dein Layer: %s) …"]):format(from)
        or L["Layer wechseln: Suche Helfer … (Tipp: vorher eine Kreatur anvisieren, dann wird dein Layer erkannt)"])
    -- Antworten sammeln (Kanaltakt 2 s + Zufallsverzögerung der Helfer)
    C_Timer.After(8, PickHelper)
end

-- Einladung vom gewählten Helfer: automatisch annehmen (sonst klickt man selbst)
function Layer.OnInvite(inviter)
    if not req or not req.helper or type(inviter) ~= "string" or Secret(inviter) then return end
    if ns.Normalize(inviter) ~= req.helper and Ambiguate(inviter, "none") ~= Ambiguate(req.helper, "none") then return end
    if Try("accept", AcceptGroup) then
        StaticPopup_Hide("PARTY_INVITE")
        C_Timer.After(0, function() StaticPopup_Hide("PARTY_INVITE") end)
    else
        ns.Print(L["Layer wechseln: Bitte die Einladung annehmen."])
    end
end

local function LeaveGroup()
    local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if not (leave and pcall(leave)) then
        ns.Print(L["Layer wechseln: Gruppe konnte nicht automatisch verlassen werden – bitte /gp layer raus eingeben."])
    end
end

-- Während des Wartens selbst nach Kreaturen schauen (Namensplaketten, Ziel),
-- damit der neue Layer auch ohne Anklicken erkannt wird
local function Poll()
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit then Observe(unit) end
        end
    end
    Observe("target")
end

-- Beitritt erkannt -> auf den neuen Layer warten, dann wieder austreten
function Layer.OnGroup()
    if not req or not req.helper then return end
    if IsInGroup() and not req.joinedAt then
        req.joinedAt = GetTime()
        local mine = req
        ns.Print(L["Layer wechseln: In der Gruppe. Warte auf den Wechsel – die Gruppe wird danach automatisch verlassen."])
        mine.ticker = C_Timer.NewTicker(2, function()
            if req ~= mine or not IsInGroup() then
                if mine.ticker then mine.ticker:Cancel() end
                return
            end
            Poll()
        end, 45)
        -- Kein Wechsel erkannt: trotzdem austreten (Layer meist längst gewechselt)
        C_Timer.After(90, function()
            if req == mine and IsInGroup() then
                Reset(L["Layer wechseln: Wechsel nicht sicher erkannt – Gruppe wird trotzdem verlassen. Eine Kreatur anvisieren zeigt deinen Layer."])
                LeaveGroup()
            end
        end)
    elseif not IsInGroup() and req.joinedAt then
        Reset()
    end
end

function Layer.OnChange()
    if not req or not req.joinedAt or not IsInGroup() then return end
    -- Geschafft, wenn ich auf dem Layer des Helfers bin oder (alter Layer bekannt)
    -- nicht mehr auf meinem alten
    if Layer.map ~= req.map then return end
    if Layer.id ~= req.target and not (req.from and Layer.id ~= req.from) then return end
    ns.Print((L["Layer gewechselt (jetzt %s). Gruppe wird verlassen – danke an %s!"]):format(Layer.id, Ambiguate(req.helper, "none")))
    Send("LYT", req.helper, ns.CLIENT_TAG, req.map)
    local s = Layer.Stats(); s.switched = s.switched + 1
    req = nil
    C_Timer.After(1.5, function() if IsInGroup() then LeaveGroup() end end)
end

---------------------------------------------------------------------
-- Knopf in der Gruppensuche und /gp layer
---------------------------------------------------------------------
if ns.IS_FOREVER and ns.GroupPage then
    local b = CreateFrame("Button", nil, ns.GroupPage, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetSize(140, 24)
    -- an der Seite verankert, nicht am sicheren Dungeonbrowser-Knopf (der wird im Kampf geparkt)
    b:SetPoint("TOPRIGHT", -(2 + (ns.GroupBrowserWidth and ns.GroupBrowserWidth + 6 or 0)), -52)
    b:SetText(L["Layer wechseln"])
    b:SetScript("OnClick", function() Layer.Request() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Layer wechseln"], 1, 1, 1)
        GameTooltip:AddLine((L["Dein Layer: %s"]):format(Layer.Text()), 0.9, 0.8, 0.5)
        GameTooltip:AddLine(L["Fragt alle mit GuildPride in deiner Zone. Jemand auf einem anderen Layer lädt dich ein, nach dem Wechsel verlässt du die Gruppe automatisch."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

-- Knopf in der Seitenleiste des Gildenfensters, direkt über „Einstellungen“.
-- Er hängt am Einstellungen-Reiter und wandert mit, wenn das Layout wechselt.
local parts = ns.UIParts
local setTab = parts and ns.SettingsPage and parts.tabs and parts.tabs[ns.SettingsPage.tabId]
if ns.IS_FOREVER and setTab then
    local b = CreateFrame("Button", nil, parts.frame, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetHeight(24)
    b:SetPoint("BOTTOMLEFT", setTab, "TOPLEFT", 0, 6)
    b:SetPoint("BOTTOMRIGHT", setTab, "TOPRIGHT", 0, 6)
    b:SetText(L["Layer wechseln"])
    b:SetScript("OnSizeChanged", function() if ns.LayerUpdateDisplay then ns.LayerUpdateDisplay() end end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button) if button == "RightButton" then Layer.ToggleList() else Layer.Request() end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Layer wechseln"], 1, 1, 1)
        GameTooltip:AddLine((L["Dein Layer: %s"]):format(Layer.Text()), 0.9, 0.8, 0.5)
        GameTooltip:AddLine(L["Klick: Ein anderer GuildPride-Spieler lädt dich automatisch ein, nach dem Wechsel verlässt du die Gruppe von selbst."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Rechtsklick: Layer-Liste"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    Layer.sideButton = b

    -- Darüber: "Layer helfen" – ein Klick gibt alles frei (Kanal + Hilfe), noch ein Klick schaltet die Hilfe ab
    local h = CreateFrame("Button", nil, parts.frame, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(h) end
    h:SetHeight(24)
    h:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 4)
    h:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 4)
    h:SetScript("OnClick", function(self)
        if Layer.HelpActive() then
            GuildPrideDB.layerHelp = false
            if ns.RefreshUI then ns.RefreshUI() end
            ns.Print(L["Du hilfst anderen nicht mehr beim Layer-Wechsel."])
        elseif ns.PUBLIC_VIA_CHAT then
            ns.Print(L["Layer wechseln braucht den serverweiten GuildPride-Kanal: Einstellungen > Serverweite Gruppensuche einschalten."])
        else
            local ready = Layer.EnableAll()
            ns.Print(ready and L["Layer helfen ist an: Andere mit GuildPride auf dem Server können über dich den Layer wechseln (lädt automatisch ein)."]
                or L["Layer helfen wird eingeschaltet: serverweiter GuildPride-Kanal wird betreten …"])
        end
        if ns.LayerUpdateDisplay then ns.LayerUpdateDisplay() end
        if GameTooltip:GetOwner() == self then self:GetScript("OnEnter")(self) end
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Layer helfen"], 1, 1, 1)
        GameTooltip:AddLine(Layer.HelpActive() and ("|cff40ff40" .. L["An"] .. "|r") or ("|cff999999" .. L["Aus"] .. "|r"))
        GameTooltip:AddLine(L["Ein Klick schaltet alles frei: serverweiter GuildPride-Kanal und Hilfe für andere. Wer auf einem anderen Layer wechseln will, wird von dir automatisch eingeladen und verlässt die Gruppe danach von selbst."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Noch ein Klick: Hilfe abschalten"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(Layer.StatsText(), 0.9, 0.8, 0.5, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", GameTooltip_Hide)
    Layer.helpButton = h
    -- Platz über „Einstellungen“: zwei Knöpfe (6 + 24 + 4 + 24 px), damit das Menü oben nicht hineinrutscht
    ns.SidebarBottomExtra = 58
    if parts.LayoutTabs then parts.LayoutTabs() end
end

---------------------------------------------------------------------
-- Fenster "Layer der Gilde": wer mit GuildPride wo auf welchem Layer ist,
-- "Hierhin" wechselt gezielt auf den Layer eines Mitglieds (gleiche Zone)
---------------------------------------------------------------------
local list
local LIST_ROWS = 12

local function ZoneName(map)
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or L["unbekannt"]
end

local function RefreshList()
    if not list or not list:IsShown() then return end
    local entries = Layer.AllList()
    local myMap = MapId()
    list.mine:SetText(("%s |cff40ff40%s|r  ·  %s"):format(L["Dein Layer:"], Layer.Text(), ZoneName(myMap)))
    local maxOff = math.max(0, #entries - LIST_ROWS)
    list.offset = math.min(list.offset or 0, maxOff)
    for i = 1, LIST_ROWS do
        local row, e = list.rows[i], entries[i + list.offset]
        if e then
            local same = e.id and e.id == Layer.id and e.here
            local idTxt = e.id and ((same and "|cff40ff40" or "|cffffd100") .. e.id .. "|r") or "|cff999999?|r"
            -- Gildenmitglieder grün, alle anderen mit GuildPride weiß
            row.name:SetText((ns.NameMark and ns.NameMark(e.name) or "") .. (e.guild and "|cff60d060" or "|cffe6e0da") .. Ambiguate(e.name, "none") .. "|r")
            local zoneTxt = e.zoneText or ZoneName(e.map)
            row.zone:SetText(e.here and ("|cffe6e0da" .. zoneTxt .. "|r") or ("|cff888888" .. zoneTxt .. "|r"))
            -- Ältere GuildPride-Version teilt keinen Layer
            row.layer:SetText(e.old and ("|cffff8040" .. L["alt"] .. "|r") or idTxt)
            -- Wechsel nur in derselben Zone und auf einen anderen, bekannten Layer
            row.go.want = (e.here and e.id and e.id ~= Layer.id) and e.id or nil
            row.go:SetShown(row.go.want ~= nil)
            row:Show()
        else
            row:Hide()
        end
    end
    local more = #entries - LIST_ROWS - list.offset
    list.empty:SetShown(#entries == 0)
    local guildN = 0
    for _, e in ipairs(entries) do if e.guild then guildN = guildN + 1 end end
    list.more:SetText((L["%d Spieler mit GuildPride (%d aus der Gilde, grün)"]):format(#entries, guildN)
        .. (more > 0 and ("  ·  " .. (L["… und %d weitere"]):format(more) .. " " .. L["(Mausrad)"]) or ""))
    list.stats:SetText(Layer.StatsText())
end
Layer.RefreshList = RefreshList

local function ToggleList()
    if not ns.IS_FOREVER then return end
    if not list then
        list = CreateFrame("Frame", "GuildPrideLayerList", UIParent, "BackdropTemplate")
        list:SetSize(380, 130 + LIST_ROWS * 22)
        list:SetPoint("CENTER", 0, 60)
        list:SetFrameStrata("DIALOG")
        list:SetMovable(true); list:EnableMouse(true); list:SetClampedToScreen(true)
        list:RegisterForDrag("LeftButton")
        list:SetScript("OnDragStart", list.StartMoving)
        list:SetScript("OnDragStop", list.StopMovingOrSizing)
        if ns.SkinDialog then ns.SkinDialog(list) end
        tinsert(UISpecialFrames, "GuildPrideLayerList")   -- Escape schließt
        local close = CreateFrame("Button", nil, list, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local title = list:CreateFontString(nil, "OVERLAY", "GPFont_Large")
        title:SetPoint("TOPLEFT", 14, -14)
        title:SetText(L["Layer der GuildPride-Spieler"])
        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(_, delta)
            list.offset = math.max(0, (list.offset or 0) - delta * 3)
            RefreshList()
        end)
        list.mine = list:CreateFontString(nil, "OVERLAY", "GPFont_Text")
        list.mine:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        list.rows = {}
        for i = 1, LIST_ROWS do
            local row = CreateFrame("Frame", nil, list)
            row:SetSize(352, 20)
            row:SetPoint("TOPLEFT", 14, -58 - (i - 1) * 22)
            row.name = row:CreateFontString(nil, "OVERLAY", "GPFont_Text")
            row.name:SetPoint("LEFT", 0, 0); row.name:SetWidth(120); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
            row.zone = row:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
            row.zone:SetPoint("LEFT", 124, 0); row.zone:SetWidth(110); row.zone:SetJustifyH("LEFT"); row.zone:SetWordWrap(false)
            row.layer = row:CreateFontString(nil, "OVERLAY", "GPFont_Text")
            row.layer:SetPoint("LEFT", 238, 0); row.layer:SetWidth(46); row.layer:SetJustifyH("LEFT")
            row.go = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(row.go) end
            row.go:SetSize(66, 18)
            row.go:SetPoint("RIGHT", 0, 0)
            row.go:SetText(L["Hierhin"])
            row.go:SetScript("OnClick", function(self) if self.want then Layer.Request(nil, self.want) end end)
            list.rows[i] = row
        end
        list.empty = list:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
        list.empty:SetPoint("TOPLEFT", 14, -62); list.empty:SetPoint("RIGHT", -14, 0)
        list.empty:SetJustifyH("LEFT")
        list.empty:SetText(L["Noch keine Meldungen – Spieler mit GuildPride melden ihren Layer, sobald er erkannt ist (serverweit ab GuildPride 2.19)."])
        list.more = list:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        list.more:SetPoint("TOPLEFT", 14, -60 - LIST_ROWS * 22)
        list.stats = list:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        list.stats:SetPoint("BOTTOMLEFT", 14, 40); list.stats:SetPoint("RIGHT", -14, 0)
        list.stats:SetJustifyH("LEFT")
        local any = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(any) end
        any:SetSize(170, 22)
        any:SetPoint("BOTTOMLEFT", 14, 12)
        any:SetText(L["Irgendein anderer Layer"])
        any:SetScript("OnClick", function() Layer.Request() end)
        local refresh = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(refresh) end
        refresh:SetSize(110, 22)
        refresh:SetPoint("BOTTOMRIGHT", -14, 12)
        refresh:SetText(L["Aktualisieren"])
        refresh:SetScript("OnClick", function() Layer.AskAll(); RefreshList() end)
        list:SetScript("OnShow", function() list.offset = 0; Layer.AskAll(); RefreshList() end)
        list:Hide()
    end
    list:SetShown(not list:IsShown())
end
Layer.ToggleList = ToggleList

---------------------------------------------------------------------
-- Layer-Anzeige: kleine Zeile unter der Minimap (verschiebbar, abschaltbar)
---------------------------------------------------------------------
local display
local function DisplayText()
    if Layer.id then return ("|cff40ff40%s|r"):format(Layer.id) end
    return "|cff999999?|r"
end

local function UpdateDisplay()
    local sb = Layer.sideButton
    if sb then
        local w = sb:GetWidth() or 0
        sb:SetText(w < 100 and L["Layer"] or (Layer.id and ("%s (%s)"):format(L["Layer wechseln"], Layer.id) or L["Layer wechseln"]))
    end
    local hb = Layer.helpButton
    if hb then
        hb:SetText(Layer.HelpActive() and ("%s: |cff40ff40%s|r"):format(L["Layer helfen"], L["An"])
            or ("%s: |cff999999%s|r"):format(L["Layer helfen"], L["Aus"]))
    end
    if list and list:IsShown() then RefreshList() end
    if display and display:IsShown() then
        display.text:SetText(("%s %s"):format(L["Layer:"], DisplayText()))
        display:SetWidth(display.text:GetStringWidth() + 12)
    end
end
ns.LayerUpdateDisplay = UpdateDisplay

local function PlaceDisplay()
    if not display or not GuildPrideDB then return end
    display:ClearAllPoints()
    local pos = GuildPrideDB.layerShowPos
    if pos then display:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else display:SetPoint("TOP", Minimap, "BOTTOM", 0, -22) end
    display:SetShown(GuildPrideDB.layerShow ~= false)
    UpdateDisplay()
end
ns.LayerShowChanged = PlaceDisplay

if ns.IS_FOREVER then
    display = CreateFrame("Button", "GuildPrideLayerDisplay", UIParent)
    display:SetSize(80, 18)
    display:SetFrameStrata("MEDIUM")
    display:SetMovable(true); display:SetClampedToScreen(true)
    display:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    display:RegisterForDrag("LeftButton")
    local bg = display:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    display.text = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    display.text:SetPoint("CENTER")
    display:Hide()
    display:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    display:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        GuildPrideDB.layerShowPos = { point, x, y }
    end)
    display:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GuildPrideDB.layerShow = false
            PlaceDisplay()
            ns.Print(L["Layer-Anzeige ausgeblendet. Wieder einblenden mit /gp layer anzeige oder in den Einstellungen."])
        else
            Layer.ToggleList()
        end
    end)
    display:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((L["Dein Layer: %s"]):format(Layer.Text()), 1, 1, 1)
        GameTooltip:AddLine(L["Die Zahl kommt vom Server: gleiche Zahl = gleicher Layer (nur innerhalb einer Zone vergleichbar). Erkannt über Kreaturen in der Nähe – eine Kreatur anvisieren aktualisiert sie."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Klick: Layer-Liste (gezielt wechseln)"], 1, 1, 1)
        GameTooltip:AddLine(L["Umschalt+Ziehen: verschieben"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Rechtsklick: ausblenden"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(Layer.StatsText(), 0.9, 0.8, 0.5, true)
        GameTooltip:Show()
    end)
    display:SetScript("OnLeave", GameTooltip_Hide)
    local login = CreateFrame("Frame")
    login:RegisterEvent("PLAYER_LOGIN")
    login:SetScript("OnEvent", function()
        PlaceDisplay()
        -- Layer ändert sich durch Zielwechsel, Zonenwechsel usw.: einmal pro Sekunde nachziehen
        C_Timer.NewTicker(1, UpdateDisplay)
    end)
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd ~= "layer" then return slash(arg) end
    if rest == "" or rest == "wechseln" or rest == "switch" then
        Layer.Request()
    elseif rest == "liste" or rest == "list" or rest == "gilde" or rest == "guild" then
        ToggleList()
    elseif rest == "anzeige" or rest == "display" then
        GuildPrideDB.layerShow = GuildPrideDB.layerShow == false
        ns.LayerShowChanged()
        ns.Print(GuildPrideDB.layerShow and L["Layer-Anzeige eingeblendet (unter der Minimap, Umschalt+Ziehen zum Verschieben)."]
            or L["Layer-Anzeige ausgeblendet. Wieder einblenden mit /gp layer anzeige oder in den Einstellungen."])
    elseif rest == "raus" or rest == "leave" then
        req = nil
        LeaveGroup()
    elseif rest == "an" or rest == "on" or rest == "aus" or rest == "off" then
        if rest == "an" or rest == "on" then Layer.EnableAll() else GuildPrideDB.layerHelp = false end
        if ns.LayerUpdateDisplay then ns.LayerUpdateDisplay() end
        ns.Print(GuildPrideDB.layerHelp and L["Du hilfst anderen beim Layer-Wechsel (lädt automatisch ein)."]
            or L["Du hilfst anderen nicht mehr beim Layer-Wechsel."])
    else
        ns.Print((L["Dein Layer: %s"]):format(Layer.Text()))
        ns.Print(L["/gp layer – wechseln · /gp layer liste – Layer-Liste · /gp layer anzeige – Anzeige ein/aus · /gp layer raus – Gruppe verlassen · /gp layer an|aus – anderen helfen"])
    end
end
