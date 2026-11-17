-- GuildPride: Briefkasten – Knopf „Twinks“ neben dem Empfänger beim Brief schreiben.
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

---------------------------------------------------------------------
-- Twinks als Empfänger: Knopf neben dem Empfänger-Feld beim Schreiben.
-- Bekannt sind alle Charaktere, mit denen du dich mit GuildPride eingeloggt hast
-- (für den ganzen Account, je Fraktion), dazu deine per Ausweis erkannten Twinks in der Gilde.
-- GuildPrideDB.ahChars = { [Fraktion] = { [Anzeigename] = { game = Name fürs Spiel, class } } }
---------------------------------------------------------------------
local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return type(f) == "string" and f or "N"
end

local function CharStore()
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    if type(GuildPrideDB.ahChars) ~= "table" then GuildPrideDB.ahChars = {} end
    if type(GuildPrideDB.ahCharsHidden) ~= "table" then GuildPrideDB.ahCharsHidden = {} end
    local f = Faction()
    if type(GuildPrideDB.ahChars[f]) ~= "table" then GuildPrideDB.ahChars[f] = {} end
    return GuildPrideDB.ahChars[f], GuildPrideDB.ahCharsHidden
end

-- Den gerade gespielten Charakter merken (beim Einloggen)
function AH.RememberChar()
    local me = GP.Me and GP.Me()
    if not me then return end
    local name, surname
    if UnitFullName then name, surname = UnitFullName("player") end
    local game = name or me
    if GP.IS_FOREVER and type(surname) == "string" and surname ~= "" then game = game .. "-" .. surname end
    local class = UnitClass and select(2, UnitClass("player"))
    local store, hiddenChars = CharStore()
    store[me] = { game = game, class = type(class) == "string" and class or nil }
    hiddenChars[me] = nil
end

-- Deine anderen Charaktere (ohne den aktuellen), sortiert: { show, game, class }
function AH.MyChars()
    local store, hiddenChars = CharStore()
    local me = GP.Me and GP.Me()
    local out, seen = {}, { [me or ""] = true }
    for show, e in pairs(store) do
        if not seen[show] and not hiddenChars[show] and type(e) == "table" then
            seen[show] = true
            out[#out + 1] = { show = show, game = e.game or show, class = e.class }
        end
    end
    if GP.IsMyChar and GetNumGuildMembers and IsInGuild and IsInGuild() then
        for i = 1, tonumber((GetNumGuildMembers())) or 0 do
            local raw, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
            local show = type(raw) == "string" and (GP.Normalize and GP.Normalize(raw) or raw)
            if show and not seen[show] and not hiddenChars[show] and GP.IsMyChar(show) then
                seen[show] = true
                out[#out + 1] = { show = show, game = raw, class = type(class) == "string" and class or nil }
            end
        end
    end
    table.sort(out, function(a, b) return a.show < b.show end)
    return out
end

function AH.ForgetChar(show)
    local store, hiddenChars = CharStore()
    store[show] = nil
    hiddenChars[show] = true
end

local twinkBtn, twinkMenu
local MAX_TWINKS = 20

local function ShowTwinks()
    local chars = AH.MyChars()
    local m = twinkMenu
    for i, b in ipairs(m.buttons) do
        local c = chars[i]
        b.char = c
        if c then
            local col = RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]
            local cs = type(col) == "table" and col.colorStr
            b.text:SetText(type(cs) == "string" and ("|c" .. cs .. c.show .. "|r") or c.show)
            b:Show()
        else b:Hide() end
    end
    local n = math.min(#chars, MAX_TWINKS)
    m.empty:SetShown(n == 0)
    m:SetHeight(n == 0 and 46 or (12 + n * 18))
    m:Show()
end

local function BuildTwinks()
    if twinkBtn or not SendMailNameEditBox then return end
    twinkBtn = CreateFrame("Button", "GuildPrideTwinkButton", SendMailNameEditBox, "UIPanelButtonTemplate")
    twinkBtn:SetSize(70, 20); twinkBtn:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 6, 0)
    twinkBtn:SetText(L["Twinks"])
    if GP.SkinButton then GP.SkinButton(twinkBtn) end
    local m = CreateFrame("Frame", "GuildPrideTwinkMenu", twinkBtn, "BackdropTemplate")
    m:SetWidth(190); m:SetPoint("TOPLEFT", twinkBtn, "BOTTOMLEFT", 0, -2)
    m:SetFrameStrata("DIALOG")
    m:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    m:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    m:Hide()
    m.empty = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    m.empty:SetPoint("TOPLEFT", 8, -8); m.empty:SetPoint("RIGHT", -8, 0)
    m.empty:SetText(L["Noch keine Twinks bekannt – logge dich einmal mit jedem Charakter ein."])
    m.buttons = {}
    for i = 1, MAX_TWINKS do
        local b = CreateFrame("Button", nil, m)
        b:SetSize(176, 18); b:SetPoint("TOPLEFT", 7, -6 - (i - 1) * 18)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 4, 0); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(_, mouse)
            if not b.char then return end
            if mouse == "RightButton" then
                AH.ForgetChar(b.char.show)
                ShowTwinks()
            else
                SendMailNameEditBox:SetText(b.char.game)
                m:Hide()
            end
        end)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(b.char and b.char.show or "")
            GameTooltip:AddLine(L["Linksklick: als Empfänger eintragen · Rechtsklick: aus der Liste entfernen"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        m.buttons[i] = b
    end
    twinkMenu = m
    twinkBtn:SetScript("OnClick", function() if m:IsShown() then m:Hide() else ShowTwinks() end end)
    twinkBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(twinkBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["An Twinks schicken"])
        GameTooltip:AddLine(L["Deine anderen Charaktere als Empfänger wählen."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    twinkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function AH._TwinkButton() return twinkBtn end   -- für Tests
function AH._TwinkMenu() return twinkMenu end

AH.Listen("PLAYER_LOGIN", function() AH.RememberChar() end)
AH.Listen("MAIL_SHOW", BuildTwinks)
AH.Listen("MAIL_CLOSED", function() if twinkMenu then twinkMenu:Hide() end end)

