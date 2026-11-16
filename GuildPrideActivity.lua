-- GuildPride: Reiter "Aktivität" (nur Offiziere)
-- Wer ist wie lange offline, wer meldet sich zu Events an (oder nie),
-- wer war zuletzt über Discord im Gildenchat aktiv.
-- Alles aus vorhandenen Daten: Gildenliste, Events, Anwesenheit, Discord-Chat.
local ADDON, ns = ...
local L = ns.L
if not ns.AddTab then return end

local page = ns.AddTab(L["Aktivität"], 85)
ns.SetTabOfficerOnly(page)

local SORTS = {
    { key = "offline", text = "Am längsten offline zuerst" },
    { key = "events",  text = "Wenigste Event-Zusagen zuerst" },
    { key = "name",    text = "Nach Name" },
}
local sortIndex = 1

local summary = page:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
summary:SetPoint("TOPLEFT", 8, -10); summary:SetWidth(400); summary:SetJustifyH("LEFT")

local bSort = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
if ns.SkinButton then ns.SkinButton(bSort) end
bSort:SetSize(230, 24); bSort:SetPoint("TOPRIGHT", -26, -4)

local head = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
head:SetPoint("TOPLEFT", 8, -36)
head:SetText(L["Name"])
local headMid = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
headMid:SetPoint("TOPLEFT", 208, -36)
headMid:SetText(L["Events (zugesagt · da) · Discord"])
local headRight = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
headRight:SetPoint("TOPRIGHT", -34, -36)
headRight:SetText(L["Zuletzt online"])

local holder = CreateFrame("Frame", nil, page)
holder:SetPoint("TOPLEFT", 0, -50); holder:SetPoint("BOTTOMRIGHT")
local list = ns.CreateList(holder, 22)

local function AgoDays(days)
    if days < 1 then return L["heute"] end
    return (L["vor %d Tag(en)"]):format(days)
end

local function OfflineText(y, m, d, h)
    if not y then return L["offline"] end
    if y > 0 then return (L["vor %d Jahr(en)"]):format(y) end
    if m > 0 then return (L["vor %d Monat(en)"]):format(m) end
    if d > 0 then return (L["vor %d Tag(en)"]):format(d) end
    if h > 0 then return (L["vor %d Std."]):format(h) end
    return L["vor < 1 Std."]
end

-- Zusagen aus den Events und Anwesenheit aus den erfassten Raids
local function EventStats()
    local stats = {}
    local function S(name)
        local key = ns.Normalize(name)
        stats[key] = stats[key] or { yes = 0, any = 0, present = 0, recorded = 0 }
        return stats[key]
    end
    for _, e in pairs(ns.GuildTable("events")) do
        if type(e) == "table" and type(e.signups) == "table" then
            for name, s in pairs(e.signups) do
                local st = S(name)
                st.any = st.any + 1
                if type(s) == "table" and s.s == "yes" then st.yes = st.yes + 1 end
            end
        end
    end
    for _, rec in pairs(ns.GuildTable("attendance")) do
        if type(rec) == "table" then
            for _, name in ipairs(rec.yes or {}) do local st = S(name); st.recorded = st.recorded + 1 end
            for _, name in ipairs(rec.present or {}) do local st = S(name); st.present = st.present + 1 end
        end
    end
    return stats
end

local function ClassHex(classFile)
    local c = classFile and RAID_CLASS_COLORS[classFile]
    return c and c.colorStr and c.colorStr:sub(3) or "f0c88c"
end

local EMPTY = { yes = 0, any = 0, present = 0, recorded = 0 }

function page:Refresh()
    bSort:SetText(L[SORTS[sortIndex].text])
    local stats, seen, now = EventStats(), ns.GuildTable("discordSeen"), GetServerTime()
    local data = {}
    for i = 1, GetNumGuildMembers() do
        local name, rank, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local full = ns.Normalize(name)
            local y, m, d, h
            if not online and GetGuildRosterLastOnline then y, m, d, h = GetGuildRosterLastOnline(i) end
            local hours = online and -1 or (((y or 0) * 365 + (m or 0) * 30 + (d or 0)) * 24 + (h or 0))
            data[#data + 1] = { name = Ambiguate(name, "guild"), rank = rank, class = classFile,
                online = online, hours = hours, last = not online and OfflineText(y, m, d, h) or nil,
                st = stats[full] or EMPTY, discord = seen[full] }
        end
    end
    local mode = SORTS[sortIndex].key
    table.sort(data, function(a, b)
        if mode == "events" and a.st.yes ~= b.st.yes then return a.st.yes < b.st.yes end
        if mode == "offline" and a.hours ~= b.hours then return a.hours > b.hours end
        return a.name < b.name
    end)

    local long, never = 0, 0
    for n, r in ipairs(data) do
        if r.hours >= 30 * 24 then long = long + 1 end
        if r.st.any == 0 then never = never + 1 end
        local row = list:GetRow(n)
        row.left:SetText(("|cff%s%s|r |cff999999%s|r"):format(ClassHex(r.class), r.name, r.rank or ""))
        local ev
        if r.st.any == 0 then
            ev = "|cffff8060" .. L["nie angemeldet"] .. "|r"
        else
            ev = (L["%d zugesagt"]):format(r.st.yes)
            if r.st.recorded > 0 then ev = ev .. " · " .. (L["da %d/%d"]):format(r.st.present, r.st.recorded) end
        end
        if r.discord then
            ev = ev .. " · |cff8c9effDiscord " .. AgoDays(math.floor((now - r.discord) / 86400)) .. "|r"
        end
        row.mid:SetText(ev)
        row.right:SetText(r.online and ("|cff40ff40" .. L["online"] .. "|r")
            or (r.hours >= 30 * 24 and ("|cffff6060" .. r.last .. "|r") or r.last))
    end
    list:Finish(#data)
    summary:SetText((L["%d Mitglieder · %d über 30 Tage offline · %d nie zu einem Event angemeldet"]):format(#data, long, never))
end

bSort:SetScript("OnClick", function()
    sortIndex = sortIndex % #SORTS + 1
    page:Refresh()
end)

local watch = CreateFrame("Frame")
watch:RegisterEvent("GUILD_ROSTER_UPDATE")
watch:SetScript("OnEvent", function() if page:IsVisible() then page:Refresh() end end)
