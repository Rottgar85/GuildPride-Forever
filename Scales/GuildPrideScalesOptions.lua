-- Small options window; docks to the right of the main window when that is open.
local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local L = ns.L
local St = ns.Style
local O = {}
ns.Options = O

local function Changed()
  ns.Bags.QueueFullRefresh()
  ns.Minimap.Apply()
end

local function Create()
  local f = St.Panel("ScalesOptionsFrame", UIParent, 340, 328)
  St.Movable(f)
  St.Header(f, St.TITLE .. " |cffffffff- " .. L.OPTIONS .. "|r")
  f:Hide()

  local items = {
    { L.OPT_TOOLTIP, function() return ScalesDB.tooltip end, function(v) ScalesDB.tooltip = v end },
    { L.OPT_ARROWS_UP, function() return ScalesDB.bagArrows end, function(v) ScalesDB.bagArrows = v end },
    { L.OPT_ARROWS_DOWN, function() return ScalesDB.bagDown end, function(v) ScalesDB.bagDown = v end },
    { L.OPT_ARROWS_OTHER, function() return ScalesDB.bagOther end, function(v) ScalesDB.bagOther = v end },
    { L.OPT_MINIMAP, function() return not ScalesDB.charButtonHide end, function(v) ScalesDB.charButtonHide = not v end },
    { L.OPT_WITHCHAR, function() return ScalesDB.withCharacter ~= false end, function(v) ScalesDB.withCharacter = v end },
  }
  for i, it in ipairs(items) do
    local cb = St.Check(f, it[1], it[2], function(v) it[3](v); Changed() end)
    cb:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 28)
  end

  -- Language: Auto / English / Deutsch; takes effect after a reload.
  local langLabel = St.Text(f, 12, "GameFontNormal")
  langLabel:SetPoint("TOPLEFT", 14, -212)
  langLabel:SetText(L.OPT_LANGUAGE)
  local langs = { { "auto", L.LANG_AUTO }, { "en", "English" }, { "de", "Deutsch" } }
  local langBtns = {}
  local function MarkLanguage()
    for _, b in ipairs(langBtns) do
      local c = b.lang == ScalesDB.language and St.GOLD or St.CYAN
      b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
  end
  for i, lg in ipairs(langs) do
    local b = St.Button(f, lg[2], 76)
    b.lang = lg[1]
    b:SetPoint("TOPLEFT", 12 + (i - 1) * 84, -232)
    b:HookScript("OnClick", function() ns.SetLanguage(lg[1]); MarkLanguage() end)
    b:HookScript("OnLeave", MarkLanguage)
    langBtns[i] = b
  end
  local reload = St.Button(f, L.RELOAD, 160)
  reload:SetPoint("TOPLEFT", 12, -256)
  reload:SetScript("OnClick", ReloadUI)
  f:HookScript("OnShow", MarkLanguage)

  local hint = St.Text(f, 11, "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 12, 12); hint:SetWidth(316)
  hint:SetText(L.OPT_SPEC_HINT)
  O.frame = f
end

function O.Toggle()
  if not O.frame then Create() end
  local f = O.frame
  if f:IsShown() then f:Hide(); return end
  f:ClearAllPoints()
  local main = ns.UI.frame
  if main and main:IsShown() then f:SetPoint("TOPLEFT", main, "TOPRIGHT", 6, 0)
  else f:SetPoint("CENTER") end
  f:Show()
end
