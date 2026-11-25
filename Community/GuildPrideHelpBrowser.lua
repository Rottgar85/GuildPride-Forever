-- GuildPride: Gruppensuche – Teil Dungeonbrowser (nur Forever): „Browser durchsuchen“ und
-- der Dungeon-Filter. Die Seite selbst baut GuildPrideHelp.lua; von dort kommen über
-- ns.GroupFinder die Seite, die Browser-Angaben, der Filter und die Höhe der Listenleiste.
local ADDON, ns = ...
local L = ns.L
local GF = ns.GroupFinder
if not GF then return end
local page, BROWSER, DungeonFilter, LIST_BAR_Y = GF.page, GF.BROWSER, GF.DungeonFilter, GF.LIST_BAR_Y

-- Suche im Dungeonbrowser: Forever sperrt C_LFGList.Search für Addons („Aktion blockiert“).
-- Der Knopf klickt deshalb sicher Blizzards „Erneut suchen“ im Dungeonbrowser; das sucht
-- in der Kategorie, die dort gewählt ist. Ohne Kategorie sucht Blizzard gar nicht.
if BROWSER then
    local asked = false
    local function BlizzardSearchButton()
        local f = LFGBrowseFrame
        local cat = f and f.CategoryDropdown and f.CategoryDropdown.GetValue and f.CategoryDropdown:GetValue()
        if type(cat) == "number" and cat > 0 then return f.RefreshButton end
    end
    local bSearch = ns.SecureClickButton(page, 150, L["Browser durchsuchen"], nil)
    bSearch:SetPoint("TOPRIGHT", -116, LIST_BAR_Y)
    bSearch:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Browser durchsuchen"], 1, 1, 1)
        GameTooltip:AddLine(L["Holt Gruppen aus Blizzards Dungeonbrowser in diese Liste. Du erkennst sie an der Markierung [Dungeonbrowser]."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bSearch:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Dungeon-Auswahl: welche Dungeons aus dem Dungeonbrowser in der Liste stehen (einer oder mehrere)
    local DUNGEON_CATEGORY = 2   -- „Dungeons“ in Forevers Dungeonbrowser
    local bDungeons = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    bDungeons:SetSize(96, 24)
    bDungeons:SetPoint("RIGHT", bSearch, "LEFT", -4, 0)
    local pickWin
    local PICK_ROWS = 14
    local function DungeonList()
        local G, seen, out = C_LFGList, {}, {}
        local ok, ids = pcall(G.GetAvailableActivities, DUNGEON_CATEGORY)
        for _, id in ipairs(ok and ids or {}) do
            local a = G.GetActivityInfoTable(id)
            local n = a and a.fullName
            if n and not seen[n] then
                seen[n] = true
                out[#out + 1] = { name = n, lvl = tonumber(a.minLevel) or 0 }
            end
        end
        table.sort(out, function(x, y) if x.lvl ~= y.lvl then return x.lvl < y.lvl end return x.name < y.name end)
        return out
    end
    local function UpdateDungeonButton()
        local n = 0
        for _ in pairs(DungeonFilter() or {}) do n = n + 1 end
        bDungeons:SetText(n > 0 and (L["Filter (%d)"]):format(n) or L["Filter"])
    end
    UpdateDungeonButton()
    bDungeons:SetScript("OnShow", UpdateDungeonButton)   -- gespeicherte Auswahl erst nach dem Laden bekannt
    local function RefreshPick()
        if not pickWin then return end
        local list, sel = pickWin.list, GuildPrideDB.lfgDungeons or {}
        pickWin.offset = math.max(0, math.min(pickWin.offset or 0, #list - PICK_ROWS))
        for i = 1, PICK_ROWS do
            local r, d = pickWin.rows[i], list[i + pickWin.offset]
            r:SetShown(d ~= nil)
            if d then
                r.dungeon = d.name
                r.check:SetChecked(sel[d.name] == true)
                r.label:SetText(d.name .. (d.lvl > 0 and (" |cff999999(%d+)|r"):format(d.lvl) or ""))
            end
        end
        pickWin.none:SetShown(#list == 0)
        UpdateDungeonButton()
    end
    local function Toggle(name, on)
        GuildPrideDB.lfgDungeons = GuildPrideDB.lfgDungeons or {}
        GuildPrideDB.lfgDungeons[name] = on or nil
        RefreshPick()
        page:Refresh()
    end
    local function OpenPick()
        if not pickWin then
            pickWin = CreateFrame("Frame", "GuildPrideLFGDungeons", UIParent, "BackdropTemplate")
            pickWin:SetSize(300, 110 + PICK_ROWS * 22)   -- Platz für den Alarm-Haken unten
            pickWin:SetPoint("CENTER", 0, 40)
            pickWin:SetFrameStrata("DIALOG")
            pickWin:SetMovable(true); pickWin:EnableMouse(true); pickWin:SetClampedToScreen(true)
            pickWin:RegisterForDrag("LeftButton")
            pickWin:SetScript("OnDragStart", pickWin.StartMoving)
            pickWin:SetScript("OnDragStop", pickWin.StopMovingOrSizing)
            if ns.SkinDialog then ns.SkinDialog(pickWin) end
            tinsert(UISpecialFrames, "GuildPrideLFGDungeons")   -- Escape schließt
            local close = CreateFrame("Button", nil, pickWin, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", -6, -6)
            if ns.SkinClose then ns.SkinClose(close) end
            close:SetScript("OnClick", function() pickWin:Hide() end)
            local title = pickWin:CreateFontString(nil, "OVERLAY", "GPFont_Large")
            title:SetPoint("TOPLEFT", 14, -12); title:SetText(L["Dungeons auswählen"])
            if ns.Paint then ns.Paint(title, "heading") end
            local sub = pickWin:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
            sub:SetPoint("TOPLEFT", 14, -34); sub:SetPoint("RIGHT", -14, 0); sub:SetJustifyH("LEFT")
            sub:SetText(L["Nichts angehakt = alle Dungeons."])
            pickWin.rows = {}
            for i = 1, PICK_ROWS do
                local r = CreateFrame("Button", nil, pickWin)
                r:SetSize(272, 22)
                r:SetPoint("TOPLEFT", 12, -50 - (i - 1) * 22)
                if ns.Paint and i % 2 == 0 then ns.Paint(r:CreateTexture(nil, "BACKGROUND"), "glow", 0.05):SetAllPoints() end
                local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
                if ns.Paint then ns.Paint(hl, "glow", 0.15) else hl:SetColorTexture(1, 1, 1, 0.1) end
                r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
                r.check:SetSize(20, 20); r.check:SetPoint("LEFT", 0, 0)
                r.check:SetScript("OnClick", function(cb) Toggle(r.dungeon, cb:GetChecked()) end)
                r.label = r:CreateFontString(nil, "OVERLAY", "GPFont_Text")
                r.label:SetPoint("LEFT", 24, 0); r.label:SetPoint("RIGHT", -2, 0)
                r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
                r:SetScript("OnClick", function() Toggle(r.dungeon, not r.check:GetChecked()) end)
                pickWin.rows[i] = r
            end
            pickWin.none = pickWin:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
            pickWin.none:SetPoint("TOPLEFT", 14, -56); pickWin.none:SetPoint("RIGHT", -14, 0)
            pickWin.none:SetJustifyH("LEFT"); pickWin.none:SetText(L["Keine Dungeons gefunden."])
            pickWin:EnableMouseWheel(true)
            pickWin:SetScript("OnMouseWheel", function(_, delta)
                pickWin.offset = (pickWin.offset or 0) - delta * 3
                RefreshPick()
            end)
            -- Ton und Chatzeile bei neuen passenden Gruppen (Standard an)
            local alarm = CreateFrame("CheckButton", nil, pickWin, "UICheckButtonTemplate")
            alarm:SetSize(22, 22); alarm:SetPoint("BOTTOMLEFT", 12, 38)
            alarm:SetChecked(not (GuildPrideDB and GuildPrideDB.lfgAlert == false))
            alarm:SetScript("OnClick", function(cb) GuildPrideDB.lfgAlert = cb:GetChecked() and true or false end)
            local alarmLabel = pickWin:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
            alarmLabel:SetPoint("LEFT", alarm, "RIGHT", 2, 0)
            alarmLabel:SetText(L["Ton bei neuen passenden Gruppen"])
            local all = CreateFrame("Button", nil, pickWin, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(all) end
            all:SetSize(130, 22); all:SetPoint("BOTTOMLEFT", 14, 12)
            all:SetText(L["Alle Dungeons"])
            all:SetScript("OnClick", function()
                GuildPrideDB.lfgDungeons = nil
                RefreshPick(); page:Refresh()
            end)
            local done = CreateFrame("Button", nil, pickWin, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(done) end
            done:SetSize(100, 22); done:SetPoint("BOTTOMRIGHT", -14, 12)
            done:SetText(OKAY or "OK")
            done:SetScript("OnClick", function() pickWin:Hide() end)
        end
        pickWin.list = DungeonList()
        pickWin.offset = 0
        pickWin:Show()
        RefreshPick()
    end
    bDungeons:SetScript("OnClick", function()
        if pickWin and pickWin:IsShown() then pickWin:Hide() else OpenPick() end
    end)
    bDungeons:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Dungeons auswählen"], 1, 1, 1)
        GameTooltip:AddLine(L["Nur Gruppen für diese Dungeons zeigen (Dungeonbrowser und GuildPride). Einträge ohne Dungeon bleiben. Einen oder mehrere anhaken."], 0.8, 0.8, 0.8, true)
        local f = DungeonFilter()
        if f then
            local names = {}
            for n in pairs(f) do names[#names + 1] = n end
            table.sort(names)
            GameTooltip:AddLine(table.concat(names, ", "), 0.4, 0.8, 1, true)
        end
        GameTooltip:Show()
    end)
    bDungeons:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Vor dem sicheren Klick das Ziel setzen (außerhalb des Kampfs erlaubt).
    -- Ohne Kategorie (Forever wählt nie selbst eine, und ein Addon darf sie nicht setzen, sonst
    -- sperrt Blizzard die Suche): Blizzards Dungeonbrowser per sicherem /click öffnen.
    -- Dort einmal „Dungeons“ wählen, danach sucht der Knopf direkt.
    bSearch:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        local target = BlizzardSearchButton()
        if target then
            self:SetAttribute("type", "click")
            self:SetAttribute("clickbutton", target)
            asked = true
            return
        end
        -- Nur den Dungeonbrowser öffnen: Ein /click auf LFGParentFrameTab2 bricht in Forever in
        -- Blizzards Code ab (LFGParentFrame_SetActiveTab fehlt), darum keinen Reiter wechseln.
        local open = LFGParentFrame and LFGParentFrame:IsShown()
        local text = (not open and LFDMicroButton and LFDMicroButton:IsEnabled()) and "/click LFDMicroButton" or ""
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", text)
        ns.Print(L["Wähle im Dungeonbrowser oben eine Kategorie (z. B. Dungeons). Bis zum Ausloggen sucht dieser Knopf danach direkt, und die Gruppen erscheinen hier."])
    end)

    local pending = false
    local function RefreshSoon()
        if pending then return end
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            if page:IsShown() then page:Refresh() end
        end)
    end
    -- Alarm: Ist im Dungeon-Filter etwas gewählt, melden neue passende Gruppen aus dem Dungeonbrowser
    -- sich mit Ton und Chatzeile (GuildPrideDB.lfgAlert, Standard an). Die erste Suche mit einer
    -- Auswahl merkt sich nur, was schon da ist – sonst käme bei jeder neuen Auswahl eine Flut.
    local alerted, primedFor = {}, nil
    local function FilterKey(f)
        local names = {}
        for n in pairs(f) do names[#names + 1] = n end
        table.sort(names)
        return table.concat(names, "|")
    end
    local function CheckAlerts()
        local f = DungeonFilter()
        if not f or not GF.BrowserEntry or (GuildPrideDB and GuildPrideDB.lfgAlert == false) then return end
        local key = FilterKey(f)
        local silent = primedFor ~= key
        primedFor = key
        local _, ids = (C_LFGList.GetFilteredSearchResults or C_LFGList.GetSearchResults)()
        local now, shown = GetServerTime(), 0
        for _, id in ipairs(ids or {}) do
            local ok, name, e = pcall(GF.BrowserEntry, id, now)
            if ok and name and name ~= ns.Me() and not alerted[name] and ns.BrowserDungeonMatch(e.acts, f) then
                alerted[name] = true
                if not silent and shown < 3 then
                    shown = shown + 1
                    ns.Print((L["Neue Gruppe für %s: %s (%d/%d)"]):format(e.note or "?", Ambiguate(name, "none"), e.size or 1, e.max or 5))
                end
            end
        end
        if shown > 0 and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING) end
    end
    GF.CheckAlerts = CheckAlerts

    local watch = CreateFrame("Frame")
    watch:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    watch:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    watch:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    watch:SetScript("OnEvent", function(_, event)
        if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then ns.Try(CheckAlerts) end
        if event ~= "LFG_LIST_SEARCH_RESULT_UPDATED" then
            if asked then
                asked = false
                if event == "LFG_LIST_SEARCH_FAILED" then
                    ns.Print(L["Die Suche im Dungeonbrowser ist fehlgeschlagen."])
                elseif (C_LFGList.GetFilteredSearchResults or C_LFGList.GetSearchResults)() == 0 then
                    ns.Print(L["Im Dungeonbrowser wurde gerade nichts gefunden."])
                end
            end
        end
        RefreshSoon()
    end)
end
