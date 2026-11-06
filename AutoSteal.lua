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
    local deepButton = makeButton("Deep", 48, 200)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -255, 0, 24)
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
        return (inst:IsA("Folder") or inst:IsA("Model")) and (n == "eggs" or n == "placedeggrenders")
            and inst.Parent == workspace
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
    local BAD_ANCESTORS = { "machines", "areaeggslotsclient", "__clienttreadmillrenders", "treadmills", "halloweeneggholders" }
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

    -- Stealable eggs live in the guarded nests: Workspace.World.Areas.GuardAreas.<Area>.Nests
    -- Pen eggs (PlacedEggRenders / Plots) belong to players and are NOT listed.
    local function guardAreas()
        local world = workspace:FindFirstChild("World")
        local areas = world and world:FindFirstChild("Areas")
        return areas and areas:FindFirstChild("GuardAreas")
    end

    local function inPen(inst)
        local per = workspace:FindFirstChild("PlacedEggRenders")
        local plots = workspace:FindFirstChild("Plots")
        return (per and inst:IsDescendantOf(per)) or (plots and inst:IsDescendantOf(plots)) or false
    end

    local function hasPrompt(inst)
        if inst:IsA("BasePart") and inst:FindFirstChildOfClass("ProximityPrompt") then return true end
        return inst:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
    end

    -- Nest helper parts (bounds, spots, points) are not eggs.
    local NEST_JUNK = { "fitbounds", "spotbottom", "eggpoint", "eggspot", "bounds", "spawn", "nestmodel", "nests", "hitbox" }
    local function isNestJunk(inst)
        local n = string.lower(inst.Name)
        for _, j in ipairs(NEST_JUNK) do
            if n == j or string.find(n, j, 1, true) == 1 then return true end
        end
        return false
    end

    local function isNestEgg(inst)
        if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
        if isNestJunk(inst) or inPen(inst) or isPlayerStuff(inst) then return false end
        if matchesEggPattern(inst) then return true end
        if hasEggInName(inst) and not isJunk(inst) then return true end
        -- An unnamed model sitting in a nest with a steal prompt.
        return inst:IsA("Model") and hasPrompt(inst)
    end

    local function areaOf(inst)
        local a = inst
        while a and a.Parent do
            if a.Parent.Name == "GuardAreas" then return a.Name end
            a = a.Parent
        end
        return nil
    end

    local function findEggs()
        local candidates, set = {}, {}
        local function consider(inst)
            if not set[inst] and isNestEgg(inst) then
                candidates[#candidates + 1] = inst
                set[inst] = true
            end
        end
        local ga = guardAreas()
        if ga then
            for _, area in ipairs(ga:GetChildren()) do
                for _, nests in ipairs(area:GetDescendants()) do
                    if nests.Name == "Nests" then
                        for _, d in ipairs(nests:GetDescendants()) do consider(d) end
                    end
                end
            end
        end
        -- Loose eggs folder (eggs dropped / spawned in the world, not in a pen)
        local loose = workspace:FindFirstChild("Eggs")
        if loose then
            for _, c in ipairs(loose:GetChildren()) do consider(c) end
        end

        -- Keep only the top-most match so a model and its parts aren't listed separately.
        local eggs = {}
        for _, inst in ipairs(candidates) do
            local ancestor = inst.Parent
            local nested = false
            while ancestor and ancestor ~= workspace do
                if set[ancestor] then nested = true break end
                ancestor = ancestor.Parent
            end
            if not nested then eggs[#eggs + 1] = inst end
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

    local nameCache = {} -- [userId] = name | false (pending)
    local function nameFromUserId(id)
        local p = Players:GetPlayerByUserId(id)
        if p then return p.Name end
        if nameCache[id] then return nameCache[id] end
        if nameCache[id] == nil then
            nameCache[id] = false
            task.spawn(function()
                local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
                nameCache[id] = ok and n or ("User " .. id)
            end)
        end
        return nil
    end

    -- PlacedEggRenders children are named "<OwnerUserId>_<32 hex guid>"
    local function splitRenderName(name)
        local id, guid = string.match(name, "^(%d+)_(%x+)$")
        if id and #guid >= 16 then return tonumber(id), guid end
        return nil, nil
    end

    local function findOwner(inst)
        local uid = splitRenderName(inst.Name)
        if uid then return nameFromUserId(uid) end
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

    local function petInfo(model)
        local data = model:FindFirstChild("Data")
        local function txt(n)
            local l = data and data:FindFirstChild(n, true)
            return l and l:IsA("TextLabel") and l.Text ~= "" and l.Text or nil
        end
        local name = txt("DisplayName") or model:GetAttribute("OriginalName")
        if not name then return nil end
        local extra = {}
        local odds, ps = txt("Odds"), txt("PerSecond")
        if odds then extra[#extra + 1] = odds end
        if ps then extra[#extra + 1] = ps end
        if #extra > 0 then name = name .. " (" .. table.concat(extra, ", ") .. ")" end
        return tostring(name)
    end

    local function findPetByGuid(guid)
        local cra = workspace:FindFirstChild("ClientRenderedAssets")
        if not cra or not guid then return nil end
        local lg = string.lower(guid)
        for _, m in ipairs(cra:GetChildren()) do
            local uid = m:GetAttribute("UID")
            if (uid and string.lower(tostring(uid)) == lg) or string.find(string.lower(m.Name), lg, 1, true) then
                return petInfo(m)
            end
        end
        return nil
    end

    local function findContents(inst)
        local _, guid = splitRenderName(inst.Name)
        local byGuid = findPetByGuid(guid)
        if byGuid then return byGuid end
        for _, d in ipairs(inst:GetDescendants()) do
            for k, v in pairs(d:GetAttributes()) do
                if keyMatches(k) or k == "OriginalName" or k == "DisplayName" then return tostring(v) end
            end
        end
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
            status.Text = "No stealable eggs found"
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 60)
            empty.BackgroundTransparency = 1
            empty.Text = "No eggs in the guarded nests right now.\nPress Deep and screenshot the box that opens."
            empty.TextColor3 = MUTED
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 12
            empty.TextWrapped = true
            empty.Parent = list
            return
        end

        status.Text = ("Stealable eggs: %d"):format(#entries)

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
            local rid, rguid = splitRenderName(e.inst.Name)
            if rid then
                title = "Egg " .. i
                area = ""
            end
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
            local nestArea = areaOf(e.inst)
            if nestArea then owner = "Nest: " .. nestArea end
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
    -- Output box (selectable text, because clipboard may not work)
    ----------------------------------------------------------------
    local function tryClipboard(text)
        local fns = {}
        if setclipboard then fns[#fns + 1] = setclipboard end
        if toclipboard then fns[#fns + 1] = toclipboard end
        if setrbxclipboard then fns[#fns + 1] = setrbxclipboard end
        if Clipboard and type(Clipboard) == "table" and Clipboard.set then fns[#fns + 1] = Clipboard.set end
        for _, f in ipairs(fns) do
            if pcall(f, text) then return true end
        end
        return false
    end

    local overlay = Instance.new("Frame")
    overlay.Name = "Output"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 50
    overlay.Visible = false
    overlay.Parent = root

    local outTitle = Instance.new("TextLabel")
    outTitle.Size = UDim2.new(1, -150, 0, 24)
    outTitle.BackgroundTransparency = 1
    outTitle.TextColor3 = TEXT
    outTitle.Font = Enum.Font.GothamMedium
    outTitle.TextSize = 12
    outTitle.TextXAlignment = Enum.TextXAlignment.Left
    outTitle.TextTruncate = Enum.TextTruncate.AtEnd
    outTitle.ZIndex = 51
    outTitle.Parent = overlay

    local function overlayButton(text, xOffset)
        local b = makeButton(text, 64, xOffset)
        b.Parent = overlay
        b.ZIndex = 52
        return b
    end
    local closeOut = overlayButton("Close", 0)
    local copyOut = overlayButton("Copy", 70)

    local outScroll = Instance.new("ScrollingFrame")
    outScroll.Position = UDim2.new(0, 0, 0, 30)
    outScroll.Size = UDim2.new(1, 0, 1, -30)
    outScroll.BackgroundColor3 = ROW
    outScroll.BorderSizePixel = 0
    outScroll.ScrollBarThickness = 6
    outScroll.ScrollBarImageColor3 = GOLD
    outScroll.CanvasSize = UDim2.new()
    outScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    outScroll.ZIndex = 51
    outScroll.Parent = overlay

    local outBox = Instance.new("TextBox")
    outBox.Size = UDim2.new(1, -10, 0, 0)
    outBox.Position = UDim2.new(0, 4, 0, 2)
    outBox.AutomaticSize = Enum.AutomaticSize.Y
    outBox.BackgroundTransparency = 1
    outBox.MultiLine = true
    outBox.ClearTextOnFocus = false
    pcall(function() outBox.TextEditable = true end)
    outBox.TextWrapped = true
    outBox.TextXAlignment = Enum.TextXAlignment.Left
    outBox.TextYAlignment = Enum.TextYAlignment.Top
    outBox.Font = Enum.Font.Code
    outBox.TextSize = 11
    outBox.TextColor3 = Color3.fromRGB(230, 230, 230)
    outBox.ZIndex = 52
    outBox.Parent = outScroll

    local outText = ""
    local function showOutput(title, text)
        outText = text
        -- keep the box light: first 150 lines on screen, full text in console
        local shown, n = {}, 0
        for line in string.gmatch(text .. "\n", "(.-)\n") do
            n += 1
            if n <= 150 then shown[#shown + 1] = line end
        end
        outBox.Text = table.concat(shown, "\n")
        outScroll.CanvasPosition = Vector2.new(0, 0)
        local copied = tryClipboard(text)
        outTitle.Text = title .. (copied and "  (copied)" or "  (copy failed - screenshot this)")
        overlay.Visible = true
        print(text)
    end

    closeOut.Activated:Connect(function() overlay.Visible = false end)
    copyOut.Activated:Connect(function()
        local ok = tryClipboard(outText)
        copyOut.Text = ok and "Copied!" or "Failed"
        task.delay(1.5, function() if copyOut.Parent then copyOut.Text = "Copy" end end)
    end)

    ----------------------------------------------------------------
    -- Buttons
    ----------------------------------------------------------------
    local function connect(button, fn)
        button.Activated:Connect(function()
            local ok, err = pcall(fn)
            if not ok then
                showOutput("Error", "BananaHub error:\n" .. tostring(err))
            end
        end)
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
        showOutput("Debug", table.concat(lines, "\n"))
    end)


    ----------------------------------------------------------------
    -- Deep debug: inspect the places where real eggs probably live
    ----------------------------------------------------------------
    local function describe(inst, lines, indent)
        local pre = string.rep(" ", indent)
        lines[#lines + 1] = pre .. inst.Name .. " (" .. inst.ClassName .. ")"
        local n = 0
        for k, v in pairs(inst:GetAttributes()) do
            if n < 12 then lines[#lines + 1] = pre .. "  attr " .. k .. " = " .. tostring(v) end
            n += 1
        end
        local cnt = 0
        for _, d in ipairs(inst:GetDescendants()) do
            if cnt >= 14 then lines[#lines + 1] = pre .. "  ..." break end
            if d:IsA("ValueBase") then
                lines[#lines + 1] = pre .. "  value " .. d:GetFullName():sub(#inst:GetFullName() + 2) .. " = " .. tostring(d.Value); cnt += 1
            elseif d:IsA("TextLabel") or d:IsA("TextButton") then
                if d.Text ~= "" then lines[#lines + 1] = pre .. "  text " .. d.Name .. " = " .. d.Text; cnt += 1 end
            elseif d:IsA("ProximityPrompt") then
                lines[#lines + 1] = pre .. "  prompt " .. d.ActionText .. " / " .. d.ObjectText; cnt += 1
            elseif d:IsA("ClickDetector") then
                lines[#lines + 1] = pre .. "  clickdetector"; cnt += 1
            end
        end
        local names = {}
        for i, c in ipairs(inst:GetChildren()) do
            if i > 12 then names[#names + 1] = "..." break end
            names[#names + 1] = c.Name .. ":" .. c.ClassName
        end
        lines[#lines + 1] = pre .. "  children(" .. #inst:GetChildren() .. ") " .. table.concat(names, ", ")
    end

    local function deepDebug()
        local lines = { "BananaHub DEEP debug v3 - GameId " .. tostring(game.GameId) }
        lines[#lines + 1] = "Stealable found: " .. #lastEggs
        for i, e in ipairs(lastEggs) do
            if i > 5 then break end
            lines[#lines + 1] = "  " .. e:GetFullName():gsub("^Workspace%.World%.Areas%.", "") .. " (" .. e.ClassName .. ")"
        end
        local ga = guardAreas()
        lines[#lines + 1] = "== GuardAreas " .. (ga and ("(" .. #ga:GetChildren() .. " areas)") or "MISSING")
        if ga then
            for ai, area in ipairs(ga:GetChildren()) do
                if ai > 2 then break end
                local nests = area:FindFirstChild("Nests", true)
                lines[#lines + 1] = " AREA " .. area.Name .. " nests=" .. tostring(nests and #nests:GetChildren())
                if nests then
                    for ni, nest in ipairs(nests:GetChildren()) do
                        if ni > 2 then break end
                        describe(nest, lines, 2)
                        for ci, c in ipairs(nest:GetChildren()) do
                            if ci > 6 then break end
                            describe(c, lines, 4)
                        end
                    end
                end
            end
        end
        local per = workspace:FindFirstChild("PlacedEggRenders")
        lines[#lines + 1] = "== PlacedEggRenders full (" .. (per and #per:GetChildren() or 0) .. ")"
        if per then
            for i, egg in ipairs(per:GetChildren()) do
                if i > 3 then break end
                local uid, guid = splitRenderName(egg.Name)
                lines[#lines + 1] = "EGG " .. egg.Name .. " owner=" .. tostring(uid and nameFromUserId(uid))
                for k, v in pairs(egg:GetAttributes()) do lines[#lines + 1] = "  attr " .. k .. "=" .. tostring(v) end
                local c = 0
                for _, d in ipairs(egg:GetDescendants()) do
                    if c >= 10 then break end
                    c += 1
                    local extra = ""
                    if d:IsA("MeshPart") then extra = " mesh=" .. d.MeshId .. " tex=" .. d.TextureID end
                    if d:IsA("BasePart") then extra = extra .. " color=" .. tostring(d.BrickColor) end
                    for k, v in pairs(d:GetAttributes()) do extra = extra .. " @" .. k .. "=" .. tostring(v) end
                    lines[#lines + 1] = "  " .. d.Name .. ":" .. d.ClassName .. extra
                end
                -- does the guid appear anywhere else?
                local hits = 0
                if guid then
                    local lg = string.lower(guid)
                    for _, svc in ipairs({ workspace, game:GetService("ReplicatedStorage"), player }) do
                        for _, d in ipairs(svc:GetDescendants()) do
                            if hits >= 4 then break end
                            if d ~= egg and not d:IsDescendantOf(egg) then
                                local hit = string.find(string.lower(d.Name), lg, 1, true)
                                if not hit then
                                    for k, v in pairs(d:GetAttributes()) do
                                        if string.find(string.lower(tostring(v)), lg, 1, true) then hit = true; break end
                                    end
                                end
                                if not hit and d:IsA("StringValue") and string.find(string.lower(d.Value), lg, 1, true) then hit = true end
                                if hit then hits += 1; lines[#lines + 1] = "  GUID HIT " .. d:GetFullName() .. " (" .. d.ClassName .. ")" end
                            end
                        end
                    end
                end
                if hits == 0 then lines[#lines + 1] = "  guid not found elsewhere" end
            end
        end
        for _, folderName in ipairs({ "Eggs", "PlacedEggRenders", "ClientRenderedAssets", "Plots", "Stands", "ClientMountedPets" }) do
            local f = workspace:FindFirstChild(folderName)
            lines[#lines + 1] = "== Workspace." .. folderName .. (f and (" (" .. #f:GetChildren() .. " children)") or " MISSING")
            if f then
                for i, c in ipairs(f:GetChildren()) do
                    if i > 3 then break end
                    describe(c, lines, 2)
                end
            end
        end
        -- SmartPromptPart samples (57 egg-named ones exist)
        local spp = workspace:FindFirstChild("SmartPromptPart")
        lines[#lines + 1] = "== SmartPromptPart samples"
        local shown = 0
        for _, c in ipairs(workspace:GetChildren()) do
            if c.Name == "SmartPromptPart" and shown < 2 then
                shown += 1
                describe(c, lines, 2)
            end
        end
        -- ReplicatedStorage: names that look like egg / pet data
        local RS = game:GetService("ReplicatedStorage")
        lines[#lines + 1] = "== ReplicatedStorage top-level: "
        local top = {}
        for _, c in ipairs(RS:GetChildren()) do top[#top + 1] = c.Name .. ":" .. c.ClassName end
        lines[#lines + 1] = "  " .. table.concat(top, ", ")
        local hits = 0
        lines[#lines + 1] = "== ReplicatedStorage egg/pet-ish names (max 30)"
        for _, d in ipairs(RS:GetDescendants()) do
            local n = string.lower(d.Name)
            if (string.find(n, "egg", 1, true) or string.find(n, "pet", 1, true) or string.find(n, "hatch", 1, true)) and hits < 30 then
                hits += 1
                lines[#lines + 1] = "  " .. d:GetFullName():gsub("^ReplicatedStorage%.", "") .. " (" .. d.ClassName .. ")"
            end
        end
        showOutput("Deep v3", table.concat(lines, "\n"))
    end

    connect(deepButton, deepDebug)

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
