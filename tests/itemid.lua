-- Tests: Item-ID im Item-Tooltip (Core/GuildPrideItemID.lua)
return function(test, eq, W, ns)
    W.Load("GuildPrideItemID.lua")

    test("Item-ID: aus Link lesen, nur mit Schalter im Tooltip", function()
        eq(ns.ItemIDFromLink("|cffffffff|Hitem:2589:0:0:0:0:0:0:0|h[Leinen]|h|r"), 2589)
        eq(ns.ItemIDFromLink(19019), 19019)
        eq(ns.ItemIDFromLink("kein Link"), nil)
        eq(ns.ItemIDFromLink(nil), nil)
        local old = GuildPrideDB.showItemID
        local lines, shown = {}, 0
        local tt = { AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() shown = shown + 1 end }
        GuildPrideDB.showItemID = false
        ns._ItemIDAdd(tt, "item:2589")
        eq(#lines, 0, "Schalter aus: keine Zeile")
        GuildPrideDB.showItemID = true
        ns._ItemIDAdd(tt, "item:2589")
        ns._ItemIDAdd(tt, "item:2589")   -- zweiter Aufruf für denselben Tooltip: nicht doppelt
        eq(#lines, 1); eq(lines[1]:find("2589") ~= nil, true)
        ns._ItemIDClear(tt)
        ns._ItemIDAdd(tt, "item:4306")
        eq(#lines, 2, "nach dem Leeren wieder eine Zeile")
        GuildPrideDB.showItemID = old
    end)
end
