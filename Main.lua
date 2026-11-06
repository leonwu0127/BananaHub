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
    for _, name in ipairs({ "EggHub", "BananaHub", "BananaHubEgg" }) do
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

----------------------------------------------------------------
-- Expanded content: feature menu + feature views
----------------------------------------------------------------
local RAW_BASE = "https://raw.githubusercontent.com/leonwu0127/BananaHub/main/"
local TEXT_COLOR = Color3.fromRGB(250, 228, 160)
local MUTED_COLOR = Color3.fromRGB(170, 165, 140)
local BUTTON_COLOR = Color3.fromRGB(36, 39, 48)

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.new(0, 12, 0, 12)
content.Size = UDim2.new(1, -24, 1, -48)
content.BackgroundTransparency = 1
content.Visible = false
content.ZIndex = 2
content.Parent = panel

local menuView = Instance.new("Frame")
menuView.Name = "Menu"
menuView.Size = UDim2.fromScale(1, 1)
menuView.BackgroundTransparency = 1
menuView.Parent = content

local menuLayout = Instance.new("UIListLayout")
menuLayout.Padding = UDim.new(0, 6)
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.Parent = menuView

local featureView = Instance.new("Frame")
featureView.Name = "Feature"
featureView.Size = UDim2.fromScale(1, 1)
featureView.BackgroundTransparency = 1
featureView.Visible = false
featureView.Parent = content

local backButton = Instance.new("TextButton")
backButton.Size = UDim2.fromOffset(60, 24)
backButton.BackgroundColor3 = BUTTON_COLOR
backButton.Text = "< Back"
backButton.TextColor3 = TEXT_COLOR
backButton.Font = Enum.Font.GothamMedium
backButton.TextSize = 12
backButton.Parent = featureView
Instance.new("UICorner", backButton).CornerRadius = UDim.new(0, 6)

local featureTitle = Instance.new("TextLabel")
featureTitle.Position = UDim2.new(0, 68, 0, 0)
featureTitle.Size = UDim2.new(1, -68, 0, 24)
featureTitle.BackgroundTransparency = 1
featureTitle.TextColor3 = TEXT_COLOR
featureTitle.Font = Enum.Font.GothamBold
featureTitle.TextSize = 14
featureTitle.TextXAlignment = Enum.TextXAlignment.Left
featureTitle.Text = ""
featureTitle.Parent = featureView

local featureHost = Instance.new("Frame")
featureHost.Position = UDim2.new(0, 0, 0, 30)
featureHost.Size = UDim2.new(1, 0, 1, -30)
featureHost.BackgroundTransparency = 1
featureHost.Parent = featureView

local activeFeature = nil

local function showMenu()
    if activeFeature then
        pcall(function() activeFeature.Destroy() end)
        activeFeature = nil
    end
    featureHost:ClearAllChildren()
    featureView.Visible = false
    menuView.Visible = true
end

local function showMessage(text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 60)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = MUTED_COLOR
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextWrapped = true
    label.Parent = featureHost
    return label
end

-- Downloads a feature file from GitHub and shows it inside the panel.
local function openFeature(title, fileName)
    showMenu()
    menuView.Visible = false
    featureView.Visible = true
    featureTitle.Text = title
    local loading = showMessage("Loading " .. title .. "...")

    task.spawn(function()
        local ok, result = pcall(function()
            local source = game:HttpGet(RAW_BASE .. fileName .. "?nocache=" .. tostring(os.time()))
            local chunk, compileError = loadstring(source)
            if not chunk then
                error(compileError, 0)
            end
            return chunk()
        end)

        if not featureView.Visible or featureTitle.Text ~= title then
            return -- user went back or closed the panel while loading
        end

        loading:Destroy()
        if not ok or type(result) ~= "function" then
            showMessage("Could not load " .. fileName .. ":\n" .. tostring(result))
            return
        end

        local started, feature = pcall(result, featureHost, {
            guiParent = guiParent,
            gameName = gameName,
        })
        if started and type(feature) == "table" then
            activeFeature = feature
        else
            featureHost:ClearAllChildren()
            showMessage("Error in " .. title .. ":\n" .. tostring(feature))
        end
    end)
end

local function addMenuButton(order, title, subtitle, callback)
    local button = Instance.new("TextButton")
    button.LayoutOrder = order
    button.Size = UDim2.new(1, 0, 0, 38)
    button.BackgroundColor3 = BUTTON_COLOR
    button.AutoButtonColor = true
    button.Text = ""
    button.Parent = menuView
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

    local name = Instance.new("TextLabel")
    name.Position = UDim2.new(0, 12, 0, 3)
    name.Size = UDim2.new(1, -24, 0, 18)
    name.BackgroundTransparency = 1
    name.Text = title
    name.TextColor3 = TEXT_COLOR
    name.Font = Enum.Font.GothamBold
    name.TextSize = 14
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Parent = button

    local sub = Instance.new("TextLabel")
    sub.Position = UDim2.new(0, 12, 0, 21)
    sub.Size = UDim2.new(1, -24, 0, 14)
    sub.BackgroundTransparency = 1
    sub.Text = subtitle
    sub.TextColor3 = MUTED_COLOR
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 11
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = button

    button.Activated:Connect(callback)
end

if game.GameId == 10563114921 then
    addMenuButton(1, "Auto Steal", "See every egg in the server", function()
        openFeature("Auto Steal", "AutoSteal.lua")
    end)
else
    local none = Instance.new("TextLabel")
    none.Size = UDim2.new(1, 0, 0, 40)
    none.BackgroundTransparency = 1
    none.Text = "No features for " .. gameName .. " yet."
    none.TextColor3 = MUTED_COLOR
    none.Font = Enum.Font.Gotham
    none.TextSize = 12
    none.Parent = menuView
end

backButton.Activated:Connect(showMenu)

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
        content.Visible = true
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
    content.Visible = false
    showMenu()
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
    if activeFeature then
        pcall(function() activeFeature.Destroy() end)
    end
    for _, tween in pairs(activeTweens) do
        tween:Cancel()
    end
end)
