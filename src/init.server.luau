-- Daily Helper: a Studio plugin for daily maintenance. It audits the open place and asks before it changes anything.

local RunService = game:GetService("RunService")

-- Plugins also load inside a playtest. The audit is for edit mode only.
if RunService:IsRunning() then
	return
end

local App = require(script.App)

-- The icon: a yellow calendar page with a check mark. Decal 101925756110390 in the group Lawak
-- Gamehouse, distributed on the Creator Store so every place can load it.
local ICON = "rbxassetid://120596024740650"

local toolbar = plugin:CreateToolbar("Daily Helper")
local toggle = toolbar:CreateButton("Daily Helper", "Daily check-up for this place", ICON)
toggle.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"DailyHelper",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 380, 720, 320, 420)
)
widget.Title = "Daily Helper"
widget.Name = "DailyHelper"

local app = App.start(plugin, widget)

toggle:SetActive(widget.Enabled)
toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(widget.Enabled)
end)

plugin.Unloading:Connect(app.stop)
