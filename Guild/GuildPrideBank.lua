-- GuildPride: Gildenbank-Verlauf, lesbar
-- Blizzard zeigt je Fach nur ein schwer lesbares Protokoll. GuildPride liest es beim Öffnen der
-- Gildenbank (QueryGuildBankLog, nur Lesen) und zeigt alles in einem Fenster: wer was eingezahlt
-- oder genommen hat, mit Namensfilter und einer Wochensumme je Spieler.
-- Gespeichert (je Gilde, nur lokal) in GuildTable("bank"):
--   tabs[fach] = { read = Zeit, list = { { who, kind, item, count, t } } }
--   money      = { read = Zeit, list = { { who, kind, amount, t } } }
-- Gibt es auf dem Server keine Gildenbank, bleibt alles still; /gp bank sagt es dann.
local ADDON, ns = ...
local L = ns.L

local Bank = {}
ns.Bank = Bank
local MONEY_TAB = (tonumber(MAX_GUILDBANK_TABS) or 8) + 1
local WEEK = 7 * 86400

local function DB()
    local db = ns.GuildTable("bank")
    db.tabs = type(db.tabs) == "table" and db.tabs or {}
    db.money = type(db.money) == "table" and db.money or { list = {} }
    return db
end

local function Money(c)
    if ns.AH and ns.AH.Money then return ns.AH.Money(c) end
    return tostring(c)
end

function Bank.Available()
    return type(QueryGuildBankLog) == "function" and type(GetGuildBankTransaction) == "function"
end

-- „vor y Jahren, m Monaten, d Tagen, h Stunden“ -> Sekunden
local function Ago(y, m, d, h)
    return ((((tonumber(y) or 0) * 365 + (tonumber(m) or 0) * 30 + (tonumber(d) or 0)) * 24) + (tonumber(h) or 0)) * 3600
end
Bank.Ago = Ago

