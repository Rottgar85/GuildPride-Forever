-- GuildPride-Fenstertest: lua5.1 tests/windows.lua (aus dem Hauptordner, eigener Lauf)
-- Lädt alle Dateien der .toc, startet das Addon und öffnet jeden Reiter und jedes Fenster einmal.
-- Findet vertippte Namen, fehlende Felder und falsche Ladereihenfolge – nicht, wie es aussieht.
package.path = "./tests/?.lua;" .. package.path
local W = require("wow")
local ns = W.ns

---------------------------------------------------------------------
-- Fenster-Nachbau: merkt sich Größe, Text, Haken und Sichtbarkeit. Unbekannte Methoden
-- (beginnen mit einem Tätigkeitswort) tun nichts, unbekannte Felder sind nil wie im Spiel.
---------------------------------------------------------------------
local Widget = {}
local widgets = {}
local VERBS = {}
for v in ("Set Get Is Enable Disable Register Unregister Clear Start Stop Add Remove Play Highlight Insert Lock Unlock Raise Lower "
    .. "Create Hook Has Can Use Update Show Hide Toggle Click Desaturate Reset Release Acquire Adjust Apply Refresh Initialize "
    .. "Open Close Enum Num Propagate Execute Wrap Assign Trigger Append Copy Finish Restart Pause"):gmatch("%a+") do VERBS[v] = true end
local mt = { __index = Widget }   -- wie im Spiel: __index ist eine Tabelle
setmetatable(Widget, { __index = function(_, k)
    if type(k) == "string" and VERBS[k:match("^%u%l+") or ""] then return function() end end
end })
local function New(parent, name)
    local w = setmetatable({ scripts = {}, events = {}, _shown = true, _w = 100, _h = 20, _parent = parent, _name = name }, mt)
    widgets[#widgets + 1] = w
    if type(name) == "string" then _G[name] = w end
    return w
end
local function Run(w, script, ...)
    local fn = w.scripts[script]
    if fn then fn(w, ...) end
end
function Widget:SetScript(k, fn) self.scripts[k] = fn end
function Widget:GetScript(k) return self.scripts[k] end
function Widget:HasScript() return true end
function Widget:HookScript(k, fn)
    local old = self.scripts[k]
    self.scripts[k] = old and function(...) old(...); fn(...) end or fn
end
function Widget:RegisterEvent(e) self.events[e] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:CreateTexture() return New(self) end
Widget.CreateFontString, Widget.CreateMaskTexture, Widget.CreateLine = Widget.CreateTexture, Widget.CreateTexture, Widget.CreateTexture
function Widget:CreateAnimationGroup() return New(self) end
Widget.CreateAnimation = Widget.CreateAnimationGroup
function Widget:Show() if not self._shown then self._shown = true; Run(self, "OnShow") end end
function Widget:Hide() if self._shown then self._shown = false; Run(self, "OnHide") end end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:SetWidth(w) self._w = w end
function Widget:SetHeight(h) self._h = h end
function Widget:GetSize() return self._w, self._h end
function Widget:GetWidth() return self._w end
function Widget:GetHeight() return self._h end
for _, k in ipairs({ "GetStringWidth", "GetUnboundedStringWidth", "GetTextWidth" }) do
    Widget[k] = function(self) return #tostring(self._text or "") * 6 end
end
for _, k in ipairs({ "GetStringHeight", "GetLineHeight", "GetTextHeight", "GetNumLines" }) do Widget[k] = function() return 12 end end
for k, v in pairs({ GetLeft = 0, GetBottom = 0, GetRight = 800, GetTop = 600, GetFrameLevel = 1, GetAlpha = 1, GetScale = 1,
    GetEffectiveScale = 1, GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetHorizontalScroll = 0, GetValue = 0,
    GetCursorPosition = 0, GetNumLetters = 0, GetNumPoints = 1, GetNumMessages = 0, GetSpacing = 0, GetZoom = 0, GetID = 1 }) do
    Widget[k] = function() return v end
end
function Widget:SetText(t) self._text = t end
function Widget:SetFormattedText(f, ...) self._text = f:format(...) end
function Widget:GetText() return self._text or "" end
function Widget:SetChecked(v) self._checked = v and true or false end
function Widget:GetChecked() return self._checked or false end
function Widget:SetEnabled(v) self._disabled = not v end
function Widget:IsEnabled() return not self._disabled end
function Widget:GetParent() return self._parent end
function Widget:SetParent(p) self._parent = p end
function Widget:GetName() return self._name end
function Widget:GetObjectType() return "Frame" end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:GetCenter() return 400, 300 end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Widget:GetTextColor() return 1, 1, 1, 1 end
Widget.GetVertexColor, Widget.GetShadowColor, Widget.GetBackdropColor = Widget.GetTextColor, Widget.GetTextColor, Widget.GetTextColor
function Widget:GetFontString() self._fs = self._fs or New(self); return self._fs end
for _, k in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetCheckedTexture",
    "GetStatusBarTexture", "GetThumbTexture" }) do
    Widget[k] = function(self) local f = "_" .. k; local t = rawget(self, f); if not t then t = New(self); self[f] = t end; return t end
