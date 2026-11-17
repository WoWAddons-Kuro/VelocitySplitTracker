-- Settings panel registered with the Blizzard options UI. Empty shell for now.
local ADDON_NAME, ST = ...
local T = ST.Theme

ST.Config = {}
local C = ST.Config

local panel, categoryID

function C.Create()
  if panel then return panel end
  panel = CreateFrame("Frame", "SplitTimerConfigPanel")
  panel.name = "SplitTimer"

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("SplitTimer")

  local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("Options and the milestone plan editor will live here. While this panel is open the Active clock is paused.")

  local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  btn:SetSize(160, 22)
  btn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
  btn:SetText("Toggle split window")
  btn:SetScript("OnClick", function() ST.Live.Toggle() end)

  local btn2 = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  btn2:SetSize(160, 22)
  btn2:SetPoint("LEFT", btn, "RIGHT", 8, 0)
  btn2:SetText("Open history")
  btn2:SetScript("OnClick", function() ST.History.Toggle() end)

  panel:SetScript("OnShow", function() ST.ConfigPanelOpen = true end)
  panel:SetScript("OnHide", function() ST.ConfigPanelOpen = false end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    category.ID = panel.name
    Settings.RegisterAddOnCategory(category)
    categoryID = category:GetID()
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  return panel
end

function C.Open()
  C.Create()
  if Settings and Settings.OpenToCategory and categoryID then
    Settings.OpenToCategory(categoryID)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end
