-- BananaHub Beta: Click TP (works in any game)
-- Turn it on, point your mouse somewhere, press the key -> you teleport there.
-- The key bind keeps working after you leave this page (turn it Off here to stop it).
-- Loaded by Main.lua. Returns function(parent, ctx) -> { Destroy = function }

return function(parent, ctx)
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer

    local VERSION = 2
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
    if state.mode == nil then state.mode = "Velocity" end -- "Velocity" or "CFrame"
    if state.speed == nil then state.speed = 200 end
    local SPEEDS = { 100, 200, 350, 500 }

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
        local goal = hit + Vector3.new(0, height, 0)
        if state.mode == "CFrame" then
            local _, yaw = hrp.CFrame:ToOrientation()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(goal) * CFrame.Angles(0, yaw, 0)
            setStatus(string.format("Teleported to (%d, %d, %d)", math.floor(hit.X), math.floor(hit.Y), math.floor(hit.Z)))
            return
        end

        -- Velocity mode: push the character toward the spot every frame.
        if state.moving then
            state.moving.cancel = true -- a new press replaces the old trip
        end
        local trip = { cancel = false }
        state.moving = trip
        local speed = state.speed
        local dist = (goal - hrp.Position).Magnitude
        local timeLimit = dist / speed * 1.5 + 1
        local started = os.clock()
        setStatus(string.format("Flying %d studs at %d/s...", math.floor(dist), speed))
        local conn
        conn = RunService.Heartbeat:Connect(function()
            local stop, msg = false, nil
            if trip.cancel then
                stop = true
            elseif not hrp.Parent or hum.Health <= 0 then
                stop, msg = true, "Stopped: character died or reset."
            else
                local offset = goal - hrp.Position
                if offset.Magnitude < 3 then
                    stop, msg = true, string.format("Arrived at (%d, %d, %d)", math.floor(hit.X), math.floor(hit.Y), math.floor(hit.Z))
                elseif os.clock() - started > timeLimit then
                    stop, msg = true, "Stopped: blocked by something (took too long)."
                else
                    hrp.AssemblyLinearVelocity = offset.Unit * math.min(speed, offset.Magnitude * 20)
                end
            end
            if stop then
                conn:Disconnect()
                if hrp.Parent then hrp.AssemblyLinearVelocity = Vector3.zero end
                if state.moving == trip then state.moving = nil end
                if msg then setStatus(msg) end
            end
        end)
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
    local modeButton = makeButton("", 0, 34, 110)
    local speedButton = makeButton("", 118, 34, 130)
    local help = makeLabel(70, 32, MUTED)
    help.Text = "Point your mouse at a spot and press the key. Velocity = fly there fast, CFrame = instant jump. Games with anti-teleport (like Steal An Egg) may still pull you back or kill you."
    local statusLabel = makeLabel(108, 32, TEXT)

    local function render()
        toggleButton.Text = state.enabled and "Click TP: ON" or "Click TP: OFF"
        toggleButton.BackgroundColor3 = state.enabled and ON_COLOR or OFF_COLOR
        if state.binding then
            keyButton.Text = "Press any key..."
        else
            keyButton.Text = "Key: " .. state.key.Name
        end
        modeButton.Text = "Mode: " .. state.mode
        speedButton.Text = "Speed: " .. state.speed .. "/s"
        speedButton.Visible = state.mode == "Velocity"
        statusLabel.Text = state.lastStatus or ""
    end
    state.onChange = render

    local conns = {}
    conns[#conns + 1] = toggleButton.Activated:Connect(function()
        state.enabled = not state.enabled
        setStatus(state.enabled and ("On - press " .. state.key.Name .. " to teleport.") or "Off.")
    end)

    conns[#conns + 1] = modeButton.Activated:Connect(function()
        state.mode = (state.mode == "Velocity") and "CFrame" or "Velocity"
        setStatus("Mode: " .. state.mode .. ".")
    end)

    conns[#conns + 1] = speedButton.Activated:Connect(function()
        local nextSpeed = SPEEDS[1]
        for i, v in ipairs(SPEEDS) do
            if v == state.speed then nextSpeed = SPEEDS[i % #SPEEDS + 1] end
        end
        state.speed = nextSpeed
        setStatus("Speed: " .. state.speed .. " studs/s.")
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
