-- GuildPride: Notizzettel auf der Karte
-- „Zettel schreiben“ (Knopf auf der Weltkarte, Kartenfilter, /gp zettel) hängt einen
-- Zettel genau dort auf, wo du stehst. Wer bis auf ~5 m herankommt, dem geht der
-- Zettel auf: Text und als Unterschrift Vor- und Nachname des Schreibers. In der
-- Nähe zeigt die Minimap die Zettel ebenfalls.
--
-- Nachrichten (Schlüssel eines Zettels = Art + Schreiber + Nummer):
--   Gilde (abgesicherter Gildenkanal, ns.On):
--     ZTG num·map·x·y·t·text            eigener Zettel
--     ZTX num                           eigenen Zettel abreißen
--     ZTQ 1                             Abgleich: welche Zettel kennt ihr?
--     ZTR autor·num·map·x·y·t·text      Antwort: bekannter Zettel eines anderen
--   Offener Kanal (GuildPride.lua → ns.OnZettelPublic), mit Kennung der Spielversion:
--     ZTP F·num·…  ZTD F·num  ZTQ F  ZTS F·autor·num·…   (wie oben)
-- Weitergereichte Zettel (ZTR/ZTS): in der Gilde vertraut; im offenen Kanal nur von
-- Gildenmitgliedern oder wenn zwei verschiedene Spieler denselben Zettel melden –
-- so kann niemand allein Zettel unter fremdem Namen unterschieben.
-- Antworten auf den Abgleich kommen mit Zufallsverzögerung; wer sieht, dass ein
-- Zettel schon geschickt wurde, schickt ihn nicht noch einmal.
-- Abgerissene, ausgeblendete und abgelaufene Zettel merkt sich jeder (zettelGone),
-- damit sie über den Abgleich nicht wiederkommen. Zettel halten 7 Tage.
-- Abschalten: Weltkarten-Knopf (Rechtsklick), Kartenfilter, Einstellungen, /gp zettel aus
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local Z = {}
ns.Zettel = Z

local MAX_TEXT    = 140            -- Byte (Platz für den offenen Kanal: 255 Byte je Nachricht)
local LIFETIME    = 7 * 86400
local RESEND      = 15 * 60        -- eigene Zettel erneut senden
local SEND_GAP    = 3              -- s zwischen zwei eigenen Zettel-Nachrichten
local TRIGGER     = 5.5            -- Yards (~5 m)
local REARM       = 15             -- erst so weit weg, dann löst der Zettel wieder aus
local MAX_OWN     = 10
local MAX_SENDER  = 5              -- fremde Zettel je Schreiber (offener Kanal)
local MAX_PUBLIC  = 300
local MAX_SYNC    = 25             -- höchstens so viele Zettel je Abgleich-Antwort
local MEDIA       = "Interface\\AddOns\\GuildPrideForever\\Media\\"
local PAPER       = MEDIA .. "zettel"
local PIN         = MEDIA .. "zettel_pin"
local HAND        = "Fonts\\MORPHEUS.TTF"   -- wirkt handgeschrieben, hat Umlaute
local BLUE, WHITE = { 0.35, 0.65, 1 }, { 1, 1, 1 }
local INK         = { 0.12, 0.16, 0.42 }

---------------------------------------------------------------------
-- Daten und Schalter
---------------------------------------------------------------------
local function Saved(key)
    if type(GuildPrideDB) ~= "table" then return {} end
    if type(GuildPrideDB[key]) ~= "table" then GuildPrideDB[key] = {} end
    return GuildPrideDB[key]
end
local function DB() return Saved("zettel") end
local function Gone() return Saved("zettelGone") end      -- [Schlüssel] = Zeit des Zettels
local function Muted() return Saved("zettelMuted") end    -- [Name] = true

local function Opt(key)
    return not (type(GuildPrideDB) == "table" and GuildPrideDB[key] == false)
end
function Z.Enabled() return Opt("mapNotes") end
function Z.ShowPublic() return Opt("mapNotesPublic") end
function Z.ShowMinimap() return Opt("mapNotesMinimap") end

local function Me() return ns.Me and ns.Me() or UnitName("player") end
-- Unterschrift: Vor- und Nachname (WoW Forever liefert den Absender schon als
-- "Vorname Nachname", siehe ns.Normalize); sonst nur den Realm abschneiden
local function Short(name)
    if name:find(" ", 1, true) then return name end
    return (Ambiguate and Ambiguate(name, "none")) or (name:gsub("%-.*$", ""))
end

-- Text auf Bytes kürzen, ohne ein UTF-8-Zeichen zu zerschneiden
local function Cut(s, max)
    s = (ns.Clean and ns.Clean(s, 1000) or tostring(s or ""):gsub("[%c|]", "")):gsub(SEP, "")
    s = strtrim(s)
    if #s <= max then return s end
    s = s:sub(1, max)
    local i = #s
    while i > 0 and s:byte(i) >= 128 and s:byte(i) < 192 do i = i - 1 end
    if i > 0 and s:byte(i) >= 192 then
        local need = s:byte(i) >= 240 and 4 or s:byte(i) >= 224 and 3 or 2
        if #s - i + 1 < need then s = s:sub(1, i - 1) end
    end
    return s
