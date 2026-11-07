-- BananaHub Beta: Click TP (works in any game)
-- Turn it on, point your mouse somewhere, press the key -> you teleport there.
-- The key bind keeps working after you leave this page (turn it Off here to stop it).
-- Loaded by Main.lua. Returns function(parent, ctx) -> { Destroy = function }

return function(parent, ctx)
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer

    local VERSION = 1
    local TEXT = Color3.fromRGB(250, 228, 160)
    local MUTED = Color3.fromRGB(170, 165, 140)
    local BTN = Color3.fromRGB(48, 52, 64)
    local ON_COLOR = Color3.fromRGB(70, 140, 80)
    local OFF_COLOR = Color3.fromRGB(140, 60, 60)

    ----------------------------------------------------------------
    -- Shared state (survives closing this page / re-opening it)
    ----------------------------------------------------------------
    local env = (getgenv and getgenv()) or _G
    local state = env.BananaHubClickTP
    if type(state) ~= "table" then
        state = { enabled = false, key = Enum.KeyCode.T, maxDistance = 1000 }
        env.BananaHubClickTP = state
    end
    state.onChange = nil -- set by the UI below

    local function setStatus(text)
        state.lastStatus = text
        if state.onChange then
            pcall(state.onChange)
        end
    end

    local function mouseTarget()
        local camera = workspace.CurrentCamera
        if not camera then return nil end
        local mousePos = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { player.Character }
        local result = workspace:Raycast(ray.Origin, ray.Direction * state.maxDistance, params)
        return result and result.Position or nil
    end

    local function teleportToMouse()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then
            setStatus("No character to teleport.")
            return
        end
        local hit = mouseTarget()
        if not hit then
            setStatus("Mouse isn't pointing at anything (sky or too far).")
            return
        end
        -- Stand on top of the spot, keep facing the same way.
        local height = hum.HipHeight + hrp.Size.Y / 2 + 0.5
        local _, yaw = hrp.CFrame:ToOrientation()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(hit + Vector3.new(0, height, 0)) * CFrame.Angles(0, yaw, 0)
        setStatus(string.format("Teleported to (%d, %d, %d)", hit.X, hit.Y, hit.Z))
    end

    -- (Re)create the key listener once; replace it if this file was updated.
    if state.conn and state.version ~= VERSION then
        pcall(function() state.conn:Disconnect() end)
        state.conn = nil
    end
    if not state.conn then
        state.version = VERSION
        state.conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end -- typing in chat / a text box
            if state.binding then return end
            if state.enabled and input.KeyCode == state.key then
                teleportToMouse()
            end
        end)
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    local root = Instance.new("Frame")
    root.Name = "ClickTPView"
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundTransparency = 1
    root.Parent = parent

    local function makeButton(text, x, y, w)
        local b = Instance.new("TextButton")
        b.Position = UDim2.new(0, x, 0, y)
        b.Size = UDim2.new(0, w, 0, 28)
        b.BackgroundColor3 = BTN
        b.AutoButtonColor = true
        b.Text = text
        b.TextColor3 = TEXT
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 12
        b.Parent = root
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        return b
    end

    local function makeLabel(y, h, color)
        local l = Instance.new("TextLabel")
        l.Position = UDim2.new(0, 0, 0, y)
        l.Size = UDim2.new(1, 0, 0, h)
        l.BackgroundTransparency = 1
        l.TextColor3 = color
        l.Font = Enum.Font.Gotham
        l.TextSize = 12
        l.TextWrapped = true
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.Parent = root
        return l
    end

    local toggleButton = makeButton("", 0, 0, 110)
    local keyButton = makeButton("", 118, 0, 130)
    local help = makeLabel(36, 32, MUTED)
    help.Text = "Point your mouse at a spot and press the key. Games with anti-teleport (like Steal An Egg) may pull you back or kill you."
    local statusLabel = makeLabel(74, 32, TEXT)

    local function render()
        toggleButton.Text = state.enabled and "Click TP: ON" or "Click TP: OFF"
        toggleButton.BackgroundColor3 = state.enabled and ON_COLOR or OFF_COLOR
        if state.binding then
            keyButton.Text = "Press any key..."
        else
            keyButton.Text = "Key: " .. state.key.Name
        end
        statusLabel.Text = state.lastStatus or ""
    end
    state.onChange = render

    local conns = {}
    conns[#conns + 1] = toggleButton.Activated:Connect(function()
        state.enabled = not state.enabled
        setStatus(state.enabled and ("On - press " .. state.key.Name .. " to teleport.") or "Off.")
    end)

    conns[#conns + 1] = keyButton.Activated:Connect(function()
        if state.binding then return end
        state.binding = true
        render()
        local bindConn
        bindConn = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            bindConn:Disconnect()
            if input.KeyCode ~= Enum.KeyCode.Escape then
                state.key = input.KeyCode
            end
            -- let this key press finish before the TP listener sees keys again
            task.wait()
            state.binding = false
            setStatus("Key set to " .. state.key.Name .. ".")
        end)
        conns[#conns + 1] = bindConn
    end)

    render()

    return {
        Destroy = function()
            -- Only the page closes; the key bind keeps working while it's ON.
            state.onChange = nil
            state.binding = false
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            root:Destroy()
        end,
    }
end
