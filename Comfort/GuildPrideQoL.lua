-- GuildPride: kleine Helfer im Alltag (jeder einzeln in den Einstellungen › Komfort)
-- * sellJunk:      beim Händler Graues verkaufen, Erlös im Chat (Rückkauf beim Händler geht weiter)
-- * autoQuest:     Quests annehmen und abgeben; bei mehreren Belohnungen wählst du selbst,
--                  Quests mit Goldkosten nie; Umschalt gedrückt halten = nichts automatisch
-- * acceptInvites: Gruppen-Einladungen von Gildenmitgliedern und Freunden annehmen
-- * declineDuels:  Duell-Anfragen ablehnen (duelAllowKnown: Gilde und Freunde dürfen)
-- * hearthInfo:    Ruhestein-Ort und Abklingzeit unter „Heute“ und im Tooltip des Ruhesteins
-- * chatLinks:     Webadressen aus dem Chat merken, /gp links zeigt sie zum Kopieren.
--                  Der Chat selbst wird nicht verändert (Umschreiben hat früher Nachrichten verschluckt).
local ADDON, ns = ...
local L = ns.L

local Q = {}
ns.QoL = Q

local HEARTHSTONE = 6948

local function Opt(key) return type(GuildPrideDB) == "table" and GuildPrideDB[key] ~= false end
local function On(key) return type(GuildPrideDB) == "table" and GuildPrideDB[key] == true end

