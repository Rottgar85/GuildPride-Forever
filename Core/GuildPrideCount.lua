-- GuildPride: Nutzerzahl für den Entwickler (immer an, anonym)
--
-- Ist der Entwickler online, meldet sich sein Client (DVA, GuildPrideErrorShare.lua) in Gilde und
-- offenem Kanal. Jeder GuildPride-Client flüstert ihm darauf höchstens einmal am Tag:
--   DVC  Kennung · Version · Stufe
-- Die Kennung ist eine Zufallszahl je Account (GuildPrideDB.installId), kein Name, kein BattleTag.
-- Der Entwickler speichert nur Kennung, ersten und letzten Tag, Version und Stufe
-- (GuildPrideDB.devCount) und sieht daraus, wie viele GuildPride nutzen: /gp dev › „Nutzerzahl“.
-- In der Einführung wird das auf Wunsch des Entwicklers nicht erwähnt.
local ADDON, ns = ...
local SEP = ns.SEP or "\031"

local C = {}
ns.UserCount = C
local DAY, MAX_IDS = 86400, 5000
local TIERS = { light = true, medium = true, max = true, none = true }

local function IsDev() return ns.IsDev and ns.IsDev() or false end
local function Today() return math.floor(GetServerTime() / DAY) end

function C.Id()
    local id = GuildPrideDB.installId
    if type(id) ~= "string" or not id:match("^%x+$") or #id ~= 12 then
        id = ("%06x%06x"):format(math.random(0, 0xFFFFFF), math.random(0, 0xFFFFFF))
        GuildPrideDB.installId = id
    end
    return id
end

local function MyTier()
    return ns.TierChosen and ns.TierChosen() and ns.Tier() or "none"
end

-- Aus GuildPrideErrorShare.lua: der echte Entwickler ist da (Absender ist dort schon geprüft)
function C.OnHello(sender)
    if type(GuildPrideDB) ~= "table" or IsDev() then return false end
    if not (ns.IsMarked and ns.IsMarked(sender)) then return false end
    local today = Today()
    if GuildPrideDB.countDay == today then return false end
    GuildPrideDB.countDay = today
    -- verteilt: nicht alle auf einmal, wenn der Entwickler sich meldet
    C_Timer.After(5 + math.random() * 115, function()
        if ns.ErrorShare and ns.ErrorShare.Whisper then
            ns.ErrorShare.Whisper(sender, "DVC:" .. table.concat({ C.Id(), ns.VERSION or "0.0.0", MyTier() }, SEP))
        end
    end)
    return true
end

---------------------------------------------------------------------
-- Entwickler: sammeln und auswerten
---------------------------------------------------------------------
local function Store()
    if type(GuildPrideDB.devCount) ~= "table" then GuildPrideDB.devCount = {} end
    return GuildPrideDB.devCount
end

function C.Collect(value, sender)
    if not IsDev() or type(value) ~= "string" then return false end
    local id, ver, tier = strsplit(SEP, value)
    if type(id) ~= "string" or #id ~= 12 or not id:match("^%x+$") then return false end
    if type(ver) ~= "string" or #ver > 20 or not ver:match("^%d+%.%d+[%.%d]*$") then return false end
    if not TIERS[tier] then return false end
    local db, today = Store(), Today()
    local e = db[id]
    if not e then
        local n, oldest = 0, nil
        for k, x in pairs(db) do
            n = n + 1
            if not oldest or (x.l or 0) < (db[oldest].l or 0) then oldest = k end
        end
        if n >= MAX_IDS and oldest then db[oldest] = nil end
        e = { f = today }
        db[id] = e
    end
    e.l, e.v, e.t = today, ver, tier
    if C.Refresh then C.Refresh() end
    return true
end

-- Zahlen: heute, 7 und 30 Tage, gesamt; Stufen und Versionen der letzten 30 Tage
function C.Summary()
    local today = Today()
    local s = { today = 0, week = 0, month = 0, total = 0, new = 0, tiers = {}, versions = {} }
    for _, e in pairs(type(GuildPrideDB.devCount) == "table" and GuildPrideDB.devCount or {}) do
        local age = today - (e.l or 0)
        s.total = s.total + 1
        if age <= 0 then s.today = s.today + 1 end
        if age < 7 then s.week = s.week + 1 end
        if age < 30 then
            s.month = s.month + 1
            s.tiers[e.t or "none"] = (s.tiers[e.t or "none"] or 0) + 1
            s.versions[e.v or "?"] = (s.versions[e.v or "?"] or 0) + 1
        end
        if today - (e.f or today) < 7 then s.new = s.new + 1 end
    end
    return s
end

function C.Lines()
    local s = C.Summary()
    local out = {
        ("|cffffd100Heute:|r %d   |cffffd1007 Tage:|r %d   |cffffd10030 Tage:|r %d   |cffffd100gesamt:|r %d"):format(s.today, s.week, s.month, s.total),
        ("Neu in den letzten 7 Tagen: %d"):format(s.new),
        " ",
        "|cffffd100Stufen (30 Tage)|r",
        ("  Light %d · Medium %d · Max %d · nicht gewählt %d"):format(s.tiers.light or 0, s.tiers.medium or 0, s.tiers.max or 0, s.tiers.none or 0),
        " ",
        "|cffffd100Versionen (30 Tage)|r",
    }
    local vers = {}
    for v, n in pairs(s.versions) do vers[#vers + 1] = { v = v, n = n } end
    table.sort(vers, function(a, b)
        local c = ns.CompareVersion and ns.CompareVersion(a.v, b.v) or 0
        if c ~= 0 then return c > 0 end
        return a.v > b.v
    end)
    for _, x in ipairs(vers) do out[#out + 1] = ("  %s: %d"):format(x.v, x.n) end
    out[#out + 1] = " "
    out[#out + 1] = "|cff888888Gezählt wird je Account, wer online war, während du online warst (Gilde oder offener Kanal).|r"
    return out
end

local win
function C.Refresh() if win and win:IsShown() then win:SetLines(C.Lines()) end end
function C.Open()
    if not IsDev() then return end
    if not win then
        win = ns.ListWindow({ name = "GuildPrideDevCount", title = "Wie viele nutzen GuildPride?", rows = 16, width = 520,
            sub = "Anonym: je Account eine Zufallskennung, kein Name. Jeder meldet sich höchstens einmal am Tag." })
        win:SetScript("OnShow", function() win.offset = 0; win:SetLines(C.Lines()) end)
    end
    win:SetShown(not win:IsShown())
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local a = strtrim(arg or ""):lower()
    if (a == "nutzer" or a == "nutzerzahl" or a == "users") and IsDev() then return C.Open() end
    return slash(arg)
end
