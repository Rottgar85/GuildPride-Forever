-- Gemeinsamer Look aller Scales-Fenster – in GuildPride im GuildPride-Style
local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local St = {}
ns.Style = St

St.LOGO = "Interface\\AddOns\\GuildPrideForever\\Media\\Scales\\Logo"
St.ARROW_UP = "Interface\\AddOns\\GuildPrideForever\\Media\\Scales\\ArrowUp"
St.ARROW_DOWN = "Interface\\AddOns\\GuildPrideForever\\Media\\Scales\\ArrowDown"
St.ARROW_OTHER = "Interface\\AddOns\\GuildPrideForever\\Media\\Scales\\ArrowOther"

-- In GuildPride: Farben aus dem gewählten GuildPride-Style (Schmiede, Frost …).
-- CYAN = Rahmen/Akzent, GOLD = Hervorhebung. Die Tabellen werden beim Style-Wechsel
-- an Ort und Stelle aktualisiert, damit alle Stellen, die sie benutzen, mitziehen.
St.CYAN = { 0.80, 0.55, 0.27 }
St.GOLD = { 1.00, 0.50, 0.20 }
St.TITLE = "|cffff7d0aScales|r"
St.GREEN, St.RED, St.GREY, St.ORANGE = "|cff1eff00", "|cffff3030", "|cff999999", "|cffff9900"
local MEDIA = "Interface\\AddOns\\GuildPrideForever\\Media\\"

local function SyncTheme()
  local t = GP.Theme and GP.Theme()
  if not t then return end
  St.CYAN[1], St.CYAN[2], St.CYAN[3] = t.accent[1], t.accent[2], t.accent[3]
  St.GOLD[1], St.GOLD[2], St.GOLD[3] = t.glow[1], t.glow[2], t.glow[3]
end
St.SyncTheme = SyncTheme
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", SyncTheme)
if GP.OnThemeChanged then GP.OnThemeChanged(SyncTheme) end

local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Fenster im GuildPride-Look: Pergament-Hintergrund, Akzent-Rahmen, Glut-Leiste oben; Esc schließt
function St.Panel(name, parent, w, h)
  local f = CreateFrame("Frame", name, parent or UIParent, TEMPLATE)
  f:SetSize(w, h)
  if GP.SkinDialog then GP.SkinDialog(f) else
    f:SetBackdrop({ bgFile = MEDIA .. "bg", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 } })
  end
  f:SetClampedToScreen(true)
  if name then tinsert(UISpecialFrames, name) end
  return f
end

-- Kopfzeile mit Logo, Titel in GuildPride-Schrift und GuildPride-Schließen-Kreuz
function St.Header(f, text)
  local h = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  h:SetPoint("TOPLEFT", 2, -6); h:SetPoint("TOPRIGHT", -2, -6)
  h:SetHeight(26)
  h:SetColorTexture(0, 0, 0, 0)
  local line = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 8, 0); line:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", -8, 0)
  line:SetHeight(1)
  if GP.Paint then GP.Paint(line, "accent", 0.6) else line:SetColorTexture(St.GOLD[1], St.GOLD[2], St.GOLD[3], 0.6) end

  local title = f:CreateFontString(nil, "OVERLAY", GPFont_Large and "GPFont_Large" or "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText(text and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or "Scales")
  if GP.Paint then GP.Paint(title, "heading") end

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -6, -8)
  if GP.SkinClose then GP.SkinClose(close) end
  f.title, f.close = title, close
  return h
end

-- Dragging the window (outside buttons and rows) moves it.
function St.Movable(f)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

-- Font string with a fixed size, independent of which named fonts a client has.
local FONT_MAP = { GameFontNormal = "GPFont_Normal", GameFontNormalSmall = "GPFont_TextBold",
  GameFontHighlight = "GPFont_Text", GameFontHighlightSmall = "GPFont_TextSmall", GameFontDisableSmall = "GPFont_Muted" }
function St.Text(parent, size, template)
  local gp = FONT_MAP[template or "GameFontHighlight"]
  local fs = parent:CreateFontString(nil, "OVERLAY", (gp and _G[gp]) and gp or template or "GameFontHighlight")
  if size then
    local file, _, flags = fs:GetFont()
    if file then fs:SetFont(file, size, flags) end
  end
  fs:SetJustifyH("LEFT")
  return fs
end

-- Knopf wie überall in GuildPride (Kupfer-/Glutknopf). Hervorhebung (z. B. gewählte
-- Sprache) über SetBackdropBorderColor in GOLD -> gedrückter Knopf-Hintergrund.
function St.Button(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  if GP.SkinButton then GP.SkinButton(b) end
  function b:SetBackdropColor() end
  function b:SetBackdropBorderColor(r, g, bl)
    local on = r == St.GOLD[1] and g == St.GOLD[2] and bl == St.GOLD[3]
    if self.gpBg then self.gpBg:SetTexture(MEDIA .. (on and "nav_active" or "nav")) end
  end
  return b
end

-- Checkbox with its own label (template label names differ between clients).
function St.Check(parent, text, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  local label = parent:CreateFontString(nil, "OVERLAY", GPFont_Text and "GPFont_Text" or "GameFontHighlight")
  label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  label:SetText(text)
  cb:SetScript("OnShow", function(self) self:SetChecked(get() and true or false) end)
  -- HookScript keeps the template's click sound; the label is clickable too.
  cb:HookScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  cb:SetHitRectInsets(0, -(label:GetStringWidth() + 4), 0, 0)
  cb.label = label
  return cb
end

-- Inline texture for text: |T...|t
function St.Icon(path, size) return "|T" .. path .. ":" .. (size or 14) .. "|t" end
