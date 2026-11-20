-- GuildPride: Schiffs-Zähler am Anleger. Steht man an einem Steg oder Zeppelinturm, zeigt ein
-- kleines, verschiebbares Fenster je Verbindung eine Karte: Schiffs- bzw. Zeppelin-Symbol, Ziel,
-- rechts groß der Countdown (grün „legt ab“, solange es am Steg liegt; gold „kommt an“), darunter
-- wann das nächste kommt, und ein dünner Balken für den Fortschritt. Ungemessene Verbindungen zeigen
-- die mittlere Wartezeit (gemessen wird beim Mitfahren, siehe GuildPrideTransit.lua).
-- Symbole: Media/transit_boat.tga und transit_zeppelin.tga aus Polestar (GPL-3.0-only).
-- Aus: Einstellungen › „Schiffs-Zähler am Anleger zeigen“. X blendet es aus, bis du den Anleger verlässt.
-- Die Uhr an einer Karte erinnert 1 Minute vor der Abfahrt (Raid-Warnung und Ton), auch wenn du
-- inzwischen woanders bist.
local ADDON, GP = ...
local T = GP.Transit
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })
if not T then return end

local ROWS, ROW_H, GAP, WIDTH = 6, 46, 4, 390
local TOP = 40      -- Kopf mit Symbol, Titel und Anlegername
local REACH = 120   -- yd um den Halt
local MEDIA = GP.MEDIA or "Interface\\AddOns\\GuildPrideForever\\Media\\"
local KIND = { boat = L["Schiff"], zeppelin = L["Zeppelin"], airship = L["Luftschiff"] }
local ICON = { boat = MEDIA .. "transit_boat", zeppelin = MEDIA .. "transit_zeppelin", airship = MEDIA .. "transit_zeppelin" }
-- Farbe je Art: Schiffe meerblau, Zeppeline und Luftschiffe messing
local TINT = { boat = { 0.45, 0.75, 1 }, zeppelin = { 1, 0.78, 0.35 }, airship = { 1, 0.78, 0.35 } }
local GREEN, GOLD, GREY = { 0.35, 0.95, 0.45 }, { 1, 0.82, 0.2 }, { 0.6, 0.6, 0.6 }

local REMIND_LEAD = 60   -- s vor der Abfahrt erinnern
local frame, dismissed, lastKey
T.reminders = {}        -- ["id|side"] = { id, side, kind, to, skipUntil }
local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.transitUI == false) end

-- Text unter dem Ziel (Zeile 2 der Karte)
function T.StatusText(b)
    if not b then return "" end
    local C = T.Countdown
    if not b.timed then
        if b.wait then return (L["|cffaaaaaanoch nicht gemessen|r · im Schnitt %s Wartezeit"]):format(C(b.wait)) end
        return L["|cffaaaaaanoch nicht gemessen|r"]
    end
    if b.arriveIn <= 0 then
        return (L["|cff40ff40liegt am Steg|r – legt ab in %s · nächstes kommt in %s"]):format(C(b.departIn), C(b.nextIn))
    end
    return (L["kommt in |cffffd100%s|r · danach in %s"]):format(C(b.arriveIn), C(b.nextIn))
end

-- Rechte Seite der Karte: großer Countdown, Beschriftung, Farbe, Balken (0–1)
function T.Clock(b)
    if not b or not b.timed then
        return "–", b and b.wait and (L["Ø %s"]):format(T.Countdown(b.wait)) or "", GREY, 0
    end
    if b.arriveIn <= 0 then
        local stay = b.stay and b.stay > 0 and b.stay or b.departIn
        return T.Countdown(b.departIn), L["legt ab"], GREEN, math.max(0, math.min(1, b.departIn / stay))
    end
    local wait = b.period and b.stay and (b.period - b.stay) or b.arriveIn
    return T.Countdown(b.arriveIn), L["kommt an"], GOLD, math.max(0, math.min(1, 1 - b.arriveIn / math.max(1, wait)))
end

