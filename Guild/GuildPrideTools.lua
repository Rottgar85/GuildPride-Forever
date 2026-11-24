-- GuildPride: Seite „Werkzeuge“ (unter „Planen“) – ein Knopf je Werkzeug mit kurzer Erklärung
local ADDON, ns = ...
local L = ns.L
if not ns.AddTab then return end

local page = ns.AddTab(L["Werkzeuge"], 58)
local TOOLS = {
    { label = L["Raid-Bereitschaft"], text = L["Vor dem Raid: wer ist satt, hat Tränke dabei und heile Ausrüstung? (Leiter und Assistenten)"],
      open = function() ns.Ready.Open() end },
    { label = L["Quests der Gilde"], text = L["Wer online ist und dieselbe Quest hat wie du – Klick lädt ein."],
      open = function() ns.GuildQuests.Open() end },
    { label = L["Boss-Notizen"], text = L["Kurze Taktik je Boss; geht beim Betreten der Instanz von selbst auf."],
      open = function() ns.BossNotes.Open() end },
    { label = L["Materialliste der Gilde"], text = L["Was die Gilde sammelt und wer wie viel beisteuert."],
      open = function() ns.Stock.Open() end },
    { label = L["Loot-Verlauf"], text = L["Wer in Dungeons und Raids was bekommen hat (ab selten)."], open = function() ns.Loot.Open() end },
    { label = L["Abklingzeiten der Gruppe"], text = L["Wiedergeburt, Schildwall und andere wichtige Zauber der Gildenmitglieder."], open = function() ns.Cooldowns.Open() end },
    { label = L["Paten für Neue"], text = L["Wer hilft neuen Mitgliedern? Selbst Pate werden."], open = function() ns.Mentor.Open() end },
    { label = L["Gildenquiz"], text = L["Offiziere stellen Fragen, die schnellste richtige Antwort zählt."], open = function() ns.Quiz.Open() end },
    { label = L["Gildenalbum"], text = L["Eure ersten Bosskills mit Datum, auf Wunsch mit Screenshot."], open = function() ns.Album.Open() end },
    { label = L["Suche über alles"], text = L["Mitglieder, Events, Einstellungen, Befehle und Rezepte finden (/gp suche)."], open = function() ns.Search.Open() end },
    { label = L["Event-Auswertung"], text = L["Verlässlichkeit, Wochentage und Verlauf aus der Anwesenheit."], officer = true,
      open = function() ns.EventStats.Open() end },
}

local rows = {}
for i, t in ipairs(TOOLS) do
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetSize(200, 24); b:SetPoint("TOPLEFT", 8, -4 - (i - 1) * 35); b:SetText(t.label)
    b:SetScript("OnClick", t.open)
    local fs = page:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    fs:SetPoint("LEFT", b, "RIGHT", 14, 0); fs:SetWidth(400); fs:SetJustifyH("LEFT")
    fs:SetText(t.text)
    rows[i] = { b = b, fs = fs, officer = t.officer }
end

function page:Refresh()
    local officer = CanEditMOTD and CanEditMOTD() and true or false
    for _, r in ipairs(rows) do
        local on = not r.officer or officer
        r.b:SetShown(on); r.fs:SetShown(on)
    end
end
