-- GuildPride: Seite „Werkzeuge“ (unter „Planen“) – ein Knopf je Werkzeug mit kurzer Erklärung
local ADDON, ns = ...
local L = ns.L
if not ns.AddTab then return end

local page = ns.AddTab(L["Werkzeuge"], 58)
local TOOLS = {
    { key = "inv_potion_54", icon = "INV_Potion_54", label = L["Raid-Bereitschaft"], text = L["Vor dem Raid: wer ist satt, hat Tränke dabei und heile Ausrüstung? (Leiter und Assistenten)"],
      open = function() ns.Ready.Open() end },
    { key = "inv_misc_book_08", icon = "INV_Misc_Book_08", label = L["Quests der Gilde"], text = L["Wer online ist und dieselbe Quest hat wie du – Klick lädt ein."],
      open = function() ns.GuildQuests.Open() end },
    { key = "inv_misc_head_dragon_01", icon = "INV_Misc_Head_Dragon_01", label = L["Boss-Notizen"], text = L["Kurze Taktik je Boss; geht beim Betreten der Instanz von selbst auf."],
      open = function() ns.BossNotes.Open() end },
    { key = "inv_crate_02", icon = "INV_Crate_02", label = L["Materialliste der Gilde"], text = L["Was die Gilde sammelt und wer wie viel beisteuert."],
      open = function() ns.Stock.Open() end },
    { key = "inv_misc_bag_10", icon = "INV_Misc_Bag_10", label = L["Loot-Verlauf"], text = L["Wer in Dungeons und Raids was bekommen hat (ab selten)."], open = function() ns.Loot.Open() end },
    { key = "inv_misc_pocketwatch_01", icon = "INV_Misc_PocketWatch_01", label = L["Abklingzeiten der Gruppe"], text = L["Wiedergeburt, Schildwall und andere wichtige Zauber der Gildenmitglieder."], open = function() ns.Cooldowns.Open() end },
    { key = "inv_misc_grouplooking", icon = "INV_Misc_GroupLooking", label = L["Paten für Neue"], text = L["Wer hilft neuen Mitgliedern? Selbst Pate werden."], open = function() ns.Mentor.Open() end },
    { key = "inv_misc_questionmark", icon = "INV_Misc_QuestionMark", label = L["Gildenquiz"], text = L["Offiziere stellen Fragen, die schnellste richtige Antwort zählt."], open = function() ns.Quiz.Open() end },
    { key = "jagd", icon = "INV_Misc_Map_01", label = L["Schnitzeljagd"], text = L["Stationen suchen; Offiziere legen sie an."], open = function() ns.Hunt.Open() end },
    { key = "inv_misc_spyglass_02", icon = "INV_Misc_Spyglass_02", label = L["Gildenalbum"], text = L["Eure ersten Bosskills mit Datum, auf Wunsch mit Screenshot."], open = function() ns.Album.Open() end },
    { key = "inv_misc_spyglass_03", icon = "INV_Misc_Spyglass_03", label = L["Suche über alles"], text = L["Mitglieder, Events, Einstellungen, Befehle und Rezepte finden (/gp suche)."], open = function() ns.Search.Open() end },
    { key = "inv_misc_note_01", icon = "INV_Misc_Note_01", label = L["Event-Auswertung"], text = L["Verlässlichkeit, Wochentage und Verlauf aus der Anwesenheit."], officer = true,
      open = function() ns.EventStats.Open() end },
}

local function Hidden()
    if type(GuildPrideDB) ~= "table" then return {} end
    GuildPrideDB.toolsHidden = type(GuildPrideDB.toolsHidden) == "table" and GuildPrideDB.toolsHidden or {}
    return GuildPrideDB.toolsHidden
end
local W, H, GAP = 306, 58, 8
local showAll = false
local tiles = {}
for i, t in ipairs(TOOLS) do
    local b = CreateFrame("Button", nil, page)
    b:SetSize(W, H)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if ns.DarkBg then ns.DarkBg(bg, 0.45) else bg:SetColorTexture(0, 0, 0, 0.4) end
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    if ns.Paint then ns.Paint(glow, "glow", 0.12) else glow:SetColorTexture(1, 0.8, 0.4, 0.1) end
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36); icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\Icons\\" .. t.icon); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = b:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1); title:SetText(t.label)
    local fs = b:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    fs:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2); fs:SetWidth(W - 66)
    fs:SetJustifyH("LEFT"); fs:SetMaxLines(2); fs:SetText(t.text)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Hidden()[t.key] = not Hidden()[t.key] or nil
            page:Refresh()
        else
            t.open()
        end
    end)
    tiles[i] = { b = b, t = t }
end
local hint = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
hint:SetPoint("BOTTOMLEFT", 8, 8)
hint:SetText(L["Rechtsklick blendet ein Werkzeug aus oder wieder ein."])
local all = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
all:SetSize(22, 22); all:SetPoint("BOTTOMRIGHT", -170, 2)
local allText = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
allText:SetPoint("LEFT", all, "RIGHT", 2, 0); allText:SetText(L["Ausgeblendete zeigen"])
all:SetScript("OnClick", function(self) showAll = self:GetChecked() and true or false; page:Refresh() end)

function page:Refresh()
    local officer = CanEditMOTD and CanEditMOTD() and true or false
    local n = 0
    for _, x in ipairs(tiles) do
        local off = Hidden()[x.t.key]
        local on = (not x.t.officer or officer) and (showAll or not off)
        x.b:SetShown(on)
        if on then
            x.b:SetAlpha(off and 0.45 or 1)
            x.b:ClearAllPoints()
            x.b:SetPoint("TOPLEFT", 4 + (n % 2) * (W + GAP), -4 - math.floor(n / 2) * (H + GAP))
            n = n + 1
        end
    end
end
