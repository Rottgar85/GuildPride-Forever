-- GuildPride Auktionshaus: Verkaufshelfer
--   * Briefkasten: beim Öffnen eine Zeile „Im Briefkasten: 5 verkauft (34g nach Gebühr) · 2 abgelaufen“
--   * Verkaufs-Hinweis: Gegenstände, die gerade deutlich teurer sind als im Schnitt der letzten Tage
--     (Münze auf dem Taschenplatz, Zeile im Tooltip)
-- Liest nur Blizzards Briefkasten-Daten, nimmt nichts heraus und verändert keine Blizzard-Fenster.
local ADDON, GP = ...
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local SELL_FACTOR = 1.25   -- 25 % über dem Durchschnitt
local SELL_MIN_DAYS = 3    -- erst ab drei Tagen Verlauf

---------------------------------------------------------------------
-- Verkaufs-Hinweis
---------------------------------------------------------------------
-- Durchschnitt der Tagespreise oder nil (zu wenig Verlauf)
function AH.HistoryAverage(key)
    local h = key and AH.History(key) or {}
    if #h < SELL_MIN_DAYS then return nil end
    local sum = 0
    for _, x in ipairs(h) do sum = sum + x.p end
    return sum / #h
end

-- true, wenn der aktuelle Preis mindestens 25 % über dem Durchschnitt liegt
function AH.SellHint(link)
    if not link or not AH.Opt("ahSellHint") then return false end
    local key = AH.KeyFromLink(link)
    local p = key and AH.PriceFor(key)
    local avg = p and AH.HistoryAverage(key)
    if not avg or p < avg * SELL_FACTOR then return false end
    return AH.Tradeable(link) and true or false
end

-- Tooltip-Zeile zum Hinweis
function AH.TooltipSell(link)
    if not AH.SellHint(link) then return nil end
    local key = AH.KeyFromLink(link)
    local pct = math.floor((AH.PriceFor(key) / AH.HistoryAverage(key) - 1) * 100 + 0.5)
    return "|cff40ff40" .. (L["Guter Zeitpunkt zum Verkaufen: %d %% über dem Schnitt"]):format(pct) .. "|r"
end

---------------------------------------------------------------------
-- Briefkasten
---------------------------------------------------------------------
local function ToPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- Zählt Auktionsbriefe: { sold, money, expired, cancelled, won, outbid }
function AH.MailSummary()
    local s = { sold = 0, money = 0, expired = 0, cancelled = 0, won = 0, outbid = 0 }
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return s end
    local expired = ToPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
    local cancelled = ToPattern(AUCTION_REMOVED_MAIL_SUBJECT)
    local outbid = ToPattern(AUCTION_OUTBID_MAIL_SUBJECT)
    for i = 1, (GetInboxNumItems() or 0) do
        local _, _, _, subject, money = GetInboxHeaderInfo(i)
        local kind = GetInboxInvoiceInfo and (GetInboxInvoiceInfo(i))
        subject = type(subject) == "string" and subject or ""
        if kind == "seller" then
            s.sold = s.sold + 1
            s.money = s.money + (tonumber(money) or 0)
        elseif kind == "buyer" then
            s.won = s.won + 1
        elseif expired and subject:match(expired) then
            s.expired = s.expired + 1
        elseif cancelled and subject:match(cancelled) then
            s.cancelled = s.cancelled + 1
        elseif outbid and subject:match(outbid) then
            s.outbid = s.outbid + 1
        end
    end
    return s
end

-- Text für den Chat oder nil, wenn kein Auktionsbrief da ist
function AH.MailSummaryText(s)
    local parts = {}
    if s.sold > 0 then parts[#parts + 1] = (L["%d verkauft (%s nach Gebühr)"]):format(s.sold, AH.Money(s.money)) end
    if s.won > 0 then parts[#parts + 1] = (L["%d gekauft"]):format(s.won) end
    if s.expired > 0 then parts[#parts + 1] = (L["%d abgelaufen"]):format(s.expired) end
    if s.cancelled > 0 then parts[#parts + 1] = (L["%d abgebrochen"]):format(s.cancelled) end
    if s.outbid > 0 then parts[#parts + 1] = (L["%d überboten"]):format(s.outbid) end
    if #parts == 0 then return nil end
    return L["Im Briefkasten: "] .. table.concat(parts, " · ")
end

local mailOpen, mailShown = false, false
AH.Listen("MAIL_SHOW", function() mailOpen, mailShown = true, false end)
AH.Listen("MAIL_CLOSED", function() mailOpen = false end)
AH.Listen("MAIL_INBOX_UPDATE", function()
    if not mailOpen or mailShown or not AH.Opt("ahMailSummary") then return end
    mailShown = true
    local text = AH.MailSummaryText(AH.MailSummary())
    if text then AH.Print(text) end
end)
