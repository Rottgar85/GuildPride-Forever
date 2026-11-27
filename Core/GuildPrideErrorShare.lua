-- GuildPride: Fehler automatisch an den Entwickler senden
--
-- Nur mit Zustimmung: Wer einen GuildPride-Fehler hatte, wird einmal gefragt
-- (GuildPrideDB.errorShare: nil = noch nicht gefragt, true, false; Schalter unter
-- Einstellungen › Teilen). Ist der Entwickler online, meldet sich sein Client (DVA) in
-- Gilde und offenem Kanal. Wer zugestimmt hat, flüstert ihm seine gespeicherten Fehler
-- als Addon-Nachricht (DVE, in Stücken), er bestätigt (DVK) – danach kommt derselbe
-- Fehler nicht noch einmal. Der Server bürgt für den Absendernamen: gesendet wird nur
-- an Charaktere, die ns.IsMarked kennt.
--
-- Datenschutz (feste Regel): gesendet werden nur Fehlertext, Aufrufstapel, Versionen,
-- Sprache und Umstände (Kampf, Instanzart, offene GuildPride-Fenster). Der Entwickler speichert keine Charakternamen, nur einen Zählcode.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"
local PREFIX = "GuildPride"
local FIELD, NEWLINE = "\029", "\030"

local S = {}
ns.ErrorShare = S

local MSG_MAX, STACK_MAX, CTX_MAX = 500, 700, 120   -- Byte je Fehler
local CHUNK, CHUNKS_MAX = 200, 12     -- Addon-Nachrichten: höchstens 255 Byte
local PER_ASK = 5                     -- Fehler je Anfrage
local ANSWER_GAP = 540                -- Sekunden zwischen zwei Antworten
local HELLO_GAP = 600                 -- Entwickler meldet sich alle 10 Minuten
local GROUPS_MAX = 200                -- Entwickler: verschiedene Fehler
local SENDER_MAX, SENDER_TIME = 20, 3600   -- Entwickler: Fehler je Absender und Stunde
local BUFFERS_MAX = 60

local function IsDev() return ns.IsDev and ns.IsDev() or false end
local function Enabled() return type(GuildPrideDB) == "table" and GuildPrideDB.errorShare == true end

-- Kurzer Code aus einem Text (zum Wiedererkennen)
local function Hash(text)
    local a, b = 5381, 2166136
    for i = 1, #text do
        local c = text:byte(i)
        a = (a * 33 + c + i) % 268435456
        b = (b * 131 + c + i) % 268435456
    end
    return ("%07x%07x"):format(a, b)
end

---------------------------------------------------------------------
-- Senden: eine Addon-Nachricht alle 1,5 s, nur per Flüstern
---------------------------------------------------------------------
local outbox, sending = {}, false
local lastAnswer

local function SendNext()
    local item = outbox[1]
    if not item then sending = false; return end
    if not item.ack and not (item.check or Enabled)() then   -- inzwischen abgeschaltet
        table.remove(outbox, 1)
        return SendNext()
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        C_Timer.After(10, SendNext)
        return
    end
    local res = ns.SendAddonMsg(PREFIX, item.msg, "WHISPER", item.to)
    local failed = type(res) == "number" and res ~= 0
    item.tries = (item.tries or 0) + 1
    if not failed or item.tries >= 5 then table.remove(outbox, 1) end
    C_Timer.After(failed and 4 or 1.5, SendNext)
end

