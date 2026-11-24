-- GuildPride: Nutzungs-Statistik (was wird benutzt, was nicht) für den Entwickler
--
-- Nur mit Zustimmung (GuildPrideDB.usageShare: nil = noch nicht gefragt, true, false; Schalter unter
-- Einstellungen › Teilen). Ohne Ja wird nichts gezählt und nichts gesendet. Gezählt wird nur, welche
-- Reiter, GuildPride-Fenster und /gp-Befehle geöffnet wurden (nie, was darin steht), dazu welche
-- Schalter vom Standard abweichen. Höchstens einmal am Tag, per Flüstern an den Entwickler, auf dem
-- Weg des Fehler-Versands (GuildPrideErrorShare.lua: DVA -> DVU -> DVK).
-- Der Entwickler speichert keine Namen, nur einen Zählcode.
local ADDON, ns = ...
local L = ns.L

local U = {}
ns.Usage = U
local FIELD = "\029"
local DAY, GAP = 86400, 20 * 3600
local KEEP, PLAYERS_MAX, USE_MAX = 60, 2000, 60

local function Enabled() return type(GuildPrideDB) == "table" and GuildPrideDB.usageShare == true end
local function IsDev() return ns.IsDev and ns.IsDev() or false end

local function Own()
    local u = GuildPrideDB.usage
    if type(u) ~= "table" then u = {}; GuildPrideDB.usage = u end
    u.use, u.days = type(u.use) == "table" and u.use or {}, u.days or 0
    return u
end

-- feature: "tab:30", "win:GuildPrideLoot", "cmd:loot"
function U.Count(feature)
    if not Enabled() or type(feature) ~= "string" or not feature:match("^%a+:[%w_]+$") or #feature > 40 then return false end
    local u = Own()
    if not u.use[feature] then
        local n = 0
        for _ in pairs(u.use) do n = n + 1 end
        if n >= USE_MAX then return false end
    end
    u.use[feature] = (u.use[feature] or 0) + 1
    local today = math.floor(GetServerTime() / DAY)
    if u.lastDay ~= today then u.lastDay = today; u.days = u.days + 1 end
    return true
end

