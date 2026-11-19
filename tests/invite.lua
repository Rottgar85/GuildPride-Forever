-- Tests: Gildeneinladung auf WoW Forever per sicherem Klick (Guild/GuildPrideInvite.lua)
return function(test, eq, W, ns)
    -- Modul als Forever-Client laden; CreateFrame merkt sich benannte Frames und Attribute
    local named = {}
    local origCreate = CreateFrame
    CreateFrame = function(_, name)
        local f = origCreate()
        f.attr = {}
        function f:SetAttribute(k, v) self.attr[k] = v end
        if name then named[name] = f end
        return f
    end
    local wasForever = ns.IS_FOREVER
    ns.IS_FOREVER = true
    W.Load("GuildPrideInvite.lua")

    local printed = {}
    local origPrint = ns.Print
    ns.Print = function(text) printed[#printed + 1] = text end

    UIParent = { GetEffectiveScale = function() return 1 end }
    local guildClub = 7
    C_Club = { GetGuildClubId = function() return guildClub end }

    -- Blizzards Einladedialog: Blizzards Knopf zeigt ihn, der Spieler tippt den Namen
    local popupShown = false
    local function BlizzardFrame(selected)
        local invite = { IsEnabled = function() return true end }
        invite.Click = function() popupShown = true end
        return { InviteButton = invite, IsShown = function() return false end,
                 GetSelectedClubId = function() return selected end }
    end

    -- unser Einladen-Knopf
    local function OurButton()
        local b = origCreate()
        b.IsVisible = function() return true end
        b.IsEnabled = function() return true end
        b.IsMouseOver = function() return false end
        b.GetLeft = function() return 100 end
        b.GetBottom = function() return 50 end
        b.GetWidth = function() return 120 end
        b.GetHeight = function() return 24 end
        b.GetEffectiveScale = function() return 1 end
        return b
    end

    -- Ein Klick wie im Spiel: PreClick, Blizzards Knopf (sicherer Klick), PostClick
    local function Click(overlay)
        if overlay.scripts.PreClick then overlay.scripts.PreClick(overlay) end
        overlay.attr.clickbutton.Click()
        overlay.scripts.PostClick(overlay)
    end

    test("Einladen: ein Klick öffnet Blizzards Einladedialog", function()
        CommunitiesFrame = BlizzardFrame(guildClub)
        popupShown = false
        local done = false
        local b = OurButton()
        ns.AttachGuildInvite(b, nil, function() done = true end)
        b.scripts.OnEnter(b)
        local o = named.GuildPrideInviteOverlay
        eq(o.attr.type, "click")
        eq(o.attr.clickbutton, CommunitiesFrame.InviteButton, "klickt Blizzards Knopf")
        eq(o.attr.useOnKeyDown, false)
        Click(o)
        eq(popupShown, true)
        eq(done, true)
    end)

    test("Einladen: Gilde ohne Namensfeld, Community mit", function()
        local function Widget(point)
            -- einfache Tabelle: Test-Frames liefern für unbekannte Felder kein nil
            local w = { point = point, scripts = {} }
            function w:Show() self.shown = true end
            function w:Hide() self.shown = false end
            function w:SetShown(v) self.shown = v and true or false end
            function w:IsShown() return self.shown and true or false end
            function w:HookScript(k, fn) self.scripts[k] = fn end
            w.GetPoint = function(self) return unpack(self.point) end
            w.ClearAllPoints = function(self) self.point = nil end
            w.SetPoint = function(self, ...) self.point = { ... } end
            return w
        end
        local box = Widget({ "BOTTOMLEFT", 8, 6 })
        local btn = Widget({ "LEFT", box, "RIGHT", 8, 0 })
        box:Show(); btn:Show()
        ns.ArrangeInvite(box, btn, true)
        eq(box:IsShown(), false, "Gilde: kein Namensfeld")
        eq(btn.point[1], "BOTTOMLEFT"); eq(btn.point[2], 8)
        box.scripts.OnShow(box)   -- anderer Code zeigt das Feld wieder: bleibt weg
        eq(box:IsShown(), false)
        ns.ArrangeInvite(box, btn, false)
        eq(box:IsShown(), true, "Community: Namensfeld")
        eq(btn.point[1], "LEFT"); eq(btn.point[2], box)
    end)

    test("Blizzards Gildenfenster: parken statt schließen, zurückholen stellt es wieder her", function()
        local f = { alpha = 1, clamped = true, points = { { "TOPLEFT", "UIParent", "TOPLEFT", 16, -116 } }, hides = 0 }
        function f:GetAlpha() return self.alpha end
        function f:SetAlpha(a) self.alpha = a end
        function f:IsClampedToScreen() return self.clamped end
        function f:SetClampedToScreen(c) self.clamped = c end
        function f:GetNumPoints() return #self.points end
        function f:GetPoint(i) return unpack(self.points[i]) end
        function f:ClearAllPoints() self.points = {} end
        function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function f:Hide() self.hides = self.hides + 1 end
        f.scripts = {}
        function f:HookScript(k, fn) self.scripts[k] = fn end
        CommunitiesFrame = f
        ns.ParkBlizzardGuild()
        eq(ns.BlizzardGuildParked(), true)
        eq(f.alpha, 0, "unsichtbar")
        eq(f.points[1][4], -4000, "aus dem Bild")
        eq(f.hides, 0, "nie per Addon geschlossen")
        ns.ParkBlizzardGuild()   -- zweimal parken merkt sich nicht die Parkposition
        ns.UnparkBlizzardGuild()
        eq(ns.BlizzardGuildParked(), false)
        eq(f.alpha, 1)
        eq(f.clamped, true)
        eq(f.points[1][1], "TOPLEFT"); eq(f.points[1][4], 16); eq(f.points[1][5], -116)

        -- Einstellung „Blizzards Gildenfenster behalten“: geparktes Fenster kommt sofort zurück
        local oldDB = GuildPrideDB
        GuildPrideDB = { replaceGuildFrame = true }
        ns.ParkBlizzardGuild()
        ns.GuildWindowChoiceChanged()
        eq(ns.BlizzardGuildParked(), true, "GuildPride-Fenster an: bleibt geparkt")
        GuildPrideDB.replaceGuildFrame = false
        ns.GuildWindowChoiceChanged()
        eq(ns.BlizzardGuildParked(), false, "Blizzard-Fenster gewählt: wieder sichtbar")
        eq(f.alpha, 1)

        -- Erstes J nach dem Einloggen: Blizzard zeigt sein Fenster erst nach unserem Haken
        GuildPrideDB.replaceGuildFrame = true
        f.scripts.OnShow(f)
        eq(ns.BlizzardGuildParked(), true, "erscheint von selbst: sofort geparkt")
        eq(f.alpha, 0)
        -- „Blizzard-Gildenfenster öffnen“: bleibt sichtbar, bis es zugeht
        ns.UnparkBlizzardGuild()
        f.scripts.OnShow(f)
        eq(ns.BlizzardGuildParked(), false, "selbst gewählt: sichtbar")
        f.scripts.OnHide(f)
        f.scripts.OnShow(f)
        eq(ns.BlizzardGuildParked(), true, "nach dem Schließen wieder geparkt")
        ns.UnparkBlizzardGuild()
        -- Blizzard-Fenster als Einstellung: nie parken
        GuildPrideDB.replaceGuildFrame = false
        f.scripts.OnHide(f)
        f.scripts.OnShow(f)
        eq(ns.BlizzardGuildParked(), false)
        GuildPrideDB = oldDB
    end)

    test("Einladen: Community gewählt -> kein sicherer Knopf", function()
        CommunitiesFrame = BlizzardFrame(guildClub)
        local o = named.GuildPrideInviteOverlay
        o.attr.clickbutton = nil
        local b = OurButton()
        ns.AttachGuildInvite(b, function() return false end)
        b.scripts.OnEnter(b)
        eq(o.attr.clickbutton, nil)
    end)

    test("Einladen: Blizzard-Fenster zeigt nicht die Gilde -> erst vorbereiten, dann Dialog", function()
        CommunitiesFrame = BlizzardFrame(99)   -- eine Community ausgewählt
        local primedDuringClick
        GuildMicroButton = { Click = function()
            primedDuringClick = ns.InvitePriming()
            CommunitiesFrame = BlizzardFrame(guildClub)   -- Blizzard öffnet sein Fenster mit der Gilde
        end }
        popupShown = false
        for i = #printed, 1, -1 do printed[i] = nil end
        local b = OurButton()
        ns.AttachGuildInvite(b)
        b.scripts.OnEnter(b)
        local o = named.GuildPrideInviteOverlay
        eq(o.attr.clickbutton, GuildMicroButton, "erster Klick: Gildenknopf")
        Click(o)
        eq(primedDuringClick, true, "Hook öffnet unser Fenster nicht um")
        eq(ns.InvitePriming(), false)
        eq(printed[#printed], "Gildeneinladung ist bereit: bitte noch einmal klicken.")
        eq(popupShown, false)
        b.scripts.OnEnter(b)
        eq(o.attr.clickbutton, CommunitiesFrame.InviteButton, "zweiter Klick: Blizzards Dialog")
        Click(o)
        eq(popupShown, true)
        GuildMicroButton = nil
    end)

    test("Einladen: im Kampf kein sicherer Knopf, nur Hinweis", function()
        CommunitiesFrame = BlizzardFrame(guildClub)
        local o = named.GuildPrideInviteOverlay
        o.attr.clickbutton = nil
        local origCombat = InCombatLockdown
        InCombatLockdown = function() return true end
        local b = OurButton()
        ns.AttachGuildInvite(b)
        b.scripts.OnEnter(b)
        eq(o.attr.clickbutton, nil)
        ns.ShowInviteHint("Anna")
        eq(printed[#printed], "|cffff4040Gildeneinladung geht nicht im Kampf.|r")
        InCombatLockdown = origCombat
    end)

    -- aufräumen
    CommunitiesFrame, C_Club, UIParent = nil, nil, nil
    ns.Print, ns.IS_FOREVER, CreateFrame = origPrint, wasForever, origCreate
end