end
for _, k in ipairs({ "ScrollToBottom", "ScrollToTop", "ScrollUp", "ScrollDown" }) do Widget[k] = function() end end
function Widget:SetScrollChild(c) self._child = c end
function Widget:GetScrollChild() return self._child end
function Widget:GetAttribute(k) return self._attr and self._attr[k] end
function Widget:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end

function CreateFrame(_, name, parent, template)
    local w = New(parent, type(name) == "string" and name or nil)
    -- Teile, die Blizzards Vorlagen mitbringen
    if type(template) == "string" then
        if template:find("ScrollFrame") then w.ScrollBar = New(w) end
        if template:find("BasicFrame") then w.CloseButton = New(w) end
        if template:find("Slider") then w.Low, w.High, w.Text = New(w), New(w), New(w) end
        if template:find("CheckButton") then w.text, w.Text = New(w), New(w) end
    end
    return w
end
function CreateFont(name) return New(nil, name) end
for _, k in ipairs({ "UIParent", "Minimap", "GameTooltip", "ItemRefTooltip", "WorldMapFrame", "DEFAULT_CHAT_FRAME", "ChatFrame1", "WorldFrame",
    "CharacterFrame", "PaperDollFrame", "CharacterModelFrame", "CharacterModelScene" }) do
    New(nil, k)
end
GameTooltip.NumLines = function() return 0 end
WorldMapFrame._shown = false
CreateFromMixins = function(...)
    local t = {}
    for i = 1, select("#", ...) do for k, v in pairs((select(i, ...)) or {}) do t[k] = v end end
    return t
end
MapCanvasPinMixin, MapCanvasDataProviderMixin = {}, {}

-- Globale: GROSS_GESCHRIEBEN ist ein Text (Blizzards Textbausteine) oder eine Zahl, sonst das
-- Alles-Objekt aus wow.lua; gespeicherte Daten und Addons, die es hier nicht gibt, sind nil
local oldIndex = getmetatable(_G).__index
local NONE = { GuildPrideRaresDB = true, ScalesDB = true, ScalesCharDB = true, LibStub = true, AuctionFrame = true, AuctionHouseFrame = true, ProfessionsFrame = true, TradeSkillFrame = true,
    MerchantFrame = true, MailFrame = true, BankFrame = true, LFGBrowseFrame = true, LFGParentFrame = true, TaxiFrame = true, FlightMapFrame = true, ElvUI = true, Bagnon = true,
    Baganator = true, WorldMapFrame = true, BattlefieldMapFrame = true, CommunitiesFrame = true, GuildFrame = true, FriendsFrame = true, CUSTOM_CLASS_COLORS = true,
    C_AddOnProfiler = true, ChatFrameUtil = true, TooltipDataProcessor = true, GetColoredName = true }
