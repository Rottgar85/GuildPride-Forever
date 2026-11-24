-- GuildPride: /gp diag – alles auf einen Blick, was bei Blizzard-Änderungen wichtig ist
-- (Realm, Gilde, Dungeonbrowser, Symbole, Community, Kanäle, gespeicherte Daten).
-- Zeigt einen Bericht zum Kopieren (ns.ShowCopy); ändert nichts.
local ADDON, ns = ...
local L = ns.L

local function Q(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<geheim>" end
    if type(v) == "string" then return '"' .. v .. '"' end
    return tostring(v)
end

local function Try(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "Fehler: " .. tostring(a) end
    return a, b, c, d
end

local function Count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function Keys(t)
    local out = {}
    if type(t) == "table" then for k in pairs(t) do out[#out + 1] = Q(k) end end
    table.sort(out)
    return #out > 0 and table.concat(out, ", ") or "-"
end

function ns.DiagReport()
    local lines = {}
    local function Add(label, ...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = Q((select(i, ...))) end
        lines[#lines + 1] = label .. ": " .. table.concat(parts, ", ")
    end
    local function Head(text) lines[#lines + 1] = ""; lines[#lines + 1] = "== " .. text .. " ==" end

    local version, build, _, toc = GetBuildInfo()
    version, build = tostring(version or "?"), tostring(build or "?")
    lines[1] = ("GuildPride %s · WoW %s (%s, %s) · %s · %s"):format(ns.VERSION or "?", version or "?", build or "?",
        tostring(toc or "?"), tostring(GetLocale and GetLocale() or "?"), date("%d.%m.%Y %H:%M"))

    Head("Spieler & Realm")
    Add("Region", GetCurrentRegion and GetCurrentRegion())
    Add("Fraktion", UnitFactionGroup("player"))
    Add("GetRealmName", GetRealmName and GetRealmName())
    Add("GetNormalizedRealmName", GetNormalizedRealmName and GetNormalizedRealmName())
    Add("RealmName (gemerkt)", ns.RealmName and ns.RealmName(), ns.RealmName and ns.RealmName(true))
    Add("Ich", ns.Me and ns.Me())
    Add("Karte", C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))

    Head("Gilde")
    Add("GetGuildInfo", GetGuildInfo("player"))
    Add("GuildId", ns.GuildId and ns.GuildId())
    local guilds = type(GuildPrideDB) == "table" and GuildPrideDB.guilds
    lines[#lines + 1] = "Gespeicherte Gilden: " .. Keys(guilds)
    Add("Meilensteine", ns.GuildLog and #ns.GuildLog())
    Add("Datenkanal", ns.DataChannelId and Try(ns.DataChannelId))
    Add("Offener Kanal", ns.PublicChannelId and Try(ns.PublicChannelId))
    Add("Serverweite Gruppensuche", ns.PublicLFGOn and ns.PublicLFGOn())

    Head("Dungeonbrowser")
    local f = LFGBrowseFrame
    Add("LFGBrowseFrame", f ~= nil, f and f:IsShown())
    Add("Kategorie", f and f.CategoryDropdown and f.CategoryDropdown.GetValue and Try(f.CategoryDropdown.GetValue, f.CategoryDropdown))
    Add("LFGParentFrame", LFGParentFrame ~= nil, LFGParentFrame and LFGParentFrame:IsShown())
    Add("LFDMicroButton", LFDMicroButton ~= nil, LFDMicroButton and LFDMicroButton:IsEnabled())
    if C_LFGList and C_LFGList.GetAvailableCategories then
        local cats = {}
        local ok, ids = pcall(C_LFGList.GetAvailableCategories)
        for _, id in ipairs(ok and ids or {}) do
            local info = C_LFGList.GetLfgCategoryInfo and C_LFGList.GetLfgCategoryInfo(id)
            cats[#cats + 1] = id .. "=" .. tostring(info and info.name)
        end
        lines[#lines + 1] = "Kategorien: " .. (#cats > 0 and table.concat(cats, ", ") or "-")
    end
    local filter = type(GuildPrideDB) == "table" and GuildPrideDB.lfgDungeons
    lines[#lines + 1] = "Dungeon-Filter: " .. Keys(filter)

    Head("Symbole")
    for _, a in ipairs({ "UI-HUD-MicroMenu-GuildCommunities-Up", "communities-icon-chat", "UI-ChatIcon-Discord" }) do
        Add(a, C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(a) ~= nil)
    end

    Head("Community")
    Add("C_Club", C_Club ~= nil, C_Club and C_Club.RedeemTicket ~= nil)
    Add("Knopf sichtbar", ns.CommunityHere and ns.CommunityHere())
    Add("Gemerkte Community", type(GuildPrideDB) == "table" and GuildPrideDB.communityClubId)
    Add("Link", ns.CommunityURL and ns.CommunityURL())
    if C_Club and C_Club.GetSubscribedClubs then
        local ok, clubs = pcall(C_Club.GetSubscribedClubs)
        local names = {}
        for _, c in ipairs(ok and clubs or {}) do names[#names + 1] = tostring(c.name) .. " (" .. tostring(c.clubType) .. ")" end
        lines[#lines + 1] = "Communitys: " .. (#names > 0 and table.concat(names, ", ") or "-")
    end

    -- Andere Addons: wer Chat, Tooltips, Gildenfenster oder Auktionshaus verändert, kann sich
    -- mit GuildPride überschneiden (so war es beim Chat-Fehler 2.37.1)
    Head("Andere Addons")
    local KNOWN = {
        chat = { "Prat-3.0", "Chattynator", "Chatter", "WIM", "ElvUI", "TukUI", "Glass", "BasicChatMods" },
        tooltip = { "TipTac", "TinyTooltip", "ElvUI", "Auctionator", "TradeSkillMaster", "RareScanner", "Questie" },
        gilde = { "Guildy", "GuildRoster", "GreenWall", "ElvUI" },
        auktionshaus = { "Auctionator", "TradeSkillMaster", "Auctioneer", "aux-addon" },
    }
    local getNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local isLoadedFn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local okNum, num = pcall(function() return getNum and getNum() end)
    num = okNum and tonumber(num) or 0
    if type(getInfo) ~= "function" or type(isLoadedFn) ~= "function" then num = 0 end
    local loaded, byName = {}, {}
    for i = 1, num do
        local name = getInfo(i)
        local isLoaded = isLoadedFn(i)
        if isLoaded and name and name ~= ADDON and not tostring(name):find("^Blizzard_") then
            loaded[#loaded + 1] = name
            byName[name] = true
        end
    end
    table.sort(loaded)
    lines[#lines + 1] = ("Geladen (%d): "):format(#loaded) .. (#loaded > 0 and table.concat(loaded, ", ") or "-")
    for _, area in ipairs({ "chat", "tooltip", "gilde", "auktionshaus" }) do
        local hits = {}
        for _, n in ipairs(KNOWN[area]) do if byName[n] then hits[#hits + 1] = n end end
        if #hits > 0 then lines[#lines + 1] = ("Mögliche Überschneidung (%s): %s"):format(area, table.concat(hits, ", ")) end
    end

    Head("Gespeicherte Daten")
    local transit = type(GuildPrideDB) == "table" and GuildPrideDB.transit
    lines[#lines + 1] = "Schiffe je Realm: " .. Keys(transit)
    lines[#lines + 1] = "Auktionshaus je Realm: " .. Keys(GuildPrideAHDB)
    Add("GuildPride-Spieler", ns.Players and ns.Players.Count and ns.Players.Count())
    Add("Versionen in der Gilde", Count(ns.Versions))

    -- Leistung: was GuildPride gerade braucht (nur Zahlen, die dieser Client liefert)
    Head("Leistung")
    local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local memory = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    local okMem, kb = pcall(function()
        if update then update() end
        return memory and memory(ADDON)
    end)
    if okMem and type(kb) == "number" then lines[#lines + 1] = ("Speicher: %.1f MB"):format(kb / 1024) end
    local prof, metric = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if type(prof) == "table" and type(metric) == "table" then
        for _, m in ipairs({ { "RecentAverageTime", "CPU je Bild zuletzt: %.3f ms" }, { "SessionAverageTime", "CPU je Bild, Sitzung: %.3f ms" },
                             { "PeakTime", "CPU längster Ruckler: %.3f ms" }, { "CountTimeOver5Ms", "Bilder über 5 ms: %d" },
                             { "CountTimeOver50Ms", "Bilder über 50 ms: %d" } }) do
            local okT, n = pcall(function() return metric[m[1]] and prof.GetAddOnMetric(ADDON, metric[m[1]]) end)
            if okT and type(n) == "number" then lines[#lines + 1] = m[2]:format(n) end
        end
    end
    local items, packed = 0, 0
    for _, sides in pairs(type(GuildPrideAHDB) == "table" and GuildPrideAHDB or {}) do
        for _, list in pairs(type(sides) == "table" and sides or {}) do
            for _, e in pairs(type(list) == "table" and list or {}) do
                items = items + 1
                if type(e) == "string" then packed = packed + 1 end
            end
        end
    end
    lines[#lines + 1] = ("Auktionspreise: %d, davon gepackt %d"):format(items, packed)
    Add("Zettel", Count(type(GuildPrideDB) == "table" and GuildPrideDB.zettel))
    Add("Gespeicherte Fehler", Count(type(GuildPrideDB) == "table" and GuildPrideDB.errors))

    return table.concat(lines, "\n")
end

local orig = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "diag" or cmd == "diagnose" then
        if ns.ShowCopy then
            ns.ShowCopy(L["Diagnose – alles markieren, kopieren und uns schicken"], ns.DiagReport())
        else
            print(ns.DiagReport())
        end
    else
        orig(arg)
    end
end