local function SavePos()
    if type(GuildPrideDB) ~= "table" then return end
    local point, _, _, x, y = frame:GetPoint(1)
    GuildPrideDB.transitPos = { point = point, x = x, y = y }
end

local function Text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

local function MakeRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(WIDTH - 20, ROW_H)
    r:SetPoint("TOPLEFT", 10, -TOP - (i - 1) * (ROW_H + GAP))
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.edge = r:CreateTexture(nil, "BORDER")                 -- farbige Kante links
    r.edge:SetPoint("TOPLEFT"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetWidth(3)
    r.iconBg = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.iconBg:SetSize(34, 34); r.iconBg:SetPoint("LEFT", 9, 0); r.iconBg:SetColorTexture(0, 0, 0, 0.35)
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.icon:SetSize(30, 30); r.icon:SetPoint("CENTER", r.iconBg, "CENTER")
    r.to = Text(r, "GameFontNormal", 1, 1, 1)
    r.to:SetPoint("TOPLEFT", 50, -8); r.to:SetPoint("RIGHT", -92, 0)
    r.status = Text(r, "GameFontHighlightSmall")
    r.status:SetPoint("TOPLEFT", 50, -25); r.status:SetPoint("RIGHT", -84, 0)
    -- Erinnerung: 1 Min. vor der Abfahrt Bescheid geben
    r.bell = CreateFrame("Button", nil, r)
    r.bell:SetSize(16, 16); r.bell:SetPoint("TOPRIGHT", -68, -7)
    r.bell.icon = r.bell:CreateTexture(nil, "ARTWORK")
    r.bell.icon:SetAllPoints(); r.bell.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    r.bell:SetScript("OnClick", function()
        if r.dock then T.ToggleReminder(r.dock); T.UpdateWindow() end
    end)
    r.bell:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Erinnern"], 1, 1, 1)
        GameTooltip:AddLine(L["1 Minute vor der Abfahrt mit Raid-Warnung und Ton Bescheid geben – auch wenn du nicht mehr am Anleger bist."],
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    r.bell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.clock = Text(r, "GameFontNormalLarge"); r.clock:SetJustifyH("RIGHT")
    r.clock:SetPoint("TOPRIGHT", -10, -7)
    r.clockLabel = Text(r, "GameFontDisableSmall"); r.clockLabel:SetJustifyH("RIGHT")
    r.clockLabel:SetPoint("TOPRIGHT", -10, -27)
    r.barBg = r:CreateTexture(nil, "ARTWORK")
    r.barBg:SetPoint("BOTTOMLEFT", 3, 0); r.barBg:SetPoint("BOTTOMRIGHT", 0, 0); r.barBg:SetHeight(2)
    r.barBg:SetColorTexture(1, 1, 1, 0.08)
    r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.bar:SetPoint("BOTTOMLEFT", 3, 0); r.bar:SetHeight(2)
    r:Hide()
    return r
end

local function Build()
    frame = CreateFrame("Frame", "GuildPrideTransitFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 80)
    local p = type(GuildPrideDB) == "table" and GuildPrideDB.transitPos
    if type(p) == "table" and p.point then frame:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    if GP.SkinDialog then GP.SkinDialog(frame) end   -- Goldrahmen wie das Gildenfenster
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePos() end)
    -- Kopf: Symbol, Titel, Anleger
    frame.logo = frame:CreateTexture(nil, "ARTWORK")
    frame.logo:SetSize(24, 24); frame.logo:SetPoint("TOPLEFT", 12, -10)
    frame.logo:SetTexture(ICON.boat); frame.logo:SetVertexColor(1, 0.82, 0.45)
    frame.title = Text(frame, "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 42, -10); frame.title:SetText(L["GuildPride – Schiffe"])
    frame.dock = Text(frame, "GameFontDisableSmall")
    frame.dock:SetPoint("TOPLEFT", 42, -24); frame.dock:SetPoint("RIGHT", -30, 0)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -4, -6)
    if GP.SkinClose then GP.SkinClose(close) end
    close:SetScript("OnClick", function() dismissed = lastKey; frame:Hide() end)
    frame.close = close
    frame.rows = {}
    for i = 1, ROWS do frame.rows[i] = MakeRow(i) end
    frame.hint = Text(frame, "GameFontDisableSmall")
    frame.hint:SetWidth(WIDTH - 24)
    frame.hint:SetText(L["Fahr einmal mit – dann misst GuildPride die Zeiten für dich und deine Gilde."])
    frame:Hide()
end

-- Alter der Messung, kurz: „vor 25 Min.“, „vor 3 Std.“, „vor 2 Tag(en)“
function T.AgeText(b)
    if not b or not b.timed or not b.age then return "" end
    local a = b.age
    if a < 3600 then return (L["vor %d Min."]):format(math.max(1, math.floor(a / 60))) end
    if a < 86400 then return (L["vor %d Std."]):format(math.floor(a / 3600)) end
    return (L["vor %d Tag(en)"]):format(math.floor(a / 86400))
end

-- Stammt die Messung von deinem Layer?
function T.LayerText(b)
    if not b or not b.timed then return "" end
    if b.guess then return L["|cffaaaaaavermutet (wie letzte Woche)|r"] end
    if b.estimated then return L["|cff66ccffgeschätzt für deinen Layer|r"] end
    if b.layer == true then return L["|cff40ff40dein Layer|r"] end
    if not b.layerKnown then return L["|cffaaaaaaLayer ?|r"] end
    return L["|cffffaa00evtl. anderer Layer|r"]
end

local function DrawRow(r, d, b)
    local tint = TINT[d.kind] or TINT.boat
    r.dock, r.board = d, b
    r.icon:SetTexture(ICON[d.kind] or ICON.boat)
    r.icon:SetVertexColor(tint[1], tint[2], tint[3])
    r.edge:SetColorTexture(tint[1], tint[2], tint[3], 0.9)
    r.to:SetText((L["%s nach %s"]):format(KIND[d.kind] or KIND.boat, tostring(d.to)))
    local clock, label, color, fill = T.Clock(b)
    r.clock:SetText(clock); r.clock:SetTextColor(color[1], color[2], color[3])
    r.clockLabel:SetText(label)
    if b and b.timed then
        local text
        if b.arriveIn <= 0 then
            text = (L["|cff40ff40liegt am Steg|r · nächstes in %s"]):format(T.Countdown(b.nextIn))
        else
            text = (L["danach in %s"]):format(T.Countdown(b.nextIn))
        end
        -- wie alt die Messung ist, ob sie von deinem Layer stammt und wie viele sie bestätigt haben
        local info = (b.guess or b.estimated) and "" or (" |cff888888· " .. T.AgeText(b) .. "|r")
        r.status:SetText(text .. info .. " · " .. T.LayerText(b) .. T.ConfirmText(b))
    elseif b and b.otherLayer then
        r.status:SetText(L["|cffaaaaaaauf deinem Layer noch nicht gemessen|r"])
    else
        r.status:SetText(L["|cffaaaaaanoch nicht gemessen|r"])
    end
    local on = T.reminders[d.id .. "|" .. d.side] ~= nil
    r.bell:SetShown(b and b.timed and true or false)
    r.bell.icon:SetDesaturated(not on); r.bell:SetAlpha(on and 1 or 0.45)
    r.fill = fill
    r.bar:SetColorTexture(color[1], color[2], color[3], 0.85)
    r.bar:SetWidth(math.max(1, (WIDTH - 23) * fill))
    r.bar:SetShown(fill > 0)
    r:Show()
end

-- „· 3× bestätigt“: so viele haben die Zeit selbst gemessen
function T.ConfirmText(b)
    if not b or not b.timed or b.guess or b.estimated or (b.confirmed or 1) < 2 then return "" end
    return (L[" |cff888888· %d× bestätigt|r"]):format(b.confirmed)
end

-- Erinnerung an/aus für eine Karte (d aus T.DocksNear)
function T.ToggleReminder(d, now)
    local key = d.id .. "|" .. d.side
    if T.reminders[key] then T.reminders[key] = nil; return false end
    now = now or T.Now()
    local b = T.Board(d.id, d.side, now)
    if not (b and b.timed) then return false end
    -- legt es gleich ab? Dann an die nächste Abfahrt erinnern
    local skip = b.departIn <= REMIND_LEAD and (now + b.departIn + 1) or nil
    T.reminders[key] = { id = d.id, side = d.side, kind = d.kind, to = d.to, skipUntil = skip }
    if GP.Print then GP.Print((L["Schiffs-Zähler: Erinnerung 1 Min. vor der Abfahrt nach %s."]):format(tostring(d.to))) end
    return true
end

-- Jede halbe Sekunde: fällige Erinnerungen auslösen
function T.CheckReminders(now)
    now = now or T.Now()
    for key, rm in pairs(T.reminders) do
        local b = (not rm.skipUntil or now >= rm.skipUntil) and T.Board(rm.id, rm.side, now)
        if b and b.timed and b.departIn <= REMIND_LEAD then
            T.reminders[key] = nil
            local text = (L["%s nach %s legt in %d Sek. ab!"]):format(KIND[rm.kind] or KIND.boat, tostring(rm.to),
                math.max(0, math.floor(b.departIn)))
            if RaidNotice_AddMessage and RaidWarningFrame then
                RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.3, b = 0.1 })
            end
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
            if GP.Print then GP.Print(text) end
        end
    end