---------------------------------------------------------------------
-- Rechnen (rein, getestet)
---------------------------------------------------------------------
-- Graues mit Händlerpreis, nicht gesperrt → Liste, Summe in Kupfer
function Q.JunkList(items)
    local out, total = {}, 0
    for _, it in ipairs(items) do
        if it.quality == 0 and (it.price or 0) > 0 and not it.locked then
            out[#out + 1] = it
            total = total + it.price * (it.count or 1)
        end
    end
    return out, total
end

-- Belohnung: true + Nummer (nil = keine Auswahl nötig) oder false (du wählst)
function Q.RewardChoice(numChoices)
    if (numChoices or 0) == 0 then return true, nil end
    if numChoices == 1 then return true, 1 end
    return false
end

function Q.CanAutoComplete(completable, moneyNeeded, shift)
    return completable and (moneyNeeded or 0) == 0 and not shift or false
end

function Q.AcceptInvite(opt, isGuild, isFriend)
    return opt and (isGuild or isFriend) and true or false
end

function Q.DeclineDuel(opt, allowKnown, isGuild, isFriend)
    if not opt then return false end
    return not (allowKnown and (isGuild or isFriend))
end

function Q.HearthText(loc, left)
    if type(loc) ~= "string" or loc == "" then return nil end
    if not left or left <= 0 then return (L["Ruhestein: %s – bereit"]):format(loc) end
    return (L["Ruhestein: %s – bereit in %d Min."]):format(loc, math.ceil(left / 60))
end

-- Webadressen in einem Text (Reihenfolge wie im Text)
function Q.FindURLs(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for word in text:gmatch("%S+") do
        local w = word:gsub("^[%(%[<\"']+", ""):gsub("[%.,;:!%?%)%]>\"']+$", "")
        local low = w:lower()
        if low:match("^https?://%S") or low:match("^www%.[%w%-]+%.%a%a") or low:match("^discord%.gg/%w") then
            out[#out + 1] = w
        end
    end
    return out
end

-- Neueste oben, ohne Doppelte, höchstens max (20)
function Q.Remember(list, entry, max)
    for i = #list, 1, -1 do if list[i].url == entry.url then table.remove(list, i) end end
    table.insert(list, 1, entry)
    while #list > (max or 20) do table.remove(list) end
end

---------------------------------------------------------------------
-- Spiel
---------------------------------------------------------------------
local Secret = ns.IsSecret
local function Money(c) return ns.AH and ns.AH.Money and ns.AH.Money(c) or (("%dg"):format(math.floor(c / 10000))) end
local function Short(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or name end
local function IsGuild(name) return ns.IsGuildMember and name and ns.IsGuildMember(Short(name)) or false end
local function IsFriend(name, guid)
    local F = C_FriendList
    if guid and F and F.IsFriend then
        local ok, r = pcall(F.IsFriend, guid)
        if ok and r then return true end
    end
    if guid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
        local ok, r = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
        if ok and r then return true end
    end
    if name and F and F.GetFriendInfo then
        local ok, r = pcall(F.GetFriendInfo, Short(name))
        if ok and r then return true end
    end
    return false
end

-- 1. Plunder verkaufen (in kleinen Schritten, damit der Server mitkommt)
local merchantOpen = false
local function SellJunk()
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo and C.UseContainerItem) then return end
    local items = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.itemID and not info.hasNoValue then
                local price = C_Item and C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(info.itemID)) or 0
                items[#items + 1] = { bag = bag, slot = slot, quality = info.quality, price = price or 0,
                                      count = info.stackCount or 1, locked = info.isLocked }
            end
        end
    end
    local list, total = Q.JunkList(items)
    if #list == 0 then return end
    local i = 0
    local function Step()
        for _ = 1, 10 do
            i = i + 1
            local it = list[i]
            if not it or not merchantOpen then break end
            pcall(C.UseContainerItem, it.bag, it.slot)
        end
        if list[i + 1] and merchantOpen then C_Timer.After(0.3, Step)
        else ns.Print((L["Plunder verkauft: %d Gegenstände für %s."]):format(math.min(i, #list), Money(total))) end
    end
    Step()
end

-- 2. Quests
local function Shift() return IsShiftKeyDown and IsShiftKeyDown() or false end
local function QuestDetail()
    if not On("autoQuest") or Shift() then return end
    if AcceptQuest then pcall(AcceptQuest) end
end
local function QuestProgress()
    if not On("autoQuest") then return end
    local completable = IsQuestCompletable and IsQuestCompletable()
    local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    if Q.CanAutoComplete(completable, money, Shift()) and CompleteQuest then pcall(CompleteQuest) end
end
local function QuestComplete()
    if not On("autoQuest") or Shift() then return end
    local ok, index = Q.RewardChoice(GetNumQuestChoices and GetNumQuestChoices() or 0)
    if ok and GetQuestReward then pcall(GetQuestReward, index) end
end
-- Gesprächsfenster: fertige Quests zuerst abgeben, sonst eine neue nehmen
local function Gossip()
    if not On("autoQuest") or Shift() then return end
    local G = C_GossipInfo
    if G and G.GetActiveQuests and G.SelectActiveQuest then
        for _, q in ipairs(G.GetActiveQuests() or {}) do
            if q.isComplete and q.questID then G.SelectActiveQuest(q.questID); return end
        end
    end
    if G and G.GetAvailableQuests and G.SelectAvailableQuest then
        local q = (G.GetAvailableQuests() or {})[1]
        if q and q.questID then G.SelectAvailableQuest(q.questID) end
    end
end
local function Greeting()
    if not On("autoQuest") or Shift() then return end
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
        local _, complete = GetActiveTitle(i)
        if complete and SelectActiveQuest then SelectActiveQuest(i); return end
    end
    if (GetNumAvailableQuests and GetNumAvailableQuests() or 0) > 0 and SelectAvailableQuest then SelectAvailableQuest(1) end
end

-- 3. Einladungen
local function Invite(name, guid)
    if Secret(name) or Secret(guid) then return end
    if not Q.AcceptInvite(On("acceptInvites"), IsGuild(name), IsFriend(name, guid)) then return end
    if AcceptGroup then
        pcall(AcceptGroup)
        ns.Print((L["Einladung von %s angenommen."]):format(Short(name) or "?"))
    end
end

-- 4. Duelle
local function Duel(name)
    if Secret(name) then return end
    if not Q.DeclineDuel(On("declineDuels"), Opt("duelAllowKnown"), IsGuild(name), IsFriend(name)) then return end
    if CancelDuel then
        pcall(CancelDuel)
        ns.Print((L["Duell von %s abgelehnt."]):format(Short(name) or "?"))
    end
end

-- 5. Ruhestein
local function HearthLeft()
    local f = C_Container and C_Container.GetItemCooldown
    if not f then return 0 end
    local start, dur = f(HEARTHSTONE)
    if Secret(start) or Secret(dur) or type(start) ~= "number" or type(dur) ~= "number" or dur <= 1.5 then return 0 end
    return math.max(0, start + dur - GetTime())
end
function Q.HearthLine()
    if not Opt("hearthInfo") then return nil end
    local f = C_Item and C_Item.GetItemCount
    if f and (f(HEARTHSTONE) or 0) == 0 then return nil end
    return Q.HearthText(GetBindLocation and GetBindLocation(), HearthLeft())
end
if ns.Today and ns.Today.EXTRA then
    table.insert(ns.Today.EXTRA, function(add) local l = Q.HearthLine(); if l then add(l) end end)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip or type(data) ~= "table" or Secret(data.id) or data.id ~= HEARTHSTONE then return end
        local line = Q.HearthLine()
        if line then tooltip:AddLine(line, 0.5, 0.8, 1) end
    end)
end

-- 6. Webadressen aus dem Chat merken (nur lesen)
local links = {}
local CHAT = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_COMMUNITIES_CHANNEL" }
local CHAT_SET = {}
for _, e in ipairs(CHAT) do CHAT_SET[e] = true end
local function OnChat(text, sender)
    if not Opt("chatLinks") or Secret(text) or Secret(sender) then return end
    if type(text) ~= "string" or not (text:find("://", 1, true) or text:find("www.", 1, true) or text:find("discord.gg", 1, true)) then return end
    for _, url in ipairs(Q.FindURLs(text)) do
        Q.Remember(links, { url = url, who = Short(sender) or "?", t = time and time() or 0 })
    end
end
function Q.Links() return links end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "MERCHANT_SHOW", "MERCHANT_CLOSED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "GOSSIP_SHOW", "QUEST_GREETING", "PARTY_INVITE_REQUEST", "DUEL_REQUESTED", unpack(CHAT))
ev:SetScript("OnEvent", function(_, event, a1, a2, _, _, _, _, a7)
    if event == "MERCHANT_SHOW" then
        merchantOpen = true
        if On("sellJunk") then ns.Try(SellJunk) end
    elseif event == "MERCHANT_CLOSED" then merchantOpen = false
    elseif event == "QUEST_DETAIL" then ns.Try(QuestDetail)
    elseif event == "QUEST_PROGRESS" then ns.Try(QuestProgress)
    elseif event == "QUEST_COMPLETE" then ns.Try(QuestComplete)
    elseif event == "GOSSIP_SHOW" then ns.Try(Gossip)
    elseif event == "QUEST_GREETING" then ns.Try(Greeting)
    elseif event == "PARTY_INVITE_REQUEST" then ns.Try(Invite, a1, a7)
    elseif event == "DUEL_REQUESTED" then ns.Try(Duel, a1)
    elseif CHAT_SET[event] then ns.Try(OnChat, a1, a2)
    end
end)

---------------------------------------------------------------------
-- /gp qol: alle Schalter aus Einstellungen › Komfort in einem kleinen Fenster.
-- Die Liste kommt aus den Einstellungen selbst – neue Schalter erscheinen hier von allein.
---------------------------------------------------------------------
function Q.MenuOptions(list)
    local out, inside = {}, false
    for _, o in ipairs(type(list) == "table" and list or {}) do
        if o.header then inside = (o.header == L["Komfort"])
        elseif inside and o.key then out[#out + 1] = o end
    end
    return out
end

local menu
local ROW = 24
local function Checked(key)
    local v = GuildPrideDB[key]
    if v == nil then return ns.DEFAULTS and ns.DEFAULTS[key] == true or false end
    return v == true
end
local function BuildMenu()
    if menu then return menu end
    local opts = Q.MenuOptions(ns.SettingOptions)
    menu = CreateFrame("Frame", "GuildPrideQoLMenu", UIParent, "BackdropTemplate")
    menu:SetSize(540, 70 + #opts * ROW)
    menu:SetPoint("CENTER", 0, 60)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:SetMovable(true); menu:EnableMouse(true)
    menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", menu.StartMoving)
    menu:SetScript("OnDragStop", menu.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(menu) end
    if UISpecialFrames then table.insert(UISpecialFrames, "GuildPrideQoLMenu") end   -- Esc schließt
    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 16, -14); title:SetText(L["GuildPride – Komfort"])
    local close = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -6, -8)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() menu:Hide() end)
    menu.checks = {}
    for i, o in ipairs(opts) do
        local sub = type(o.label) == "string" and o.label:find("^…") ~= nil
        local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
        cb:SetSize(22, 22); cb:SetPoint("TOPLEFT", sub and 34 or 14, -38 - (i - 1) * ROW)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetWidth(sub and 470 or 490); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:SetText(o.label)
        cb:SetScript("OnClick", function(self)
            GuildPrideDB[o.key] = self:GetChecked() and true or false
            if o.changed then ns.Try(o.changed) end
        end)
        menu.checks[#menu.checks + 1] = { cb = cb, key = o.key }
    end
    local hint = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 12)
    hint:SetText(L["Dieselben Schalter stehen in den Einstellungen unter „Komfort“."])
    menu:SetScript("OnShow", function()
        for _, c in ipairs(menu.checks) do c.cb:SetChecked(Checked(c.key)) end
    end)
    menu:Hide()
    return menu
end

function Q.ToggleMenu(on)
    if type(GuildPrideDB) ~= "table" then return end
    BuildMenu()
    if on == nil then on = not menu:IsShown() end
    menu:SetShown(on)
end

local orig = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "qol" or cmd == "komfort" or cmd == "comfort" then
        Q.ToggleMenu()
    elseif cmd == "links" or cmd == "link" then
        if #links == 0 then ns.Print(L["Noch keine Webadressen im Chat gesehen."]); return end
        local lines = {}
        for _, e in ipairs(links) do lines[#lines + 1] = e.url .. "   (" .. e.who .. ")" end
        if ns.ShowCopy then ns.ShowCopy(L["Webadressen aus dem Chat – markieren und kopieren"], table.concat(lines, "\n"))
        else print(table.concat(lines, "\n")) end
    elseif orig then
        orig(arg)
    end
end
