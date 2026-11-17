-- Visual constants and small widget factories shared by all SplitTimer windows.
local ADDON_NAME, ST = ...

ST.Theme = {}
local T = ST.Theme

T.Font        = "Fonts\\ARIALN.TTF"
T.FontSize    = 13
T.TimerSize   = 34
T.TitleSize   = 13
T.RowHeight   = 20
T.TitleHeight = 24
T.TimerHeight = 46
T.FooterHeight = 20
T.Width       = 270
T.Padding     = 6

T.Colour = {
  Bg          = { 0.05, 0.05, 0.05, 0.85 },
  RowAlt      = { 1, 1, 1, 0.04 },
  RowCurrent  = { 0.20, 0.45, 0.95, 0.35 },
  Separator   = { 1, 1, 1, 0.12 },
  Text        = { 0.92, 0.92, 0.92 },
  TextDim     = { 0.60, 0.60, 0.60 },
  Ahead       = { 0.30, 0.85, 0.30 },
  Behind      = { 0.90, 0.30, 0.30 },
  Gold        = { 0.95, 0.80, 0.25 },
  Stopped     = { 0.80, 0.80, 0.80 },
  Frozen      = { 0.55, 0.55, 0.60 },
  Progress    = { 0.35, 0.55, 0.95, 0.55 },
}

function T.SetColour(obj, c, alphaOverride)
  if obj.SetTextColor then obj:SetTextColor(c[1], c[2], c[3], alphaOverride or c[4] or 1)
  elseif obj.SetColorTexture then obj:SetColorTexture(c[1], c[2], c[3], alphaOverride or c[4] or 1)
  elseif obj.SetVertexColor then obj:SetVertexColor(c[1], c[2], c[3], alphaOverride or c[4] or 1) end
end

function T.DeltaColour(delta, gold)
  if gold then return T.Colour.Gold end
  if delta == nil then return T.Colour.TextDim end
  if delta < 0 then return T.Colour.Ahead end
  return T.Colour.Behind
end

-- FontString with our font applied.
function T.Text(parent, size, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(T.Font, size or T.FontSize, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  T.SetColour(fs, T.Colour.Text)
  return fs
end

function T.Texture(parent, colour, layer)
  local tx = parent:CreateTexture(nil, layer or "BACKGROUND")
  T.SetColour(tx, colour)
  return tx
end

-- Thin horizontal line.
function T.Separator(parent)
  local tx = T.Texture(parent, T.Colour.Separator, "ARTWORK")
  tx:SetHeight(1)
  return tx
end

-- Click-to-open dropdown. Uses the modern MenuUtil when present, else UIDropDownMenu.
-- items: { { text=, checked=bool, func=function } ... }
function T.ShowMenu(anchor, items)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      for _, it in ipairs(items) do
        if it.separator then root:CreateDivider()
        elseif it.title then root:CreateTitle(it.title)
        else
          local fn = it.func
          if it.checked ~= nil then
            root:CreateRadio(it.text, function() return it.checked end, fn)
          else
            root:CreateButton(it.text, fn)
          end
        end
      end
    end)
    return
  end
  if not ST._menuFrame then
    ST._menuFrame = CreateFrame("Frame", "SplitTimerMenuFrame", UIParent, "UIDropDownMenuTemplate")
  end
  local list = {}
  for _, it in ipairs(items) do
    if it.separator then
      list[#list + 1] = { text = "", disabled = true, notCheckable = true }
    elseif it.title then
      list[#list + 1] = { text = it.title, isTitle = true, notCheckable = true }
    else
      list[#list + 1] = { text = it.text, checked = it.checked, func = it.func, notCheckable = it.checked == nil }
    end
  end
  if EasyMenu then
    EasyMenu(list, ST._menuFrame, anchor, 0, 0, "MENU")
  else
    UIDropDownMenu_Initialize(ST._menuFrame, function(_, level)
      for _, info in ipairs(list) do UIDropDownMenu_AddButton(info, level) end
    end, "MENU")
    ToggleDropDownMenu(1, nil, ST._menuFrame, anchor, 0, 0)
  end
end
