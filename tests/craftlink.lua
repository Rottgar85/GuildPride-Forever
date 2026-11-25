-- Tests: Öffnet das Spiel das Berufsfenster eines anderen? (Guild/GuildPrideCraftLink.lua)
return function(test, eq, W, ns)
    W.Load("GuildPrideCraftLink.lua")
    local X = ns.CraftLink
    local LINK, OTHER = "trade:Player-6947-00A4542C:3104:165", "trade:Player-6941-0000000B:3104:165"

    test("Berufsfenster: je Spieler gemerkt, ob das Spiel es öffnet; Ergebnis kommt genau einmal", function()
        local oldAfter, oldT, oldP, timers, linked = C_Timer.After, C_TradeSkillUI, rawget(_G, "ProfessionsFrame"), {}, false
        C_Timer.After = function(_, f) timers[#timers + 1] = f end
        C_TradeSkillUI, ProfessionsFrame = { IsTradeSkillLinked = function() return linked end }, false
        local function Run() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end
        local n, got = 0, nil
        local function Done(ok) n = n + 1; got = ok end
        local ok, err = pcall(function()
            eq(X.Watch("item:1", Done), false)
            X.Watch(LINK, Done); Run()
            eq(got, false); eq(n, 1); eq(X.IsBroken(LINK), true); eq(X.IsBroken(OTHER), false, "gilt nur für diesen Spieler")
            X.Watch(LINK, Done); W.Fire("TRADE_SKILL_SHOW"); timers[1](); timers = {}
            eq(got, true); eq(n, 2); eq(X.IsBroken(LINK), false, "geht wieder")
            -- eigenes Fenster war schon offen und zeigt jetzt den fremden Beruf
            X.Watch(LINK, Done); linked = true; Run(); eq(got, true)
            -- war schon das Fenster eines anderen offen, zählt das nicht als Antwort
            X.Watch(LINK, Done); Run(); eq(got, false)
        end)
        C_Timer.After, C_TradeSkillUI, ProfessionsFrame = oldAfter, oldT, oldP
        wipe(X.broken)
        if not ok then error(err, 0) end
    end)

    test("Berufe: das Fenster eines Gildenmitglieds zählt nie als eigenes", function()
        local oldT = C_TradeSkillUI
        local T = { GetAllRecipeIDs = function() return { 1 } end, GetRecipeInfo = function() return { learned = true } end,
            GetBaseProfessionInfo = function() return { professionName = "Fremdberuf" } end }
        C_TradeSkillUI = T
        local before = ns.Crafts.ReadOpenRecipes()
        T.IsTradeSkillGuildMember = function() return true end
        local after = ns.Crafts.ReadOpenRecipes()
        C_TradeSkillUI = oldT
        eq(before, "Fremdberuf"); eq(after, nil)
    end)
end