setmetatable(_G, { __index = function(t, k)
    if NONE[k] or (type(k) == "string" and k:find("^ContainerFrame")) then return nil end
    if type(k) == "string" and k:match("^%u[%u%d_]+$") then
        if k:find("^NUM_") or k:find("^MAX_") or k:find("^LE_") or k:find("_MAX") then return 1 end
        return k
    end
    return oldIndex(t, k)
end })

-- Zahlen und Texte, mit denen das Addon gleich rechnet
GetScreenWidth, GetScreenHeight = function() return 1920 end, function() return 1080 end
GetCursorPosition = function() return 0, 0 end
GetLocale = function() return "deDE" end
UnitLevel, UnitHealth, GetMoney = function() return 60 end, function() return 1 end, function() return 12345 end
GetNumGroupMembers = function() return 0 end
GetNumSkillLines, GetNumFriends, GetNumQuestLogEntries = function() return 0 end, function() return 0 end, function() return 0 end
UnitClass = function() return "Krieger", "WARRIOR", 1 end
UnitRace = function() return "Mensch", "Human", 1 end
UnitGUID = function() return "Player-1-0000001" end
UnitPosition = function() return nil end
IsInInstance = function() return false, "none" end
GetAddOnMetadata = function(_, k) return k == "Version" and "9.9.9" or nil end
C_AddOns.GetAddOnMetadata = GetAddOnMetadata
C_AddOns.GetNumAddOns = function() return 0 end
GetNumAddOns = C_AddOns.GetNumAddOns
GetGuildRosterMOTD = function() return "Hallo" end
GetGuildInfoText = function() return "" end
GetChannelName = function() return 0 end
GetCVar, GetCVarBool = function() return "0" end, function() return false end
C_Map = { GetBestMapForUnit = function() return 1429 end, GetMapInfo = function(id) return { mapID = id, name = "Karte", mapType = 3, parentMapID = 0 } end,
    GetPlayerMapPosition = function() return nil end, GetMapWorldSize = function() return 1000, 1000 end,
    GetMapChildrenInfo = function() return {} end }
C_Texture = { GetAtlasInfo = function() return nil end }
C_QuestLog = { GetNumQuestLogEntries = function() return 0 end, GetInfo = function() return nil end }
C_FriendList = { GetNumFriends = function() return 0 end }
C_Timer.NewTimer = function() return { Cancel = function() end } end
C_Timer.NewTicker = C_Timer.NewTimer
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
Enum = setmetatable({}, { __index = function(t, k)
    local e = setmetatable({}, { __index = function() return 0 end }); rawset(t, k, e); return e
end })
hooksecurefunc = function() end
GetGuildRosterLastOnline = function() return 0, 0, 1, 2 end
GetNumTalentTabs, GetNumTalents, GetNumSpecializations = function() return 0 end, function() return 0 end, function() return 0 end
C_SpecializationInfo = { GetSpecialization = function() return nil end }
for _, k in ipairs({ "UnitStat", "UnitArmor", "UnitAttackPower", "UnitRangedAttackPower", "UnitResistance", "UnitDefense", "UnitDamage", "UnitAttackSpeed",
    "GetCombatRating", "GetCombatRatingBonus", "GetSpellBonusDamage", "GetSpellBonusHealing", "GetCritChance", "GetRangedCritChance", "GetSpellCritChance",
    "GetHitModifier", "GetSpellHitModifier", "GetDodgeChance", "GetParryChance", "GetBlockChance", "GetManaRegen", "GetHaste", "GetMeleeHaste",
    "GetMasteryEffect", "GetVersatilityBonus", "GetExpertise", "GetShieldBlock", "UnitHealthMax", "UnitPowerMax", "UnitSpellHaste" }) do
    _G[k] = function() return 1, 1, 0, 0 end
end
GetSpecialization, GetPrimaryTalentTree = function() return nil end, function() return nil end
W.roster = { { "Tester", 1 }, { "Gm", 0 }, { "Anna", 3, 20, false } }

