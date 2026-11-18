-- GuildPride: Markierungen an Spielernamen (Symbol vor dem Namen, Tooltip-Zeile)
local ADDON, ns = ...
local SEP = ns.SEP or "\031"

local K1 = "0bip88v1ndy026"
local K2 = {
    ["1vxs7k00jec691"] = true,
}

local ICON = "|TInterface\\AddOns\\GuildPrideForever\\Media\\logo_small:14:14:0:0|t"
local TITLE_HEX = "ff8000"
local T_DE, T_EN = { 74, 120, 108, 111, 103, 83, 117, 108, 103, 104, 48, 72, 113, 119, 122, 108, 102, 110, 111, 104, 117 }, { 74, 120, 108, 111, 103, 83, 117, 108, 103, 104, 35, 103, 104, 121, 104, 111, 114, 115, 104, 117 }
local function Txt(t) local o = {} for i, b in ipairs(t) do o[i] = string.char(b - 3) end return table.concat(o) end
local MAX_KNOWN = 40

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local M32 = 4294967296
local function Mix(s, seed, mult)
    local h = seed
    for i = 1, #s do h = (h * mult + s:byte(i) + i) % M32 end
    return h
end
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Base36(n, len)
    local out = {}
    for i = len, 1, -1 do
        local d = n % 36
        out[i] = DIGITS:sub(d + 1, d + 1)
        n = math.floor(n / 36)
    end
    return table.concat(out)
end
local function MakeCode(text)
    return Base36(Mix(text, 5381, 33), 7) .. Base36(Mix(text, 2166136, 131), 7)
end

local codeCache = {}
local function CharCode(name)
    local c = codeCache[name]
    if not c then
        c = MakeCode("GPS" .. SEP .. name:lower())
        codeCache[name] = c
    end
    return c
end

local function AccountCode()
    if not BNGetInfo then return nil end
    local ok, _, tag = pcall(BNGetInfo)
    if not ok or type(tag) ~= "string" or tag == "" or Secret(tag) then return nil end
    return MakeCode("GPSB" .. SEP .. tag:lower())
end

local function ValidCode(c) return type(c) == "string" and #c == 14 and c:match("^[0-9a-z]+$") ~= nil end

local function Known()
    if not GuildPrideDB then return nil end
    GuildPrideDB.mk = GuildPrideDB.mk or {}
    return GuildPrideDB.mk
end

local own
local function Own()
    if own == nil and GuildPrideDB then
        local acc = K1 ~= "" and AccountCode()
        own = (acc and acc == K1) or (GuildPrideDB.mka == true) or false
    end
    return own
end

local function IsMarkedCode(code)
    if K2[code] then return true end
    local k = Known()
    return k ~= nil and k[code] ~= nil
end

function ns.IsMarked(name)
    if type(name) ~= "string" or name == "" or Secret(name) then return false end
    local n = ns.Normalize and ns.Normalize(name) or name
    return n ~= nil and IsMarkedCode(CharCode(n))
end

function ns.NameMark(name)
    return ns.IsMarked(name) and (ICON .. " ") or ""
end

local function MyCodes()
    local list, seen = {}, {}
    local me = CharCode(ns.Me())
    list[1], seen[me] = me, true
    for code in pairs(GuildPrideDB.mkc or {}) do
        if not seen[code] and #list < 12 then list[#list + 1], seen[code] = code, true end
    end
    return list
end

local lastAnnounce = -600
local function Announce()
    if not Own() or not ns.Queue or GetTime() - lastAnnounce < 300 then return end
    if not ns.IsMarked(ns.Me()) then return end
    lastAnnounce = GetTime()
    local codes = MyCodes()
    if IsInGuild() then ns.Queue("GPS", nil, unpack(codes)) end
    if ns.PublicLFGOn and ns.PublicLFGOn() and ns.PublicChannelId and ns.PublicChannelId() and not ns.PUBLIC_VIA_CHAT then
        ns.Queue("GPS", "@PUBLIC", unpack(codes))
    end
end

function ns.OnMarkMessage(message, sender)
    if not ns.IsMarked(sender) or sender == ns.Me() then return end
    local k = Known()
    if not k then return end
    local count = 0
    for _ in pairs(k) do count = count + 1 end
    local changed = false
    for _, code in ipairs({ strsplit(SEP, message:sub(5)) }) do
        if ValidCode(code) and not IsMarkedCode(code) and count < MAX_KNOWN then
            k[code] = GetServerTime()
            count, changed = count + 1, true
        end
    end
    if changed and ns.RefreshUI then ns.RefreshUI() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if Own() then
            GuildPrideDB.mka = true
            GuildPrideDB.mkc = GuildPrideDB.mkc or {}
            GuildPrideDB.mkc[CharCode(ns.Me())] = true
            Known()[CharCode(ns.Me())] = Known()[CharCode(ns.Me())] or GetServerTime()
        end
    end
    C_Timer.After(40, Announce)
end)

local function OnUnitTooltip(tip)
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or not unit or Secret(unit) or not UnitIsPlayer(unit) then return end
    local n, s = UnitFullName(unit)
    if not n or Secret(n) or Secret(s) then return end
    if ns.IsMarked((s and s ~= "") and (n .. "-" .. s) or n) then
        tip:AddLine(ICON .. " |cff" .. TITLE_HEX .. Txt(ns.IS_GERMAN and T_DE or T_EN) .. "|r")
    end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
elseif GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
end

local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddFilter then
    local function Filter(_, _, msg, author, ...)
        if Secret(msg) or Secret(author) or type(msg) ~= "string" then return false end
        if not ns.IsMarked(author) then return false end
        return false, ICON .. " " .. msg, author, ...
    end
    for _, e in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                         "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
                         "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
                         "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL" }) do
        AddFilter(e, Filter)
    end
end

function ns.MarkCommand()
    local lines = {
        "K1 = \"" .. (AccountCode() or "?") .. "\"",
        "[\"" .. CharCode(ns.Me()) .. "\"] = true,",
    }
    if ns.ShowCopy then ns.ShowCopy("GPS", table.concat(lines, "\n"))
    else for _, l in ipairs(lines) do print(l) end end
end
