-- GuildPride Handwerk: „Wer kann das?“ – die Gilde fragen
-- Frage an alle Mitglieder mit GuildPride (abgesicherter Gildenkanal); wer einen Charakter mit
-- passendem Rezept hat, antwortet von selbst. Antworten werden gemerkt (auch wenn der
-- Handwerker später offline ist).
--   CWQ  frage                        Frage (ab 3 Buchstaben, Rezeptname)
--   CWA  frage · charakter · rezept   Antwort (nur über die eigenen Charaktere)
-- Gespeichert: GuildPrideDB.craftAsk = { { q, who, char, id, t }, … } (die neuesten 150)
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"
local Craft = ns.Craft

local Ask = {}
ns.CraftAsk = Ask

local MAX_KEEP, MAX_HITS = 150, 6

local function Clean(s, max) return ns.Clean and ns.Clean(s, max) or tostring(s or ""):sub(1, max) end
local function Answers()
    if type(GuildPrideDB) ~= "table" then return {} end
    GuildPrideDB.craftAsk = type(GuildPrideDB.craftAsk) == "table" and GuildPrideDB.craftAsk or {}
    return GuildPrideDB.craftAsk
end
Ask.Answers = Answers

-- Welche deiner Charaktere können ein Rezept, dessen Name q enthält? { { char, id } }
function Ask.MyMatches(q)
    q = strtrim(q or ""):lower()
    local out = {}
    if #q < 3 then return out end
    for name, e in pairs(Craft.Chars()) do
        if type(e) == "table" and e.known then
            for _, set in pairs(e.known) do
                for id in pairs(set) do
                    local n = Craft.RecipeName(id)
                    if n and n:lower():find(q, 1, true) then
                        out[#out + 1] = { char = name, id = id }
                        if #out >= MAX_HITS then return out end
                    end
                end
            end
        end
    end
    return out
end

local lastAsk = 0
function Ask.Ask(q)
    q = Clean(strtrim(q or ""), 40)
    if #q < 3 then ns.Print(L["Bitte mindestens 3 Buchstaben eingeben."]); return false end
    if GetTime() - lastAsk < 20 then ns.Print(L["Bitte kurz warten, bevor du wieder fragst."]); return false end
    if not IsInGuild() then return false end
    lastAsk = GetTime()
    ns.Queue("CWQ", "@CHANNEL", q)
    ns.Print((L["Gilde gefragt: Wer kann „%s“? Antworten erscheinen hier unter Gilde."]):format(q))
    return true
end

-- Gemerkte Antworten zu einem Suchtext (leer = alle): neueste zuerst
function Ask.Find(text)
    text = strtrim(text or ""):lower()
    local out = {}
    for _, a in ipairs(Answers()) do
        local name = Craft.RecipeName(a.id) or ""
        if text == "" or name:lower():find(text, 1, true) or (a.q or ""):lower():find(text, 1, true) then
            out[#out + 1] = a
        end
    end
    table.sort(out, function(x, y) return (x.t or 0) > (y.t or 0) end)
    return out
end

function Ask.Store(q, who, char, id)
    local list = Answers()
    for _, a in ipairs(list) do
        if a.who == who and a.char == char and a.id == id then a.t = GetServerTime(); a.q = q; return end
    end
    list[#list + 1] = { q = q, who = who, char = char, id = id, t = GetServerTime() }
    while #list > MAX_KEEP do table.remove(list, 1) end
end

-- Empfang
local answeredAt = {}
ns.On("CWQ", function(payload, sender)
    if sender == Craft.Me() then return end
    if answeredAt[sender] and GetTime() - answeredAt[sender] < 30 then return end
    local q = Clean((strsplit(SEP, payload or "")), 40)
    local hits = Ask.MyMatches(q)
    if #hits == 0 then return end
    answeredAt[sender] = GetTime()
    C_Timer.After(1 + math.random() * 3, function()
        for _, h in ipairs(hits) do ns.Queue("CWA", sender, q, h.char, h.id) end
    end)
end)

ns.On("CWA", function(payload, sender)
    if sender == Craft.Me() then return end
    local a = { strsplit(SEP, payload or "") }
    local q, char, id = Clean(a[1], 40), Clean(a[2], 60), tonumber(a[3])
    if not (id and id > 0 and id < 2000000 and char ~= "") then return end
    Ask.Store(q, sender, char, id)
    if ns.CraftWindow and ns.CraftWindow.Refresh then ns.CraftWindow.Refresh() end
end)
