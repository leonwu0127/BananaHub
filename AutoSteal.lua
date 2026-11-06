-- BananaHub Beta: Auto Steal (Steal An Egg)
-- Step 1: list every egg currently in the server (and highlight them in the world).
-- Loaded by Main.lua. Returns function(parent, ctx) -> { Destroy = function }

return function(parent, ctx)
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

    local alive = true
    local espEnabled = true
    local highlights = {} -- [Instance] = Highlight
    local MAX_HIGHLIGHTS = 30
    local REFRESH_SECONDS = 3

    local TEXT = Color3.fromRGB(250, 228, 160)
    local MUTED = Color3.fromRGB(170, 165, 140)
    local ROW = Color3.fromRGB(36, 39, 48)
    local BTN = Color3.fromRGB(48, 52, 64)
    local GOLD = Color3.fromRGB(245, 205, 90)

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    local root = Instance.new("Frame")
    root.Name = "AutoStealView"
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundTransparency = 1
    root.Parent = parent

    local function makeButton(text, width, xOffset)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0)
        b.Position = UDim2.new(1, -xOffset, 0, 0)
        b.Size = UDim2.new(0, width, 0, 24)
        b.BackgroundColor3 = BTN
        b.AutoButtonColor = true
        b.Text = text
        b.TextColor3 = TEXT
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 12
        b.Parent = root
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = b
        return b
    end

    local refreshButton = makeButton("Refresh", 64, 0)
    local espButton = makeButton("ESP: On", 64, 70)
    local debugButton = makeButton("Debug", 54, 140)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -200, 0, 24)
    status.BackgroundTransparency = 1
    status.Text = "Scanning..."
    status.TextColor3 = TEXT
    status.Font = Enum.Font.GothamMedium
    status.TextSize = 13
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.Parent = root

    local list = Instance.new("ScrollingFrame")
    list.Position = UDim2.new(0, 0, 0, 30)
    list.Size = UDim2.new(1, 0, 1, -30)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 4
    list.ScrollBarImageColor3 = GOLD
    list.CanvasSize = UDim2.new()
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.Parent = root

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = list

    ----------------------------------------------------------------
    -- Egg discovery
    ----------------------------------------------------------------
    local function hasEggInName(inst)
        return string.find(string.lower(inst.Name), "egg", 1, true) ~= nil
    end

    local function isEggContainer(inst)
        -- A folder/model literally called "Egg" / "Eggs" holds the eggs as children.
        local n = string.lower(inst.Name)
        return (inst:IsA("Folder") or inst:IsA("Model")) and (n == "eggs" or n == "egg")
            and not inst:IsA("BasePart")
    end

    local function isPlayerStuff(inst)
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character and inst:IsDescendantOf(p.Character) then
                return true
            end
        end
        return false
    end

    -- Nest / spawn helper parts that contain "egg" in the name but are not eggs.
    local JUNK = { "fitbounds", "spotbottom", "eggpoint", "holder", "eggspot", "bounds", "slot", "spawn" }
    local function isJunk(inst)
        local n = string.lower(inst.Name)
        for _, j in ipairs(JUNK) do
            if string.find(n, j, 1, true) then return true end
        end
        return false
    end

    -- Decoration / machine / nest containers whose "egg" parts are never real eggs.
    local BAD_ANCESTORS = { "machines", "areaeggslotsclient", "__clienttreadmillrenders", "treadmills" }
    local function inBadPlace(inst)
        local a = inst
        while a and a ~= workspace do
            local n = string.lower(a.Name)
            for _, b in ipairs(BAD_ANCESTORS) do
                if n == b then return true end
            end
            a = a.Parent
        end
        return false
    end

    -- Real eggs are named like "FirstAreaEgg_5500179517_5979771_Forest".
    local function matchesEggPattern(inst)
        local n = inst.Name
        if string.find(n, "Meshes/", 1, true) or string.find(string.lower(n), "steal an egg", 1, true) then
            return false
        end
        return string.match(n, "^%a*Egg_%d+") ~= nil
    end

    local function isEggLike(inst)
        return (inst:IsA("Model") or inst:IsA("BasePart"))
            and matchesEggPattern(inst) and not isJunk(inst) and not inBadPlace(inst)
    end

    -- "FirstAreaEgg_5500179517_5979771_Forest" -> kind "FirstAreaEgg", numbers {...}, area "Forest"
    local function parseName(name)
        local parts = string.split(name, "_")
        local kind = parts[1]
        local nums, words = {}, {}
        for i = 2, #parts do
            if tonumber(parts[i]) then nums[#nums + 1] = tonumber(parts[i])
            else words[#words + 1] = parts[i] end
        end
        return kind, nums, table.concat(words, " ")
    end

    local function prettyKind(kind)
        -- "FirstAreaEgg" -> "First Area Egg"
        local spaced = string.gsub(kind or "", "(%l)(%u)", "%1 %2")
        return spaced
    end

    local function findEggs()
        local candidates = {}
        local set = {}

        for _, inst in ipairs(workspace:GetDescendants()) do
            if isEggLike(inst) and not inst:IsA("Terrain") and not isPlayerStuff(inst) then
                candidates[#candidates + 1] = inst
                set[inst] = true
            elseif isEggContainer(inst) and not inBadPlace(inst) and not isPlayerStuff(inst) then
                for _, child in ipairs(inst:GetChildren()) do
                    if (child:IsA("Model") or child:IsA("BasePart")) and not set[child]
                        and not isJunk(child) and not string.find(child.Name, "Meshes/", 1, true) then
                        candidates[#candidates + 1] = child
                        set[child] = true
                    end
                end
            end
        end

        -- Keep only the top-most match so a model and its parts aren't listed separately.
        local eggs = {}
        for _, inst in ipairs(candidates) do
            local ancestor = inst.Parent
            local nested = false
            while ancestor and ancestor ~= workspace do
                if set[ancestor] then
                    nested = true
                    break
                end
                ancestor = ancestor.Parent
            end
            if not nested then
                eggs[#eggs + 1] = inst
            end
        end
        return eggs
    end

    ----------------------------------------------------------------
    -- Details (owner, rarity, distance)
    ----------------------------------------------------------------
    local OWNER_KEYS = { "Owner", "OwnerName", "OwnerId", "OwnerUserId", "Player", "PlayerName" }
    local RARITY_KEYS = { "Rarity", "Tier", "Type", "Mutation" }

    local function playerFromValue(value)
        if typeof(value) == "Instance" and value:IsA("Player") then
            return value.Name
        elseif type(value) == "number" then
            local p = Players:GetPlayerByUserId(value)
            return p and p.Name or nil
        elseif type(value) == "string" and value ~= "" then
            return value
        end
        return nil
    end

    local function findOwner(inst)
        local _, nums = parseName(inst.Name)
        for _, n in ipairs(nums) do
            local p = Players:GetPlayerByUserId(n)
            if p then return p.Name end
        end
        local node = inst
        for _ = 1, 6 do
            if not node or node == workspace then break end
            for _, key in ipairs(OWNER_KEYS) do
                local attr = node:GetAttribute(key)
                local name = attr ~= nil and playerFromValue(attr)
                if name then return name end

                local child = node:FindFirstChild(key)
                if child and child:IsA("ValueBase") then
                    name = playerFromValue(child.Value)
                    if name then return name end
                end
            end
            -- A plot/folder named after a player also tells us who owns it.
            for _, p in ipairs(Players:GetPlayers()) do
                if node.Name == p.Name or node.Name == p.DisplayName then
                    return p.Name
                end
            end
            node = node.Parent
        end
        return nil
    end

    local function findRarity(inst)
        for _, key in ipairs(RARITY_KEYS) do
            local attr = inst:GetAttribute(key)
            if attr ~= nil then return tostring(attr) end
            local child = inst:FindFirstChild(key)
            if child and child:IsA("ValueBase") then return tostring(child.Value) end
        end
        return nil
    end

    -- Best effort: what the egg will hatch into, if the game exposes it on the client.
    local PET_KEYS = { "pet", "hatch", "contain", "inside", "reward", "content", "result", "animal", "creature" }
    local SKIP_KEYS = { "owner", "player", "userid", "rarity", "tier" }
    local function keyMatches(name)
        local n = string.lower(name)
        for _, k in ipairs(SKIP_KEYS) do
            if string.find(n, k, 1, true) then return false end
        end
        for _, k in ipairs(PET_KEYS) do
            if string.find(n, k, 1, true) then return true end
        end
        return false
    end

    local function findContents(inst)
        local found = {}
        local function add(v)
            v = tostring(v)
            if v ~= "" and v ~= "nil" and #found < 3 then
                for _, f in ipairs(found) do if f == v then return end end
                found[#found + 1] = v
            end
        end
        for k, v in pairs(inst:GetAttributes()) do
            if keyMatches(k) then add(v) end
        end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("ValueBase") and keyMatches(d.Name) then
                add(d.Value)
            elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
                local label = string.lower(d.Name)
                if keyMatches(d.Name) or string.find(label, "name", 1, true) then add(d.Text) end
            end
            if #found >= 3 then break end
        end
        if #found == 0 then return nil end
        return table.concat(found, ", ")
    end

    local function distanceTo(inst)
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if not ok then return nil end
        return (pivot.Position - hrp.Position).Magnitude
    end

    ----------------------------------------------------------------
    -- ESP highlights
    ----------------------------------------------------------------
    local function clearHighlight(inst)
        local h = highlights[inst]
        if h then
            pcall(function() h:Destroy() end)
            highlights[inst] = nil
        end
    end

    local function syncHighlights(eggs)
        local keep = {}
        local count = 0
        if espEnabled then
            for _, egg in ipairs(eggs) do
                if count >= MAX_HIGHLIGHTS then break end
                keep[egg] = true
                count += 1
                if not highlights[egg] then
                    local h = Instance.new("Highlight")
                    h.Name = "BananaHubEgg"
                    h.Adornee = egg
                    h.FillColor = GOLD
                    h.FillTransparency = 0.6
                    h.OutlineColor = Color3.fromRGB(255, 255, 255)
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    local ok = pcall(function() h.Parent = ctx.guiParent end)
                    if not ok or not h.Parent then
                        pcall(function() h.Parent = egg end)
                    end
                    highlights[egg] = h
                end
            end
        end
        for inst in pairs(highlights) do
            if not keep[inst] then
                clearHighlight(inst)
            end
        end
    end

    ----------------------------------------------------------------
    -- Rendering
    ----------------------------------------------------------------
    local lastEggs = {}

    local function render(eggs)
        local savedScroll = list.CanvasPosition
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end

        local entries = {}
        for _, egg in ipairs(eggs) do
            entries[#entries + 1] = {
                inst = egg,
                dist = distanceTo(egg),
                owner = findOwner(egg),
                rarity = findRarity(egg),
                contents = findContents(egg),
            }
        end
        table.sort(entries, function(a, b)
            return (a.dist or math.huge) < (b.dist or math.huge)
        end)

        if #entries == 0 then
            status.Text = "No eggs found in the server"
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 60)
            empty.BackgroundTransparency = 1
            empty.Text = "No real eggs found (nest parts are ignored).\nPress Debug and send me the output."
            empty.TextColor3 = MUTED
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 12
            empty.TextWrapped = true
            empty.Parent = list
            return
        end

        status.Text = ("Eggs in server: %d"):format(#entries)

        for i, e in ipairs(entries) do
            local row = Instance.new("Frame")
            row.LayoutOrder = i
            row.Size = UDim2.new(1, -6, 0, 30)
            row.BackgroundColor3 = ROW
            row.BorderSizePixel = 0
            row.Parent = list

            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 6)
            c.Parent = row

            local name = Instance.new("TextLabel")
            name.Position = UDim2.new(0, 8, 0, 0)
            name.Size = UDim2.new(0.5, -8, 1, 0)
            name.BackgroundTransparency = 1
            local kind, _, area = parseName(e.inst.Name)
            local title = prettyKind(kind)
            for _, key in ipairs({ "EggName", "EggType", "DisplayName", "PetName" }) do
                local v = e.inst:GetAttribute(key)
                if v ~= nil then title = tostring(v) break end
            end
            if area ~= "" then title = title .. " (" .. area .. ")" end
            if e.rarity then title = title .. " [" .. e.rarity .. "]" end
            if e.contents then title = title .. " -> " .. e.contents end
            name.Text = title
            name.TextColor3 = TEXT
            name.Font = Enum.Font.GothamMedium
            name.TextSize = 12
            name.TextXAlignment = Enum.TextXAlignment.Left
            name.TextTruncate = Enum.TextTruncate.AtEnd
            name.Parent = row

            local info = Instance.new("TextLabel")
            info.AnchorPoint = Vector2.new(1, 0)
            info.Position = UDim2.new(1, -8, 0, 0)
            info.Size = UDim2.new(0.5, -8, 1, 0)
            info.BackgroundTransparency = 1
            local owner = e.owner
            if owner == player.Name then owner = "You" end
            local dist = e.dist and (math.floor(e.dist) .. " studs") or "? studs"
            info.Text = (owner or "Unknown owner") .. "  |  " .. dist
            info.TextColor3 = MUTED
            info.Font = Enum.Font.Gotham
            info.TextSize = 11
            info.TextXAlignment = Enum.TextXAlignment.Right
            info.TextTruncate = Enum.TextTruncate.AtEnd
            info.Parent = row
        end

        list.CanvasPosition = savedScroll
    end

    local function refresh()
        if not alive then return end
        local ok, eggs = pcall(findEggs)
        if not ok then
            status.Text = "Scan error: " .. tostring(eggs)
            return
        end
        lastEggs = eggs
        syncHighlights(eggs)
        render(eggs)
    end

    ----------------------------------------------------------------
    -- Buttons
    ----------------------------------------------------------------
    local function connect(button, fn)
        button.Activated:Connect(fn)
    end

    connect(refreshButton, refresh)

    connect(espButton, function()
        espEnabled = not espEnabled
        espButton.Text = espEnabled and "ESP: On" or "ESP: Off"
        syncHighlights(lastEggs)
    end)

    connect(debugButton, function()
        local lines = { "BananaHub debug - GameId " .. tostring(game.GameId) .. ", PlaceId " .. tostring(game.PlaceId) }
        lines[#lines + 1] = "Eggs found: " .. #lastEggs
        for i, egg in ipairs(lastEggs) do
            lines[#lines + 1] = "  " .. egg:GetFullName() .. " (" .. egg.ClassName .. ")"
            if i <= 12 then
                for k, v in pairs(egg:GetAttributes()) do
                    lines[#lines + 1] = "    attr " .. k .. " = " .. tostring(v)
                end
                for _, d in ipairs(egg:GetDescendants()) do
                    if d:IsA("ValueBase") then
                        lines[#lines + 1] = "    value " .. d.Name .. " = " .. tostring(d.Value)
                    elseif d:IsA("TextLabel") or d:IsA("TextButton") then
                        lines[#lines + 1] = "    text " .. d.Name .. " = " .. d.Text
                    elseif d:IsA("ProximityPrompt") then
                        lines[#lines + 1] = "    prompt " .. d.Name .. " action=" .. d.ActionText .. " object=" .. d.ObjectText
                    elseif d:IsA("ClickDetector") then
                        lines[#lines + 1] = "    clickdetector " .. d.Name
                    end
                end
                local names = {}
                for _, c in ipairs(egg:GetChildren()) do names[#names + 1] = c.Name .. ":" .. c.ClassName end
                lines[#lines + 1] = "    children " .. table.concat(names, ", ")
            end
        end
        -- Compact map of every "egg" name in the world, grouped by parent path (counts only).
        local groups, order = {}, {}
        local looseSamples = {}
        for _, inst in ipairs(workspace:GetDescendants()) do
            if string.find(string.lower(inst.Name), "egg", 1, true) then
                local key = inst.Parent and inst.Parent:GetFullName() or "?"
                key = string.gsub(key, "%d+", "#")
                if not groups[key] then groups[key] = 0; order[#order + 1] = key end
                groups[key] = groups[key] + 1
                if string.match(inst.Name, "Egg_%d") and #looseSamples < 15 then
                    looseSamples[#looseSamples + 1] = inst:GetFullName() .. " (" .. inst.ClassName .. ")"
                end
            end
        end
        lines[#lines + 1] = "Egg-name groups by parent (count):"
        table.sort(order, function(a, b) return groups[a] > groups[b] end)
        for i = 1, math.min(#order, 25) do
            lines[#lines + 1] = "  " .. groups[order[i]] .. "  " .. order[i]
        end
        lines[#lines + 1] = "Names containing Egg_<digits> (first 15):"
        for _, l in ipairs(looseSamples) do lines[#lines + 1] = "  " .. l end
        lines[#lines + 1] = "Players: " .. #Players:GetPlayers()
        for _, p in ipairs(Players:GetPlayers()) do
            lines[#lines + 1] = "  " .. p.Name .. " userId " .. p.UserId
        end
        lines[#lines + 1] = "Workspace children:"
        for _, child in ipairs(workspace:GetChildren()) do
            lines[#lines + 1] = "  " .. child.Name .. " (" .. child.ClassName .. ")"
        end
        local text = table.concat(lines, "\n")
        print(text)
        local copied = false
        if setclipboard then
            copied = pcall(setclipboard, text)
        end
        status.Text = copied and "Debug copied to clipboard (also in console)" or "Debug printed to console"
    end)

    ----------------------------------------------------------------
    -- Live refresh while the view is open
    ----------------------------------------------------------------
    task.spawn(function()
        while alive and root.Parent do
            refresh()
            task.wait(REFRESH_SECONDS)
        end
    end)

    return {
        Destroy = function()
            alive = false
            for inst in pairs(highlights) do
                clearHighlight(inst)
            end
            root:Destroy()
        end,
    }
end
