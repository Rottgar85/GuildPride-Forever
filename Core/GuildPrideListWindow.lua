-- GuildPride: kleines Listenfenster im GuildPride-Design (Titel, Untertitel, Zeilen mit Mausrad).
-- Genutzt von Gildenbank-Verlauf und „Wer braucht noch …“.
--   local win = ns.ListWindow({ name = "GuildPrideX", title = "…", sub = "…", rows = 12, width = 480 })
--   win:SetLines({ "Zeile 1", "Zeile 2" })   -- Mausrad blättert
--   win.bottomY: y-Position unter den Zeilen für eigene Knöpfe
local ADDON, ns = ...
local L = ns.L

function ns.ListWindow(o)
    local rows, width = o.rows or 12, o.width or 480
    local top = o.top or -54
    local win = CreateFrame("Frame", o.name, UIParent, "BackdropTemplate")
    win:SetSize(width, -top + 20 + rows * 20 + (o.extra or 40))
    win:SetPoint("CENTER", 0, 60)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(win) end
    if o.name then tinsert(UISpecialFrames, o.name) end
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() win:Hide() end)
    win.title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    win.title:SetPoint("TOPLEFT", 14, -12); win.title:SetText(o.title or "")
    if ns.Paint then ns.Paint(win.title, "heading") end
    win.sub = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.sub:SetPoint("TOPLEFT", 14, -34); win.sub:SetPoint("RIGHT", -14, 0); win.sub:SetJustifyH("LEFT")
    win.sub:SetText(o.sub or "")

    win.rows = {}
    for i = 1, rows do
        local r = CreateFrame("Frame", nil, win)
        r:SetSize(width - 28, 18)
        r:SetPoint("TOPLEFT", 14, top - (i - 1) * 20)
        if ns.Paint and i % 2 == 0 then ns.Paint(r:CreateTexture(nil, "BACKGROUND"), "glow", 0.05):SetAllPoints() end
        r.text = r:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
        r.text:SetPoint("LEFT", 4, 0); r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        win.rows[i] = r
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
    win.empty:SetPoint("TOPLEFT", 18, top - 4); win.empty:SetPoint("RIGHT", -18, 0); win.empty:SetJustifyH("LEFT")
    win.empty:SetText(o.empty or L["Noch keine Einträge."])
    win.bottomY = top - rows * 20 - 8

    win.lines, win.offset = {}, 0
    function win:Paint()
        self.offset = math.max(0, math.min(self.offset, #self.lines - rows))
        for i = 1, rows do
            local line = self.lines[i + self.offset]
            self.rows[i]:SetShown(line ~= nil)
            if line then self.rows[i].text:SetText(line) end
        end
        self.empty:SetShown(#self.lines == 0)
    end
    function win:SetLines(lines)
        self.lines = lines or {}
        self:Paint()
    end
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta * 3
        self:Paint()
    end)
    win:Hide()
    return win
end
