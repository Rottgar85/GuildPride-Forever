-- Tests: Speicher aufräumen (Core/GuildPrideCleanup.lua)
return function(test, eq, W, ns)
    W.Load("GuildPrideCleanup.lua")
    local C = ns.Cleanup

    test("Rezepte packen: hin und zurück gleich, alte Form bleibt lesbar, Unsinn ergibt nichts", function()
        local text = C.PackRecipe({ made = 2, r = { { 2589, 3 }, { 2840, 1 } } })
        eq(type(text), "string")
        local made, r = C.Recipe(text)
        eq(made, 2); eq(#r, 2); eq(r[1][1], 2589); eq(r[1][2], 3); eq(r[2][1], 2840); eq(r[2][2], 1)
        made, r = C.Recipe({ made = 1, r = { { 5, 6 } } }); eq(made, 1); eq(r[1][2], 6)
        made, r = C.Recipe({ r = { { 5, 6 } } }); eq(made, 1); eq(r[1][1], 5)
        eq(C.Recipe(nil), nil); eq(C.Recipe(5), nil); eq(C.Recipe("kaputt"), nil); eq(C.Recipe({}), nil)
        eq(C.PackRecipe({ made = 1, r = {} }), nil); eq(C.PackRecipe(nil), nil)
        -- Dezimalmengen und fremde Werte: lieber die alte Form behalten als Daten verlieren
        eq(C.PackRecipe({ made = 1.5, r = { { 5, 6 } } }), nil); eq(C.PackRecipe({ made = 1, r = { { "x", 6 } } }), nil)
    end)

    test("Rezepte packen: Bestand wird einmal umgestellt, Auktionshaus und Materialliste rechnen gleich", function()
        local old = GuildPrideDB.ahCraft
        GuildPrideDB.ahCraft = { [41021] = { made = 1, r = { { 41020, 2 } } }, [41022] = { made = 1, r = { { "x", 2 } } }, [41023] = "1|41020:4" }
        eq(C.PackRecipes(), 1); eq(GuildPrideDB.ahCraft[41021], "1|41020:2")
        eq(type(GuildPrideDB.ahCraft[41022]), "table", "nicht packbar: bleibt")
        eq(C.PackRecipes(), 0)
        ns.AH.RecordOwn("41020", 40, 1, math.floor(W.server))
        eq(ns.AH.CraftInfo(41021).cost, 80); eq(ns.AH.CraftInfo(41023).cost, 160)
        local oldItem, oldBags, oldCont = C_Item, NUM_BAG_SLOTS, C_Container
        NUM_BAG_SLOTS, C_Container = 0, { GetContainerNumSlots = function() return 0 end }
        C_Item = { GetItemInfo = function(x) if tonumber(x) == 41020 then return "Prüfstoff", "|Hitem:41020::|h[x]|h" end end }
        eq(ns.Stock.Resolve("prüfstoff"), 41020)
        C_Item, NUM_BAG_SLOTS, C_Container = oldItem, oldBags, oldCont
        GuildPrideDB.ahCraft = old
    end)

    test("Chat-Zwischenspeicher: lange stille Kanäle fallen weg, höchstens 12 bleiben", function()
        local now = math.floor(W.server)
        local cache = {}
        for i = 1, 15 do cache["1:" .. i] = { { t = now - i * 60 } } end
        cache["alt:1"] = { { t = now - 61 * 86400 } }
        cache["leer:1"], cache["falsch:1"] = {}, "x"
        eq(C.TrimChat(cache, now), 6)
        local n = 0
        for _ in pairs(cache) do n = n + 1 end
        eq(n, 12); eq(cache["1:1"] ~= nil, true); eq(cache["1:13"], nil); eq(cache["alt:1"], nil)
        eq(C.TrimChat(nil, now), 0)
    end)

    test("Aufräumen: Daten entfernter Funktionen (Gold-Verlauf) fallen weg", function()
        local db = { goldHistory = { Ich = {} }, goldNow = { Ich = 5 }, goldLog = true, sound = true }
        eq(C.DropRemoved(db), 3)
        eq(db.goldHistory, nil); eq(db.goldNow, nil); eq(db.goldLog, nil); eq(db.sound, true, "Rest bleibt")
        eq(C.DropRemoved(db), 0)
    end)

    test("Aufräumen: Daten alter Gilden fallen nach 180 Tagen ohne Besuch weg", function()
        local now = math.floor(W.server)
        local guilds = { ["Jetzt@R"] = { log = {} }, ["Alt@R"] = { log = {} }, ["Neu gesehen@R"] = { log = {} } }
        local seen = { ["Alt@R"] = now - 181 * 86400, ["Weg@R"] = now - 5 }
        eq(C.TrimGuilds(guilds, seen, "Jetzt@R", now), 1)
        eq(guilds["Alt@R"], nil, "alte Gilde weg"); eq(seen["Alt@R"], nil)
        eq(guilds["Jetzt@R"] ~= nil, true, "aktuelle bleibt"); eq(seen["Jetzt@R"], now)
        eq(guilds["Neu gesehen@R"] ~= nil, true, "ohne Zeitstempel: Uhr startet erst")
        eq(seen["Neu gesehen@R"], now)
        eq(seen["Weg@R"], nil, "Zeitstempel ohne Gilde aufgeräumt")
        eq(C.TrimGuilds(guilds, seen, nil, now), 0, "ohne aktuelle Gilde (noch nicht geladen): nichts löschen")
    end)

    test("Sicherung: neu Lernbares bleibt draußen und überlebt das Zurückspielen", function()
        local oldDB, oldBackup, oldReload = GuildPrideDB, GuildPrideBackupDB, ReloadUI
        local ok, err = pcall(function()
            GuildPrideDB = { sound = true, ahCraft = { [1] = "1|2:3" }, clubCache = { a = {} }, craftVendor = { x = 1 } }
            GuildPrideBackupDB = { snaps = { { t = 1, data = { sound = false, ahCraft = { [9] = "1|2:3" }, craftAll = {} } } } }
            eq(C.TrimBackups(), 2); eq(GuildPrideBackupDB.snaps[1].data.ahCraft, nil); eq(GuildPrideBackupDB.snaps[1].data.sound, false)
            eq(C.TrimBackups(), 0)
            ns.BackupNow("Hand")
            local d = GuildPrideBackupDB.snaps[1].data
            eq(d.sound, true); eq(d.ahCraft, nil); eq(d.clubCache, nil); eq(d.craftVendor.x, 1)
            eq(GuildPrideDB.ahCraft[1], "1|2:3", "das Original bleibt")
            ReloadUI = function() end
            StaticPopupDialogs.GUILDPRIDE_RESTORE.OnAccept(nil, 2)
            eq(GuildPrideDB.sound, false, "alte Sicherung zurückgespielt")
            eq(GuildPrideDB.ahCraft[1], "1|2:3", "Gelerntes bleibt erhalten"); eq(GuildPrideDB.craftVendor, nil)
        end)
        GuildPrideDB, GuildPrideBackupDB, ReloadUI = oldDB, oldBackup, oldReload
        if not ok then error(err, 0) end
    end)
end