---------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------
local function Pairs(t)
    local out = {}
    for k, n in pairs(t) do out[#out + 1] = k .. "=" .. n end
    table.sort(out)
    return table.concat(out, ",")
end
-- Schalter, die vom Standard abweichen: "+key" (an) oder "-key" (aus)
local function Changed()
    local out = {}
    for k, d in pairs(ns.DEFAULTS or {}) do
        if type(d) == "boolean" and type(GuildPrideDB[k]) == "boolean" and GuildPrideDB[k] ~= d then
            out[#out + 1] = (GuildPrideDB[k] and "+" or "-") .. k
        end
    end
    table.sort(out)
    return table.concat(out, ",")
end
function U.Encode()
    local u = Own()
    return table.concat({ ns.VERSION or "0.0.0", u.days, Pairs(u.use):sub(1, 1500), Changed():sub(1, 600) }, FIELD)
end

function U.OnHello(sender)
    if not Enabled() or IsDev() or not next(Own().use) then return end
    if GetServerTime() - (GuildPrideDB.usageSent or 0) < GAP then return end
    C_Timer.After(70 + math.random() * 120, function()
        if not Enabled() or GetServerTime() - (GuildPrideDB.usageSent or 0) < GAP then return end
        local u = Own()
        u.pending = {}
        for k, n in pairs(u.use) do u.pending[k] = n end
        u.pendingDays = u.days
        ns.ErrorShare.Send(sender, "DVU", "u" .. math.floor(GetServerTime() / 60), U.Encode(), Enabled)
    end)
end
-- Bestätigt: nur das Gesendete abziehen (inzwischen Gezähltes bleibt)
function U.OnAck(id)
    if type(id) ~= "string" or id:sub(1, 1) ~= "u" or not Enabled() then return end
    local u = Own()
    if type(u.pending) ~= "table" then return end
    for k, n in pairs(u.pending) do
        local left = (u.use[k] or 0) - n
        u.use[k] = left > 0 and left or nil
    end
    u.days = math.max(0, u.days - (u.pendingDays or 0))
    u.pending, u.pendingDays = nil, nil
    GuildPrideDB.usageSent = GetServerTime()
end

---------------------------------------------------------------------
-- Entwickler: sammeln und auswerten
---------------------------------------------------------------------
local function Store()
    if type(GuildPrideDB.devUsage) ~= "table" then GuildPrideDB.devUsage = {} end
    return GuildPrideDB.devUsage
end
-- Zählcode statt Name (Hash aus GuildPrideErrorShare.lua). true = in Ordnung, wird bestätigt
function U.Collect(data, code)
    local f = {}
    for part in (data .. FIELD):gmatch("(.-)" .. FIELD) do f[#f + 1] = part end
    if #f ~= 4 or #f[1] > 20 or not f[1]:match("^%d+%.%d+[%.%d]*$") then return false end
    local days = tonumber(f[2])
    if not days or days < 0 or days > 400 or days % 1 ~= 0 then return false end
    local use, n = {}, 0
    for k, c in f[3]:gmatch("(%a+:[%w_]+)=(%d+)") do
        c = tonumber(c)
        if #k <= 40 and c >= 1 and c <= 100000 and n < USE_MAX and not use[k] then use[k] = c; n = n + 1 end
    end
    if n == 0 then return false end
    local db = Store()
    local p = db[code]
    if not p then
        local count, oldest = 0, nil
        for k, x in pairs(db) do
            count = count + 1
            if not oldest or x.last < db[oldest].last then oldest = k end
        end
        if count >= PLAYERS_MAX and oldest then db[oldest] = nil end
        p = { use = {}, days = 0 }
        db[code] = p
    end
    p.last, p.v, p.days = GetServerTime(), f[1], p.days + days
    for k, c in pairs(use) do p.use[k] = (p.use[k] or 0) + c end
    p.off = {}
    n = 0
    for key in f[4]:gmatch("[+-][%w_]+") do
        if #key <= 40 and n < 60 then p.off[#p.off + 1] = key; n = n + 1 end
    end
    return true
end

-- Alles, was es gibt: damit auch „nie benutzt“ auffällt
local function Known()
    local out = {}
    for _, t in pairs(ns.UIParts and ns.UIParts.tabs or {}) do if t.key then out["tab:" .. t.key] = true end end
    for _, name in ipairs(UISpecialFrames) do
        if name:find("^GuildPride%w+$") and name ~= "GuildPrideFrame" and not name:find("^GuildPrideDev") then out["win:" .. name] = true end
    end
    for _, c in ipairs(ns.Search and ns.Search.COMMANDS or {}) do out["cmd:" .. c[1]:match("^%S+")] = true end
    return out
end

function U.Report(days)
    local since = GetServerTime() - (days or KEEP) * DAY
    local players, use, off, versions = 0, {}, {}, {}
    for _, p in pairs(Store()) do
        if p.last >= since then
            players = players + 1
            versions[p.v] = (versions[p.v] or 0) + 1
            for k, n in pairs(p.use) do
                local u = use[k] or { key = k, players = 0, n = 0 }
                u.players, u.n = u.players + 1, u.n + n
                use[k] = u
            end
            for _, k in ipairs(p.off or {}) do off[k] = (off[k] or 0) + 1 end
        end
    end
    for k in pairs(Known()) do use[k] = use[k] or { key = k, players = 0, n = 0 } end
    local list, offList = {}, {}
    for _, u in pairs(use) do list[#list + 1] = u end
    table.sort(list, function(a, b)
        if a.players ~= b.players then return a.players > b.players end
        if a.n ~= b.n then return a.n > b.n end
        return a.key < b.key
    end)
    for k, n in pairs(off) do offList[#offList + 1] = { key = k, n = n } end
    table.sort(offList, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.key < b.key end)
    return { players = players, list = list, off = offList, versions = versions }
end

-- Lesbarer Name einer Funktion
local function Label(key)
    local kind, id = key:match("^(%a+):(.+)$")
    if kind == "tab" then
        for _, t in pairs(ns.UIParts and ns.UIParts.tabs or {}) do if t.key == id then return "Reiter " .. (t.defaultLabel or id) end end
        return "Reiter " .. id
    elseif kind == "cmd" then
        return "/gp " .. id
    end
    local f = _G[id]
    local title = type(f) == "table" and type(f.title) == "table" and f.title.GetText and f.title:GetText()
    return "Fenster " .. (type(title) == "string" and title ~= "" and title or (id:gsub("^GuildPride", "")))
end

function U.Lines()
    local r = U.Report()
    if r.players == 0 then return { "Noch keine Daten. Spieler senden nur, wenn sie zugestimmt haben und du online bist." } end
    local lines = { ("|cffffd100%d Spieler in den letzten %d Tagen|r"):format(r.players, KEEP) }
    local v = {}
    for k, n in pairs(r.versions) do v[#v + 1] = k .. " (" .. n .. ")" end
    table.sort(v)
    lines[#lines + 1] = "|cff999999Versionen: " .. table.concat(v, ", ") .. "|r"
    lines[#lines + 1] = "|cffffd100Nutzung: Spieler · Anteil · geöffnet|r"
    for _, u in ipairs(r.list) do
        local pct = math.floor(u.players / r.players * 100 + 0.5)
        local col = u.players == 0 and "ff6060" or (pct >= 50 and "40ff40" or (pct >= 20 and "ffd100" or "e6e0da"))
        lines[#lines + 1] = ("   |cff%s%d · %d %%|r  |cff999999%d×|r  %s"):format(col, u.players, pct, u.n, Label(u.key))
    end
    if #r.off > 0 then
        lines[#lines + 1] = "|cffffd100Schalter anders als ab Werk (+ an, - aus)|r"
        for _, o in ipairs(r.off) do
            lines[#lines + 1] = ("   %d · %d %%  %s"):format(o.n, math.floor(o.n / r.players * 100 + 0.5), o.key)
        end
    end
    return lines
end

local win
function U.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideDevUsage", title = "Nutzung von GuildPride", rows = 20, width = 520,
            sub = "Nur von Spielern, die zugestimmt haben. Rot = nie benutzt. Mausrad blättert." })
        local function Button(label, x, fn)
            local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(b) end
            b:SetSize(140, 22); b:SetPoint("TOPLEFT", x, win.bottomY); b:SetText(label)
            b:SetScript("OnClick", fn)
        end
        Button("Kopieren", 14, function()
            local text = table.concat(U.Lines(), "\n"):gsub("|cff%x%x%x%x%x%x", ""):gsub("|r", "")
            if ns.ShowCopy then ns.ShowCopy("GuildPride-Nutzung", text) end
        end)
        Button("Aktualisieren", 162, function() win:SetLines(U.Lines()) end)
        win:SetScript("OnShow", function() win.offset = 0; win:SetLines(U.Lines()) end)
    end
    win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------
-- Zählen: Fenster (alle GuildPride-Fenster, die Escape schließt) und /gp-Befehle
---------------------------------------------------------------------
local hooked = {}
local function HookWindows()
    if not Enabled() then return end
    for _, name in ipairs(UISpecialFrames) do
        local f = type(name) == "string" and name:find("^GuildPride%w+$") and _G[name]
        -- das Gildenfenster selbst zählt über seine Reiter
        if type(f) == "table" and f.HookScript and not hooked[name] and name ~= "GuildPrideFrame" then
            hooked[name] = true
            f:HookScript("OnShow", function() U.Count("win:" .. name) end)
            if f:IsShown() then U.Count("win:" .. name) end
        end
    end
end
U.HookWindows = HookWindows

---------------------------------------------------------------------
-- Frage (einmal)
---------------------------------------------------------------------
function U.ShouldAsk()
    return type(GuildPrideDB) == "table" and GuildPrideDB.usageShare == nil and not IsDev() and (GuildPrideDB.introSeen or 0) > 0
end
local ask, asked
function U.Choose(yes)
    GuildPrideDB.usageShare = yes and true or false
    if not yes then GuildPrideDB.usage = nil end
    if ask then ask:Hide() end
    if yes then HookWindows() end
    if ns.RefreshUI then ns.RefreshUI() end
end
-- Schalter in den Einstellungen: ausschalten löscht das Gezählte
function U.Changed()
    if GuildPrideDB.usageShare ~= true then GuildPrideDB.usage = nil else HookWindows() end
end

local function BuildAsk()
    ask = CreateFrame("Frame", "GuildPrideUsageAsk", UIParent, "BackdropTemplate")
    ask:SetSize(420, 220)
    ask:SetPoint("CENTER", 0, 120)
    ask:SetFrameStrata("DIALOG")
    ask:SetMovable(true); ask:EnableMouse(true); ask:SetClampedToScreen(true)
    ask:RegisterForDrag("LeftButton")
    ask:SetScript("OnDragStart", ask.StartMoving)
    ask:SetScript("OnDragStop", ask.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(ask) end
    local title = ask:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 14, -12); title:SetText(L["Hilfst du mit, GuildPride zu verbessern?"])
    if ns.Paint then ns.Paint(title, "heading") end
    local text = ask:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    text:SetPoint("TOPLEFT", 14, -40); text:SetWidth(392); text:SetJustifyH("LEFT")
    text:SetText(L["Darf GuildPride dem Entwickler mitteilen, welche Funktionen du benutzt? So sieht er, was sich lohnt und was weg kann.\n\nGezählt wird nur, welche Reiter, GuildPride-Fenster und /gp-Befehle du öffnest und welche Schalter du geändert hast – nie Inhalte, Chat, Gold oder Namen. Höchstens einmal am Tag, im Spiel an den Entwickler; gespeichert wird dort nur ein Zählcode statt deines Namens.\n\nDu kannst das jederzeit ändern: Einstellungen › Teilen."])
    local function Button(label, yes, ...)
        local b = CreateFrame("Button", nil, ask, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(150, 24); b:SetPoint(...); b:SetText(label)
        b:SetScript("OnClick", function() U.Choose(yes) end)
    end
    Button(L["Ja, gern"], true, "BOTTOMLEFT", 14, 12)
    Button(L["Nein"], false, "BOTTOMRIGHT", -14, 12)
    ask:SetScript("OnShow", function(self)
        local h = text:GetStringHeight()
        if type(h) == "number" and h > 0 then self:SetHeight(h + 96) end
    end)
    ask:Hide()
end
local function TryAsk()
    if asked or not U.ShouldAsk() then return end
    if InCombatLockdown() or IsInInstance() then C_Timer.After(300, TryAsk) return end
    asked = true
    if not ask then BuildAsk() end
    ask:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    -- Befehle: nur das erste Wort und nur bekannte (Liste der Suche)
    local slash = SlashCmdList.GUILDPRIDE
    SlashCmdList.GUILDPRIDE = function(arg)
        local cmd = strtrim(arg or ""):lower():match("^(%S+)")
        if cmd then
            for _, c in ipairs(ns.Search and ns.Search.COMMANDS or {}) do
                if c[1]:match("^%S+") == cmd then U.Count("cmd:" .. cmd) break end
            end
        end
        return slash(arg)
    end
    HookWindows()
    ns.Every(30, HookWindows)
    C_Timer.After(600, TryAsk)
end)
