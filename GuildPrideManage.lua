-- GuildPride: Mitglieder verwalten (Gilde und Communities)
--
-- Befördern, Degradieren, Entfernen und Gildenleitung sind seit Patch 7.3 für Addons
-- gesperrt. Wir nutzen deshalb sichere Knöpfe (SecureActionButtonTemplate), die beim
-- Klick die Blizzard-Befehle /gpromote, /gdemote, /gremove und /gleader ausführen –
-- genau wie ein Makro. Gildennotizen kann kein Addon ändern; dafür öffnen wir das
-- Blizzard-Gildenfenster. Communities (C_Club) lassen sich direkt verwalten.
local ADDON, ns = ...
local L = ns.L

local CMD = {
    promote = ns.SlashCmd("GUILD_PROMOTE", "/gpromote"),
    demote  = ns.SlashCmd("GUILD_DEMOTE", "/gdemote"),
    remove  = ns.SlashCmd("GUILD_UNINVITE", "/gremove"),
    leader  = ns.SlashCmd("GUILD_LEADER", "/gleader"),
}
local InviteToGroup = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
local AddAltMenu

---------------------------------------------------------------------
-- Rechte
---------------------------------------------------------------------
local function MyRankIndex()
    local _, _, r = GetGuildInfo("player")
    return r or 99
end

local function NumRanks()
    return GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
end

local function RankName(rankIndex)
    return GuildControlGetRankName and GuildControlGetRankName(rankIndex + 1) or tostring(rankIndex)
end

local function CanViewOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then return C_GuildInfo.CanViewOfficerNote() end
    return CanViewOfficerNote and CanViewOfficerNote()
end

local function CanEditNotes()
    local pub = (C_GuildInfo and C_GuildInfo.CanEditPublicNote and C_GuildInfo.CanEditPublicNote())
        or (CanEditPublicNote and CanEditPublicNote())
    local off = (C_GuildInfo and C_GuildInfo.CanEditOfficerNote and C_GuildInfo.CanEditOfficerNote())
        or (CanEditOfficerNote and CanEditOfficerNote())
    return pub or off
end

local function Can(fn) return fn and fn() and true or false end

local function Has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- Gildenmitglied frisch aus der Gildenliste lesen
local function GuildMember(full)
    for i = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, _, zone, note, officerNote, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and ns.FullName(name) == full then
            return { name = Ambiguate(name, "guild"), full = full, rank = rank, rankIndex = rankIndex, level = level,
                     zone = zone, note = note, officerNote = officerNote, online = isOnline, class = classFile,
                     guild = true, inGuild = true, isSelf = full == ns.Me(), guid = select(17, GetGuildRosterInfo(i)) }
        end
    end
end

---------------------------------------------------------------------
-- Detailfenster für Gildenmitglieder
---------------------------------------------------------------------
local page = ns.MembersPage
local panel = CreateFrame("Frame", "GuildPrideMemberPanel", page, "BackdropTemplate")
panel:SetSize(300, 410)
panel:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -30)
panel:SetFrameLevel(page:GetFrameLevel() + 20)
panel:EnableMouse(true)
panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
panel:SetBackdropColor(0.07, 0.05, 0.04, 0.97)
ns.Paint(panel, "accent")
panel:Hide()

local closeBtn = CreateFrame("Button", nil, panel)
closeBtn:SetSize(22, 22); closeBtn:SetPoint("TOPRIGHT", -8, -8)
closeBtn:SetNormalTexture(ns.MEDIA .. "close"); closeBtn:SetHighlightTexture(ns.MEDIA .. "close_hover")
closeBtn:SetScript("OnClick", function() panel:Hide() end)

local function Text(font, y, width)
    local fs = panel:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetWidth(width or 268); fs:SetJustifyH("LEFT")
    return fs
end

