local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local L = ns.L
local St = ns.Style

local GREEN, RED, GREY, ORANGE = St.GREEN, St.RED, St.GREY, St.ORANGE
local TAG = St.Icon(St.LOGO, 14) .. " " .. St.TITLE

local function fmt(n) return BreakUpLargeNumbers(math.floor(n + 0.5)) end

-- Several hooks can fire for the same tooltip; this keeps the Scales lines to one set per display.
-- Every new item clears the tooltip first (OnTooltipCleared), which resets the flag.
local done = setmetatable({}, { __mode = "k" })

local function Render(tooltip, link)
  -- Same verdict as the bag arrows and the preview, so they never disagree.
  local verdict, r = ns.Compare.Verdict(link)
  if not r then return end
  local others = (not r.unusable) and ns.Compare.OtherSpecs(link) or {}
  tooltip:AddLine(" ")
  -- With other specs listed, the main line names the active spec so the lines can be told apart.
  if #others > 0 then
    for _, s in ipairs(ns.Specs.List()) do
      if s.active then tooltip:AddLine(TAG .. "  " .. St.Icon(s.icon, 14) .. " |cffffd100" .. s.name .. "|r") end
    end
  end
  if r.unusable then
    tooltip:AddDoubleLine(TAG, RED .. L.UNUSABLE_ARMOR .. "|r")
  elseif r.same then
    tooltip:AddDoubleLine(TAG, GREY .. L.EQUIPPED .. "|r")
  elseif r.empty and verdict == "up" then
    tooltip:AddDoubleLine(TAG, GREEN .. St.Icon(St.ARROW_UP, 12) .. " " .. L.EMPTY_SLOT .. "|r")
  else
    local color = verdict == "up" and GREEN or (verdict == "down" and RED or GREY)
    local word = verdict == "up" and (St.Icon(St.ARROW_UP, 12) .. " " .. L.UPGRADE)
      or verdict == "down" and (St.Icon(St.ARROW_DOWN, 12) .. " " .. L.DOWNGRADE) or L.SIDEGRADE
    tooltip:AddDoubleLine(TAG .. "  " .. color .. word .. "|r", string.format("%s%+.1f%%|r %s", color, r.pct, L.VS_EQUIPPED))
    if r.newValue then
      tooltip:AddDoubleLine("   " .. r.simLabel,
        string.format("%s -> %s%s|r (%s%+.0f|r)", fmt(ns.Sim.last.value), color, fmt(r.newValue), color, r.simDelta))
    end
  end
  -- One line per other spec ticked in the window (Pawn-style), e.g. "Holy  ↑ Upgrade  +3.2%".
  for _, o in ipairs(others) do
    local oc = o.verdict == "up" and GREEN or (o.verdict == "down" and RED or GREY)
    local ow = o.verdict == "up" and (St.Icon(St.ARROW_UP, 11) .. " " .. L.UPGRADE)
      or o.verdict == "down" and (St.Icon(St.ARROW_DOWN, 11) .. " " .. L.DOWNGRADE) or L.SIDEGRADE
    local right = o.r.empty and (oc .. L.EMPTY .. "|r") or string.format("%s%+.1f%%|r", oc, o.r.pct)
    tooltip:AddDoubleLine("   " .. St.Icon(o.icon, 14) .. " " .. o.names .. "  " .. oc .. ow .. "|r", right, 1, 1, 1)
  end
  if r.armor == "wrong" then tooltip:AddLine("   " .. ORANGE .. L.WRONG_ARMOR .. "|r") end
  -- Other addons scan items with a hidden GameTooltip: never pop that up or preview it.
  if tooltip:IsShown() then
    tooltip:Show()
    if ns.UI.Preview then ns.UI.Preview(link, r, verdict) end
  end
end

local function AddLines(tooltip, link)
  if not link or not ScalesDB or not ScalesDB.tooltip or done[tooltip] then return end
  if ns.C.IsSecret(link) then return end
  done[tooltip] = true
  -- A Scales error must never break the game's tooltip.
  local ok, err = pcall(Render, tooltip, link)
  if not ok then ns.lastTooltipError = tostring(err) end
end

local TOOLTIPS = { GameTooltip, ItemRefTooltip }

local function FromTooltip(tooltip)
  local _, link = tooltip:GetItem()
  AddLines(tooltip, link)
end

for _, tt in ipairs(TOOLTIPS) do
  -- A new item in the same tooltip clears it first; then the lines may be added again.
  if tt:HasScript("OnTooltipCleared") then tt:HookScript("OnTooltipCleared", function(self) done[self] = nil end) end
  tt:HookScript("OnHide", function(self) done[self] = nil end)
end

-- Modern clients: one hook for every item tooltip.
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local _, link = tooltip:GetItem()
    AddLines(tooltip, link or (data and data.hyperlink))
  end)
end

-- Classic clients do not route every tooltip through TooltipDataProcessor (the auction house in
-- TBC Anniversary, for one), so like Pawn we also hook the item setters and OnTooltipSetItem.
for _, tt in ipairs(TOOLTIPS) do
  if tt:HasScript("OnTooltipSetItem") then tt:HookScript("OnTooltipSetItem", FromTooltip) end
end
for _, method in ipairs({ "SetAuctionItem", "SetAuctionSellItem", "SetItemKey", "SetBagItem", "SetBuybackItem",
  "SetGuildBankItem", "SetHyperlink", "SetInboxItem", "SetInventoryItem", "SetItemByID", "SetLootItem",
  "SetLootRollItem", "SetMerchantItem", "SetQuestItem", "SetQuestLogItem", "SetSendMailItem",
  "SetTradePlayerItem", "SetTradeTargetItem", "SetTradeSkillItem", "SetRecipeResultItem" }) do
  if GameTooltip[method] then hooksecurefunc(GameTooltip, method, FromTooltip) end
end
if ItemRefTooltip.SetHyperlink then hooksecurefunc(ItemRefTooltip, "SetHyperlink", FromTooltip) end
GameTooltip:HookScript("OnHide", function() if ns.UI.Preview then ns.UI.Preview(nil) end end)
