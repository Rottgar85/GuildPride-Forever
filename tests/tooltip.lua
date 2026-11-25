-- Tests: gemeinsamer Block im Item-Tooltip (Core/GuildPrideTooltip.lua)
return function(test, eq, W, ns)
    local function tiptest(name, fn)
        test(name, function()
            local old = { GameTooltip, ItemRefTooltip, TooltipDataProcessor, Enum, issecretvalue, IsShiftKeyDown, InCombatLockdown, GuildPrideDB.tipDetails, ns.Tip, C_Container }
            local post
            local function Tip()
                local t = { lines = {}, scripts = {}, visible = true }
                t.AddLine = function(_, a) t.lines[#t.lines + 1] = a end
                t.AddDoubleLine = function(_, a, b) t.lines[#t.lines + 1] = a .. " || " .. b end
                t.Show, t.HasScript = function() end, function() return true end
                t.HookScript = function(_, n, f) t.scripts[n] = f end
                t.GetName, t.NumLines, t.IsShown = function() return nil end, function() return 0 end, function() return t.visible end
                t.GetItem = function() return "x", t.link end
                return t
            end
            GameTooltip, ItemRefTooltip = Tip(), Tip()
            TooltipDataProcessor = { AddTooltipPostCall = function(_, f) post = f end }
            Enum = { TooltipDataType = { Item = 0 } }
            IsShiftKeyDown, InCombatLockdown = function() return false end, function() return false end
            GuildPrideDB.tipDetails = nil
            W.Load("GuildPrideTooltip.lua")
            local ok, err = pcall(fn, ns.Tip, GameTooltip, function(...) post(...) end)
            GameTooltip, ItemRefTooltip, TooltipDataProcessor, Enum, issecretvalue, IsShiftKeyDown, InCombatLockdown, GuildPrideDB.tipDetails, ns.Tip, C_Container = unpack(old, 1, 10)
            if not ok then error(err, 0) end
        end)
    end

    tiptest("Tooltip-Block: eine Überschrift, feste Reihenfolge, Empfehlung rechts im Kopf", function(T, tip, post)
        T.Add(20, function() return { { "zweite" } } end)
        T.Add(10, function(ctx) ctx.head = "BEHALTEN"; return { { "erste", "rechts" } } end)
        T.Add(30, function() return nil end)
        tip.link = "|Hitem:2589::::|h[x]|h"
        post(tip, {})
        eq(#tip.lines, 4); eq(tip.lines[2]:find("GuildPride", 1, true) ~= nil and tip.lines[2]:find("BEHALTEN", 1, true) ~= nil, true)
        eq(tip.lines[3], "erste || rechts"); eq(tip.lines[4], "zweite")
        post(tip, {}); eq(#tip.lines, 4, "nicht doppelt")
        tip.scripts.OnTooltipCleared(tip); tip.lines = {}
        post(tip, {}); eq(#tip.lines, 4, "nach dem Leeren wieder")
    end)

    tiptest("Tooltip-Block: Einzelheiten nur mit Umschalt oder Schalter; Hinweis zählt sie", function(T, tip, post)
        T.Add(10, function() return { { "immer" }, { "mehr 1", more = true }, { "mehr 2", more = true } } end)
        local b = T.Build({ id = 1 }); eq(#b.lines, 1); eq(b.hidden, 2)
        b = T.Build({ id = 1, more = true }); eq(#b.lines, 3); eq(b.hidden, 0)
        tip.link = "item:1:"; post(tip, {})
        eq(tip.lines[#tip.lines]:find("2", 1, true) ~= nil, true, "Umschalt: 2 weitere Zeilen")
        tip.scripts.OnHide(tip); tip.lines = {}
        GuildPrideDB.tipDetails = true
        post(tip, {}); eq(tip.lines[#tip.lines], "mehr 2")
    end)

    tiptest("Tooltip-Block: ein Fehler in einem Teil stört die anderen nicht und wird gemeldet", function(T, tip, post)
        local before = #W.swallowed
        T.Add(10, function() error("kaputt", 0) end)
        T.Add(20, function() return { { "geht" } } end)
        tip.link = "item:1:"; post(tip, {})
        eq(tip.lines[3], "geht"); eq(#W.swallowed, before + 1)
        W.swallowed[#W.swallowed] = nil
    end)

    tiptest("Tooltip-Block: geschützte Links, Nicht-Items und leere Blöcke bleiben unberührt", function(T, tip, post)
        T.Add(10, function(ctx) return ctx.id == 1 and {} or { { "x" } } end)
        tip.link = "item:1:"; post(tip, {}); eq(#tip.lines, 0, "nichts zu sagen")
        tip.scripts.OnHide(tip)
        tip.link = "spell:5"; post(tip, {}); eq(#tip.lines, 0)
        local SECRET = "geheim"
        issecretvalue = function(v) return v == SECRET end
        tip.link = SECRET; post(tip, { hyperlink = "item:2:" }); eq(#tip.lines, 0)
        issecretvalue = nil
        tip.link = nil; post(tip, { hyperlink = "item:2:" }); eq(#tip.lines > 0, true, "Link aus den Tooltip-Daten")
        post({}, {})   -- fremder Tooltip
    end)

    tiptest("Tooltip-Block: Stapelgröße aus der Tasche, Umschalt baut neu auf, nie im Kampf", function(T, tip, post)
        local seen
        T.Add(10, function(ctx) seen = ctx; return { { "a" }, { "b", more = true } } end)
        C_Container = { GetContainerItemInfo = function(b, s) return b == 1 and s == 3 and { stackCount = 17 } or nil end }
        tip.processingInfo = { getterName = "GetBagItem", getterArgs = { 1, 3 } }
        tip.link = "item:2589:"; post(tip, {}); eq(seen.count, 17)
        local n = 0
        tip.RefreshData = function() n = n + 1 end
        W.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1); eq(n, 1)
        W.Fire("MODIFIER_STATE_CHANGED", "LCTRL", 1); eq(n, 1)
        InCombatLockdown = function() return true end
        W.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1); eq(n, 1)
        InCombatLockdown = function() return false end
        eq(T.Refresh(function(link) return link:find("2589", 1, true) ~= nil end), true); eq(n, 2)
        eq(T.Refresh(function() return false end), false)
        tip.visible = false; eq(T.Refresh(), false)
    end)
end
