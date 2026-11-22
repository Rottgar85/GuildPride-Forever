-- GuildPride: Einstellungen sichern und übertragen
--   /gp export  zeigt einen Text mit allen Einstellungen (zum Kopieren)
--   /gp import  nimmt so einen Text wieder an – auf einem anderen PC oder für einen Twink
-- Übertragen werden nur Einstellungen (Haken, Zahlen, Begrüßungstext), keine Gildendaten,
-- Preise oder Listen. Format: "GP1;schlüssel=b1;schlüssel=n12;schlüssel=sText" (Text mit %-Escapes).
local ADDON, ns = ...
local L = ns.L

local IO = {}
ns.SettingsIO = IO
local HEAD = "GP1"
-- zusätzlich zu den Standard-Einstellungen
local EXTRA = { welcomeText = "string", lfgAlert = "boolean", playersFilter = "string" }

local function Esc(s) return (s:gsub("[%%;=|%c]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function Allowed(k, v)
    local d = ns.DEFAULTS and ns.DEFAULTS[k]
    local want = d ~= nil and type(d) or EXTRA[k]
    return want ~= nil and type(v) == want
end

function IO.Export(db)
    db = db or GuildPrideDB or {}
    local keys = {}
    for k in pairs(ns.DEFAULTS or {}) do keys[#keys + 1] = k end
    for k in pairs(EXTRA) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = { HEAD }
    for _, k in ipairs(keys) do
        local v = db[k]
        if Allowed(k, v) then
            if type(v) == "boolean" then parts[#parts + 1] = k .. "=b" .. (v and "1" or "0")
            elseif type(v) == "number" then parts[#parts + 1] = k .. "=n" .. tostring(v)
            else parts[#parts + 1] = k .. "=s" .. Esc(v) end
        end
    end
    return table.concat(parts, ";")
end

-- Gibt die Anzahl übernommener Einstellungen zurück oder nil, Grund
function IO.Import(text, db)
    db = db or GuildPrideDB
    text = strtrim(tostring(text or ""))
    if text:sub(1, #HEAD + 1) ~= HEAD .. ";" then return nil, "format" end
    local n = 0
    for part in text:sub(#HEAD + 2):gmatch("[^;]+") do
        local k, t, raw = part:match("^([%w_]+)=([bns])(.*)$")
        local v
        if t == "b" then v = raw == "1"
        elseif t == "n" then v = tonumber(raw)
        elseif t == "s" then v = Unesc(raw) end
        if k and v ~= nil and Allowed(k, v) then
            if type(v) == "number" and (v ~= v or v > 1e6 or v < -1e6) then v = nil end
            if type(v) == "string" then v = v:gsub("|", ""):sub(1, 300) end
            if v ~= nil then db[k] = v; n = n + 1 end
        end
    end
    return n
end

StaticPopupDialogs["GUILDPRIDE_SETTINGS_IMPORT"] = {
    text = L["GuildPride-Einstellungen einfügen (Strg+V) und mit OK übernehmen:"],
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true, maxLetters = 4000, editBoxWidth = 320,
    OnAccept = function(self)
        local n, why = IO.Import((self.editBox or self.EditBox):GetText())
        if not n then
            ns.Print(why == "format" and L["Das ist kein GuildPride-Einstellungstext (/gp export)."] or tostring(why))
        else
            ns.Print((L["%d Einstellungen übernommen. /reload wendet alles an."]):format(n))
        end
    end,
    EditBoxOnEnterPressed = function(eb)
        local dlg = eb:GetParent()
        StaticPopupDialogs.GUILDPRIDE_SETTINGS_IMPORT.OnAccept(dlg); dlg:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):match("^(%S+)")
    cmd = cmd and cmd:lower()
    if cmd == "export" then
        if ns.ShowCopy then ns.ShowCopy(L["GuildPride-Einstellungen – Text kopieren (Strg+C)"], IO.Export()) end
    elseif cmd == "import" then
        StaticPopup_Show("GUILDPRIDE_SETTINGS_IMPORT")
    elseif origSlash then
        origSlash(arg)
    end
end
