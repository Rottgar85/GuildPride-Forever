-- GuildPride: Schiffs-Zähler am Anleger. Steht man an einem Steg oder Zeppelinturm, zeigt ein
-- kleines, verschiebbares Fenster je Verbindung, ob das Schiff gerade anliegt und wann es ablegt,
-- wann das nächste kommt und wann das danach. Ungemessene Verbindungen zeigen die mittlere
-- Wartezeit (gemessen wird beim Mitfahren, siehe GuildPrideTransit.lua).
-- Aus: Einstellungen › „Schiffs-Zähler am Anleger zeigen“. X blendet es aus, bis du den Anleger verlässt.
local ADDON, GP = ...
local T = GP.Transit
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })
if not T then return end

local ROWS, ROW_H, WIDTH = 6, 32, 330
local REACH = 120   -- yd um den Halt
local KIND = { boat = L["Schiff"], zeppelin = L["Zeppelin"], airship = L["Luftschiff"] }
local ICON = {
    boat = "Interface\\Icons\\INV_Misc_Spyglass_03",
    zeppelin = "Interface\\Icons\\INV_Misc_EngGizmos_01",
    airship = "Interface\\Icons\\INV_Misc_EngGizmos_01",
}

local frame, dismissed, lastKey
local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.transitUI == false) end

-- Text einer Verbindung: Zeile 1 Ziel, Zeile 2 Zeiten
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

local function SavePos()
    if type(GuildPrideDB) ~= "table" then return end
    local point, _, _, x, y = frame:GetPoint(1)
    GuildPrideDB.transitPos = { point = point, x = x, y = y }
end

local function Build()
    frame = CreateFrame("Frame", "GuildPrideTransitFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 40)
    local p = type(GuildPrideDB) == "table" and GuildPrideDB.transitPos
    if type(p) == "table" and p.point then frame:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePos() end)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 10, -8); frame.title:SetText(L["GuildPride – Schiffe"])
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -2, -2)
    if GP.SkinClose then GP.SkinClose(close) end
    close:SetScript("OnClick", function() dismissed = lastKey; frame:Hide() end)
    frame.close = close
    frame.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, frame)
        r:SetSize(WIDTH - 16, ROW_H)
        r:SetPoint("TOPLEFT", 8, -26 - (i - 1) * ROW_H)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 0, 0)
        r.to = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.to:SetPoint("TOPLEFT", 28, -2); r.to:SetPoint("RIGHT", 0, 0); r.to:SetJustifyH("LEFT")
        r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("TOPLEFT", 28, -17); r.status:SetPoint("RIGHT", 0, 0); r.status:SetJustifyH("LEFT")
        r:Hide()
        frame.rows[i] = r
    end
    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.hint:SetJustifyH("LEFT"); frame.hint:SetWidth(WIDTH - 20)
    frame.hint:SetText(L["Fahr einmal mit – dann misst GuildPride die Zeiten für dich und deine Gilde."])
    frame:Hide()
end

-- Neu zeichnen; docks = T.DocksNear(...)
local function Draw(docks, now)
    local shown, untimed = 0, false
    for i, r in ipairs(frame.rows) do
        local d = docks[i]
        if not d then r.dock, r.board = nil, nil; r:Hide() else
            local b = T.Board(d.id, d.side, now)
            r.dock, r.board = d, b
            r.icon:SetTexture(ICON[d.kind] or ICON.boat)
            r.to:SetText((L["%s nach %s"]):format(KIND[d.kind] or KIND.boat, tostring(d.to)))
            r.status:SetText(T.StatusText(b))
            if b and not b.timed then untimed = true end
            r:Show()
            shown = i
        end
    end
    local h = 30 + shown * ROW_H
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOPLEFT", 10, -(26 + shown * ROW_H))
    frame.hint:SetShown(untimed); frame.untimed = untimed
    if untimed then h = h + 26 end
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
    ev:SetScript("OnEvent", function() C_Timer.NewTicker(0.5, function() T.UpdateWindow() end) end)
end
