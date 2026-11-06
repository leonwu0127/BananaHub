-- BananaHub Beta
-- Collapsible UI + experience detection

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
if not player then
    warn("BananaHub: Join a game before running this script.")
    return
end

local playerGui = player:WaitForChild("PlayerGui")

-- Pick the safest parent available in the executor.
local function getGuiParent()
    local ok, ui = pcall(function()
        return gethui and gethui()
    end)
    if ok and ui then
        return ui
    end

    local okCore, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and coreGui then
        return coreGui
    end

    return playerGui
end

local guiParent = getGuiParent()

local supportedGames = {
    [10563114921] = "Steal An Egg",
    [994732206] = "Blox Fruits",
    [1686885941] = "Brookhaven RP",
    [66654135] = "Murder Mystery 2",
    [6035872082] = "RIVALS",
    [383310974] = "Adopt Me!",
    [3508322461] = "Jujutsu Shenanigans",
    [7709344486] = "Steal a Brainrot",
    [10765288803] = "Break and Steal an Egg",
    [10766972131] = "Throw Food For Animals",
    [7326934954] = "99 Nights in the Forest",
    [5569032992] = "Dandy's World",
}

local gameName = supportedGames[game.GameId] or "Unsupported Game"

-- Remove old copies from every possible location.
for _, container in ipairs({ guiParent, playerGui }) do
    for _, name in ipairs({ "EggHub", "BananaHub" }) do
        local existing = container:FindFirstChild(name)
        if existing then
            existing:Destroy()
        end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "BananaHub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999999
gui.Parent = guiParent

local COLLAPSED_SIZE = UDim2.fromScale(1 / 5, 1 / 30)
local EXPANDED_SIZE = UDim2.fromScale(1 / 3, 1 / 3)
local TOP_GAP = 10 -- pixels from the top of the screen

local BASE_COLOR = Color3.fromRGB(25, 27, 34)
local HOVER_COLOR = Color3.fromRGB(36, 39, 48)
local BASE_BORDER = Color3.fromRGB(85, 79, 54)
local HOVER_BORDER = Color3.fromRGB(245, 205, 90)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, TOP_GAP)
panel.Size = COLLAPSED_SIZE
panel.BackgroundColor3 = BASE_COLOR
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = BASE_BORDER
stroke.Transparency = 0.3
stroke.Thickness = 1
stroke.Parent = panel

-- Collapsed bar (whole bar is clickable)
local openButton = Instance.new("TextButton")
openButton.Name = "OpenButton"
openButton.Size = UDim2.fromScale(1, 1)
openButton.BackgroundTransparency = 1
openButton.AutoButtonColor = false
openButton.Text = "BananaHub Beta - " .. gameName
openButton.TextColor3 = Color3.fromRGB(250, 228, 160)
openButton.Font = Enum.Font.GothamMedium
openButton.TextScaled = true
openButton.ZIndex = 2
openButton.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 4)
padding.PaddingBottom = UDim.new(0, 4)
padding.Parent = openButton

local textConstraint = Instance.new("UITextSizeConstraint")
textConstraint.MinTextSize = 1
textConstraint.MaxTextSize = 16
textConstraint.Parent = openButton

-- Small handle at the bottom to collapse again
local collapseButton = Instance.new("TextButton")
collapseButton.Name = "CollapseHandle"
collapseButton.AnchorPoint = Vector2.new(0.5, 1)
collapseButton.Position = UDim2.new(0.5, 0, 1, -4)
collapseButton.Size = UDim2.fromOffset(72, 24)
collapseButton.BackgroundTransparency = 1
collapseButton.Text = ""
collapseButton.AutoButtonColor = false
collapseButton.Visible = false
collapseButton.ZIndex = 2
collapseButton.Parent = panel

local handle = Instance.new("Frame")
handle.AnchorPoint = Vector2.new(0.5, 0.5)
handle.Position = UDim2.fromScale(0.5, 0.5)
handle.Size = UDim2.fromOffset(36, 4)
handle.BackgroundColor3 = Color3.fromRGB(245, 205, 90)
handle.BackgroundTransparency = 0.45
handle.BorderSizePixel = 0
handle.Parent = collapseButton

local handleCorner = Instance.new("UICorner")
handleCorner.CornerRadius = UDim.new(1, 0)
handleCorner.Parent = handle

local expanded = false
local busy = false
local hovered = false
local activeTweens = {}

local function animate(channel, object, duration, properties, style)
    if activeTweens[channel] then
        activeTweens[channel]:Cancel()
    end

    local tween = TweenService:Create(
        object,
        TweenInfo.new(
            duration,
            style or Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        properties
    )

    activeTweens[channel] = tween
    tween:Play()
    return tween
end

local function updateHover()
    local highlight = hovered and not expanded and not busy

    animate("background", panel, 0.15, {
        BackgroundColor3 = highlight and HOVER_COLOR or BASE_COLOR,
    })

    animate("border", stroke, 0.15, {
        Color = highlight and HOVER_BORDER or BASE_BORDER,
        Transparency = highlight and 0 or 0.3,
    })
end

local function expand()
    if busy or expanded then
        return
    end

    busy = true
    expanded = true
    updateHover()

    animate("title", openButton, 0.1, { TextTransparency = 1 })
    animate("size", panel, 0.32, {
        Size = EXPANDED_SIZE,
    }, Enum.EasingStyle.Quint)

    task.delay(0.34, function()
        if not gui.Parent then return end
        openButton.Visible = false
        collapseButton.Visible = true
        busy = false
    end)
end

local function collapse()
    if busy or not expanded then
        return
    end

    busy = true
    expanded = false

    collapseButton.Visible = false
    openButton.Visible = true
    openButton.TextTransparency = 1

    animate("size", panel, 0.28, {
        Size = COLLAPSED_SIZE,
    }, Enum.EasingStyle.Quint)

    task.delay(0.3, function()
        if not gui.Parent then return end
        animate("title", openButton, 0.15, { TextTransparency = 0 })
        busy = false
        updateHover()
    end)
end

openButton.MouseEnter:Connect(function()
    hovered = true
    updateHover()
end)

openButton.MouseLeave:Connect(function()
    hovered = false
    updateHover()
end)

-- Connect both events; the busy/expanded guards ignore duplicates.
openButton.Activated:Connect(expand)
openButton.MouseButton1Click:Connect(expand)

collapseButton.Activated:Connect(collapse)
collapseButton.MouseButton1Click:Connect(collapse)

collapseButton.MouseEnter:Connect(function()
    animate("handle", handle, 0.12, { BackgroundTransparency = 0 })
end)

collapseButton.MouseLeave:Connect(function()
    animate("handle", handle, 0.12, { BackgroundTransparency = 0.45 })
end)

gui.Destroying:Connect(function()
    for _, tween in pairs(activeTweens) do
        tween:Cancel()
    end
end)