---------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------
local failed, passed = 0, 0
local function guard(name, fn)
    local n = 0
    debug.sethook(function() n = n + 1; if n > 100 then error("Endlosschleife") end end, "", 1000000)
    local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
    debug.sethook()
    if ok then passed = passed + 1; return true end
    failed = failed + 1
    print("FEHLER " .. name .. ": " .. tostring(err):sub(1, 900))
end
geterrorhandler = function() return function(e) error(e, 0) end end
seterrorhandler = function() end

local files = 0
for line in io.lines("GuildPrideForever.toc") do
    local path = line:gsub("\r", ""):gsub("\\", "/")
    if path:match("%.lua$") and not path:find("^#") then
        files = files + 1
        guard("laden " .. path, function() assert(loadfile(path))("GuildPrideForever", ns) end)
    end
end
ns.Print = function() end

local function Fire(event, ...)
    local list = {}
    for _, w in ipairs(widgets) do if w.events[event] and w.scripts.OnEvent then list[#list + 1] = w end end
    for i, w in ipairs(list) do
        local args = { ... }
        guard(event .. " #" .. i, function() w.scripts.OnEvent(w, event, unpack(args)) end)
    end
end
Fire("ADDON_LOADED", "GuildPrideForever")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
Fire("GUILD_ROSTER_UPDATE")

-- Fenster; fehlt eines, ist das ein Fehler
local function call(name, ...)
    local args, n = { ... }, select("#", ...)
    guard(name, function()
        local f = ns
        for part in name:gmatch("[^.]+") do f = type(f) == "table" and f[part] or nil end
        if type(f) ~= "function" then error("fehlt: ns." .. name, 0) end
        f(unpack(args, 1, n))
    end)
end

call("ToggleUI")
local tabs, seen = 0, {}
for id = 1, 40 do
    guard("Reiter " .. id, function()
        ns.OpenTab({ tabId = id })
        local key = ns.CurrentTabKey()
        if key and not seen[key] then seen[key] = true; tabs = tabs + 1 end
        ns.RefreshUI()
    end)
end
call("ShowIntro"); call("ShowIntro", true); call("ShowSetup"); call("ShowNews")
call("ShowCopy", "Titel", "Text")
call("ToggleBackupWindow"); call("BugReport"); call("ErrorReport")
call("ErrorShare.Toggle"); call("ErrorShare.Refresh")
call("ToggleApps"); call("ShowCreateDialog"); call("ShowPollDialog")
call("Players.Toggle"); call("Transit.UpdateWindow")
call("Zettel.OpenWriter"); call("Zettel.UpdateMinimap")
call("Ready.Open"); call("GuildQuests.Open"); call("BossNotes.Open"); call("Stock.Open"); call("EventStats.Open")
call("Loot.Open"); call("Album.Open"); call("Cooldowns.Open"); call("Mentor.Open"); call("Quiz.Open"); call("Search.Open", "hand")
for _, p in ipairs({ "guild", "raid", "all" }) do call("ApplyPreset", p) end
call("ApplyReadable")
call("Search.Help"); call("Usage.Open"); call("Usage.Choose", true); call("Usage.HookWindows"); call("Hunt.Open"); call("ShowCreateDialog")
call("DiagReport")

for _, cmd in ipairs({ "", "dkp", "bank", "spieler", "hilfe", "zettel", "zettel schreiben", "handwerk", "handwerk mini", "tracker",
    "buff", "rast", "rares", "wunsch", "wishlist", "board", "abwesenheit", "block", "nachrichten", "willkommen", "diag", "melden",
    "fehler", "version", "sicherung", "bewerbungen", "intro", "neu", "ah", "export", "import" }) do
    guard("/gp " .. cmd, function() SlashCmdList.GUILDPRIDE(cmd) end)
end

print(("\nFenster: %d Dateien, %d Reiter, %d Schritte ohne Fehler, %d fehlgeschlagen"):format(files, tabs, passed, failed))
if tabs < 5 then print("FEHLER zu wenige Reiter geöffnet"); failed = failed + 1 end
if failed > 0 then os.exit(1) end
