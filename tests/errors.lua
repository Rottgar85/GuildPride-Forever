-- Tests: Fehlerbericht (Core/GuildPrideErrors.lua) – nur eigene Fehler, nach einem Update leer.
-- Die Aufrufstapel sind echte aus dem Spiel (der Fehlerbehandler steht immer selbst obenauf).
local HANDLER = "[Interface/AddOns/GuildPrideForever/Core/GuildPrideErrors.lua]:56: in function <...e/AddOns/GuildPrideForever/Core/GuildPrideErrors.lua:55>\n"

return function(test, eq, W, ns)
    test("Fehlerbericht: abgefangene eigene Fehler gehen weiter, stehen aber im Bericht", function()
        local oldTry, oldErrors, oldPrint = ns.Try, GuildPrideDB.errors, ns.Print
        local oldSet, oldGet, oldShare = seterrorhandler, geterrorhandler, ns.ErrorShare
        GuildPrideDB.errors = {}
        ns.Print, ns.ErrorShare = function() end, nil
        local oldStack = rawget(_G, "debugstack")
        debugstack = function() return "" end
        seterrorhandler, geterrorhandler = function() end, function() return function() end end
        W.Load("GuildPrideErrors.lua"); W.Fire("ADDON_LOADED", "GuildPrideForever")
        local ok, err = pcall(function()
            local a, b, c = ns.Try(function(x, y) return x + y, nil, "z" end, 2, 3)
            eq(a, true); eq(b, 5); eq(c, nil)
            local okT = ns.Try(function() error("GuildPrideForever/Guild/GuildPrideX.lua:7: kaputt", 0) end)
            eq(okT, false); eq(#GuildPrideDB.errors, 1); eq(GuildPrideDB.errors[1].msg:find("kaputt", 1, true) ~= nil, true)
            for _ = 1, 5 do ns.Try(function() error("GuildPrideForever/Guild/GuildPrideX.lua:7: kaputt", 0) end) end
            eq(#GuildPrideDB.errors, 1); eq(GuildPrideDB.errors[1].n, 6, "gleicher Fehler nur gezählt")
        end)
        ns.Try, GuildPrideDB.errors, ns.Print = oldTry, oldErrors, oldPrint
        debugstack = oldStack
        seterrorhandler, geterrorhandler, ns.ErrorShare = oldSet, oldGet, oldShare
        if not ok then error(err, 0) end
    end)

    local handler, forwarded, stack
    -- Spielstart nachstellen: Datei laden, Fehler vor ADDON_LOADED, gespeicherte Fehler
    local function Start(saved, early)
        handler, forwarded, stack = nil, 0, ""
        GuildPrideDB.errors = saved
        seterrorhandler = function(fn) handler = fn end
        local oldGet = geterrorhandler
        geterrorhandler = function() return function() forwarded = forwarded + 1 end end
        debugstack = function() return stack end
        local first = #W.frames + 1
        W.Load("GuildPrideErrors.lua")
        geterrorhandler = oldGet
        if early then early() end
        for i = first, #W.frames do
            local f = W.frames[i]
            if f.events.ADDON_LOADED then f.scripts.OnEvent(f, "ADDON_LOADED", "GuildPrideForever") end
        end
    end
    local function Raise(msg, frames) stack = HANDLER .. frames; handler(msg) end
    local function errtest(name, fn)
        test(name, function()
            local oldVersion, oldPrint, oldErrors = ns.VERSION, ns.Print, GuildPrideDB.errors
            ns.VERSION, ns.Print = "9.9.9", function() end
            local ok, err = pcall(fn)
            ns.VERSION, ns.Print, GuildPrideDB.errors = oldVersion, oldPrint, oldErrors
            seterrorhandler, debugstack = nil, nil
            if not ok then error(err, 0) end
        end)
    end

    errtest("Fehlerbericht: Fehler anderer Addons zählen nicht, laufen aber weiter", function()
        Start()
        Raise("Interface/AddOns/ManaSigil/Sandbox.lua:38: attempt to perform arithmetic on local 'l'",
            "[C]: ?\n[Interface/AddOns/ManaSigil/Sandbox.lua]:38: in function <Interface/AddOns/ManaSigil/Sandbox.lua:34>\n"
            .. "[tail call]: ?\n[Interface/AddOns/ManaSigil/Core.lua]:304: in function <Interface/AddOns/ManaSigil/Core.lua:302>\n")
        eq(#GuildPrideDB.errors, 0); eq(forwarded, 1, "vorheriger Fehlerbehandler")
    end)

    errtest("Fehlerbericht: fremder Fehler, den GuildPride nur ausgelöst hat, zählt nicht", function()
        Start()
        Raise("...s/ManaSigil/Display.lua:635: bad argument",
            "[C]: ?\n[Interface/AddOns/ManaSigil/Display.lua]:635: in function 'Refresh'\n"
            .. "[C]: in function 'Show'\n[Interface/AddOns/GuildPrideForever/Core/GuildPrideUI.lua]:2537: in function 'ToggleUI'\n")
        eq(#GuildPrideDB.errors, 0)
    end)

    errtest("Fehlerbericht: Blizzard-Fehler ohne GuildPride und /run zählen nicht", function()
        Start()
        Raise("...zard_GroupFinder_VanillaStyle/Mainline/Templates.lua:17: attempt to call a nil value",
            "[C]: in function 'LFGParentFrame_SetActiveTab'\n"
            .. "[Interface/AddOns/Blizzard_GroupFinder_VanillaStyle/Mainline/Templates.lua]:17: in function <...>\n")
        Raise("[string \"for _,n in ipairs({\"GuildMicroButton\"...\"]:1: unfinished string near '<eof>'",
            "[C]: ?\n[C]: in function 'RunScript'\n[Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua]:1235: in function '?'\n")
        eq(#GuildPrideDB.errors, 0)
    end)

    errtest("Fehlerbericht: fremde Meldung, die nur das Wort GuildPride enthält, zählt nicht", function()
        Start()
        Raise("Interface/AddOns/ManaSigil/Core.lua:5: cannot anchor to GuildPrideWindow",
            "[C]: ?\n[Interface/AddOns/ManaSigil/Core.lua]:5: in main chunk\n")
        eq(#GuildPrideDB.errors, 0)
    end)

    errtest("Fehlerbericht: eigene Fehler werden gespeichert, ohne den Fehlerbehandler im Stapel", function()
        Start()
        Raise("...ddOns/GuildPrideForever/Community/GuildPrideHelp.lua:1251: attempt to index global 'GuildPrideDB' (a nil value)",
            "[C]: ?\n[Interface/AddOns/GuildPrideForever/Community/GuildPrideHelp.lua]:1251: in function <...>\n")
        local e = GuildPrideDB.errors[1]
        eq(#GuildPrideDB.errors, 1); eq(e.v, "9.9.9", "Version")
        eq(e.stack:find("GuildPrideErrors", 1, true), nil)
        eq(e.stack:find("GuildPrideHelp.lua]:1251", 1, true) ~= nil, true)
    end)

    errtest("Fehlerbericht: eigener Fehler ohne Dateiname in der Meldung", function()
        Start()
        Raise("Frame:RegisterEvent(): Attempt to register unknown event \"NEW_AUCTION_UPDATE\"",
            "[C]: ?\n[C]: in function 'RegisterEvent'\n[Interface/AddOns/GuildPrideForever/AuctionHouse/GuildPrideAHData.lua]:190: in function 'Listen'\n")
        eq(#GuildPrideDB.errors, 1)
    end)

    errtest("Fehlerbericht: Blizzard-Funktion mit falschem Aufruf aus GuildPride zählt", function()
        Start()
        Raise("...ce/AddOns/Blizzard_UIParent/Shared/UIParent.lua:12: bad argument #1",
            "[C]: ?\n[Interface/AddOns/Blizzard_UIParent/Shared/UIParent.lua]:12: in function 'ShowUIPanel'\n"
            .. "[Interface/AddOns/GuildPrideForever/Core/GuildPrideUI.lua]:2537: in function 'ToggleUI'\n")
        eq(#GuildPrideDB.errors, 1)
    end)

    errtest("Fehlerbericht: eigener Fehler über die Fehlerweiterleitung eines anderen Addons", function()
        Start()
        Raise("...ddOns/GuildPrideForever/Guild/GuildPrideRaid.lua:80: attempt to call a nil value",
            "[Interface/AddOns/AndererFehlerSammler/Core.lua]:9: in function <...>\n[C]: ?\n"
            .. "[Interface/AddOns/GuildPrideForever/Guild/GuildPrideRaid.lua]:80: in function <...>\n")
        eq(#GuildPrideDB.errors, 1)
    end)

    errtest("Fehlerbericht: derselbe lange Fehler steht nur einmal mit Zähler", function()
        Start()
        local msg = "...ddOns/GuildPrideForever/Guild/GuildPrideRaid.lua:80: " .. ("x"):rep(600)
        for _ = 1, 3 do Raise(msg, "[C]: ?\n[Interface/AddOns/GuildPrideForever/Guild/GuildPrideRaid.lua]:80: in main chunk\n") end
        eq(#GuildPrideDB.errors, 1); eq(GuildPrideDB.errors[1].n, 3)
    end)

    errtest("Fehlerbericht: nach einem Update sind alte Fehler weg", function()
        Start({ { msg = "gleiche Version", n = 1, v = "9.9.9" }, { msg = "alt", n = 1, v = "9.9.8" }, { msg = "uralt ohne Version", n = 4394 } })
        eq(#GuildPrideDB.errors, 1); eq(GuildPrideDB.errors[1].msg, "gleiche Version")
    end)

    errtest("Fehlerbericht: kurze Pfade (BugGrabber) und Blizzards FrameXML", function()
        Start()
        -- BugGrabber lässt „Interface/AddOns/“ weg
        Raise("ManaSigil/Core.lua:5: fremd", "[ManaSigil/Core.lua]:5: in main chunk\n[GuildPrideForever/Core/GuildPrideUI.lua]:1: in main chunk\n")
        eq(#GuildPrideDB.errors, 0)
        Raise("bad argument #1", "[FrameXML/UIParent.lua]:12: in function 'ShowUIPanel'\n[GuildPrideForever/Core/GuildPrideUI.lua]:2537: in function 'ToggleUI'\n")
        Raise("bad argument #2", "[string \"@Interface/AddOns/GuildPrideForever/Core/GuildPrideUI.lua\"]:7: in main chunk\n")
        eq(#GuildPrideDB.errors, 2)
    end)

    errtest("Fehlerbericht: mit BugGrabber werden dessen Fehler übernommen, nur eigene und nur diese Sitzung", function()
        Start()
        local list = {
            { message = "GuildPrideForever/Core/GuildPrideUI.lua:1: alt", stack = "", session = 6, counter = 9 },
            { message = "ManaSigil/Core.lua:5: fremd", stack = "[ManaSigil/Core.lua]:5: in main chunk", session = 7, counter = 3 },
            { message = "GuildPrideForever/Core/GuildPrideUI.lua:2: neu", session = 7, counter = 2,
              stack = "[GuildPrideForever/Core/GuildPrideUI.lua]:2: in main chunk" },
        }
        BugGrabber = { GetDB = function() return list end, GetSessionId = function() return 7 end }
        ns.PollBugGrabber()
        local e = GuildPrideDB.errors
        eq(#e, 1); eq(e[1].msg:find(": neu", 1, true) ~= nil, true); eq(e[1].n, 2, "Zähler von BugGrabber")
        ns.PollBugGrabber()
        eq(e[1].n, 2, "nichts Neues")
        list[3].counter = 5
        ns.PollBugGrabber()
        eq(#e, 1); eq(e[1].n, 5, "nur der Zuwachs")
        BugGrabber = nil
        ns.PollBugGrabber()   -- ohne BugGrabber: nichts
    end)

    errtest("Fehlerbericht: Testfehler landet im Bericht, jeder einzeln", function()
        Start()
        local old, thrown = C_Timer.After, {}
        C_Timer.After = function(_, fn) thrown[#thrown + 1] = fn end
        local called = pcall(function() ns.ThrowTestError(); W.Advance(1); ns.ThrowTestError() end)
        C_Timer.After = old
        eq(called, true); eq(#thrown, 2)
        for _, fn in ipairs(thrown) do
            local ok, err = pcall(fn)
            eq(ok, false, "wirft einen echten Fehler")
            local text = tostring(err):gsub("^.-:%d+: ", "")
            Raise("Interface/AddOns/GuildPrideForever/Core/GuildPrideErrors.lua:99: " .. text,
                "[C]: in function 'error'\n[Interface/AddOns/GuildPrideForever/Core/GuildPrideErrors.lua]:99: in function <...>\n")
        end
        eq(#GuildPrideDB.errors, 2); eq(GuildPrideDB.errors[1].msg:find("Testfehler", 1, true) ~= nil, true)
    end)

    errtest("Fehlerbericht: Umstände ohne Namen (Kampf, Instanz, offene Fenster)", function()
        local oldC, oldI, oldF, oldW = InCombatLockdown, IsInInstance, UISpecialFrames, GuildPrideTestWin
        InCombatLockdown = function() return true end
        IsInInstance = function() return true, "party" end
        GuildPrideTestWin = { IsShown = function() return true end }
        GuildPrideZuWin = { IsShown = function() return false end }
        UISpecialFrames = { "GuildPrideTestWin", "GuildPrideZuWin", "FremdesFenster" }
        Start()
        Raise("...ddOns/GuildPrideForever/Guild/GuildPrideRaid.lua:80: x", "[C]: ?\n")
        InCombatLockdown, IsInInstance, UISpecialFrames, GuildPrideTestWin, GuildPrideZuWin = oldC, oldI, oldF, oldW, nil
        eq(GuildPrideDB.errors[1].ctx, "combat=yes inst=party win=GuildPrideTestWin")
    end)

    errtest("Fehlerbericht: Hinweis im Chat passt zur Entscheidung", function()
        local said = {}
        local function Run(share)
            said = {}
            GuildPrideDB.errorShare = share
            Start()
            ns.Print = function(t) said[#said + 1] = t end
            Raise("...ddOns/GuildPrideForever/Guild/GuildPrideRaid.lua:80: x", "[C]: ?\n")
            GuildPrideDB.errorShare = nil
        end
        Run(false); eq(#said, 1); eq(said[1]:find("/gp fehler", 1, true) ~= nil, true)
        Run(true); eq(#said, 1); eq(said[1]:find("/gp fehler", 1, true), nil); eq(said[1]:find("automatisch", 1, true) ~= nil, true)
    end)

    errtest("Fehlerbericht: Fehler beim Laden bleiben erhalten", function()
        ns.VERSION = nil
        Start({ { msg = "alt", n = 1, v = "9.9.8" } }, function()
            Raise("...ddOns/GuildPrideForever/Core/GuildPrideTheme.lua:3: frueh",
                "[C]: ?\n[Interface/AddOns/GuildPrideForever/Core/GuildPrideTheme.lua]:3: in main chunk\n")
            ns.VERSION = "9.9.9"
        end)
        eq(#GuildPrideDB.errors, 1); eq(GuildPrideDB.errors[1].msg:find("frueh", 1, true) ~= nil, true)
        eq(GuildPrideDB.errors[1].v, "9.9.9", "bekommt die Version nachgetragen")
    end)
end