local function Push(to, msg, ack, check)
    outbox[#outbox + 1] = { to = to, msg = msg, ack = ack, check = check }
end
local function Flush()
    if sending or not outbox[1] then return end
    sending = true
    SendNext()
end

-- Kurze Nachricht auf demselben Weg (GuildPrideTester.lua)
function S.Whisper(to, msg)
    Push(to, msg, true)
    Flush()
end

-- Daten in Stücken an den Entwickler (auch GuildPrideUsage.lua); check = darf noch gesendet werden?
function S.Send(to, kind, id, data, check)
    local count = math.ceil(#data / CHUNK)
    if count < 1 or count > CHUNKS_MAX then return false end
    for i = 1, count do
        Push(to, kind .. ":" .. table.concat({ id, i, count, data:sub((i - 1) * CHUNK + 1, i * CHUNK) }, SEP), nil, check)
    end
    Flush()
    return true
end

local function Plain(s, max)
    s = tostring(s or ""):gsub("|", "/"):gsub("\n", NEWLINE)
    return (s:gsub("%c", function(c) return c == NEWLINE and c or "" end)):sub(1, max)
end

local function Encode(e)
    local version = GetBuildInfo()
    return table.concat({ Plain(e.v or ns.VERSION, 20), Plain(version, 12), Plain(GetLocale and GetLocale() or "", 4),
        tostring(e.n or 1), Plain(e.ctx, CTX_MAX), Plain(e.msg, MSG_MAX), Plain(e.stack, STACK_MAX) }, FIELD)
end
local function ErrorId(e) return Hash(Plain(e.v, 20) .. Plain(e.msg, MSG_MAX)) end

local function SendErrors(to)
    local n = 0
    for _, e in ipairs(GuildPrideDB.errors or {}) do
        if not e.sent and n < PER_ASK then
            n = n + 1
            local data, id = Encode(e), ErrorId(e)
            local count = math.ceil(#data / CHUNK)
            for i = 1, count do
                Push(to, "DVE:" .. table.concat({ id, i, count, data:sub((i - 1) * CHUNK + 1, i * CHUNK) }, SEP))
            end
        end
    end
    Flush()
end

local function OnHello(value, sender)
    if value ~= ns.CLIENT_TAG or not Enabled() or IsDev() then return end
    if not (ns.IsMarked and ns.IsMarked(sender)) then return end
    if lastAnswer and GetTime() - lastAnswer < ANSWER_GAP then return end
    lastAnswer = GetTime()
    -- zeitversetzt: sonst flüstern alle gleichzeitig
    C_Timer.After(3 + math.random() * 60, function() if Enabled() then SendErrors(sender) end end)
end

local function OnAck(id, sender)
    if not (ns.IsMarked and ns.IsMarked(sender)) then return end
    for _, e in ipairs(GuildPrideDB.errors or {}) do
        if ErrorId(e) == id then e.sent = true end
    end
    if ns.Usage then ns.Usage.OnAck(id) end
    if ns.UserCount then ns.UserCount.OnAck(id) end
end

-- Behobene Fehler (DVF): wer einen davon gemeldet hat, erfährt es einmal
local function OnFixed(value, sender)
    if not (ns.IsMarked and ns.IsMarked(sender)) then return end
    local tag, list = strsplit(SEP, value)
    if tag ~= ns.CLIENT_TAG or type(list) ~= "string" then return end
    local ids, n = {}, 0
    for id in list:sub(1, 250):gmatch("%w+") do ids[id] = true end
    for _, e in ipairs(GuildPrideDB.errors or {}) do
        if not e.fixed and ids[ErrorId(e)] then e.fixed = true; n = n + 1 end
    end
    if n > 0 then
        ns.Print(L["Ein GuildPride-Fehler, den du gemeldet hast, ist behoben und kommt mit dem nächsten Update. Danke!"])
    end
end

---------------------------------------------------------------------
-- Entwickler: empfangen und zusammenfassen
---------------------------------------------------------------------
local buffers, quota = {}, {}
local news, newsPlayers, newsTimer, newsTold = 0, {}, false, false

local function Store()
    if type(GuildPrideDB.dev) ~= "table" then GuildPrideDB.dev = {} end
    return GuildPrideDB.dev
end

-- Platz schaffen: zuerst Erledigtes, dann das, was am längsten her ist
local function MakeRoom(db)
    local count, oldest = 0, nil
    for key, g in pairs(db) do
        count = count + 1
        local o = oldest and db[oldest]
        if not o or (g.done and not o.done)
            or ((g.done or false) == (o.done or false) and (g.last or 0) < (o.last or 0)) then oldest = key end
    end
    if count >= GROUPS_MAX and oldest then db[oldest] = nil end
end

local function TellNews()
    newsTimer = false
    if newsTold or news == 0 then return end
    newsTold = true
    local players = 0
    for _ in pairs(newsPlayers) do players = players + 1 end
    ns.Print(("%d neue GuildPride-Fehler von %d Spielern. /gp dev zeigt sie."):format(news, players))
end

-- true: Nachricht war in Ordnung (wird bestätigt)
local function Collect(data, sender, id)
    local f = {}
    for part in (data .. FIELD):gmatch("(.-)" .. FIELD) do f[#f + 1] = part end
    if #f ~= 7 then return false end
    local v, game, loc, n, ctx, msg, stack = f[1], f[2], f[3], tonumber(f[4]), f[5], f[6], f[7]
    if #v > 20 or not v:match("^%d+%.%d+[%.%d]*$") or #game > 12 or not game:match("^[%d%.]+$")
        or #loc > 4 or not loc:match("^%a*$") then return false end
    if not n or n < 1 or n > 1e6 or msg == "" then return false end
    if #ctx > CTX_MAX or not ctx:match("^[%w=,_ ]*$") then return false end
    msg = Plain(msg, MSG_MAX):gsub(NEWLINE, "\n")
    stack = Plain(stack, STACK_MAX):gsub(NEWLINE, "\n")
    local who = Hash("DV" .. sender:lower())
    local db = Store()
    local key = Hash(v .. msg)
    local g = db[key]
    if g and g.who[who] then return true end   -- schon gezählt
    local q, now = quota[sender], GetTime()
    if not q or now - q.t > SENDER_TIME then q = { t = now, n = 0 }; quota[sender] = q end
    if q.n >= SENDER_MAX then return true end
    q.n = q.n + 1
    if not g then
        MakeRoom(db)
        g = { key = key, id = id, v = v, msg = msg, stack = stack, n = 0, players = 0, who = {}, first = GetServerTime() }
        db[key] = g
        news = news + 1
    end
    g.who[who] = true
    g.players, g.n = g.players + 1, g.n + math.floor(n)
    g.game, g.loc, g.last = game, loc, GetServerTime()
    if ctx ~= "" then g.ctx = ctx end
    newsPlayers[who] = true
    if not newsTimer and not newsTold then
        newsTimer = true
        C_Timer.After(120, TellNews)
    end
    return true
end

local function OnPiece(value, sender, kind)
    if not IsDev() then return end
    local id, i, n, part = value:match("^(%w+)" .. SEP .. "(%d+)" .. SEP .. "(%d+)" .. SEP .. "(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not id or #id > 20 or not i or not n or n < 1 or n > CHUNKS_MAX or i < 1 or i > n then return end
    local now, count = GetTime(), 0
    for k, b in pairs(buffers) do
        if now - b.t > 300 then buffers[k] = nil else count = count + 1 end
    end
    local key = sender .. ":" .. kind .. id
    local buf = buffers[key]
    if not buf then
        if count >= BUFFERS_MAX then return end
        buf = { n = n, got = 0, parts = {}, t = now }
        buffers[key] = buf
    end
    if buf.n ~= n then return end
    if not buf.parts[i] then buf.parts[i] = part; buf.got = buf.got + 1 end
    if buf.got < n then return end
    buffers[key] = nil
    local data = table.concat(buf.parts)
    if kind == "DVU" then
        if not (ns.Usage and ns.Usage.Collect(data, Hash("DV" .. sender:lower()))) then return end
    elseif not Collect(data, sender, id) then
        return
    end
    Push(sender, "DVK:" .. id, true)
    Flush()
    if S.Refresh then S.Refresh() end
end

-- Aus GuildPride.lua (geschützte Werte sind dort schon aussortiert)
function ns.OnErrorShareMessage(message, sender, channel)
    if type(GuildPrideDB) ~= "table" or sender == ns.Me() then return end
    local kind, value = message:match("^(DV%u):(.*)$")
    if kind == "DVA" then
        OnHello(value, sender)
        if ns.Usage and value == ns.CLIENT_TAG and ns.IsMarked and ns.IsMarked(sender) then ns.Usage.OnHello(sender) end
        -- Nutzerzahl (GuildPrideCount.lua): immer an, anonym
        if ns.UserCount and value == ns.CLIENT_TAG then ns.UserCount.OnHello(sender) end
        if ns.Tester then ns.Tester.OnMessage(kind, value, sender, channel) end
    elseif kind == "DVT" or kind == "DVR" then
        if ns.Tester then ns.Tester.OnMessage(kind, value, sender, channel) end
    elseif kind == "DVF" then OnFixed(value, sender)
    elseif channel ~= "WHISPER" then return
    elseif kind == "DVE" or kind == "DVU" then OnPiece(value, sender, kind)
    elseif kind == "DVC" then
        local ok, id
        if ns.UserCount then ok, id = ns.UserCount.Collect(value, sender) end
        if ok and id then Push(sender, "DVK:" .. id, true); Flush() end   -- Quittung: der Tag zählt als gemeldet
    elseif kind == "DVK" then OnAck(value, sender) end
end

-- Offene Einträge: die meisten Spieler zuerst, dann die neuesten
function S.List()
    local list = {}
    for _, g in pairs(type(GuildPrideDB.dev) == "table" and GuildPrideDB.dev or {}) do
        if not g.done then list[#list + 1] = g end
    end
    table.sort(list, function(a, b)
        if a.players ~= b.players then return a.players > b.players end
        if a.last ~= b.last then return a.last > b.last end
        return a.key < b.key
    end)
    return list
end

function S.Done(key)
    local g = type(GuildPrideDB.dev) == "table" and GuildPrideDB.dev[key]
    if g then g.done = true end
end

-- Behoben: aus der Liste, und wer ihn gemeldet hat, erfährt es (S.Hello schickt DVF)
function S.Fixed(key)
    local g = type(GuildPrideDB.dev) == "table" and GuildPrideDB.dev[key]
    if g then g.done, g.fixed = true, GetServerTime() end
end

-- Je Meldung zwölf behobene Fehler der letzten 30 Tage, reihum
local FIXED_MAX, FIXED_DAYS, fixedAt = 12, 30, 0
local function FixedIds()
    local all, now = {}, GetServerTime()
    for _, g in pairs(type(GuildPrideDB.dev) == "table" and GuildPrideDB.dev or {}) do
        if g.fixed and g.id and now - g.fixed < FIXED_DAYS * 86400 then all[#all + 1] = g.id end
    end
    if #all == 0 then return nil end
    table.sort(all)
    local out = {}
    for i = 1, math.min(FIXED_MAX, #all) do out[i] = all[(fixedAt + i - 1) % #all + 1] end
    fixedAt = (fixedAt + #out) % #all
    return table.concat(out, ",")
end

-- Entwickler: „ich bin da“ an Gilde und offenen Kanal
function S.Hello()
    if not IsDev() or not ns.Queue then return end
    local public = not ns.PUBLIC_VIA_CHAT and ns.PublicChannelId and ns.PublicChannelId()
    local fixed = FixedIds()
    for _, target in ipairs({ "GUILD", "@PUBLIC" }) do
        if (target == "GUILD" and IsInGuild()) or (target == "@PUBLIC" and public) then
            local to = target ~= "GUILD" and target or nil
            ns.Queue("DVA", to, ns.CLIENT_TAG)
            if fixed then ns.Queue("DVF", to, ns.CLIENT_TAG, fixed) end
        end
    end
end

---------------------------------------------------------------------
-- Frage (einmal, nur wer einen GuildPride-Fehler hatte)
---------------------------------------------------------------------
function S.ShouldAsk()
    if type(GuildPrideDB) ~= "table" or GuildPrideDB.errorShare ~= nil or IsDev() then return false end
    return type(GuildPrideDB.errors) == "table" and #GuildPrideDB.errors > 0
end

local ask, asked
function S.Choose(yes)
    GuildPrideDB.errorShare = yes and true or false
    if ask then ask:Hide() end
    if ns.RefreshUI then ns.RefreshUI() end
end

local function BuildAsk()
    ask = CreateFrame("Frame", "GuildPrideErrorAsk", UIParent, "BackdropTemplate")
    ask:SetSize(420, 240)
    ask:SetPoint("CENTER", 0, 120)
    ask:SetFrameStrata("DIALOG")
    ask:SetMovable(true); ask:EnableMouse(true); ask:SetClampedToScreen(true)
    ask:RegisterForDrag("LeftButton")
    ask:SetScript("OnDragStart", ask.StartMoving)
    ask:SetScript("OnDragStop", ask.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(ask) end
    local title = ask:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L["Fehler automatisch senden?"])
    if ns.Paint then ns.Paint(title, "heading") end
    local text = ask:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    text:SetPoint("TOPLEFT", 14, -40)
    text:SetWidth(392)
    text:SetJustifyH("LEFT")
    text:SetText(L["In GuildPride ist ein Fehler aufgetreten. Dürfen solche Fehler automatisch im Spiel an den Entwickler von GuildPride gehen? Dann werden sie schneller behoben.\n\nGesendet werden nur Fehlertext (kann selten einen Spielernamen enthalten), Stelle im Code, Versionen von GuildPride und WoW, die Spielsprache und die Umstände (Kampf, Instanzart, offene GuildPride-Fenster). Deinen Charakternamen speichert er nicht, nur einen daraus berechneten Zählcode.\n\nDu kannst das jederzeit ändern: Einstellungen › Teilen."])
    local function Button(label, yes, ...)
        local b = CreateFrame("Button", nil, ask, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(150, 24)
        b:SetPoint(...)
        b:SetText(label)
        b:SetScript("OnClick", function() S.Choose(yes) end)
    end
    Button(L["Ja, immer"], true, "BOTTOMLEFT", 14, 12)
    Button(L["Nein"], false, "BOTTOMRIGHT", -14, 12)
    -- Höhe nach Text (andere Schriftgröße oder Sprache)
    ask:SetScript("OnShow", function(self)
        local h = text:GetStringHeight()
        if type(h) == "number" and h > 0 then self:SetHeight(h + 96) end
    end)
    ask:Hide()
end

local ev = CreateFrame("Frame")
local function TryAsk()
    if asked or not S.ShouldAsk() then return end
    if InCombatLockdown() then ev:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    asked = true
    if not ask then BuildAsk() end
    ask:Show()
end

-- Aus GuildPrideErrors.lua: ein eigener Fehler wurde neu gespeichert
function S.Recorded()
    if not asked then C_Timer.After(5, TryAsk) end
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent(event)
        C_Timer.After(2, TryAsk)
        return
    end
    C_Timer.After(30, TryAsk)
    if IsDev() then
        C_Timer.After(45, S.Hello)
        C_Timer.NewTicker(HELLO_GAP, S.Hello)
    end
end)

---------------------------------------------------------------------
-- Fenster des Entwicklers (/gp dev) – nur für ihn, deshalb ohne Übersetzung
---------------------------------------------------------------------
local win
local function Detail(g)
    return ("GuildPride %s · WoW %s · %s\n%d Spieler, %d-mal · zuerst %s · zuletzt %s\n%s\n\n%s\n\n%s"):format(
        g.v, g.game or "?", g.loc or "?", g.players, g.n, date("%d.%m.%Y %H:%M", g.first or 0),
        date("%d.%m.%Y %H:%M", g.last or 0), g.ctx or "", g.msg, g.stack or "")
end

function S.Refresh()
    if not win or not win:IsShown() then return end
    win.list = S.List()
    local lines = {}
    for _, g in ipairs(win.list) do
        -- Fehlertext ohne Pfad und Zeilenumbrüche: passt in eine Zeile
        local short = g.msg:gsub("\n", " "):gsub("^.-([%w_]+%.lua:%d+:)", "%1")
        lines[#lines + 1] = ("|cffffd100%d|r  |cff999999%s · %s|r  %s"):format(g.players, g.v, date("%d.%m. %H:%M", g.last or 0), short)
    end
    win:SetLines(lines)
end

local function BuildWindow()
    win = ns.ListWindow({ name = "GuildPrideDev", title = "GuildPride-Fehler der Spieler", rows = 16, width = 680,
        sub = "Spieler · Version · zuletzt · Fehler.  Links: kopieren, Rechts: behoben (Melder erfahren es), Umschalt+Rechts: nur ausblenden.",
        empty = "Keine offenen Fehler. Spieler senden nur, wenn sie zugestimmt haben und du online bist." })
    for i, row in ipairs(win.rows) do
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(_, button)
            local g = win.list and win.list[i + win.offset]
            if not g then return end
            if button == "RightButton" then
                if IsShiftKeyDown() then S.Done(g.key) else S.Fixed(g.key) end
                S.Refresh()
            elseif ns.ShowCopy then ns.ShowCopy("GuildPride-Fehler", Detail(g)) end
        end)
    end
    local function Button(label, x, onClick)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(150, 22)
        b:SetPoint("TOPLEFT", x, win.bottomY)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
    end
    Button("Alle kopieren", 14, function()
        local out = {}
        for _, g in ipairs(S.List()) do out[#out + 1] = Detail(g) end
        if out[1] and ns.ShowCopy then ns.ShowCopy("GuildPride-Fehler", table.concat(out, "\n\n" .. ("-"):rep(40) .. "\n\n")) end
    end)
    Button("Jetzt abfragen", 174, function() S.Hello() end)
    Button("Nutzung", 494, function() if ns.Usage then ns.Usage.Open() end end)
    local count = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(count) end
    count:SetSize(110, 22); count:SetPoint("TOPRIGHT", -280, -10); count:SetText("Nutzerzahl")
    count:SetScript("OnClick", function() if ns.UserCount then ns.UserCount.Open() end end)
    local tests = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(tests) end
    tests:SetSize(110, 22); tests:SetPoint("TOPRIGHT", -44, -10); tests:SetText("Testliste")
    tests:SetScript("OnClick", function() if ns.DevTest then ns.DevTest.Open() end end)
    local testers = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(testers) end
    testers:SetSize(110, 22); testers:SetPoint("RIGHT", tests, "LEFT", -6, 0); testers:SetText("Tester")
    testers:SetScript("OnClick", function() if ns.Tester then ns.Tester.Open() end end)
    Button("Alle erledigt", 334, function()
        for _, g in ipairs(S.List()) do S.Done(g.key) end
        S.Refresh()
    end)
    win:SetScript("OnShow", function() win.offset = 0; S.Refresh() end)
end

function S.Toggle()
    if not win then BuildWindow() end
    win:SetShown(not win:IsShown())
end

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "dev" and IsDev() then S.Toggle()
    elseif origSlash then origSlash(arg) end
end
