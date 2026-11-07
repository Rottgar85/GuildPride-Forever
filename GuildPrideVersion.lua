-- GuildPride: Versionscheck
local ADDON, ns = ...
local L = ns.L
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local MY_VERSION = GetMeta(ADDON, "Version") or "0.0.0"
ns.VERSION = MY_VERSION
ns.Versions = {}

local function Parse(v)
    local a, b, c = tostring(v):match("^(%d+)%.?(%d*)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function Compare(a, b)
    local a1, a2, a3 = Parse(a)
    local b1, b2, b3 = Parse(b)
    if a1 ~= b1 then return a1 > b1 and 1 or -1 end
    if a2 ~= b2 then return a2 > b2 and 1 or -1 end
    if a3 ~= b3 then return a3 > b3 and 1 or -1 end
    return 0
end

local warned = false
ns.On("VER", function(payload, sender)
    if sender == ns.Me() then return end
    local theirs, isReply = strsplit(ns.SEP, payload)
    -- Nur echte Versionsnummern ("1.12.3") annehmen: der Text landet im Chat
    -- und in der Bildschirmwarnung, darf also keine Farb- oder Link-Codes enthalten
    if not theirs or #theirs > 20 or not theirs:match("^%d+%.%d+[%.%d]*$") then return end
    ns.Versions[sender] = theirs
    local cmp = Compare(theirs, MY_VERSION)
    if cmp > 0 and not warned then
        warned = true
        local msg = (L["Neue GuildPride-Version verfügbar: |cff40ff40%s|r (du hast %s). Bitte aktualisieren!"]):format(theirs, MY_VERSION)
        ns.Print(msg)
        RaidNotice_AddMessage(RaidWarningFrame, ns.IconString(20) .. " " .. msg, ChatTypeInfo["GUILD"])
    end
    -- Auf eine Login-Meldung antworten wir immer (einmal) per Flüstern:
    -- so erfährt der Neue, wer GuildPride hat (Logo im Chat), und ältere Versionen werden gewarnt.
    if isReply ~= "r" then
        ns.Queue("VER", sender, MY_VERSION, "r")
    end
end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- Altes und neues Addon teilen sich globale Namen und GuildPrideDB
    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if IsLoaded and IsLoaded("GuildPride") then ns.Print(L["Das alte Addon „GuildPride“ ist auch aktiv. Bitte schalte es in der Addon-Liste ab, sonst stören sich beide."]) end
    C_Timer.After(12, function() ns.Queue("VER", nil, MY_VERSION, "") end)
end)

local orig = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    if (arg or ""):lower() == "version" then
        -- Frisch nachfragen: alle antworten per Flüstern. Sonst fehlen alle, die sich
        -- nach uns eingeloggt haben und deren Login-Meldung an die Gilde nicht ankam.
        ns.Queue("VER", nil, MY_VERSION, "")
        ns.Print(L["Frage Versionen ab …"])
        C_Timer.After(6, function() SlashCmdList.GUILDPRIDE("versionlist") end)
    elseif (arg or ""):lower() == "versionlist" then
        ns.Print(L["Deine Version: "] .. MY_VERSION)
        local n = 0
        for name, v in pairs(ns.Versions) do
            n = n + 1
            local c = Compare(v, MY_VERSION)
            print(("  %s: %s%s|r"):format(Ambiguate(name, "guild"),
                c < 0 and "|cffff4040" or (c > 0 and "|cff40ff40" or "|cffffffff"), v))
        end
        if n == 0 then print(L["  Noch keine anderen Versionen empfangen."]) end
    else
        orig(arg)
    end
end
