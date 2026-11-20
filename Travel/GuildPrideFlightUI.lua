-- GuildPride: Flug-Zähler. Solange du mit dem Greif, Windreiter oder Hippogryphen fliegst, zeigt ein
-- kleines, verschiebbares Fenster wie der Schiffs-Zähler eine Karte: Flugsymbol, Ziel, rechts groß die
-- Restzeit bis zur Landung und ein dünner Balken für den Fortschritt. Gemessene Strecken in Gold,
-- geschätzte (wie bei Polestar) mit „ca.“ in Grau; nach der Landung wird die Zeit gemessen
-- (GuildPrideFlight.lua). Symbol: Media/transit_flight.tga aus Polestar (GPL-3.0-only).
-- Aus: Einstellungen › „Flug-Zähler im Flug zeigen“. X blendet es bis zum nächsten Flug aus.
local ADDON, GP = ...
local F = GP.Flight
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })
if not F then return end

local WIDTH, ROW_H = 330, 46
local TOP = 40
local MEDIA = GP.MEDIA or "Interface\\AddOns\\GuildPrideForever\\Media\\"
local ICON = MEDIA .. "transit_flight"
local SKY = { 0.55, 0.85, 1 }
local GOLD, GREY = { 1, 0.82, 0.2 }, { 0.75, 0.75, 0.75 }
local frame, dismissed

local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.flightUI == false) end

-- Rechte Seite der Karte: großer Countdown, Beschriftung, Farbe, Balken (0–1)
function F.Clock(st)
    if not st then return "", "", GREY, 0 end
    if not st.total then return F.Countdown(st.elapsed), L["unterwegs"], GREY, 0 end
    if st.left <= 0 then return L["gleich da"], L["Landung"], GOLD, 1 end
    if st.measured then return F.Countdown(st.left), L["bis zur Landung"], GOLD, st.fill end
    return (L["ca. %s"]):format(F.Countdown(st.left)), L["bis zur Landung"], GREY, st.fill
end

-- Zeile unter dem Ziel
function F.StatusText(st)
    if not st then return "" end
    if not st.total then return L["|cffaaaaaaFlugzeit unbekannt|r – wird bei der Landung gemessen"] end
    if st.measured then return (L["Flugzeit %s · |cff40ff40gemessen|r"]):format(F.Countdown(st.total)) end
    return (L["Flugzeit ca. %s · |cffaaaaaageschätzt, wird bei der Landung gemessen|r"]):format(F.Countdown(st.total))
end

local function SavePos()
    if type(GuildPrideDB) ~= "table" then return end
    local point, _, _, x, y = frame:GetPoint(1)
    GuildPrideDB.flightPos = { point = point, x = x, y = y }
end

local function Text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

local function Build()
    frame = CreateFrame("Frame", "GuildPrideFlightFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, TOP + ROW_H + 10)
    local p = type(GuildPrideDB) == "table" and GuildPrideDB.flightPos
    if type(p) == "table" and p.point then frame:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else frame:SetPoint("TOP", UIParent, "TOP", 0, -110) end
    if GP.SkinDialog then GP.SkinDialog(frame) end   -- Goldrahmen wie das Gildenfenster
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePos() end)
    -- Kopf: Symbol und Titel
    frame.logo = frame:CreateTexture(nil, "ARTWORK")
    frame.logo:SetSize(24, 24); frame.logo:SetPoint("TOPLEFT", 12, -10)
    frame.logo:SetTexture(ICON); frame.logo:SetVertexColor(1, 0.82, 0.45)
    frame.title = Text(frame, "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 42, -10); frame.title:SetText(L["GuildPride – Flug"])
    frame.sub = Text(frame, "GameFontDisableSmall")
    frame.sub:SetPoint("TOPLEFT", 42, -24); frame.sub:SetPoint("RIGHT", -30, 0)
    frame.sub:SetText(L["Restzeit bis zur Landung"])
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -4, -6)
    if GP.SkinClose then GP.SkinClose(close) end
    close:SetScript("OnClick", function() dismissed = true; frame:Hide() end)
    frame.close = close
    -- Karte
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(WIDTH - 20, ROW_H)
    r:SetPoint("TOPLEFT", 10, -TOP)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.edge = r:CreateTexture(nil, "BORDER")
    r.edge:SetPoint("TOPLEFT"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetWidth(3)
    r.edge:SetColorTexture(SKY[1], SKY[2], SKY[3], 0.9)
    r.iconBg = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.iconBg:SetSize(34, 34); r.iconBg:SetPoint("LEFT", 9, 0); r.iconBg:SetColorTexture(0, 0, 0, 0.35)
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.icon:SetSize(30, 30); r.icon:SetPoint("CENTER", r.iconBg, "CENTER")
    r.icon:SetTexture(ICON); r.icon:SetVertexColor(SKY[1], SKY[2], SKY[3])
    r.to = Text(r, "GameFontNormal", 1, 1, 1)
    r.to:SetPoint("TOPLEFT", 50, -8); r.to:SetPoint("RIGHT", -92, 0)
    r.status = Text(r, "GameFontHighlightSmall")
    r.status:SetPoint("TOPLEFT", 50, -25); r.status:SetPoint("RIGHT", -84, 0)
    r.clock = Text(r, "GameFontNormalLarge"); r.clock:SetJustifyH("RIGHT")
    r.clock:SetPoint("TOPRIGHT", -10, -7)
    r.clockLabel = Text(r, "GameFontDisableSmall"); r.clockLabel:SetJustifyH("RIGHT")
    r.clockLabel:SetPoint("TOPRIGHT", -10, -27)
    r.barBg = r:CreateTexture(nil, "ARTWORK")
    r.barBg:SetPoint("BOTTOMLEFT", 3, 0); r.barBg:SetPoint("BOTTOMRIGHT", 0, 0); r.barBg:SetHeight(2)
    r.barBg:SetColorTexture(1, 1, 1, 0.08)
    r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.bar:SetPoint("BOTTOMLEFT", 3, 0); r.bar:SetHeight(2)
    frame.row = r
    frame:Hide()
end

local function Draw(st)
    local r = frame.row
    r.to:SetText((L["Flug nach %s"]):format(tostring(st.to or "?")))
    r.status:SetText(F.StatusText(st))
    local clock, label, color, fill = F.Clock(st)
    r.clock:SetText(clock); r.clock:SetTextColor(color[1], color[2], color[3])
    r.clockLabel:SetText(label)
    r.fill = fill
    r.bar:SetColorTexture(color[1], color[2], color[3], 0.85)
    r.bar:SetWidth(math.max(1, (WIDTH - 23) * fill))
    r.bar:SetShown(fill > 0)
end

function F.UpdateWindow(now)
    local st = F.Status(now)
    if not st then
        dismissed = nil   -- nächster Flug zeigt das Fenster wieder
        if frame then frame:Hide() end
        return
    end
    if not Enabled() or dismissed then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Draw(st)
    frame:Show()
end

function F._Window() return frame end   -- für Tests

-- Einstellungen: an/aus wirkt sofort
function F.SetWindow(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.flightUI = on and true or false end
    dismissed = nil
    F.UpdateWindow()
end

F.onTick = function() F.UpdateWindow() end
