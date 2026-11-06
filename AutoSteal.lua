-- BananaHub Beta: Auto Steal (Steal An Egg)
-- Step 1: list every egg currently in the server (and highlight them in the world).
-- Loaded by Main.lua. Returns function(parent, ctx) -> { Destroy = function }

return function(parent, ctx)
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

    local alive = true
    local espEnabled = true
    local highlights = {} -- [Instance] = Highlight
    local MAX_HIGHLIGHTS = 28 -- Roblox only draws ~31 Highlights at once; the rest get a box outline
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
    local sortButton = makeButton("Sort: Near", 96, 254)
    local SORT_MODES = { "Near", "Far", "Most $/s", "Most Rare" }
    local sortMode = 1
    local selectedEgg = nil
    local stealing = false
    local showStealLog -- set after the output box exists

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -356, 0, 24)
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

    local nestOfEgg
    local function areaOf(inst)
        if nestOfEgg and nestOfEgg[inst] then return nestOfEgg[inst] end
        local a = inst
        while a and a.Parent do
            if a.Parent.Name == "GuardAreas" then return a.Name end
            a = a.Parent
        end
        return nil
    end

    -- Nest eggs are not children of the nest: the game renders them elsewhere and
    -- places them on the nest. So find every nest's EggFitBounds / EggSpotBottom box
    -- and treat egg models standing inside one as that nest's egg.
    local function nestSpots()
        local spots = {}
        local ga = guardAreas()
        if not ga then return spots end
        for _, area in ipairs(ga:GetChildren()) do
            for _, d in ipairs(area:GetDescendants()) do
                if d:IsA("BasePart") and (d.Name == "EggFitBounds" or d.Name == "EggSpotBottom") then
                    local nest = d.Parent
                    if not spots[nest] or d.Name == "EggFitBounds" then
                        spots[nest] = { part = d, area = area.Name }
                    end
                end
            end
        end
        local out = {}
        for nest, sp in pairs(spots) do sp.nest = nest; out[#out + 1] = sp end
        return out
    end

    local function spotAt(spots, pos)
        for _, sp in ipairs(spots) do
            local rel = sp.part.CFrame:PointToObjectSpace(pos)
            local half = sp.part.Size / 2
            if math.abs(rel.X) <= half.X + 2 and math.abs(rel.Z) <= half.Z + 2
                and rel.Y >= -half.Y - 2 and rel.Y <= half.Y + 10 then
                return sp
            end
        end
        return nil
    end

    local SKIP_TOP = { World = true, Plots = true, PlacedEggRenders = true, ClientRenderedAssets = true,
        Terrain = true, Camera = true, ClientMountedPets = true }
    nestOfEgg = {} -- [egg] = area name
    local spotOfEgg = {} -- [egg] = nest model (for one-egg-per-nest dedupe)

    local function positionOf(inst)
        if inst:IsA("BasePart") then return inst.Position end
        local ok, cf = pcall(function() return inst:GetPivot() end)
        return ok and cf and cf.Position or nil
    end

    local function looksLikeEggModel(inst)
        if not inst:IsA("Model") then return false end
        if isPlayerStuff(inst) or Players:GetPlayerFromCharacter(inst) then return false end
        if hasEggInName(inst) or matchesEggPattern(inst) or hasPrompt(inst) then return true end
        if inst:FindFirstChild("Hitbox") then return true end
        local attr = inst:GetAttribute("PreparedSourceName")
        return attr ~= nil and string.find(string.lower(tostring(attr)), "egg", 1, true) ~= nil
    end

    local function findEggsByPosition()
        local found = {}
        local spots = nestSpots()
        if #spots == 0 then return found, 0 end
        local seen = {}
        local function scan(container)
            for _, d in ipairs(container:GetDescendants()) do
                if not seen[d] and looksLikeEggModel(d) and not inPen(d) then
                    local pos = positionOf(d)
                    local sp = pos and spotAt(spots, pos)
                    if sp then
                        seen[d] = true
                        for _, dd in ipairs(d:GetDescendants()) do seen[dd] = true end
                        nestOfEgg[d] = sp.area
                        spotOfEgg[d] = sp.nest
                        found[#found + 1] = d
                    end
                end
            end
        end
        for _, top in ipairs(workspace:GetChildren()) do
            if not SKIP_TOP[top.Name] and not Players:GetPlayerFromCharacter(top) then
                if looksLikeEggModel(top) then
                    local pos = positionOf(top)
                    local sp = pos and spotAt(spots, pos)
                    if sp then nestOfEgg[top] = sp.area; spotOfEgg[top] = sp.nest; found[#found + 1] = top; seen[top] = true end
                end
                if not seen[top] then scan(top) end
            end
        end
        -- also models parented inside the GuardAreas but outside the nest meshes
        local ga = guardAreas()
        if ga then
            for _, area in ipairs(ga:GetChildren()) do
                for _, c in ipairs(area:GetChildren()) do
                    if c.Name ~= "Nests" then scan(c) end
                end
            end
        end
        return found, #spots
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

        for _, e in ipairs((findEggsByPosition())) do
            if not set[e] then candidates[#candidates + 1] = e; set[e] = true end
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
        -- One egg per nest: the slot copy (AreaEggSlotsClient) and the real egg model sit on the same nest.
        -- Prefer the one that carries a name label (PreparedSourceName).
        local function score(inst)
            local sc = 0
            if inst:GetAttribute("PreparedSourceName") then sc += 2 end
            for _, d in ipairs(inst:GetDescendants()) do
                if d:GetAttribute("PreparedSourceName") then sc += 1 break end
            end
            return sc
        end
        local bestByNest, out = {}, {}
        for _, inst in ipairs(eggs) do
            local nest = spotOfEgg[inst]
            if nest then
                local cur = bestByNest[nest]
                if not cur or score(inst) > score(cur) then bestByNest[nest] = inst end
            else
                out[#out + 1] = inst
            end
        end
        for _, inst in pairs(bestByNest) do out[#out + 1] = inst end
        return out
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

    ----------------------------------------------------------------
    -- Remote logger: listens to the game's RemoteEvents (read-only) so we can
    -- see which one sends egg names, and learn guid -> name pairs from them.
    ----------------------------------------------------------------
    local remoteLog = {}      -- recent payloads (strings)
    local remoteNames = {}    -- [lower guid] = name seen next to it in a payload
    local remoteConns = {}
    local GUID_PAT = "^%x%x%x%x%x%x%x%x%-?%x%x%x%x%-?%x%x%x%x%-?%x%x%x%x%-?%x%x%x%x%x%x%x%x%x%x%x%x$"
    local function isGuid(v)
        return type(v) == "string" and (string.match(v, GUID_PAT) ~= nil or (#v >= 24 and string.match(v, "^%x+$") ~= nil))
    end
    local function ser(v, depth, budget)
        depth = depth or 0
        local t = typeof(v)
        if t == "string" then return '"' .. string.sub(v, 1, 40) .. '"' end
        if t == "Instance" then return v.Name end
        if t ~= "table" then return tostring(v) end
        if depth > 2 then return "{...}" end
        local parts, n = {}, 0
        for k, x in pairs(v) do
            n += 1
            if n > 8 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. ser(x, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    local function learnNames(v, depth)
        if type(v) ~= "table" or depth > 4 then return end
        local guid, name
        for k, x in pairs(v) do
            if isGuid(x) then guid = x end
            if type(k) == "string" and isGuid(k) and type(x) == "table" then learnNames(x, depth + 1)
                for _, y in pairs(x) do
                    if type(y) == "string" and not isGuid(y) and string.match(y, "%a%a%a") and #y < 40 then
                        remoteNames[string.lower(k)] = remoteNames[string.lower(k)] or y
                        break
                    end
                end
            end
            if type(x) == "string" and not isGuid(x) and string.match(x, "^%u%a+") and #x < 40 then
                local lk = type(k) == "string" and string.lower(k) or ""
                if lk == "" or string.find(lk, "name", 1, true) or string.find(lk, "pet", 1, true)
                    or string.find(lk, "egg", 1, true) or string.find(lk, "type", 1, true) then
                    name = name or x
                end
            end
            if type(x) == "table" then learnNames(x, depth + 1) end
        end
        if guid and name then remoteNames[string.lower((string.gsub(guid, "%-", "")))] = name end
    end
    local function hookRemote(r)
        local ok, conn = pcall(function()
            return r.OnClientEvent:Connect(function(...)
                local args = table.pack(...)
                pcall(function()
                    local strs = {}
                    for i = 1, math.min(args.n, 4) do strs[#strs + 1] = ser(args[i]) end
                    local line = r.Name .. "(" .. table.concat(strs, ", ") .. ")"
                    remoteLog[#remoteLog + 1] = string.sub(line, 1, 220)
                    if #remoteLog > 80 then table.remove(remoteLog, 1) end
                    for i = 1, args.n do learnNames(args[i], 0) end
                    if args.n >= 2 and isGuid(args[1]) and type(args[2]) == "string" then
                        remoteNames[string.lower((string.gsub(args[1], "%-", "")))] = args[2]
                    end
                end)
            end)
        end)
        if ok and conn then remoteConns[#remoteConns + 1] = conn end
    end
    pcall(function()
        for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") then hookRemote(d) end
        end
    end)

    ----------------------------------------------------------------
    -- Proximity prompts (for naming unknown eggs and for stealing)
    ----------------------------------------------------------------
    local promptCache, promptCacheAt = {}, 0
    local function promptPos(pp)
        local p = pp.Parent
        if not p then return nil end
        if p:IsA("BasePart") then return p.Position end
        if p:IsA("Attachment") then return p.WorldPosition end
        return positionOf(p)
    end
    local function allPrompts()
        if os.clock() - promptCacheAt < 10 then return promptCache end
        promptCacheAt = os.clock()
        promptCache = {}
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and not inPen(d) then promptCache[#promptCache + 1] = d end
        end
        return promptCache
    end
    local function promptFor(inst, radius)
        local own = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
        if own then return own end
        local pos = positionOf(inst)
        if not pos then return nil end
        local best, bestD = nil, radius or 14
        for _, pp in ipairs(allPrompts()) do
            if pp.Parent then
                local pp_pos = promptPos(pp)
                local d = pp_pos and (pp_pos - pos).Magnitude
                if d and d < bestD then best, bestD = pp, d end
            end
        end
        return best
    end
    local PROMPT_WORDS = { steal = true, take = true, grab = true, pick = true, ["pick up"] = true, hatch = true, egg = true, [""] = true }
    local function promptName(inst)
        local pp = promptFor(inst, 10)
        if not pp then return nil end
        for _, t in ipairs({ pp.ObjectText, pp.ActionText }) do
            if type(t) == "string" and not PROMPT_WORDS[string.lower(t)] and string.match(t, "%a%a") then
                return t
            end
        end
        return nil
    end

    ----------------------------------------------------------------
    -- $/s and rarity, read from whatever the egg exposes
    ----------------------------------------------------------------
    local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qd = 1e15, qi = 1e18 }
    local function parseNum(numStr, suf)
        local n = tonumber((string.gsub(numStr or "", ",", "")))
        if not n then return nil end
        return n * (SUFFIX[string.lower(suf or "")] or 1)
    end
    local function perSecFromText(t)
        if type(t) ~= "string" then return nil end
        local num, suf = string.match(t, "([%d%.,]+)%s*(%a?%a?)%s*/%s*s")
        if not num then num, suf = string.match(t, "([%d%.,]+)%s*(%a?%a?)%s*per%s*sec") end
        return num and parseNum(num, suf)
    end
    local RARITY_RANK = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, mythic = 6, mythical = 6,
        secret = 7, divine = 8, celestial = 8, cosmic = 8, exclusive = 9, godly = 9, og = 10, limited = 9 }
    local function rarityFromText(t)
        if type(t) ~= "string" then return nil end
        local low = string.lower(t)
        local big = string.match(low, "1%s*in%s*([%d%.,]+%a?)")
        if big then
            local num, suf = string.match(big, "([%d%.,]+)(%a?)")
            local n = parseNum(num, suf)
            if n and n > 0 then return 100 + math.log10(n) * 10 end
        end
        local pct = string.match(low, "([%d%.]+)%s*%%")
        if pct and tonumber(pct) and tonumber(pct) > 0 then return 100 + math.log10(100 / tonumber(pct)) * 10 end
        local best
        for word, rank in pairs(RARITY_RANK) do
            if string.find(low, word, 1, true) and (not best or rank > best) then best = rank end
        end
        return best
    end
    local function eggStats(inst, contents, rarity)
        local ps, rr = perSecFromText(contents), rarityFromText(rarity) or rarityFromText(contents)
        local function look(obj)
            for k, v in pairs(obj:GetAttributes()) do
                local lk = string.lower(k)
                if not ps and (string.find(lk, "persec", 1, true) or string.find(lk, "income", 1, true)
                    or string.find(lk, "cash", 1, true) or string.find(lk, "money", 1, true) or lk == "rate") then
                    ps = tonumber(v) or perSecFromText(tostring(v)) or ps
                end
                if not rr and (string.find(lk, "odds", 1, true) or string.find(lk, "chance", 1, true)
                    or string.find(lk, "rarity", 1, true) or string.find(lk, "tier", 1, true)) then
                    rr = rarityFromText(tostring(v)) or rr
                end
            end
        end
        look(inst)
        local n = 0
        for _, d in ipairs(inst:GetDescendants()) do
            if ps and rr then break end
            n += 1
            if n > 120 then break end
            look(d)
            if d:IsA("TextLabel") and d.Text ~= "" then
                ps = ps or perSecFromText(d.Text)
                rr = rr or rarityFromText(d.Text)
            end
        end
        return ps, rr
    end

    local meshName
    -- names Blender / the importer gives parts: Cube.003, Plane.002, untitled.054, Meshes/..._0011.004
    local JUNK = { hitbox = true, hitboxweld = true, part = true, model = true, meshpart = true, root = true,
        handle = true, weld = true, attachment = true, primarypart = true, body = true, mesh = true, egg = true,
        eggs = true, assets = true, meshes = true, models = true, cube = true, plane = true, sphere = true,
        cylinder = true, circle = true, icosphere = true, torus = true, cone = true, base = true, top = true,
        bottom = true, shell = true, folder = true, slot = true, slots = true }
    local function isJunkName(n)
        if type(n) ~= "string" or n == "" then return true end
        local low = string.lower(n)
        local stem = string.gsub(low, "[%._%s]*%d+$", "")   -- "cube.003" -> "cube"
        stem = string.gsub(stem, "%.%d+$", "")
        if JUNK[low] or JUNK[stem] then return true end
        if string.find(low, "/", 1, true) or string.find(low, "untitled", 1, true) or string.find(low, "union", 1, true)
            or string.find(low, "boundingbox", 1, true) or string.find(low, "weld", 1, true) then return true end
        if string.match(n, "^%x+$") and #n >= 8 then return true end
        if string.match(n, "^[%d%.%s_]+$") then return true end
        if not string.match(n, "%a%a") then return true end
        return false
    end
    -- MeshId -> template name, built once from ReplicatedStorage / named egg folders
    local meshIndex
    local function buildMeshIndex()
        meshIndex = {}
        local roots = { game:GetService("ReplicatedStorage") }
        for _, c in ipairs(workspace:GetChildren()) do
            if string.find(string.lower(c.Name), "egg", 1, true) and c.Name ~= "PlacedEggRenders" then
                roots[#roots + 1] = c
            end
        end
        for _, root in ipairs(roots) do
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("MeshPart") and d.MeshId ~= "" and not meshIndex[d.MeshId] then
                    -- walk up to the first ancestor whose name is a real name
                    local a = d.Parent
                    while a and a ~= root do
                        local n = a.Name
                        if (a:IsA("Model") or a:IsA("Folder")) and not isJunkName(n) then
                            meshIndex[d.MeshId] = n
                            break
                        end
                        a = a.Parent
                    end
                end
            end
        end
    end
    meshName = function(inst)
        if not meshIndex then pcall(buildMeshIndex) end
        if not meshIndex then return nil end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("MeshPart") and meshIndex[d.MeshId] then return meshIndex[d.MeshId] end
        end
        return nil
    end

    local function hatchName(inst)
        -- PreparedSourceName = "Workspace.NewEnchantedEggs.CelestialSunlion" -> "Celestial Sunlion"
        local function fromPath(v)
            if type(v) ~= "string" or v == "" then return nil end
            local last = string.match(v, "([^%.]+)$") or v
            last = string.gsub(last, "_", " ")
            last = string.gsub(last, "(%l)(%u)", "%1 %2")
            last = string.gsub(last, "(%a)(%d)", "%1 %2")
            if not string.match(last, "%a%a") then return nil end
            return last
        end
        local r = fromPath(inst:GetAttribute("PreparedSourceName"))
        if r then return r end
        for _, d in ipairs(inst:GetDescendants()) do
            r = fromPath(d:GetAttribute("PreparedSourceName"))
            if r then return r end
        end
        -- match the egg's mesh against named egg templates in the game
        local named = meshName(inst)
        if named then return fromPath(named) end
        -- fallback: a child model / mesh with a real name (never Cube.003 / Plane / 001)
        for _, d in ipairs(inst:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("MeshPart")) and not isJunkName(d.Name) then
                return fromPath(d.Name)
            end
        end
        return nil
    end
    local function isIdName(name)
        if string.match(name, "^%x+$") and #name >= 16 then return true end
        local id = string.match(name, "^(%d+)_(%x+)$")
        return id ~= nil
    end
    local function findContents(inst)
        local hn = hatchName(inst)
        if hn then return hn end
        local rn = remoteNames[string.lower((string.gsub(inst.Name, "%-", "")))]
        if rn then return rn end
        local pn = promptName(inst)
        if pn then return pn end
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
            local sorted = table.clone(eggs)
            table.sort(sorted, function(a, b)
                return (distanceTo(a) or math.huge) < (distanceTo(b) or math.huge)
            end)
            for _, egg in ipairs(sorted) do
                keep[egg] = true
                local hh = highlights[egg]
                if hh and hh:IsA("Highlight") then
                    hh.FillColor = (egg == selectedEgg) and Color3.fromRGB(255, 70, 70) or GOLD
                end
                count += 1
                local wantBox = count > MAX_HIGHLIGHTS
                local h = highlights[egg]
                if h and (h:IsA("SelectionBox") ~= wantBox) then
                    clearHighlight(egg)
                end
                if wantBox and not highlights[egg] then
                    local b = Instance.new("SelectionBox")
                    b.Name = "BananaHubEggBox"
                    b.Adornee = egg
                    b.Color3 = GOLD
                    b.LineThickness = 0.08
                    b.SurfaceColor3 = GOLD
                    b.SurfaceTransparency = 0.8
                    local ok = pcall(function() b.Parent = ctx.guiParent end)
                    if not ok or not b.Parent then
                        pcall(function() b.Parent = egg end)
                    end
                    highlights[egg] = b
                end
                if not highlights[egg] then
                    local h = Instance.new("Highlight")
                    h.Name = "BananaHubEgg"
                    h.Adornee = egg
                    h.FillColor = (egg == selectedEgg) and Color3.fromRGB(255, 70, 70) or GOLD
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
    local stealEgg -- defined below

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
        for _, e in ipairs(entries) do
            local ok, ps, rr = pcall(eggStats, e.inst, e.contents, e.rarity)
            if ok then e.perSec, e.rank = ps, rr end
        end
        local mode = SORT_MODES[sortMode]
        table.sort(entries, function(a, b)
            local da, db = a.dist or math.huge, b.dist or math.huge
            if mode == "Far" then
                if da == math.huge or db == math.huge then return da < db end
                return da > db
            end
            if mode == "Most $/s" then
                local pa, pb = a.perSec or -1, b.perSec or -1   -- unknown goes last
                if pa ~= pb then return pa > pb end
            elseif mode == "Most Rare" then
                local ra, rb = a.rank or -1, b.rank or -1
                if ra ~= rb then return ra > rb end
            end
            return da < db
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
            local row = Instance.new("TextButton")
            row.LayoutOrder = i
            row.Size = UDim2.new(1, -6, 0, 30)
            row.BackgroundColor3 = ROW
            row.BorderSizePixel = 0
            row.AutoButtonColor = false
            row.Text = ""
            row.Parent = list

            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 6)
            c.Parent = row

            if e.inst == selectedEgg then
                local stroke = Instance.new("UIStroke")
                stroke.Color = GOLD
                stroke.Thickness = 2
                stroke.Parent = row
            end
            row.Activated:Connect(function()
                selectedEgg = (selectedEgg ~= e.inst) and e.inst or nil
                syncHighlights(lastEggs)
                render(lastEggs)
            end)

            local stealBtn = Instance.new("TextButton")
            stealBtn.AnchorPoint = Vector2.new(1, 0.5)
            stealBtn.Position = UDim2.new(1, -4, 0.5, 0)
            stealBtn.Size = UDim2.new(0, 50, 0, 22)
            stealBtn.BackgroundColor3 = GOLD
            stealBtn.Text = "Steal"
            stealBtn.TextColor3 = Color3.fromRGB(30, 30, 30)
            stealBtn.Font = Enum.Font.GothamBold
            stealBtn.TextSize = 12
            stealBtn.Parent = row
            local sc = Instance.new("UICorner")
            sc.CornerRadius = UDim.new(0, 5)
            sc.Parent = stealBtn
            stealBtn.Activated:Connect(function()
                selectedEgg = e.inst
                if stealEgg then task.spawn(stealEgg, e.inst) end
            end)

            local name = Instance.new("TextLabel")
            name.Position = UDim2.new(0, 8, 0, 0)
            name.Size = UDim2.new(0.5, -8, 1, 0)
            name.BackgroundTransparency = 1
            local kind, _, area = parseName(e.inst.Name)
            local title = prettyKind(kind)
            local rid, rguid = splitRenderName(e.inst.Name)
            if rid or isIdName(e.inst.Name) then
                title = e.contents or "Unknown egg"
                area = ""
            end
            for _, key in ipairs({ "EggName", "EggType", "DisplayName", "PetName" }) do
                local v = e.inst:GetAttribute(key)
                if v ~= nil then title = tostring(v) break end
            end
            if area ~= "" then title = title .. " (" .. area .. ")" end
            if e.rarity then title = title .. " [" .. e.rarity .. "]" end
            if e.contents and e.contents ~= title then title = title .. " -> " .. e.contents end
            name.Text = title
            name.Size = UDim2.new(0.55, -8, 1, 0)
            name.TextColor3 = TEXT
            name.Font = Enum.Font.GothamMedium
            name.TextSize = 12
            name.TextXAlignment = Enum.TextXAlignment.Left
            name.TextTruncate = Enum.TextTruncate.AtEnd
            name.Parent = row

            local info = Instance.new("TextLabel")
            info.AnchorPoint = Vector2.new(1, 0)
            info.Position = UDim2.new(1, -60, 0, 0)
            info.Size = UDim2.new(0.45, -64, 1, 0)
            info.BackgroundTransparency = 1
            local owner = e.owner
            if owner == player.Name then owner = "You" end
            local nestArea = areaOf(e.inst)
            if nestArea then owner = "Nest: " .. nestArea end
            local dist = e.dist and (math.floor(e.dist) .. " studs") or "? studs"
            local extras = ""
            if e.perSec then extras = extras .. "$" .. tostring(math.floor(e.perSec)) .. "/s  |  " end
            info.Text = extras .. (owner or "Unknown owner") .. "  |  " .. dist
            info.TextColor3 = MUTED
            info.Font = Enum.Font.Gotham
            info.TextSize = 11
            info.TextXAlignment = Enum.TextXAlignment.Right
            info.TextTruncate = Enum.TextTruncate.AtEnd
            info.Parent = row
        end

        list.CanvasPosition = savedScroll
    end

    sortButton.MouseButton1Click:Connect(function()
        sortMode = sortMode % #SORT_MODES + 1
        sortButton.Text = "Sort: " .. SORT_MODES[sortMode]
        if lastEggs and #lastEggs > 0 then render(lastEggs) end
    end)

    local function refresh()
        if not alive then return end
        local ok, eggs = pcall(findEggs)
        if not ok then
            status.Text = "Scan error: " .. tostring(eggs)
            return
        end
        lastEggs = eggs
        if selectedEgg and not selectedEgg.Parent then selectedEgg = nil end
        syncHighlights(eggs)
        render(eggs)
    end

    ----------------------------------------------------------------
    -- Steal: teleport to the egg, trigger its prompt, teleport back
    ----------------------------------------------------------------
    local function firePrompt(pp)
        pcall(function() pp.RequiresLineOfSight = false end)
        if fireproximityprompt then
            local ok = pcall(fireproximityprompt, pp)
            if ok then return true, "fireproximityprompt" end
            ok = pcall(fireproximityprompt, pp, 1)
            if ok then return true, "fireproximityprompt" end
        end
        local hold = pp.HoldDuration
        pcall(function() pp.HoldDuration = 0 end)
        local ok = pcall(function()
            pp:InputHoldBegin()
            task.wait(math.max(hold, 0) + 0.1)
            pp:InputHoldEnd()
        end)
        return ok, "InputHoldBegin"
    end

    -- Fast glide (sets the root CFrame every frame, so walls / falling don't stop it)
    local RunService = game:GetService("RunService")
    local TWEEN_SPEED = 110   -- studs per second on the way back
    local WALK_LAST = 14      -- walk this many studs at the end to claim
    local function glide(hrp, target, speed)
        local from = hrp.Position
        local dist = (target - from).Magnitude
        if dist < 0.5 then return end
        local t, total = 0, dist / speed
        while t < total and alive and hrp.Parent do
            t = t + RunService.Heartbeat:Wait()
            local a = math.min(t / total, 1)
            local p = from:Lerp(target, a)
            local look = Vector3.new(target.X, p.Y, target.Z)
            if (look - p).Magnitude > 0.1 then hrp.CFrame = CFrame.lookAt(p, look) else hrp.CFrame = CFrame.new(p) end
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end

    -- Did we pick the egg up? (egg moved into our character, or follows us, or vanished from the nest)
    local function carrying(egg, char, startPos)
        if not egg or not egg.Parent then return true, "egg removed from nest" end
        if egg:IsDescendantOf(char) then return true, "egg inside character" end
        for _, d in ipairs(char:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and string.match(d.Name, "^%x+$") and #d.Name >= 32 then return true, "guid model on character: " .. d.Name end
            if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("RigidConstraint") then
                local other = d.Part1 or d.Part0
                if other and other:IsDescendantOf(egg) then return true, "egg welded to character" end
            end
        end
        -- egg moved away from the nest AND is close to us = we're holding it
        local p = positionOf(egg)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if p and startPos and hrp and (p - startPos).Magnitude > 4 and (p - hrp.Position).Magnitude < 8 then
            return true, "egg follows character"
        end
        return false, nil
    end

    local lastStealLog = {}
    local function fmtV(v) return v and string.format("(%.0f, %.0f, %.0f)", v.X, v.Y, v.Z) or "nil" end

    -- go to a spot: instant teleport, and if the server pulls us back, glide there instead
    local function goTo(hrp, target, log)
        hrp.CFrame = CFrame.new(target)
        pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
        task.wait(0.6)
        local off = (hrp.Position - target).Magnitude
        log[#log + 1] = "TP to " .. fmtV(target) .. " -> 0.6s later " .. string.format("%.1f", off) .. " studs away"
        if off < 8 then return true end
        log[#log + 1] = "  pulled back by server (anti-teleport). Gliding there at 45 studs/s instead"
        glide(hrp, target, 45)
        task.wait(0.6)
        off = (hrp.Position - target).Magnitude
        log[#log + 1] = "  after glide: " .. string.format("%.1f", off) .. " studs away"
        return off < 8
    end

    local function describePrompt(pp)
        return string.format("%s | Action='%s' Object='%s' Hold=%.2f MaxDist=%.0f Enabled=%s",
            pp:GetFullName(), tostring(pp.ActionText), tostring(pp.ObjectText),
            pp.HoldDuration or 0, pp.MaxActivationDistance or 0, tostring(pp.Enabled))
    end

    stealEgg = function(egg)
        if stealing then return end
        stealing = true
        local log = {}
        lastStealLog = log
        local logStart = #remoteLog
        local trigConn
        pcall(function()
            trigConn = game:GetService("ProximityPromptService").PromptTriggered:Connect(function(pp)
                log[#log + 1] = "  PromptTriggered fired: " .. pp:GetFullName()
            end)
        end)
        local got, why = false, nil
        local ok, err = pcall(function()
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum then status.Text = "No character" return end
            if not egg or not egg.Parent then status.Text = "That egg is gone" return end
            local pos = positionOf(egg)
            if not pos then status.Text = "Can't find egg position" return end
            local home = hrp.Position -- stand at your base when you press Steal
            log[#log + 1] = "Egg: " .. egg:GetFullName() .. " at " .. fmtV(pos)
            log[#log + 1] = "Home (where you pressed Steal): " .. fmtV(home)
            local c0, w0 = carrying(egg, char, pos)
            if c0 then log[#log + 1] = "WARNING: carrying-check already true before stealing: " .. tostring(w0) end
            -- nearby prompts
            promptCacheAt = 0
            local near = {}
            for _, p in ipairs(allPrompts()) do
                local pp_pos = promptPos(p)
                if pp_pos and (pp_pos - pos).Magnitude < 25 then near[#near + 1] = { p, (pp_pos - pos).Magnitude } end
            end
            table.sort(near, function(a, b) return a[2] < b[2] end)
            log[#log + 1] = "Prompts within 25 studs of egg: " .. #near
            for i = 1, math.min(#near, 6) do
                log[#log + 1] = string.format("  %.1f studs: ", near[i][2]) .. describePrompt(near[i][1])
            end
            status.Text = "Going to egg..."
            if not goTo(hrp, pos + Vector3.new(0, 3, 0), log) then
                status.Text = "Server keeps pulling me back - see log"
                return
            end
            promptCacheAt = 0
            local pp = promptFor(egg, 18)
            if not pp then status.Text = "No steal prompt at this egg - see log" log[#log + 1] = "No prompt found" return end
            log[#log + 1] = "Using prompt: " .. describePrompt(pp)
            local ppPos = promptPos(pp) or pos
            local stand = ppPos + Vector3.new(0, 2.5, 0)
            hrp.CFrame = CFrame.new(stand + Vector3.new(2, 0, 0), stand)
            task.wait(0.3)
            log[#log + 1] = string.format("Standing %.1f studs from prompt", (hrp.Position - ppPos).Magnitude)
            -- try 1: executor fire
            local fired, how = firePrompt(pp)
            log[#log + 1] = "Try 1: " .. tostring(how) .. " ok=" .. tostring(fired)
            status.Text = "Picking up..."
            local t0 = os.clock()
            while os.clock() - t0 < 2 do
                got, why = carrying(egg, char, pos)
                if got then break end
                task.wait(0.1)
            end
            if not got then
                -- try 2: real hold for the full hold time
                local hold = pp.HoldDuration or 0
                local ok2, e2 = pcall(function()
                    pp:InputHoldBegin()
                    task.wait(hold + 0.3)
                    pp:InputHoldEnd()
                end)
                log[#log + 1] = "Try 2: InputHoldBegin " .. string.format("%.2f", hold + 0.3) .. "s ok=" .. tostring(ok2) .. (e2 and (" err=" .. tostring(e2)) or "")
                local t1 = os.clock()
                while os.clock() - t1 < 1.5 do
                    got, why = carrying(egg, char, pos)
                    if got then break end
                    task.wait(0.1)
                end
            end
            log[#log + 1] = "Picked up: " .. tostring(got) .. (why and (" (" .. why .. ")") or "")
            if not got then
                status.Text = "Didn't pick it up - try pressing E yourself now, then tell me"
                return -- stay here so you can test the prompt by hand
            end
            status.Text = "Got it! Gliding back..."
            local h2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local hum2 = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if not h2 or not hum2 then return end
            local flat = Vector3.new(home.X - h2.Position.X, 0, home.Z - h2.Position.Z)
            local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
            local before = home - dir * WALK_LAST
            glide(h2, h2.Position + Vector3.new(0, 6, 0), TWEEN_SPEED)
            glide(h2, Vector3.new(before.X, home.Y + 6, before.Z), TWEEN_SPEED)
            glide(h2, Vector3.new(before.X, home.Y, before.Z), TWEEN_SPEED)
            log[#log + 1] = "Glided back, now " .. string.format("%.1f", (h2.Position - before).Magnitude) .. " studs from target"
            status.Text = "Walking in to claim..."
            hum2:MoveTo(home)
            local done = false
            local c = hum2.MoveToFinished:Connect(function() done = true end)
            local t2 = os.clock()
            while not done and os.clock() - t2 < 4 do task.wait(0.1) end
            c:Disconnect()
            log[#log + 1] = "Walked in, " .. string.format("%.1f", (h2.Position - home).Magnitude) .. " studs from home"
            status.Text = "Stolen - walked into base"
        end)
        if trigConn then trigConn:Disconnect() end
        if not ok then status.Text = "Steal error: " .. tostring(err) log[#log + 1] = "ERROR: " .. tostring(err) end
        log[#log + 1] = "Remote events during steal:"
        local any = false
        for i = math.max(logStart + 1, #remoteLog - 15), #remoteLog do
            if remoteLog[i] then log[#log + 1] = "  " .. remoteLog[i] any = true end
        end
        if not any then log[#log + 1] = "  (none)" end
        stealing = false
        if not got and showStealLog then showStealLog() end
        task.delay(1, function() if alive then refresh() end end)
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
    showStealLog = function()
        showOutput("Steal log v9 (screenshot this)", table.concat(lastStealLog, "\n"))
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
        local lines = { "BananaHub DEEP debug v7 - GameId " .. tostring(game.GameId) }
        -- names learned from remotes + prompts at the first unknown eggs
        local learned = 0
        for _ in pairs(remoteNames) do learned += 1 end
        lines[#lines + 1] = "Remotes hooked: " .. #remoteConns .. " | guid names learned: " .. learned
        promptCacheAt = 0
        local shownP = 0
        for _, egg in ipairs(lastEggs) do
            if shownP >= 6 then break end
            if not hatchName(egg) then
                shownP += 1
                local pp = promptFor(egg, 16)
                if pp then
                    local pp_pos = promptPos(pp)
                    local d = pp_pos and positionOf(egg) and math.floor((pp_pos - positionOf(egg)).Magnitude) or "?"
                    local at = {}
                    for k, v in pairs(pp:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v) end
                    lines[#lines + 1] = "PROMPT " .. egg.Name:sub(1, 8) .. " obj='" .. pp.ObjectText .. "' act='" .. pp.ActionText
                        .. "' hold=" .. pp.HoldDuration .. " d=" .. tostring(d) .. " at " .. pp:GetFullName() .. " " .. table.concat(at, ",")
                else
                    lines[#lines + 1] = "PROMPT " .. egg.Name:sub(1, 8) .. " none within 16 studs"
                end
            end
        end
        lines[#lines + 1] = "== Last remote events (newest last, max 25)"
        for i = math.max(1, #remoteLog - 24), #remoteLog do lines[#lines + 1] = "  " .. remoteLog[i] end
        if #remoteLog == 0 then lines[#lines + 1] = "  (none yet - walk around / wait for eggs to spawn, then press Deep again)" end
        local remotes = {}
        for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and #remotes < 40 then remotes[#remotes + 1] = d.Name end
        end
        lines[#lines + 1] = "== Remotes: " .. table.concat(remotes, ", ")
        local spots = nestSpots()
        lines[#lines + 1] = "Nest spots: " .. #spots
        for i, egg in ipairs(lastEggs) do
            if i > 3 then break end
            local at = {}
            for k, v in pairs(egg:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v) end
            lines[#lines + 1] = "EGG" .. i .. " " .. egg:GetFullName() .. " | " .. table.concat(at, ", ")
        end
        -- full look inside the first egg that has no name label
        for _, egg in ipairs(lastEggs) do
            if egg:GetAttribute("PreparedSourceName") == nil then
                lines[#lines + 1] = "NONAME " .. egg:GetFullName()
                local n = 0
                for _, d in ipairs(egg:GetDescendants()) do
                    if n >= 25 then lines[#lines + 1] = "   ..." break end
                    n += 1
                    local extra = {}
                    for k, v in pairs(d:GetAttributes()) do extra[#extra + 1] = k .. "=" .. tostring(v) end
                    if d:IsA("MeshPart") then extra[#extra + 1] = "mesh=" .. tostring(d.MeshId) end
                    if d:IsA("BasePart") then extra[#extra + 1] = "color=" .. tostring(d.BrickColor) end
                    if d:IsA("ValueBase") then extra[#extra + 1] = "value=" .. tostring(d.Value) end
                    lines[#lines + 1] = "   " .. d:GetFullName():sub(#egg:GetFullName() + 2) .. " (" .. d.ClassName .. ") " .. table.concat(extra, ", ")
                end
                break
            end
        end
        -- What is standing near the nests? (any model, any folder)
        local near, shownNear = {}, 0
        if #spots > 0 then
            for _, d in ipairs(workspace:GetDescendants()) do
                if shownNear >= 12 then break end
                if d:IsA("Model") and not d:IsDescendantOf(spots[1].part.Parent.Parent) then
                    local inNest = false
                    local a = d
                    while a do if a.Name == "NestModel" then inNest = true break end a = a.Parent end
                    if not inNest and not Players:GetPlayerFromCharacter(d) then
                        local pos = positionOf(d)
                        local sp = pos and spotAt(spots, pos)
                        if sp and not near[d.Parent] then
                            near[d.Parent] = true
                            shownNear += 1
                            lines[#lines + 1] = "  NEAR " .. sp.area .. ": " .. d:GetFullName() .. " (" .. #d:GetChildren() .. " ch)"
                        end
                    end
                end
            end
        end
        if shownNear == 0 then lines[#lines + 1] = "  nothing found standing in any nest" end
        local slots = workspace:FindFirstChild("AreaEggSlotsClient", true)
        lines[#lines + 1] = "== AreaEggSlotsClient " .. (slots and slots:GetFullName() or "MISSING")
        if slots then
            describe(slots, lines, 2)
            for i, c in ipairs(slots:GetChildren()) do
                if i > 3 then break end
                describe(c, lines, 4)
                for j, cc in ipairs(c:GetChildren()) do
                    if j > 3 then break end
                    describe(cc, lines, 6)
                end
            end
        end
        local sp1 = spots[1]
        if sp1 then
            lines[#lines + 1] = "  spot1 " .. sp1.area .. " " .. sp1.part.Name .. " pos " .. tostring(sp1.part.Position) .. " size " .. tostring(sp1.part.Size)
            lines[#lines + 1] = "  nest attrs:"
            for k, v in pairs(sp1.nest:GetAttributes()) do lines[#lines + 1] = "    " .. k .. "=" .. tostring(v) end
            local nests = sp1.nest.Parent
            for k, v in pairs(nests:GetAttributes()) do lines[#lines + 1] = "    Nests." .. k .. "=" .. tostring(v) end
        end
        lines[#lines + 1] = "Stealable found: " .. #lastEggs
        for i, e in ipairs(lastEggs) do
            if i > 5 then break end
            lines[#lines + 1] = "  " .. e:GetFullName():gsub("^Workspace%.World%.Areas%.", "") .. " (" .. e.ClassName .. ")"
        end
        local ga = guardAreas()
        lines[#lines + 1] = "== GuardAreas " .. (ga and ("(" .. #ga:GetChildren() .. " areas)") or "MISSING")
        if ga then
            for ai, area in ipairs(ga:GetChildren()) do
                if ai > 13 then break end
                local nests = area:FindFirstChild("Nests", true)
                lines[#lines + 1] = " AREA " .. area.Name .. " nests=" .. tostring(nests and #nests:GetChildren())
                if nests and false then
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
        showOutput("Deep v7", table.concat(lines, "\n"))
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
            for _, cn in ipairs(remoteConns) do pcall(function() cn:Disconnect() end) end
            for inst in pairs(highlights) do
                clearHighlight(inst)
            end
            root:Destroy()
        end,
    }
end
