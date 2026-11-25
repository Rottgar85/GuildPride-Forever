-- Tests: Item-ID im Item-Tooltip (Core/GuildPrideItemID.lua)
return function(test, eq, W, ns)
    W.Load("GuildPrideItemID.lua")

    test("Item-ID: aus Link lesen, nur mit Schalter im Tooltip", function()
        eq(ns.ItemIDFromLink("|cffffffff|Hitem:2589:0:0:0:0:0:0:0|h[Leinen]|h|r"), 2589)
        eq(ns.ItemIDFromLink(19019), 19019)
        eq(ns.ItemIDFromLink("kein Link"), nil)
        eq(ns.ItemIDFromLink(nil), nil)
        local old = GuildPrideDB.showItemID
        GuildPrideDB.showItemID = false
        eq(ns.ItemIDText("item:2589"), nil, "Schalter aus: keine Zeile")
        GuildPrideDB.showItemID = true
        eq(ns.ItemIDText("item:2589"):find("2589") ~= nil, true)
        GuildPrideDB.showItemID = old
    end)
end