end

-- Neu zeichnen; docks = T.DocksNear(...)
local function Draw(docks, now)
    local shown, untimed, unknown = 0, false, false
    local ask = {}
    for i, r in ipairs(frame.rows) do
        local d = docks[i]
        if not d then r.dock, r.board = nil, nil; r:Hide() else
            local b = T.Board(d.id, d.side, now)
            DrawRow(r, d, b)
            if b and not b.timed then untimed = true end
            if b and not b.layerKnown then unknown = true end
            -- nicht für deinen Layer gemessen: andere GuildPride-Spieler fragen
            if b and not (b.timed and b.layer == true) and T.RoutesOf then
                for _, id in ipairs(T.RoutesOf(d.id)) do ask[#ask + 1] = id end
            end
            shown = i
        end
    end
    if #ask > 0 and T.RequestPublic then T.RequestPublic(ask) end
    frame.dock:SetText(docks[1] and T.EndName(docks[1].id, docks[1].side) or "")
    frame.logo:SetTexture(ICON[docks[1] and docks[1].kind] or ICON.boat)
    local h = TOP + shown * (ROW_H + GAP) + 6
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", 12, -(TOP + shown * (ROW_H + GAP)))
    -- Hinweis: einmal mitfahren bzw. Layer erkennen lassen
    if untimed then
        frame.hint:SetText(L["Fahr einmal mit – dann misst GuildPride die Zeiten für dich und deine Gilde."])
    elseif unknown then
        frame.hint:SetText(L["Tipp: eine Kreatur anvisieren – dann erkennt GuildPride deinen Layer und zeigt dessen Zeiten."])
    end
    local hint = untimed or unknown
    frame.hint:SetShown(hint); frame.untimed = untimed
    if hint then h = h + 26 end
    frame:SetHeight(h)
end

function T.UpdateWindow(now)
    if not Enabled() then
        if frame then frame:Hide() end
        return
    end
    local x, y, _, map = T.Position()
    local docks = x and T.DocksNear(map, x, y, REACH) or {}
    if #docks == 0 then
        dismissed, lastKey = nil, nil
        if frame then frame:Hide() end
        return
    end
    local key = docks[1].id .. docks[1].side
    lastKey = key
    if dismissed == key then return end
    if not frame then Build() end
    Draw(docks, now)
    frame:Show()
end

function T._Window() return frame end   -- für Tests

-- Einstellungen: an/aus wirkt sofort
function T.SetWindow(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.transitUI = on and true or false end
    dismissed = nil
    T.UpdateWindow()
end

T.onChanged = function() if frame and frame:IsShown() then T.UpdateWindow() end end

if C_Timer and C_Timer.NewTicker then
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        C_Timer.NewTicker(0.5, function() T.UpdateWindow(); T.CheckReminders() end)
    end)
end