end
Z.Cut = Cut

-- Zeichen zählen (Umlaute zählen einfach, nicht doppelt)
function Z.Chars(s)
    local _, n = tostring(s or ""):gsub("[^\128-\191]", "")
    return n
end

local function Num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v < lo or v > hi then return nil end
    return math.floor(v)
end

local function ValidMap(map)
    if not map then return false end
    if C_Map and C_Map.GetMapInfo then return C_Map.GetMapInfo(map) ~= nil end
    return true
end

local function Key(guild, author, num) return (guild and "g:" or "p:") .. author .. "#" .. num end

-- Soll dieser Zettel gezeigt werden (Schalter, Stummschaltung)?
local function Visible(n)
    if not n then return false end
    if not n.guild and not Z.ShowPublic() and n.sender ~= Me() then return false end
    if Muted()[n.sender] then return false end
    return true
end
Z.Visible = Visible

-- Abgelaufene wegräumen; bei zu vielen fremden Zetteln die ältesten
local function Prune()
    local db, gone, now = DB(), Gone(), GetServerTime()
    local public = {}
    for k, n in pairs(db) do
        if type(n) ~= "table" or not n.t or now - n.t > LIFETIME then db[k] = nil
        elseif not n.guild and n.sender ~= Me() then public[#public + 1] = k end
    end
    if #public > MAX_PUBLIC then
        table.sort(public, function(a, b) return db[a].t < db[b].t end)
        for i = 1, #public - MAX_PUBLIC do db[public[i]] = nil end
    end
    for k, t in pairs(gone) do
        if type(t) ~= "number" or now - t > LIFETIME then gone[k] = nil end
    end
end

local function Refresh()
    if ns.RefreshMapPins then ns.RefreshMapPins(true) end
    if Z.UpdateMinimap then Z.ForgetNear(); Z.UpdateMinimap() end
end

-- Wie oft wurde ein Zettel in dieser Abgleich-Runde schon geschickt?
local seenRound = {}

-- Eingang (aus beiden Kanälen). author = Schreiber (bei Weitergabe nicht der Absender).
-- Rückgabe: true, wenn neu oder geändert
function Z.Apply(guild, author, num, map, x, y, t, text)
    num, map = Num(num, 1, 999999), Num(map, 1, 99999)
    x, y = Num(x, 0, 10000), Num(y, 0, 10000)
    t = ns.Stamp and ns.Stamp(t) or tonumber(t)
    text = Cut(text, MAX_TEXT)
    if type(author) ~= "string" or author == "" then return false end
    if not (num and map and x and y and t and t > 0) or text == "" or not ValidMap(map) then return false end
    if GetServerTime() - t > LIFETIME then return false end
    if ns.Block and ns.Block.IsBlocked and ns.Block.IsBlocked(author) then return false end
    if Muted()[author] then return false end
    if not guild and not Z.ShowPublic() then return false end
    local db, key = DB(), Key(guild, author, num)
    seenRound[key] = (seenRound[key] or 0) + 1
    local gone = Gone()[key]
    if gone and gone >= t then return false end
    local old = db[key]
    if old and old.t >= t then return false end
    if not old and not guild then
        local n = 0
        for _, e in pairs(db) do if not e.guild and e.sender == author then n = n + 1 end end
        if n >= MAX_SENDER then return false end
    end
    db[key] = { num = num, map = map, x = x / 10000, y = y / 10000, t = t, text = text,
                sender = author, by = Short(author), guild = guild and true or nil }
    Prune()
    Refresh()
    return true
end

local function Forget(key, t)
    local n = DB()[key]
    Gone()[key] = math.max(t or 0, n and n.t or 0, Gone()[key] or 0)
    DB()[key] = nil
    if Z.shownKey == key and Z.reader then Z.reader:Hide() end
    Refresh()
end

function Z.Remove(guild, sender, num)
    num = Num(num, 1, 999999)
    if not num then return false end
    local key = Key(guild, sender, num)
    -- auch ohne bekannten Zettel merken: kommt er später per Abgleich, bleibt er weg
    Forget(key, GetServerTime())
    return true
end

---------------------------------------------------------------------
-- Senden (eigene Warteschlange: der offene Kanal hält je Art nur die neueste Nachricht)
---------------------------------------------------------------------
local outbox = {}
local function Push(item)
    for i = #outbox, 1, -1 do
        if outbox[i].key == item.key then table.remove(outbox, i) end
    end
    outbox[#outbox + 1] = item
end

local function Fields(n)
    return n.num, n.map, math.floor(n.x * 10000 + 0.5), math.floor(n.y * 10000 + 0.5), n.t, n.text
end

local function PublicOk() return ns.PublicChannelId and ns.PublicChannelId() and true or false end

local function SendNote(n)
    Push({ key = (n.guild and "g" or "p") .. n.num, fn = function()
        if n.guild then
            if IsInGuild() then ns.Queue("ZTG", "@CHANNEL", Fields(n)) end
        elseif PublicOk() then
            ns.Queue("ZTP", "@PUBLIC", ns.CLIENT_TAG, Fields(n))
        end
    end })
end

-- Bekannten Zettel eines anderen weiterreichen (Antwort auf den Abgleich)
local function SendRelay(key, n)
    Push({ key = "r" .. key, fn = function()
        if DB()[key] ~= n then return end                  -- inzwischen weg
        if (seenRound[key] or 0) >= (n.guild and 1 or 2) then return end   -- schon geschickt
        if n.guild then
            if IsInGuild() then ns.Queue("ZTR", "@CHANNEL", n.sender, Fields(n)) end
        elseif PublicOk() then
            ns.Queue("ZTS", "@PUBLIC", ns.CLIENT_TAG, n.sender, Fields(n))
        end
        seenRound[key] = (seenRound[key] or 0) + 1
    end })
end

local function SendRemove(guild, num)
    Push({ key = (guild and "g" or "p") .. num, fn = function()
        if guild then
            if IsInGuild() then ns.Queue("ZTX", "@CHANNEL", num) end
        else
            ns.Queue("ZTD", "@PUBLIC", ns.CLIENT_TAG, num)
        end
    end })
end

local function SendNext()
    local item = table.remove(outbox, 1)
    if item and ns.Queue then item.fn() end
    return item ~= nil
end
Z.SendNext = SendNext
C_Timer.NewTicker(SEND_GAP, SendNext)

local function OwnNotes()
    local list, me = {}, Me()
    for k, n in pairs(DB()) do
        if n.sender == me then list[#list + 1] = k end
    end
    table.sort(list, function(a, b) return DB()[a].t < DB()[b].t end)
    return list
end

-- Neuen Zettel schreiben: map + x, y (0 … 1) auf dieser Karte
function Z.Write(map, x, y, text, guild)
    text = Cut(text, MAX_TEXT)
    if text == "" or not map or not x or not y then return false end
    if guild and not IsInGuild() then return false end
    local db, me = DB(), Me()
    GuildPrideDB.zettelN = (tonumber(GuildPrideDB.zettelN) or 0) % 999999 + 1
    local num = GuildPrideDB.zettelN
    local key = Key(guild, me, num)
    db[key] = { num = num, map = map, x = x, y = y, t = GetServerTime(), text = text,
                sender = me, by = Short(me), guild = guild and true or nil }
    -- Höchstens MAX_OWN eigene: die ältesten abreißen
    local own = OwnNotes()
    for i = 1, #own - MAX_OWN do Z.Tear(own[i]) end
    Z.armed[key] = false     -- steht man gerade drauf, nicht sofort aufgehen
    SendNote(db[key])
    Refresh()
    return key
end

-- Eigenen Zettel abreißen (bei allen)
function Z.Tear(key)
    local n = DB()[key]
    if not n or n.sender ~= Me() then return false end
    Forget(key, n.t)
    SendRemove(n.guild, n.num)
    return true
end

-- Fremden Zettel nur bei dir ausblenden
function Z.Hide(key)
    if not DB()[key] then return false end
    Forget(key)
    return true
end

-- Alle Zettel dieses Spielers bei dir ausblenden (und künftige nicht annehmen)
function Z.Mute(name)
    if type(name) ~= "string" or name == "" or name == Me() then return false end
    Muted()[name] = true
    for k, n in pairs(DB()) do if n.sender == name then Forget(k) end end
    return true
end
function Z.Unmute(name) Muted()[name] = nil end

-- Eigene Zettel regelmäßig erneut verschicken (für später Eingeloggte)
local lastOwnSend = 0
local function ResendOwn()
    if not Z.Enabled() then return end
    Prune()
    lastOwnSend = GetTime()
    for _, k in ipairs(OwnNotes()) do SendNote(DB()[k]) end
end
C_Timer.NewTicker(RESEND, ResendOwn)

---------------------------------------------------------------------
-- Abgleich: beim Einloggen fragen, andere antworten mit dem, was sie kennen
---------------------------------------------------------------------
local answered = {}       -- [Fragender] = GetTime()
local function Answer(guild, asker)
    if not Z.Enabled() or asker == Me() then return end
    if answered[asker] and GetTime() - answered[asker] < 300 then return end
    answered[asker] = GetTime()
    -- neue Runde: zählen, was andere schon schicken
    for k in pairs(seenRound) do seenRound[k] = nil end
    -- eigene Zettel kommen im Original (höchstens alle 2 Minuten)
    if GetTime() - lastOwnSend > 120 then ResendOwn() end
    C_Timer.After(2 + math.random() * 8, function()
        local list, me = {}, Me()
        for k, n in pairs(DB()) do
            if n.sender ~= me and (n.guild and true or false) == guild then list[#list + 1] = k end
        end
        table.sort(list, function(a, b) return DB()[a].t > DB()[b].t end)
        for i = 1, math.min(#list, MAX_SYNC) do SendRelay(list[i], DB()[list[i]]) end
    end)
end
Z.Answer = Answer

function Z.Sync()
    if not Z.Enabled() then return end
    if IsInGuild() then ns.Queue("ZTQ", "@CHANNEL", 1) end
    if Z.ShowPublic() and PublicOk() then ns.Queue("ZTQ", "@PUBLIC", ns.CLIENT_TAG) end
end

---------------------------------------------------------------------
-- Empfang
---------------------------------------------------------------------
ns.On("ZTG", function(payload, sender)
    if sender == Me() or not Z.Enabled() then return end
    local a = { strsplit(SEP, payload or "") }
    Z.Apply(true, sender, a[1], a[2], a[3], a[4], a[5], a[6])
end)
ns.On("ZTX", function(payload, sender)
    if sender == Me() then return end
    Z.Remove(true, sender, (strsplit(SEP, payload or "")))
end)
ns.On("ZTQ", function(_, sender) Answer(true, sender) end)
ns.On("ZTR", function(payload, sender)
    if sender == Me() or not Z.Enabled() then return end
    local a = { strsplit(SEP, payload or "") }
    local author = ns.Clean and ns.Clean(a[1], 60) or a[1]
    if not author or author == "" or author == Me() then return end
    Z.Apply(true, author, a[2], a[3], a[4], a[5], a[6], a[7])
end)

-- Offener Kanal: jeder kann schreiben – gebremst und streng geprüft
local perSender = {}
local function Allowed(sender)
    local now = GetTime()
    local s = perSender[sender]
    if not s then s = { n = 0, since = now }; perSender[sender] = s end
    if s.blockedUntil and now < s.blockedUntil then return false end
    if now - s.since > 60 then s.n, s.since = 0, now end
    s.n = s.n + 1
    if s.n > 30 then s.blockedUntil = now + 600; return false end
    return true
end

-- Weitergereicht von Fremden: erst angenommen, wenn zwei verschiedene es melden
local pending = {}        -- [Schlüssel|t|text] = { [Absender] = true, n = Zahl, at = Zeit }
local function Confirmed(id, sender)
    local p = pending[id]
    if not p or GetTime() - p.at > 600 then p = { n = 0, at = GetTime(), by = {} }; pending[id] = p end
    if not p.by[sender] then p.by[sender] = true; p.n = p.n + 1 end
    return p.n >= 2
end

function ns.OnZettelPublic(message, sender)
    if type(message) ~= "string" or #message > 255 or sender == Me() or not Z.Enabled() then return end
    local kind, value = message:match("^(%u+):(.*)$")
    if kind ~= "ZTP" and kind ~= "ZTD" and kind ~= "ZTQ" and kind ~= "ZTS" then return end
    if not Allowed(sender) then return end
    local a = { strsplit(SEP, value) }
    if a[1] ~= ns.CLIENT_TAG then return end
    if kind == "ZTP" then
        Z.Apply(false, sender, a[2], a[3], a[4], a[5], a[6], a[7])
    elseif kind == "ZTD" then
        Z.Remove(false, sender, a[2])
    elseif kind == "ZTQ" then
        if Z.ShowPublic() then Answer(false, sender) end
    else
        local author = ns.Clean and ns.Clean(a[2], 60) or a[2]
        if not author or author == "" or author == Me() then return end
        local key = Key(false, author, tostring(a[3]))
        seenRound[key] = (seenRound[key] or 0) + 1
        local trusted = ns.IsGuildMember and ns.IsGuildMember(sender)
        if not trusted and not Confirmed(key .. "|" .. tostring(a[7]) .. "|" .. tostring(a[8]), sender) then return end
        -- Apply zählt die Runde selbst noch einmal: ausgleichen
        seenRound[key] = seenRound[key] - 1
        Z.Apply(false, author, a[3], a[4], a[5], a[6], a[7], a[8])
    end
end

---------------------------------------------------------------------
-- Karte: Punkte (blau = Gilde, weiß = alle)
---------------------------------------------------------------------
local function Translate(map, x, y, shown)
    if map == shown then return x, y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or not cont or not world then return end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, shown)
    if not ok2 or not pos then return end
    local px, py = pos:GetXY()
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return end
    return px, py
end
Z.Translate = Translate

local function Ago(t)
    local d = GetServerTime() - (t or 0)
    if d < 3600 then return (L["vor %d Min."]):format(math.max(1, math.floor(d / 60))) end
    if d < 86400 then return (L["vor %d Std."]):format(math.floor(d / 3600)) end
    return (L["vor %d Tag(en)"]):format(math.floor(d / 86400))
end

local function PinEnter(pin, n)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(n.guild and L["Notizzettel der Gilde"] or L["Notizzettel"],
        n.guild and BLUE[1] or 1, n.guild and BLUE[2] or 1, n.guild and BLUE[3] or 1)
    GameTooltip:AddLine(L["Geh hin, um ihn zu lesen (~5 m)."], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(("– %s · %s"):format(n.by or "?", Ago(n.t)), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Pins(shown)
    local list = {}
    if not Z.Enabled() or not shown then return list end
    for _, n in pairs(DB()) do
        if Visible(n) then
            local x, y = Translate(n.map, n.x, n.y, shown)
            if x then
                list[#list + 1] = { x = x, y = y, tex = PIN, size = 13, ring = false,
                    color = n.guild and BLUE or WHITE, alpha = 0.95,
                    enter = function(pin) PinEnter(pin, n) end }
            end
        end
    end
    return list
end
if ns.AddMapSource then ns.AddMapSource(Pins) end

---------------------------------------------------------------------
-- Zettel-Fenster (Lesen und Schreiben): Papier mit Ringbuch-Abriss oben,
-- zerfranst unten (Media/zettel.tga), Schrift wie von Hand
---------------------------------------------------------------------
local function Hand(fs, size)
    -- ältere Clients geben nichts zurück: nur bei ausdrücklichem false ausweichen
    if fs:SetFont(HAND, size or 15, "") == false then
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", (size or 15) - 1, "")
    end
    fs:SetTextColor(INK[1], INK[2], INK[3])
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
end

local function Small(fs, size)
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 10, "")
    fs:SetTextColor(0.45, 0.42, 0.35)
    fs:SetShadowOffset(0, 0)
end

local function PaperSound()
    if not (PlaySound and SOUNDKIT) then return end
    local id = SOUNDKIT.IG_SPELLBOOK_OPEN or SOUNDKIT.IG_QUEST_LOG_OPEN
    if id then PlaySound(id) end
end

local function Paper(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(320, 320)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")   -- auch über der großen Weltkarte
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(PAPER)
    f.title = f:CreateFontString(nil, "OVERLAY")
    Hand(f.title, 17)
    f.title:SetPoint("TOPLEFT", 48, -42)
    f.title:SetPoint("TOPRIGHT", -30, -42)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -30)
    close:SetScale(0.8)
    -- sanft einblenden (wie ein Zettel, der dir in die Hand fällt)
    if f.CreateAnimationGroup then
        local ag = f:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        if a.SetFromAlpha then
            a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.3); a:SetSmoothing("OUT")
            f.fadeIn = ag
        end
    end
    f:SetScript("OnShow", function(self)
        PaperSound()
        if self.fadeIn then self.fadeIn:Stop(); self.fadeIn:Play() end
    end)
    tinsert(UISpecialFrames, name)
    return f
end

local function Btn(parent, w, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Reader()
    if Z.reader then return Z.reader end
    local f = Paper("GuildPrideZettelFrame")
    f.text = f:CreateFontString(nil, "OVERLAY")
    Hand(f.text, 16)
    f.text:SetPoint("TOPLEFT", 48, -72)
    f.text:SetPoint("TOPRIGHT", -26, -72)
    f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
    f.text:SetSpacing(3)
    f.sign = f:CreateFontString(nil, "OVERLAY")
    Hand(f.sign, 17)
    f.sign:SetPoint("BOTTOMRIGHT", -30, 54)
    f.sign:SetJustifyH("RIGHT")
    f.when = f:CreateFontString(nil, "OVERLAY")
    Small(f.when, 10)
    f.when:SetPoint("BOTTOMLEFT", 48, 58)
    -- eigener Zettel: abreißen · fremder: ausblenden / Spieler ausblenden
    f.tear = Btn(f, 110, L["Abreißen"], function()
        if Z.shownKey then Z.Tear(Z.shownKey) end
        f:Hide()
    end)
    f.tear:SetPoint("BOTTOMLEFT", 44, 26)
    f.hide = Btn(f, 96, L["Ausblenden"], function()
        if Z.shownKey then Z.Hide(Z.shownKey) end
        f:Hide()
    end)
    f.hide:SetPoint("BOTTOMLEFT", 44, 26)
    f.hide:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Diesen Zettel nur bei dir ausblenden."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.hide:SetScript("OnLeave", GameTooltip_Hide)
    f.mute = Btn(f, 132, L["Spieler ausblenden"], function()
        local n = Z.shownKey and DB()[Z.shownKey]
        if n and Z.Mute(n.sender) then
            ns.Print((L["Zettel von %s werden nicht mehr gezeigt (/gp zettel zeigen %s)."]):format(n.by or n.sender, n.sender))
        end
        f:Hide()
    end)
    f.mute:SetPoint("LEFT", f.hide, "RIGHT", 6, 0)
    f.mute:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Alle Zettel dieses Spielers bei dir ausblenden – auch künftige."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.mute:SetScript("OnLeave", GameTooltip_Hide)
    local base = f:GetScript("OnShow")
    f:SetScript("OnHide", function() Z.shownKey = nil end)
    f:SetScript("OnShow", base)
    Z.reader = f
    return f
end

function Z.Show(key)
    local n = DB()[key]
    if not n then return end
    local f = Reader()
    if f:IsShown() then f:Hide() end   -- neu einblenden (OnHide setzt shownKey zurück)
    Z.shownKey = key
    if n.guild then
        f.title:SetText(("|cff3a78c8%s|r"):format(L["Notizzettel der Gilde"]))
    else
        f.title:SetText(("|cff6b5a3a%s|r"):format(L["Notizzettel"]))
    end
    f.text:SetText(n.text)
    f.sign:SetText("– " .. (n.by or "?"))
    f.when:SetText(Ago(n.t))
    local own = n.sender == Me()
    f.tear:SetShown(own)
    f.hide:SetShown(not own)
    f.mute:SetShown(not own)
    f:Show()
end

-- Schreiben
local function Writer()
    if Z.writer then return Z.writer end
    local f = Paper("GuildPrideZettelWriteFrame")
    f.title:SetText(("|cff6b5a3a%s|r"):format(L["Zettel schreiben"]))
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxBytes(MAX_TEXT + 1)
    eb:SetPoint("TOPLEFT", 48, -72)
    eb:SetPoint("TOPRIGHT", -26, -72)
    eb:SetHeight(170)
    if eb:SetFont(HAND, 16, "") == false then eb:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "") end
    eb:SetTextColor(INK[1], INK[2], INK[3])
    eb:SetSpacing(3)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.count = f:CreateFontString(nil, "OVERLAY")
    Small(f.count, 10)
    f.count:SetPoint("BOTTOMRIGHT", -30, 58)
    eb:SetScript("OnTextChanged", function(self)
        local s = self:GetText() or ""
        -- Grenze ist in Byte (Kanal); angezeigt werden echte Zeichen
        f.count:SetText(("%d/%d"):format(Z.Chars(s), Z.Chars(s) + math.max(0, MAX_TEXT - #s)))
    end)
    -- Klick irgendwo aufs Papier setzt den Schreibcursor
    f:SetScript("OnMouseDown", function() eb:SetFocus() end)
    f.edit = eb
    local function Done(guild)
        local text = eb:GetText()
        if strtrim(text or "") == "" then return end
        if Z.Write(f.map, f.x, f.y, text, guild) then
            ns.Print(guild and L["Zettel für die Gilde aufgehängt."] or L["Zettel für alle aufgehängt."])
            f:Hide()
        end
    end
    f.guildBtn = Btn(f, 112, L["Für die Gilde"], function() Done(true) end)
    f.guildBtn:SetHeight(22)
    f.guildBtn:SetPoint("BOTTOMLEFT", 44, 24)
    f.allBtn = Btn(f, 112, L["Für alle"], function() Done(false) end)
    f.allBtn:SetHeight(22)
    f.allBtn:SetPoint("LEFT", f.guildBtn, "RIGHT", 8, 0)
    local base = f:GetScript("OnShow")
    f:SetScript("OnHide", function() eb:ClearFocus() end)
    f:SetScript("OnShow", base)
    Z.writer = f
    return f
end

-- Auf Kontinent- oder Weltkarte: möglichst auf die Gebietskarte umrechnen
local function ZoneOf(map, x, y)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    if info and info.mapType and info.mapType >= zoneType then return map, x, y end
    local at = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(map, x, y)
    if at and at.mapID and at.mapID ~= map then
        local zx, zy = Translate(map, x, y, at.mapID)
        if zx then return at.mapID, zx, zy end
    end
    return map, x, y
end

function Z.OpenWriter(map, x, y)
    if not Z.Enabled() then ns.Print(L["Notizzettel sind ausgeschaltet (/gp zettel an)."]); return end
    map, x, y = ZoneOf(map, x, y)
    local f = Writer()
    f.map, f.x, f.y = map, x, y
    f.edit:SetText("")
    f.guildBtn:SetEnabled(IsInGuild() and true or false)
    f:Show()
    f.edit:SetFocus()
end

---------------------------------------------------------------------
-- Abstand zum Spieler: Auslösen (~5 m) und Minimap
---------------------------------------------------------------------
Z.armed = {}
local sizeCache = {}
local function MapSize(map)
    if sizeCache[map] ~= nil then return sizeCache[map] or nil end
    local w, h
    if C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(map) end
    if not (w and w > 0) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok1, _, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
        local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 1))
        if ok1 and ok2 and a and b then
            local ax, ay = a:GetXY(); local bx, by = b:GetXY()
            w, h = math.abs(bx - ax), math.abs(by - ay)
        end
    end
    if w and w > 0 and h and h > 0 then sizeCache[map] = { w, h } else sizeCache[map] = false end
    return sizeCache[map] or nil
end

-- Versatz Zettel – Spieler in Yards (x nach Osten, y nach Süden); nil = nicht auf dieser Karte
local posCache, posAt = {}, 0
function Z.Offset(n)
    if not C_Map.GetPlayerMapPosition then return end
    if GetTime() ~= posAt then posCache, posAt = {}, GetTime() end
    local p = posCache[n.map]
    if p == nil then
        local pos = C_Map.GetPlayerMapPosition(n.map, "player")
        local px, py
        if pos then px, py = pos:GetXY() end
        if px and not (px == 0 and py == 0) then p = { px, py } else p = false end
        posCache[n.map] = p
    end
    if not p then return end
    local s = MapSize(n.map)
    if not s then return end
    return (n.x - p[1]) * s[1], (n.y - p[2]) * s[2]
end

function Z.Distance(n)
    local dx, dy = Z.Offset(n)
    if not dx then return end
    return math.sqrt(dx * dx + dy * dy)
end

-- Zettel im Umkreis: höchstens einmal je Sekunde über alle Zettel gehen, die schnellen Takte
-- (Aufgehen, Minimap) rechnen nur noch mit diesen
local NEAR = 400          -- Yards (größter Minimap-Radius ~235, dazu Platz für schnelles Reiten)
local near, nearAt = {}, -1
function Z.ForgetNear() nearAt = -1 end
function Z.Near()
    local now = GetTime()
    if nearAt >= 0 and now - nearAt < 1 then return near end
    nearAt = now
    wipe(near)
    for key, n in pairs(DB()) do
        local d = Visible(n) and Z.Distance(n)
        if d then
            if d > REARM then Z.armed[key] = true end
            if d <= NEAR then near[key] = n end
        end
    end
    return near
end

C_Timer.NewTicker(0.5, function()
    if not Z.Enabled() or not next(Z.Near()) or UnitIsDeadOrGhost("player") then return end
    local best, bestD
    for key, n in pairs(Z.Near()) do
        local d = Visible(n) and Z.Distance(n)
        if d and d <= TRIGGER and Z.armed[key] ~= false and (not bestD or d < bestD) then best, bestD = key, d end
    end
    if best and Z.shownKey ~= best then
        Z.armed[best] = false
        Z.Show(best)
    end
end)

-- Minimap: Zettel in Reichweite als kleine Symbole
-- Sichtweite der Minimap (Durchmesser in Yards) je Zoomstufe, draußen und drinnen
local MM_OUT = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
local MM_IN  = { [0] = 300, 240, 180, 120, 80, 50 }
local mmPins = {}
local function MinimapPin(i)
    local b = mmPins[i]
    if b then return b end
    b = CreateFrame("Button", nil, Minimap)
    b:SetSize(12, 12)
    b:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetAllPoints()
    b.tex:SetTexture(PIN)
    b:SetScript("OnEnter", function(self) if self.note then PinEnter(self, self.note) end end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    mmPins[i] = b
    return b
end

function Z.UpdateMinimap()
    if not Minimap then return end
    local n = 0
    local list = Z.Enabled() and Z.ShowMinimap() and Z.Near()
    local width = list and next(list) and Minimap.GetWidth and Minimap:GetWidth()
    if Z.Enabled() and Z.ShowMinimap() and type(width) == "number" and width > 0 then
        local zoom = Minimap:GetZoom() or 0
        local indoor = IsIndoors and IsIndoors()
        local radius = ((indoor and MM_IN or MM_OUT)[zoom] or 200) / 2
        local pxRadius = width / 2
        local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
        local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
        local cf, sf = math.cos(facing), math.sin(facing)
        for _, note in pairs(list) do
            if Visible(note) then
                local dx, dy = Z.Offset(note)
                if dx and dx * dx + dy * dy <= (radius * 0.95) ^ 2 then
                    -- Bildschirm: x nach rechts (Osten), y nach oben (Norden)
                    local sx, sy = dx, -dy
                    if rotate then sx, sy = sx * cf + sy * sf, -sx * sf + sy * cf end
                    n = n + 1
                    local b = MinimapPin(n)
                    b.note = note
                    local c = note.guild and BLUE or WHITE
                    b.tex:SetVertexColor(c[1], c[2], c[3])
                    b:ClearAllPoints()
                    b:SetPoint("CENTER", Minimap, "CENTER", sx / radius * pxRadius, sy / radius * pxRadius)
                    b:Show()
                end
            end
        end
    end
    for i = n + 1, #mmPins do mmPins[i]:Hide(); mmPins[i].note = nil end
end
C_Timer.NewTicker(0.2, function() Z.UpdateMinimap() end)

---------------------------------------------------------------------
-- Ein/Aus und Knopf auf der Weltkarte (wie bei den Rares)
---------------------------------------------------------------------
local button

local function UpdateButton()
    if not button then return end
    local on = Z.Enabled()
    button.icon:SetDesaturated(not on)
    button.icon:SetAlpha(on and 1 or 0.4)
end

function Z.SetEnabled(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.mapNotes = on and true or false end
    if not on then
        if Z.reader then Z.reader:Hide() end
        if Z.writer then Z.writer:Hide() end
    end
    UpdateButton()
    Refresh()
end
function Z.SetOption(key, on)
    if type(GuildPrideDB) == "table" then GuildPrideDB[key] = on and true or false end
    Refresh()
end
function Z.Changed() UpdateButton(); Refresh() end

-- „Zettel schreiben“: der Zettel kommt direkt an die Stelle, an der du stehst
function Z.WriteHere()
    if not Z.Enabled() then Z.SetEnabled(true) end
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y
    if pos then x, y = pos:GetXY() end
    if not (x and y) or (x == 0 and y == 0) then
        ns.Print(L["Hier kann kein Zettel hängen (keine Position, z. B. in Instanzen)."])
        return
    end
    Z.OpenWriter(map, x, y)
end

local function MakeButton()
    if button or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    local sc = WorldMapFrame.ScrollContainer
    button = CreateFrame("Button", "GuildPrideZettelMapButton", sc)
    button:SetSize(26, 26)
    button:SetFrameLevel(sc:GetFrameLevel() + 2000)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2); button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexture(PIN)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, b)
        if b == "RightButton" then
            Z.SetEnabled(not Z.Enabled())
            ns.Print(Z.Enabled() and L["Notizzettel |cff40ff40an|r"] or L["Notizzettel |cffff6060aus|r – auf der Karte ausgeblendet"])
        else
            Z.WriteHere()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["GuildPride Notizzettel"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Linksklick: Zettel schreiben (hängt da, wo du stehst)"], 1, 1, 1)
        GameTooltip:AddLine(L["Rechtsklick: Zettel an/aus"], 1, 1, 1)
        GameTooltip:AddLine(Z.Enabled() and L["Zurzeit: an"] or L["Zurzeit: aus"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    -- unter den Rare-Knopf, wenn der zu sehen ist
    local function Place()
        button:ClearAllPoints()
        local rare = _G.GPRaresMapToggle
        if rare and rare:IsShown() then button:SetPoint("TOP", rare, "BOTTOM", 0, -4)
        else button:SetPoint("TOPLEFT", sc, "TOPLEFT", 8, -8) end
    end
    Place()
    WorldMapFrame:HookScript("OnShow", Place)
    UpdateButton()
end

local menuHooked = false
local function HookFilterMenu()
    if menuHooked or not (Menu and Menu.ModifyMenu) then return end
    menuHooked = true
    Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root)
        root:CreateDivider()
        root:CreateTitle(L["GuildPride Notizzettel"])
        root:CreateCheckbox(L["Notizzettel zeigen"], function() return Z.Enabled() end,
            function() Z.SetEnabled(not Z.Enabled()) end)
        root:CreateCheckbox(L["Zettel für alle (weiß) zeigen"], function() return Z.ShowPublic() end,
            function() Z.SetOption("mapNotesPublic", not Z.ShowPublic()) end)
        root:CreateCheckbox(L["Zettel auf der Minimap"], function() return Z.ShowMinimap() end,
            function() Z.SetOption("mapNotesMinimap", not Z.ShowMinimap()) end)
        root:CreateButton(L["Zettel schreiben"], function() Z.WriteHere() end)
    end)
end

local function Setup()
    MakeButton()
    HookFilterMenu()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        Setup()
        Prune()
        -- nach dem Kanalbeitritt: eigene Zettel verschicken, die der anderen abfragen
        C_Timer.After(45, ResendOwn)
        C_Timer.After(55, Z.Sync)
    elseif name == "Blizzard_WorldMap" then
        Setup()
    end
end)

---------------------------------------------------------------------
-- /gp zettel [an|aus|schreiben|weg|zeigen Name]
---------------------------------------------------------------------
local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
    local word, name = (rest or ""):match("^(%S*)%s*(.-)$")
    cmd, word = (cmd or ""):lower(), (word or ""):lower()
    if cmd ~= "zettel" and cmd ~= "notes" then return origSlash(arg) end
    if word == "aus" or word == "off" then
        Z.SetEnabled(false); ns.Print(L["Notizzettel |cffff6060aus|r – auf der Karte ausgeblendet"])
    elseif word == "an" or word == "on" then
        Z.SetEnabled(true); ns.Print(L["Notizzettel |cff40ff40an|r"])
    elseif word == "weg" or word == "clear" then
        local own = OwnNotes()
        for _, k in ipairs(own) do Z.Tear(k) end
        ns.Print((L["%d eigene Zettel abgerissen."]):format(#own))
    elseif word == "schreiben" or word == "write" then
        Z.WriteHere()
    elseif (word == "zeigen" or word == "show") and name ~= "" then
        local found
        for n in pairs(Muted()) do if n:lower() == name:lower() then found = n end end
        if found then Z.Unmute(found); ns.Print((L["Zettel von %s werden wieder gezeigt."]):format(found)) end
    else
        local n, own = 0, #OwnNotes()
        for _ in pairs(DB()) do n = n + 1 end
        ns.Print((L["Notizzettel: %s · %d bekannt, %d eigene. /gp zettel an|aus|schreiben|weg"]):format(
            Z.Enabled() and L["an"] or L["aus"], n, own))
    end
end
