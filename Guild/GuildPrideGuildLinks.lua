-- GuildPride: Links der eigenen Gilde (Discord-Server und Ingame-Community)
-- Offiziere tragen sie in der Verwaltung ein; GuildPride verteilt sie an alle Mitglieder. Genutzt im
-- Willkommensfenster und im Begrüßungstext ({discord}, {community}).
-- Die Knöpfe oben im Gildenfenster („D“, Community) bleiben die von GuildPride selbst (Hilfe & Support).
--   GLK  ver · von · Discord-Link · Community-Link   (direkt von Offizieren sofort, sonst erst bei zwei gleichen Meldungen)
--   GLQ  1                                           (Anfrage nach dem Einloggen; wer die Links hat, antwortet)
-- Gespeichert: GuildTable("links") = { ver, by, discord, community }
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Links = {}
ns.GuildLinks = Links
local MAX_LEN = 120

local function DB() return ns.GuildTable("links") end

-- Nur echte Einladungslinks: https://…, ohne Leerzeichen und Steuerzeichen.
-- Discord: discord.gg/… oder discord.com/invite/…; Community: Blizzards Einladungslink.
-- "" = Link löschen. nil = ungültig.
function Links.Clean(kind, text)
    text = strtrim(tostring(text or ""))
    if text == "" then return "" end
    if #text > MAX_LEN or text:find("[%s|%c]") then return nil end
    local lower = text:lower()
    if not lower:find("^https?://") then text = "https://" .. text; lower = "https://" .. lower end
    if kind == "discord" then
        if lower:match("^https?://discord%.gg/[%w%-_]+/?$") or lower:match("^https?://discord%.com/invite/[%w%-_]+/?$")
            or lower:match("^https?://www%.discord%.gg/[%w%-_]+/?$") then return text end
        return nil
    end
    if lower:match("^https?://[%w%.]*worldofwarcraft%.com/invite/[%w%-_]+[%w%-_%?=&]*$") then return text end
    return nil
end

function Links.Get(kind)
    local v = DB()[kind]
    return type(v) == "string" and v ~= "" and v or nil
end

local function Send(target)
    local db = DB()
    if not db.ver then return end
    ns.Queue("GLK", target, db.ver, db.by or "", db.discord or "", db.community or "")
end

local function Apply(ver, by, discord, community)
    local db = DB()
    if (db.ver or 0) >= ver then return false end
    db.ver, db.by, db.discord, db.community = ver, by, discord, community
    if Links.Changed then Links.Changed() end
    return true
end

-- Offizier speichert: gibt true zurück oder nil, Grund ("recht", "discord", "community")
function Links.Set(discord, community)
    if not (ns.IsOfficer and ns.IsOfficer()) then return nil, "recht" end
    local d, c = Links.Clean("discord", discord), Links.Clean("community", community)
    if not d then return nil, "discord" end
    if not c then return nil, "community" end
    local db = DB()
    Apply(math.max(GetServerTime(), (db.ver or 0) + 1), ns.Me(), d, c)
    Send()
    return true
end

ns.On("GLK", function(payload, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    local ver, by, discord, community = strsplit(SEP, payload or "")
    ver = ns.Stamp(ver)
    if ver == 0 then return end
    discord, community = Links.Clean("discord", discord), Links.Clean("community", community)
    if not discord or not community then return end
    -- direkt von einem Offizier: sofort; weitergegeben: erst, wenn zwei Mitglieder dasselbe melden
    local direct = ns.IsOfficerName and ns.IsOfficerName(sender)
    if not direct and not ns.Confirmed("GLK:" .. ver .. ":" .. discord .. ":" .. community, sender) then return end
    Apply(ver, tostring(by or ""):sub(1, 60), discord, community)
end)

ns.On("GLQ", function(_, sender)
    if sender == ns.Me() or not DB().ver then return end
    C_Timer.After(1 + math.random() * 5, function() Send(sender) end)
end)

-- Platzhalter im Begrüßungstext ersetzen; ohne Link fällt der Platzhalter weg
function Links.Fill(text)
    text = tostring(text or "")
    text = text:gsub("{discord}", function() return Links.Get("discord") or "" end)
    text = text:gsub("{community}", function() return Links.Get("community") or "" end)
    return strtrim((text:gsub("  +", " ")))
end

-- Kleines Fenster wie beim „D“-Knopf: eine Zeile, Link markiert, nur zum Kopieren
local shownUrl = ""
StaticPopupDialogs["GUILDPRIDE_GUILD_LINK"] = {
    text = "%s",
    button1 = CLOSE or OKAY,
    hasEditBox = true, editBoxWidth = 280,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        eb:SetText(shownUrl); eb:SetFocus(); eb:HighlightText()
    end,
    -- nur lesen: Eingaben sofort zurücksetzen
    EditBoxOnTextChanged = function(eb)
        if eb:GetText() ~= shownUrl then eb:SetText(shownUrl); eb:HighlightText() end
    end,
    EditBoxOnEnterPressed = function(eb) eb:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Link zum Kopieren zeigen (oder Hinweis, dass noch keiner eingetragen ist)
function Links.Show(kind)
    local url = Links.Get(kind)
    if not url then
        ns.Print(kind == "discord" and L["Für diese Gilde ist noch kein Discord-Link eingetragen (Offiziere: Verwaltung › Links der Gilde)."]
            or L["Für diese Gilde ist noch kein Community-Link eingetragen (Offiziere: Verwaltung › Links der Gilde)."])
        return false
    end
    shownUrl = url
    StaticPopup_Show("GUILDPRIDE_GUILD_LINK", kind == "discord" and L["Discord der Gilde\n\nStrg+C kopiert den Link."]
        or L["Community der Gilde\n\nStrg+C kopiert den Link, dann im Spiel unter „Gilde & Communitys“ einfügen."])
    return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(35, function() if IsInGuild() then ns.Queue("GLQ", nil, "1") end end)
end)