local nameText = Text("GPFont_Large", -14, 240)
local infoText = Text("GPFont_TextSmall", -38)
local statusText = Text("GPFont_TextSmall", -56)
-- Mitglied seit … (GuildPrideHistory.lua); Maus darüber: ganzer Verlauf
local historyText = Text("GPFont_MutedSmall", -69)
local historyHover = CreateFrame("Frame", nil, panel)
historyHover:SetAllPoints(historyText)
historyHover:EnableMouse(true)
local noteLabel = Text("GPFont_TextBold", -82); noteLabel:SetText(L["Öffentliche Notiz"])
local noteText = Text("GPFont_TextSmall", -100); noteText:SetHeight(28); noteText:SetJustifyV("TOP")
local offLabel = Text("GPFont_TextBold", -132); offLabel:SetText(L["Offiziersnotiz"])
local offText = Text("GPFont_TextSmall", -150); offText:SetHeight(28); offText:SetJustifyV("TOP")
local manageLabel = Text("GPFont_TextBold", -222); manageLabel:SetText(L["Verwaltung"])

local function Button(w, label, x, y, secure)
    if not secure then
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(w, 24); b:SetPoint("TOPLEFT", x, y); b:SetText(label)
        return b
    end
    local b = ns.SecureMacroButton(panel, w, label)
    b:SetPoint("TOPLEFT", x, y)
    return b
end

-- Falls WoW eine Aktion trotzdem blockiert: klar melden statt still nichts zu tun
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
local blockedAt = {}
blocked:SetScript("OnEvent", function(_, _, addon, func)
    if addon ~= ADDON then return end
    func = tostring(func)
    -- Dieselbe Sperre höchstens einmal pro Minute melden
    local now = GetTime()
    if blockedAt[func] and now - blockedAt[func] < 60 then return end
    blockedAt[func] = now
    -- UNKNOWN(): WoW nennt keine Funktion. Das Event kommt noch während des
    -- Aufrufs, der Stapel zeigt also die auslösende Zeile unseres Codes.
    local file, line = debugstack(2):match("(GuildPride%w*%.lua)[^:]*:(%d+)")
    local shown = file and ("%s, %s:%s"):format(func, file, line) or func
    local text = func == "UNKNOWN()" and L["|cffff4040WoW hat eine Aktion blockiert (%s).|r"]
        or L["|cffff4040WoW hat die Aktion blockiert (%s). Bitte im Blizzard-Gildenfenster ausführen.|r"]
    ns.Print(text:format(shown))
end)

local bNotes   = Button(180, L["Notizen bearbeiten"], 16, -186)
local bTpl     = Button(84, L["Vorlage"], 200, -186)
local bRank    = Button(170, L["Rang wählen  ▾"], 16, -242)
local bSetRank = Button(94, L["Rang setzen"], 190, -242, true)
local bKick    = Button(268, L["Aus der Gilde entfernen …"], 16, -272)
local bKickYes = Button(268, L["|cffff4040Wirklich entfernen|r"], 16, -272, true)
local bLead    = Button(268, L["Gildenleitung übergeben …"], 16, -302)
local bLeadYes = Button(268, L["|cffff4040Wirklich Gildenleitung übergeben|r"], 16, -302, true)
local bTell    = Button(132, L["Anflüstern"], 16, -342)
local bGroup   = Button(132, L["In Gruppe einladen"], 152, -342)
local hint = Text("GPFont_MutedSmall", -376)
hint:SetText(L["Rangänderungen und Entfernen laufen über die Blizzard-Befehle /gpromote, /gdemote und /gremove."])

local current, targetRank

local function SetMacro(b, text)
    if InCombatLockdown() then return end
    b:SetAttribute("macrotext", text)
end

-- Bestätigungsknöpfe kurz nach dem Klick wieder einklappen
-- (verzögert, damit die Aktion beim Loslassen der Maustaste noch läuft)
for _, pair in ipairs({ { bKick, bKickYes }, { bLead, bLeadYes } }) do
    local ask, yes = pair[1], pair[2]
    yes:Hide()
    -- nach dem Kampf erneut fragen statt die alte Bestätigung zu zeigen
    yes.gpAfterCombat = function(_, wasShown) yes:Hide(); if wasShown then ask:Show() end end
    ask:SetScript("OnClick", function() if not InCombatLockdown() then ask:Hide(); yes:Show() end end)
    yes:HookScript("OnClick", function()
        C_Timer.After(0.3, function() if not InCombatLockdown() then yes:Hide(); ask:Show() end end)
    end)