-- Fach einlesen (nach GUILDBANKLOG_UPDATE)
function Bank.ReadTab(tab, now)
    now = now or GetServerTime()
    local list = {}
    for i = 1, (GetNumGuildBankTransactions(tab) or 0) do
        local kind, who, item, count, _, _, y, m, d, h = GetGuildBankTransaction(tab, i)
        if kind and who then
            list[#list + 1] = { who = who, kind = kind, item = item, count = tonumber(count) or 1, t = now - Ago(y, m, d, h) }
        end
    end
    -- Noch nicht geladenes Fach (leere Antwort) überschreibt keinen gelesenen Stand
    local old = DB().tabs[tab]
    if #list == 0 and old and old.list and #old.list > 0 then return end
    DB().tabs[tab] = { read = now, list = list }
end

function Bank.ReadMoney(now)
    if not GetNumGuildBankMoneyTransactions then return end
    now = now or GetServerTime()
    local list = {}
    for i = 1, (GetNumGuildBankMoneyTransactions() or 0) do
        local kind, who, amount, y, m, d, h = GetGuildBankMoneyTransaction(i)
        if kind and who then
            list[#list + 1] = { who = who, kind = kind, amount = tonumber(amount) or 0, t = now - Ago(y, m, d, h) }
        end
    end
    local old = DB().money
    if #list == 0 and old and old.list and #old.list > 0 then return end
    DB().money = { read = now, list = list }
end

-- Alle Einträge, neueste zuerst; filter = Teil des Namens (ohne Groß/klein)
function Bank.Entries(filter)
    local out, db = {}, DB()
    filter = filter and strtrim(filter):lower() or ""
    local function Keep(e) return filter == "" or tostring(e.who):lower():find(filter, 1, true) end
    for tab, t in pairs(db.tabs) do
        for _, e in ipairs(t.list or {}) do
            if Keep(e) then out[#out + 1] = { who = e.who, kind = e.kind, item = e.item, count = e.count, t = e.t, tab = tab } end
        end
    end
    for _, e in ipairs(db.money.list or {}) do
        if Keep(e) then out[#out + 1] = { who = e.who, kind = e.kind, amount = e.amount, t = e.t } end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

-- Wochensumme je Spieler: { { who, deposit, withdraw, gold } } (gold = eingezahlt − genommen)
function Bank.WeekTotals(now, filter)
    now = now or GetServerTime()
    local by, list = {}, {}
    for _, e in ipairs(Bank.Entries(filter)) do
        if now - (e.t or 0) <= WEEK then
            local s = by[e.who]
            if not s then s = { who = e.who, deposit = 0, withdraw = 0, gold = 0 }; by[e.who] = s; list[#list + 1] = s end
            if e.amount then
                if e.kind == "deposit" then s.gold = s.gold + e.amount
                elseif e.kind == "withdraw" or e.kind == "repair" then s.gold = s.gold - e.amount end
            elseif e.kind == "deposit" then s.deposit = s.deposit + (e.count or 1)
            elseif e.kind == "withdraw" then s.withdraw = s.withdraw + (e.count or 1) end
        end
    end
    table.sort(list, function(a, b)
        if a.withdraw ~= b.withdraw then return a.withdraw > b.withdraw end
        return a.who < b.who
    end)
    return list
end

local KIND_COLOR = { deposit = "40ff40", withdraw = "ff8060", repair = "ff8060" }
local function KindText(kind)
    if kind == "deposit" then return L["eingezahlt"] end
    if kind == "withdraw" then return L["genommen"] end
    if kind == "repair" then return L["Reparatur"] end
    if kind == "move" then return L["verschoben"] end
    return tostring(kind)
end

local function AgoText(sec)
    sec = math.max(0, sec)
    if sec < 3600 then return L["gerade eben"] end
    if sec < 86400 then return (L["vor %d Std."]):format(math.floor(sec / 3600)) end
    return (L["vor %d Tagen"]):format(math.floor(sec / 86400))
end

function Bank.LineText(e, now)
    now = now or GetServerTime()
    local obj
    if e.amount then
        obj = Money(e.amount)
    else
        obj = (e.count and e.count > 1 and (e.count .. "× ") or "") .. (e.item or "?")
            .. (e.tab and ("  |cff777777" .. (L["Fach %d"]):format(e.tab) .. "|r") or "")
    end
    return ("|cff999999%s|r  %s  |cff%s%s|r  %s"):format(AgoText(now - (e.t or now)), Ambiguate(e.who, "guild"),
        KIND_COLOR[e.kind] or "aaaaaa", KindText(e.kind), obj)
end

---------------------------------------------------------------------
-- Einlesen beim Öffnen der Gildenbank
---------------------------------------------------------------------
-- Neuere Clients (auch WoW Forever) melden die Gildenbank nicht mehr mit
-- GUILDBANKFRAME_OPENED, sondern über PLAYER_INTERACTION_MANAGER_FRAME_SHOW.
-- Der Server beantwortet nur eine Protokoll-Abfrage nach der anderen: Fächer
-- darum einzeln im Abstand abfragen, jede Antwort (GUILDBANKLOG_UPDATE) einlesen.
local ev = CreateFrame("Frame")
local open, session = false, 0
local GUILD_BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
local function ReadAll()
    if not Bank.Available() or not IsInGuild() then return end
    local now = GetServerTime()
    for tab = 1, (GetNumGuildBankTabs and GetNumGuildBankTabs() or 0) do ns.Try(Bank.ReadTab, tab, now) end
    ns.Try(Bank.ReadMoney, now)
    if Bank.Refresh then Bank.Refresh() end
end
local function Query()
    if not Bank.Available() then return end
    session = session + 1
    local mine = session
    local list = {}
    for tab = 1, (GetNumGuildBankTabs and GetNumGuildBankTabs() or 0) do list[#list + 1] = tab end
    list[#list + 1] = MONEY_TAB
    for i, tab in ipairs(list) do
        C_Timer.After((i - 1) * 0.8, function()
            if not open or mine ~= session then return end
            pcall(QueryGuildBankLog, tab)
        end)
    end
    -- falls eine Antwort kein Ereignis auslöst: am Ende noch einmal alles lesen
    C_Timer.After(#list * 0.8 + 1, function() if open and mine == session then ReadAll() end end)
end
local function Opened()
    if open then return end
    open = true
    C_Timer.After(0.5, Query)
end
local function Closed() open = false end
for _, e in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKLOG_UPDATE",
                     "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
                     "ADDON_LOADED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local hooked = false
local function HookFrame()
    -- Zusätzlich am Blizzard-Fenster selbst (lädt erst beim ersten Öffnen)
    if hooked or not GuildBankFrame then return end
    hooked = true
    GuildBankFrame:HookScript("OnShow", Opened)
    GuildBankFrame:HookScript("OnHide", Closed)
    if GuildBankFrame:IsShown() then Opened() end
end
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "GUILDBANKFRAME_OPENED" then Opened()
    elseif event == "GUILDBANKFRAME_CLOSED" then Closed()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg == GUILD_BANKER then Opened()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and arg == GUILD_BANKER then Closed()
    elseif event == "ADDON_LOADED" and arg == "Blizzard_GuildBankUI" then HookFrame()
    elseif event == "GUILDBANKLOG_UPDATE" and open then ReadAll() end
end)
HookFrame()

---------------------------------------------------------------------
-- Fenster (/gp bank, Verwaltung › „Gildenbank …“)
---------------------------------------------------------------------
local win, mode = nil, "log"
local function Build()
    win = ns.ListWindow({ name = "GuildPrideBankLog", title = L["Gildenbank-Verlauf"], rows = 14, width = 520,
        sub = L["Aus Blizzards Protokoll, gelesen beim letzten Öffnen der Gildenbank. Mausrad blättert."],
        empty = L["Noch nichts gelesen – öffne einmal die Gildenbank."] })
    local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    box:SetSize(160, 22); box:SetPoint("TOPLEFT", 20, win.bottomY)
    box:SetAutoFocus(false); box:SetMaxLetters(40)
    if ns.SkinEditBox then ns.SkinEditBox(box) end
    local hint = box:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    hint:SetPoint("LEFT", 2, 0); hint:SetText(L["Name filtern"])
    box:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == ""); Bank.Refresh() end)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    local sw = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(sw) end
    sw:SetSize(170, 22); sw:SetPoint("LEFT", box, "RIGHT", 10, 0)
    sw:SetScript("OnClick", function() mode = mode == "log" and "week" or "log"; win.offset = 0; Bank.Refresh() end)
    win.box, win.sw = box, sw
    win:SetScript("OnShow", function() win.offset = 0; Bank.Refresh() end)
end

function Bank.Refresh()
    if not win or not win:IsShown() then return end
    local now, lines, filter = GetServerTime(), {}, win.box:GetText()
    if mode == "week" then
        win.sw:SetText(L["Einzelne Einträge"])
        for _, s in ipairs(Bank.WeekTotals(now, filter)) do
            local gold = s.gold ~= 0 and ("  ·  " .. (s.gold > 0 and "|cff40ff40+" or "|cffff8060-") .. Money(math.abs(s.gold)) .. "|r") or ""
            lines[#lines + 1] = ("%s  |cff40ff40%s|r  |cffff8060%s|r%s"):format(Ambiguate(s.who, "guild"),
                (L["%d eingezahlt"]):format(s.deposit), (L["%d genommen"]):format(s.withdraw), gold)
        end
    else
        win.sw:SetText(L["Wochensumme je Spieler"])
        for _, e in ipairs(Bank.Entries(filter)) do lines[#lines + 1] = Bank.LineText(e, now) end
    end
    win:SetLines(lines)
end

function Bank.Toggle()
    if not Bank.Available() then ns.Print(L["Auf diesem Server gibt es keine Gildenbank."]); return end
    if not win then Build() end
    win:SetShown(not win:IsShown())
end

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):match("^(%S+)")
    cmd = cmd and cmd:lower()
    if cmd == "bank" or cmd == "gildenbank" then Bank.Toggle()
    elseif origSlash then origSlash(arg) end
end