end

-- voller Name mit Server, sonst bewirken /gpromote und /gdemote in Retail nichts (wie Guild Roster Manager)
local function Steps(m, target)
    local n, lines = m.full, {}
    local diff = target - m.rankIndex
    local cmd = diff > 0 and CMD.demote or CMD.promote
    for _ = 1, math.abs(diff) do lines[#lines + 1] = cmd .. " " .. n end
    return table.concat(lines, "\n")
end

local function UpdateRankButton()
    local m = current
    if not m then return end
    bRank:SetText((targetRank and RankName(targetRank) or L["Rang wählen"]) .. "  ▾")
    local ok = targetRank ~= nil and targetRank ~= m.rankIndex
    bSetRank:SetEnabled(ok)
    SetMacro(bSetRank, ok and Steps(m, targetRank) or "")
end

bRank:SetScript("OnClick", function(self)
    local m = current
    if not (m and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local my = MyRankIndex()
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(L["Neuer Rang"])
        for r = my + 1, NumRanks() - 1 do
            local up = r < m.rankIndex
            local allowed = r == m.rankIndex or (up and Can(CanGuildPromote)) or (not up and Can(CanGuildDemote))
            if allowed then
                local label = RankName(r) .. (r == m.rankIndex and (" |cff999999(" .. L["aktuell"] .. ")|r") or "")
                root:CreateRadio(label, function() return targetRank == r end, function()
                    targetRank = r
                    UpdateRankButton()
                end)
            end
        end
    end)
end)

bNotes:SetScript("OnClick", function()
    ns.OpenBlizzardGuild()
    ns.Print(L["Gildennotizen können Addons nicht ändern. Bearbeite sie im Blizzard-Gildenfenster (Rechtsklick auf das Mitglied)."])
end)
-- Gildennotizen kann kein Addon setzen: Vorlage markiert zum Kopieren anzeigen
-- und das Blizzard-Fenster öffnen, dort mit Strg+V einfügen
StaticPopupDialogs["GUILDPRIDE_NOTE_TEMPLATE"] = {
    text = L["Vorlage mit Strg+C kopieren und im Blizzard-Fenster als Notiz einfügen:"],
    button1 = OKAY,
    hasEditBox = true, editBoxWidth = 320,
    OnShow = function(self, t)
        local eb = self.editBox or self.EditBox
        eb:SetText(t or ""); eb:SetFocus(); eb:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function NoTemplates()
    ns.Print(L["Noch keine Notiz-Vorlagen. Lege sie unter Einstellungen an."])
end

bTpl:SetScript("OnClick", function(self)
    local list = ns.NoteTemplates and ns.NoteTemplates() or {}
    if #list == 0 then NoTemplates(); return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(L["Notiz-Vorlage"])
        for _, t in ipairs(list) do
            root:CreateButton(t, function()
                ns.OpenBlizzardGuild()
                StaticPopup_Show("GUILDPRIDE_NOTE_TEMPLATE", nil, nil, t)
            end)
        end
    end)
end)

bTell:SetScript("OnClick", function() if current then ChatFrame_SendTell(current.full) end end)
bGroup:SetScript("OnClick", function() if current and InviteToGroup then InviteToGroup(current.full) end end)

local function Fill(m)
    current = m
    targetRank = nil
    local c = RAID_CLASS_COLORS[m.class] or NORMAL_FONT_COLOR
    nameText:SetText(("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, m.name))
    local info = ("Lvl %d · %s"):format(m.level or 0, m.rank or "")
    -- Zeit im Rang (für die Beförderung nach Zeit)
    local since = ns.RankSince and m.full and ns.RankSince(m.full)
    if since then info = info .. (L["  ·  seit %d Tagen im Rang"]):format(math.floor((GetServerTime() - since) / 86400)) end
    infoText:SetText(info)
    historyText:SetText((ns.HistoryLine and ns.HistoryLine(m.full)) or L["|cff888888Beitritt noch unbekannt|r"])
    historyHover:SetScript("OnEnter", function(self)
        if not ns.HistoryTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        ns.HistoryTooltip(GameTooltip, m.full)
        GameTooltip:Show()
    end)
    historyHover:SetScript("OnLeave", GameTooltip_Hide)
    statusText:SetText(m.online and ("|cff40ff40●|r " .. (m.zone or "")) or ("|cff777777" .. (m.last or L["offline"]) .. "|r"))
    noteText:SetText((m.note and m.note ~= "") and m.note or L["|cff888888Keine Notiz.|r"])
    local canOff = CanViewOfficerNote()
    offLabel:SetShown(canOff); offText:SetShown(canOff)
    offText:SetText((m.officerNote and m.officerNote ~= "") and m.officerNote or L["|cff888888Keine Notiz.|r"])
    bNotes:SetShown(CanEditNotes() and true or false)
    bTpl:SetShown(CanEditNotes() and true or false)
    bTell:SetEnabled(m.online and not m.isSelf)
    bGroup:SetEnabled(m.online and not m.isSelf)

    local my, last = MyRankIndex(), NumRanks() - 1
    local below = not m.isSelf and m.rankIndex > my          -- Ziel steht unter mir
    local canPromote = below and Can(CanGuildPromote) and m.rankIndex - 1 > my
    local canDemote = below and Can(CanGuildDemote) and m.rankIndex < last
    local canKick = below and Can(CanGuildRemove)
    local canLead = not m.isSelf and Can(IsGuildLeader)
    local any = canPromote or canDemote or canKick or canLead

    manageLabel:SetShown(any); hint:SetShown(any)
    bRank:SetShown(any); bSetRank:SetShown(any)
    bRank:SetEnabled((canPromote or canDemote) and true or false)
    bKick:SetShown(canKick and true or false); bKickYes:Hide()
    bLead:SetShown(canLead and true or false); bLeadYes:Hide()

    local n = Ambiguate(m.full, "none")
    SetMacro(bKickYes, CMD.remove .. " " .. n)
    SetMacro(bLeadYes, CMD.leader .. " " .. n)
    UpdateRankButton()
end

function ns.HideMemberPanel()
    if not InCombatLockdown() then panel:Hide() end
end

---------------------------------------------------------------------
-- Community: Notiz, Rolle, Entfernen
---------------------------------------------------------------------
StaticPopupDialogs["GUILDPRIDE_CLUB_NOTE"] = {
    text = L["Notiz für %s:"],
    button1 = L["Speichern"], button2 = L["Abbrechen"],
    hasEditBox = true, maxLetters = 120, editBoxWidth = 320,
    OnShow = function(self, m)
        local eb = self.editBox or self.EditBox
        eb:SetText(m and m.note or ""); eb:HighlightText()
    end,
    OnAccept = function(self, m)
        local eb = self.editBox or self.EditBox
        local ok = pcall(C_Club.SetClubMemberNote, m.clubId, m.memberId, strtrim(eb:GetText()))
        if not ok then ns.Print(L["|cffff4040Notiz konnte nicht gespeichert werden.|r"]) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        StaticPopupDialogs["GUILDPRIDE_CLUB_NOTE"].OnAccept(p, p.data); p:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["GUILDPRIDE_CLUB_KICK"] = {
    text = L["%s wirklich aus „%s“ entfernen?"],
    button1 = YES, button2 = NO,
    OnAccept = function(_, m)
        local ok = pcall(C_Club.KickMember, m.clubId, m.memberId)
        if not ok then ns.Print(L["|cffff4040Mitglied konnte nicht entfernt werden.|r"]) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function ClubPrivileges(clubId)
    return C_Club.GetClubPrivileges and C_Club.GetClubPrivileges(clubId) or {}
end

local function AddClubManagement(root, m)
    local priv = ClubPrivileges(m.clubId)
    local roles = (not m.isSelf and C_Club.GetAssignableRoles) and C_Club.GetAssignableRoles(m.clubId, m.memberId) or {}
    local canNote = (m.isSelf and priv.canSetOwnMemberNote) or (not m.isSelf and priv.canSetOtherMemberNote)
    local canKick = not m.isSelf and Has(priv.kickableRoleIds, m.role)
    if #roles == 0 and not canNote and not canKick then return end

    root:CreateDivider()
    root:CreateTitle(L["Verwaltung"])
    if #roles > 0 and C_Club.AssignMemberRole then
        local sub = root:CreateButton(L["Rolle ändern"])
        for _, role in ipairs(roles) do
            sub:CreateRadio(ns.CLUB_ROLES[role] or tostring(role), function() return m.role == role end, function()
                local ok = pcall(C_Club.AssignMemberRole, m.clubId, m.memberId, role)
                if not ok then ns.Print(L["|cffff4040Rolle konnte nicht geändert werden.|r"]) end
            end)
        end
    end
    if canNote and C_Club.SetClubMemberNote then
        root:CreateButton(L["Notiz bearbeiten"], function()
            StaticPopup_Show("GUILDPRIDE_CLUB_NOTE", m.name, nil, m)
        end)
        -- Community-Notizen lassen sich direkt setzen
        local list = ns.NoteTemplates and ns.NoteTemplates() or {}
        if #list > 0 then
            local sub = root:CreateButton(L["Notiz-Vorlage"])
            for _, t in ipairs(list) do
                sub:CreateButton(t, function()
                    local ok = pcall(C_Club.SetClubMemberNote, m.clubId, m.memberId, t)
                    if not ok then ns.Print(L["|cffff4040Notiz konnte nicht gespeichert werden.|r"]) end
                end)
            end
        end
    end
    if canKick and C_Club.KickMember then
        root:CreateButton(L["|cffff4040Aus der Community entfernen|r"], function()
            StaticPopup_Show("GUILDPRIDE_CLUB_KICK", m.name, m.club and m.club.name or "", m)
        end)
    end
end

---------------------------------------------------------------------
-- Rechtsklick-Menü (Gilde und Community)
---------------------------------------------------------------------
---------------------------------------------------------------------
-- Twinks (GuildPrideAusweis.lua): eigenen Main festlegen; Gildenleitung und
-- Offiziere ordnen Twinks von Hand zu (für Spieler ohne GuildPride)
---------------------------------------------------------------------
StaticPopupDialogs["GUILDPRIDE_ALT_OF"] = {
    text = L["%s ist ein Twink von … (Name des Mains)"],
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true,
    OnShow = function(self) local eb = self.editBox or self.EditBox; eb:SetText(""); eb:SetFocus() end,
    OnAccept = function(self, twink)
        local typed = strtrim((self.editBox or self.EditBox):GetText() or "")
        if typed == "" then return end
        -- eingegebenen Namen in der Gildenliste suchen (ohne Groß/klein)
        local main
        for i = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(i)
            if name and (Ambiguate(name, "none"):lower() == typed:lower() or ns.FullName(name):lower() == typed:lower()) then
                main = ns.FullName(name)
                break
            end
        end
        if not main then ns.Print((L["%s ist nicht in der Gilde."]):format(typed)) return end
        if ns.SetAltManual(twink, main) then
            ns.Print((L["%s ist jetzt Twink von %s."]):format(Ambiguate(twink, "guild"), Ambiguate(main, "guild")))
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        StaticPopupDialogs["GUILDPRIDE_ALT_OF"].OnAccept(p, p.data); p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

AddAltMenu = function(root, m)
    if not (m.full and ns.MainOf) then return end
    local mine = ns.Ausweis and ns.IsMyChar and ns.IsMyChar(m.full)
    if mine and ns.MainOf(m.full) ~= m.full then
        root:CreateButton(L["Als Main festlegen"], function() ns.SetMyMain(m.full) end)
    end
    if ns.CanSetAlts and ns.CanSetAlts() and not m.isSelf then
        root:CreateButton(L["Twink von … festlegen"], function()
            StaticPopup_Show("GUILDPRIDE_ALT_OF", Ambiguate(m.full, "guild"), nil, m.full)
        end)
        if ns.IsManualAlt(m.full) then
            root:CreateButton(L["Twink-Zuordnung lösen"], function() ns.ClearAltManual(m.full) end)
        end
    end
end

function ns.MemberMenu(owner, m)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        if m.full and m.online and not m.isSelf then ChatFrame_SendTell(m.full) end
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(m.name)
        if m.full and m.online and not m.isSelf then
            root:CreateButton(L["Anflüstern"], function() ChatFrame_SendTell(m.full) end)
            if InviteToGroup then root:CreateButton(L["In Gruppe einladen"], function() InviteToGroup(m.full) end) end
        end
        if m.full and not m.isSelf and C_FriendList and C_FriendList.AddFriend then
            root:CreateButton(L["Als Freund hinzufügen"], function() C_FriendList.AddFriend(m.full) end)
        end
        if m.full and not m.inGuild and IsInGuild() and (not CanGuildInvite or CanGuildInvite()) then
            root:CreateButton(L["In Gilde einladen"], function() ns.InviteToGuild(m.full) end)
        end
        if m.full and not m.isSelf then
            local clubs = {}
            for _, club in ipairs(ns.Communities()) do
                if not club.bnet and club.id ~= m.clubId and ns.CanInviteToClub(club.id) then clubs[#clubs + 1] = club end
            end
            if #clubs > 0 then
                local sub = root:CreateButton(L["In Community einladen"])
                for _, club in ipairs(clubs) do
                    sub:CreateButton(club.name, function() ns.InviteToClub(club, m.full) end)
                end
            end
        end
        if m.full then
            root:CreateButton(L["Namen in den Chat einfügen"], function()
                if ChatFrame_OpenChat then ChatFrame_OpenChat(Ambiguate(m.full, "none")) end
            end)
        end
        if m.guild then
            root:CreateDivider()
            AddAltMenu(root, m)
            root:CreateButton(L["Details und Verwaltung …"], function() ns.ShowMemberPanel(m) end)
        elseif m.clubId then
            AddClubManagement(root, m)
        end
    end)
end

---------------------------------------------------------------------
-- Rechtsklick auf Spieler in Blizzards Menüs (Ziel, Fokus, Gruppe, Chatname,
-- Freunde, Communities): „In Gilde einladen“, nur mit Einladerecht
---------------------------------------------------------------------
local function Plain(v) return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v)) end

local function FullName(name, realm)
    if not Plain(name) then return nil end
    if name:find("-", 1, true) or not Plain(realm) then return name end
    return name .. "-" .. (realm:gsub("[%s%-]", ""))
end

-- Wen das Menü meint, als Name(-Realm); nil, wenn kein Eintrag passt
local function MenuInviteName(ctx)
    if not (ctx and IsInGuild()) then return nil end
    if CanGuildInvite and not CanGuildInvite() then return nil end
    local name
    if Plain(ctx.unit) and UnitExists(ctx.unit) then
        local unit = ctx.unit
        if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return nil end
        if UnitIsInMyGuild and UnitIsInMyGuild(unit) then return nil end
        local theirs = UnitFactionGroup(unit)
        if Plain(theirs) and theirs ~= UnitFactionGroup("player") then return nil end
        -- Forever: UnitFullName liefert den Nachnamen, UnitName nicht verlässlich
        if ns.IS_FOREVER and UnitFullName then name = FullName(UnitFullName(unit))
        else name = FullName(UnitName(unit)) end
    elseif ctx.bnetIDAccount and C_BattleNet and C_BattleNet.GetAccountInfoByID then
        -- Battle.net-Freund: nur, wenn er gerade in derselben Spielversion spielt
        local info = C_BattleNet.GetAccountInfoByID(ctx.bnetIDAccount)
        local game = info and info.gameAccountInfo
        if not (game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW
                and game.wowProjectID == WOW_PROJECT_ID) then return nil end
        name = FullName(game.characterName, game.realmName)
    else
        name = FullName(ctx.chatTarget) or FullName(ctx.name, ctx.server)
    end
    if not name or ns.IsGuildMember(name) then return nil end
    -- Forever: „Reon-Strobek“ oder „Reon Strobek-Realm“ -> „Reon Strobek“
    return ns.IS_FOREVER and ns.Normalize(name) or name
end

local MENU_WHICH = { "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "TARGET", "FOCUS", "FRIEND", "BN_FRIEND",
                     "CHAT_ROSTER", "WORLD_STATE_SCORE", "COMMUNITIES_MEMBER", "COMMUNITIES_WOW_MEMBER" }

if Menu and Menu.ModifyMenu then
    -- Neues Menüsystem: Retail und die aktuellen Classic-Clients
    local function AddGuildInvite(_, root, ctx)
        local ok, name = pcall(MenuInviteName, ctx)
        if not (ok and name) then return end
        root:CreateDivider()
        root:CreateTitle("GuildPride")
        root:CreateButton(L["In Gilde einladen"], function() ns.InviteToGuild(name) end)
    end
    for _, which in ipairs(MENU_WHICH) do
        Menu.ModifyMenu("MENU_UNIT_" .. which, AddGuildInvite)
    end
elseif UnitPopup_ShowMenu and UIDropDownMenu_AddButton then
    -- Altes Aufklappmenü (Clients ohne neues Menüsystem): unten anhängen
    local wanted = {}
    for _, which in ipairs(MENU_WHICH) do wanted[which] = true end
    hooksecurefunc("UnitPopup_ShowMenu", function(dropdown, which, unit, name)
        if UIDROPDOWNMENU_MENU_LEVEL ~= 1 or not wanted[which] then return end
        dropdown = dropdown or {}
        local ok, target = pcall(MenuInviteName, { unit = unit or dropdown.unit, name = name or dropdown.name,
            server = dropdown.server, chatTarget = dropdown.chatTarget, bnetIDAccount = dropdown.bnetIDAccount })
        if not (ok and target) then return end
        if UIDropDownMenu_AddSeparator then UIDropDownMenu_AddSeparator(1) end
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.isTitle, info.notCheckable = "GuildPride", true, true
        UIDropDownMenu_AddButton(info, 1)
        info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = L["In Gilde einladen"], true
        info.func = function() ns.InviteToGuild(target) end
        UIDropDownMenu_AddButton(info, 1)
    end)
end

-- Linksklick: Gildenmitglied -> Detailfenster, Community-Mitglied -> Menü
function ns.ShowMemberPanel(m, owner)
    if InCombatLockdown() then return end
    if not m.guild then
        if owner then ns.MemberMenu(owner, m) end
        return
    end
    local fresh = GuildMember(m.full)
    if fresh then fresh.last = m.last end
    Fill(fresh or m)
    panel:Show()
end

---------------------------------------------------------------------
-- Aktuell halten
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("GUILD_RANKS_UPDATE")
ev:SetScript("OnEvent", function()
    if not panel:IsShown() or not current or InCombatLockdown() then return end
    local fresh = GuildMember(current.full)
    if fresh then
        local keep = targetRank
        fresh.last = current.last
        Fill(fresh)
        if keep and keep ~= fresh.rankIndex then targetRank = keep; UpdateRankButton() end
    else
        panel:Hide()   -- nicht mehr in der Gilde
    end
end)

page:HookScript("OnHide", function() if not InCombatLockdown() then panel:Hide() end end)
