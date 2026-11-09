local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera
local mouse = lp:GetMouse()

local DEFAULTS = {
    ESP = false, Aim = false, Trigger = false, Silent = false,
    TeamCheck = false, MaxDistance = 700,
    AimFov = 55, SmoothSpeed = 18,
    TriggerDelay = 60, TriggerRange = 120,
    SilentSize = 6,
}

local Config = {}
for k, v in pairs(DEFAULTS) do Config[k] = v end

local EnemyColor = Color3.fromRGB(255, 55, 55)
local AllyColor = Color3.fromRGB(70, 160, 255)
local BoxColor = Color3.fromRGB(255, 35, 35)
local BoxFlash = Color3.fromRGB(40, 255, 120)

local GREEN = Color3.fromRGB(0, 90, 60)
local BLUE = Color3.fromRGB(30, 90, 190)
local DARK = Color3.fromRGB(22, 22, 28)

local gui = Instance.new("ScreenGui")
gui.Name = "ESP_Gui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = lp:WaitForChild("PlayerGui")

local ESP = {}
local conns = {}
local silData = {}
local boxOwner = {}
local skipHook = false
local lastClick = 0
local adsDown = false
local touchCount = 0

local function isEnemy(plr)
    if plr == lp then return false end
    if plr.Team and plr.Team.Name:lower():find("spect") then return false end
    if Config.TeamCheck and plr.Team and lp.Team then
        return plr.Team ~= lp.Team
    end
    return true
end

local function getChar(plr)
    local char = plr.Character
    if char and char.Parent and char:FindFirstChildOfClass("Humanoid") then return char end
    local alt = workspace:FindFirstChild(plr.Name)
    if alt and alt:FindFirstChildOfClass("Humanoid") then return alt end
    return nil
end

local function modelCenter(char)
    local ok, cf, size = pcall(function() return char:GetBoundingBox() end)
    if ok and cf then return cf.Position, size end
    return nil, nil
end

local function removeESP(plr)
    local d = ESP[plr]
    if not d then return end
    if d.highlight then d.highlight:Destroy() end
    if d.billboard then d.billboard:Destroy() end
    ESP[plr] = nil
end

local function createESP(plr)
    removeESP(plr)
    local d = {}

    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.75
    hl.OutlineTransparency = 0
    hl.OutlineColor = EnemyColor
    hl.FillColor = EnemyColor
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = gui
    d.highlight = hl

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(190, 46)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = Config.MaxDistance
    bb.Enabled = false
    bb.Parent = gui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0.55, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0
    label.TextSize = 13
    label.Font = Enum.Font.GothamBold
    label.Text = plr.Name
    label.Parent = bb

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(0.6, 0, 0.12, 0)
    barBg.Position = UDim2.new(0.2, 0, 0.62, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    barBg.BorderSizePixel = 0
    barBg.Parent = bb

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(60, 255, 90)
    bar.BorderSizePixel = 0
    bar.Parent = barBg

    d.billboard = bb
    d.label = label
    d.bar = bar
    ESP[plr] = d
end

local function updateESP(plr, d)
    local char = getChar(plr)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    local ok = Config.ESP and hrp and hum and hum.Health > 0 and isEnemy(plr)

    local dist = 0
    if ok then
        dist = (cam.CFrame.Position - hrp.Position).Magnitude
        if dist > Config.MaxDistance then ok = false end
    end

    local color = isEnemy(plr) and EnemyColor or AllyColor

    if d.highlight then
        d.highlight.Adornee = ok and char or nil
        d.highlight.OutlineColor = color
        d.highlight.FillColor = color
    end

    if d.billboard then
        if ok then
            local center, size = modelCenter(char)
            local topY = center and (center.Y + (size and size.Y / 2 or 2)) or (hrp.Position.Y + 2)
            d.billboard.Adornee = hrp
            d.billboard.StudsOffsetWorldSpace = Vector3.new(0, topY - hrp.Position.Y + 0.4, 0)
            d.billboard.MaxDistance = Config.MaxDistance
            d.billboard.Enabled = true
            d.label.Text = string.format("%s [%d]", plr.Name, dist)
            local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            d.bar.Size = UDim2.new(pct, 0, 1, 0)
            d.bar.BackgroundColor3 = Color3.fromRGB(
                math.floor(255 * (1 - pct)), math.floor(255 * pct), 60)
        else
            d.billboard.Enabled = false
        end
    end
end

local function track(plr)
    if plr == lp then return end
    createESP(plr)
    conns[plr] = plr.CharacterAdded:Connect(function()
        restoreSilent(plr)
        task.wait(0.4)
        createESP(plr)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do track(p) end
Players.PlayerAdded:Connect(track)

local function boxSize(s)
    return Vector3.new(s, s * 1.5, s)
end

local function buildBox(plr, char, hrp)
    local old = char:FindFirstChild("MileiHitbox")
    if old then old:Destroy() end

    local box = Instance.new("Part")
    box.Name = "MileiHitbox"
    box.Size = boxSize(Config.SilentSize)
    box.Color = BoxColor
    box.Material = Enum.Material.SmoothPlastic
    box.Transparency = 0.35
    box.CanCollide = false
    box.CanTouch = false
    box.CanQuery = true
    box.CastShadow = false
    box.Massless = true
    box.Anchored = true
    box.CFrame = CFrame.new(hrp.Position)
    box.Parent = char

    local outline = Instance.new("SelectionBox")
    outline.Name = "Outline"
    outline.Adornee = box
    outline.LineThickness = 0.05
    outline.Color3 = BoxColor
    outline.SurfaceTransparency = 1
    outline.AlwaysOnTop = true
    outline.Parent = box

    boxOwner[box] = plr
    return box
end

local function restoreSilent(plr)
    local d = silData[plr]
    if not d then return end
    if d.box then
        boxOwner[d.box] = nil
        d.box:Destroy()
    end
    silData[plr] = nil
end

local function restoreAllSilent()
    for plr in pairs(silData) do restoreSilent(plr) end
end

Players.PlayerRemoving:Connect(function(p)
    if conns[p] then conns[p]:Disconnect(); conns[p] = nil end
    restoreSilent(p)
    removeESP(p)
end)

local function fire()
    local ok = pcall(function()
        VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.delay(0.03, function()
            pcall(function()
                VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end)
        end)
    end)
    if not ok and mouse1click then pcall(mouse1click) end
end

local function rayParams(exclude)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclude
    params.IgnoreWater = true
    return params
end

local function visible(from, target, char)
    skipHook = true
    local hit = workspace:Raycast(from, target - from, rayParams({ lp.Character, char }))
    skipHook = false
    return hit == nil
end

local function screenCenter()
    local vp = cam.ViewportSize
    return Vector2.new(vp.X / 2, vp.Y / 2)
end

local function bestTarget()
    local center = screenCenter()
    local best, bestScore = nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) then
            local char = getChar(plr)
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local center3d, size = modelCenter(char)
                local aimAt = center3d or (hrp.Position + Vector3.new(0, 0.4, 0))
                if center3d and size then
                    aimAt = center3d + Vector3.new(0, size.Y * 0.15, 0)
                end

                local sp, onScreen = cam:WorldToViewportPoint(aimAt)
                if onScreen and sp.Z > 0 then
                    local d2 = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d2 <= Config.AimFov and d2 < bestScore then
                        if visible(cam.CFrame.Position, aimAt, char) then
                            best, bestScore = aimAt, d2
                        end
                    end
                end
            end
        end
    end
    return best
end

local function boxList()
    local list = {}
    for _, d in pairs(silData) do
        if d.box and d.box.Parent then table.insert(list, d.box) end
    end
    return list
end

local function boxUnderAim()
    local list = boxList()
    if #list == 0 then return nil end

    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Include
    p.FilterDescendantsInstances = list
    p.IgnoreWater = true

    skipHook = true
    local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 1400, p)
    skipHook = false
    if not hit then return nil end

    local box = hit.Instance
    local plr = boxOwner[box]
    local char = plr and getChar(plr)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (plr and hrp and hum and hum.Health > 0 and isEnemy(plr)) then return nil end

    return box, char, hrp
end

local function flash(box)
    if not box or not box.Parent then return end
    box.Color = BoxFlash
    local outline = box:FindFirstChild("Outline")
    if outline then outline.Color3 = BoxFlash end
    task.delay(0.18, function()
        if box.Parent then
            box.Color = BoxColor
            if outline then outline.Color3 = BoxColor end
        end
    end)
end

local function isOriginPoint(v)
    if v.Magnitude < 5 then return true end
    if (v - cam.CFrame.Position).Magnitude < 7 then return true end
    local char = lp.Character
    local center, size = char and modelCenter(char)
    if center and (v - center).Magnitude < (size and size.Magnitude / 2 or 6) + 12 then
        return true
    end
    return false
end

local function rewriteArgs(args)
    local box, char, hrp = boxUnderAim()
    if not box then return args, nil end

    local origin = cam.CFrame.Position
    local dir = cam.CFrame.LookVector
    local body = hrp.Position
    local tolerance = math.max(16, Config.SilentSize)
    local replaced = false

    for i, v in ipairs(args) do
        local t = typeof(v)
        if t == "Instance" then
            if v == box or (v:IsA("BasePart") and char:IsAncestorOf(v)) then
                args[i] = hrp
                replaced = true
            end
        elseif t == "Ray" then
            args[i] = Ray.new(v.Origin, body - v.Origin)
            replaced = true
        elseif t == "string" then
            if v == "MileiHitbox" then
                args[i] = hrp.Name
                replaced = true
            end
        elseif t == "CFrame" then
            local pos = v.Position
            if not isOriginPoint(pos) then
                local toP = pos - origin
                local along = toP:Dot(dir)
                if along > 6 and along < 1400 then
                    if (toP - dir * along).Magnitude <= tolerance then
                        args[i] = CFrame.new(body) * (v - v.Position)
                        replaced = true
                    end
                end
            end
        elseif t == "Vector3" and not replaced then
            if not isOriginPoint(v) then
                local toP = v - origin
                local along = toP:Dot(dir)
                if along > 6 and along < 1400 then
                    if (toP - dir * along).Magnitude <= tolerance then
                        args[i] = body
                        replaced = true
                    end
                end
            end
        end
    end

    return args, replaced and box or nil
end

pcall(function()
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    local oldIndex = mt.__index
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()

        if not skipHook and Config.Silent then
            if method == "FireServer" or method == "InvokeServer" then
                if (self:IsA("RemoteEvent") or self:IsA("RemoteFunction"))
                    and os.clock() - lastClick < 1 then
                    local args = { ... }
                    local newArgs, box = rewriteArgs(args)
                    if box then
                        flash(box)
                        return oldNamecall(self, table.unpack(newArgs))
                    end
                end
            elseif self == workspace then
                if method == "Raycast" then
                    local args = { ... }
                    if typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
                        local box, char, hrp = boxUnderAim()
                        if hrp then
                            local parts = {}
                            for _, v in ipairs(char:GetDescendants()) do
                                if v:IsA("BasePart") then table.insert(parts, v) end
                            end
                            local pBody = RaycastParams.new()
                            pBody.FilterType = Enum.RaycastFilterType.Include
                            pBody.FilterDescendantsInstances = parts
                            pBody.IgnoreWater = true
                            local toBody = hrp.Position - args[1]
                            skipHook = true
                            local real = workspace:Raycast(args[1],
                                toBody.Unit * (toBody.Magnitude + 6), pBody)
                            skipHook = false
                            if real then
                                flash(box)
                                return real
                            end
                        end
                    end
                elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" then
                    local ray = (...)
                    if typeof(ray) == "Ray" then
                        local box, char, hrp = boxUnderAim()
                        if hrp then
                            flash(box)
                            return hrp, hrp.Position, Vector3.new(0, 1, 0), Enum.Material.Plastic
                        end
                    end
                end
            end
        end

        return oldNamecall(self, ...)
    end)

    mt.__index = newcclosure(function(self, key)
        if not skipHook and Config.Silent and self == mouse then
            if key == "Target" or key == "Hit" then
                local target = mouse.Target
                if target and target.Name == "MileiHitbox" then
                    local plr = boxOwner[target]
                    local char = plr and getChar(plr)
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        if key == "Target" then return hrp end
                        return CFrame.new(hrp.Position)
                    end
                end
            end
        end
        return oldIndex(self, key)
    end)

    setreadonly(mt, true)
end)

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1
fovCircle.NumSides = 64
fovCircle.Filled = false
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Transparency = 0.55
fovCircle.Visible = false

local dot = Drawing.new("Circle")
dot.Radius = 2
dot.Thickness = 1
dot.Filled = true
dot.Color = Color3.fromRGB(0, 255, 140)
dot.Visible = false

RunService.RenderStepped:Connect(function(dt)
    for plr, d in pairs(ESP) do
        if plr.Parent then updateESP(plr, d) else removeESP(plr) end
    end

    for plr, d in pairs(silData) do
        local char = getChar(plr)
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if d.box and d.box.Parent == char and hrp and hum and hum.Health > 0 and isEnemy(plr) then
            d.box.Size = boxSize(Config.SilentSize)
            d.box.CFrame = CFrame.new(hrp.Position)
        else
            restoreSilent(plr)
        end
    end

    local aiming = Config.Aim and adsDown
    local center = screenCenter()
    fovCircle.Position = center
    fovCircle.Radius = Config.AimFov
    fovCircle.Visible = aiming
    dot.Position = center
    dot.Visible = aiming

    if aiming then
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local target = bestTarget()
            if target then
                dot.Color = Color3.fromRGB(0, 255, 140)
                local desired = CFrame.lookAt(cam.CFrame.Position, target)
                local alpha = 1 - math.exp(-Config.SmoothSpeed * dt)
                cam.CFrame = cam.CFrame:Lerp(desired, alpha)
            else
                dot.Color = Color3.fromRGB(255, 255, 255)
            end
        end
    end
end)

local lastFire = 0
local lastSilent = 0

RunService.Heartbeat:Connect(function()
    local now = os.clock()

    if Config.Trigger and now - lastFire >= Config.TriggerDelay / 1000 then
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local params = rayParams({ char })
            local hit = workspace:Raycast(cam.CFrame.Position,
                cam.CFrame.LookVector * Config.TriggerRange, params)
            local part = hit and hit.Instance
            local model = part and part:FindFirstAncestorOfClass("Model")
            local plr = (part and boxOwner[part]) or (model and Players:GetPlayerFromCharacter(model))
            if plr and isEnemy(plr) then
                local tchar = getChar(plr)
                local thum = tchar and tchar:FindFirstChildOfClass("Humanoid")
                if thum and thum.Health > 0 then
                    fire()
                    lastFire = now
                end
            end
        end
    end

    if now - lastSilent >= 0.3 then
        lastSilent = now
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = getChar(plr)
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local inRange = false

            if Config.Silent and hrp and hum and hum.Health > 0 and isEnemy(plr) then
                inRange = (cam.CFrame.Position - hrp.Position).Magnitude <= Config.MaxDistance
            end

            if inRange then
                if not silData[plr] then
                    silData[plr] = { box = buildBox(plr, char, hrp) }
                end
            elseif silData[plr] then
                restoreSilent(plr)
            end
        end
    end
end)

mouse.Button1Down:Connect(function()
    lastClick = os.clock()
end)

mouse.Button2Down:Connect(function()
    adsDown = true
end)

mouse.Button2Up:Connect(function()
    adsDown = false
end)

UIS.InputBegan:Connect(function(input, gp)
    if input.UserInputType == Enum.UserInputType.Touch then
        lastClick = os.clock()
        local vp = cam.ViewportSize
        if input.Position.X > vp.X * 0.5 then
            touchCount += 1
            adsDown = true
        end
    elseif not gp and input.UserInputType == Enum.UserInputType.MouseButton2 then
        adsDown = true
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        touchCount = math.max(0, touchCount - 1)
        if touchCount == 0 then adsDown = false end
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        adsDown = false
    end
end)

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(296, 470)
panel.Position = UDim2.new(0, 14, 0.5, -235)
panel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(60, 60, 75)
stroke.Thickness = 1

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 34)
titleBar.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "Panel Milei"
title.TextColor3 = Color3.fromRGB(0, 220, 140)
title.Font = Enum.Font.GothamBlack
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(26, 26)
minBtn.Position = UDim2.new(1, -62, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.Text = "-"
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(26, 26)
closeBtn.Position = UDim2.new(1, -32, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Text = "X"
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.fromOffset(104, 34)
openBtn.Position = UDim2.new(0, 14, 0.5, -17)
openBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
openBtn.TextColor3 = Color3.fromRGB(0, 220, 140)
openBtn.Font = Enum.Font.GothamBlack
openBtn.TextSize = 13
openBtn.Text = "PANEL MILEI"
openBtn.Visible = false
openBtn.Parent = gui
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 8)

closeBtn.Activated:Connect(function()
    panel.Visible = false
    openBtn.Visible = true
end)
openBtn.Activated:Connect(function()
    panel.Visible = true
    openBtn.Visible = false
end)

local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = panel.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -44)
scroll.Position = UDim2.fromOffset(6, 38)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local minimized = false
minBtn.Activated:Connect(function()
    minimized = not minimized
    scroll.Visible = not minimized
    panel.Size = minimized and UDim2.fromOffset(296, 34) or UDim2.fromOffset(296, 470)
    minBtn.Text = minimized and "+" or "-"
end)

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local toggles = {}
local sliders = {}

local function section(text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -6, 0, 20)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(150, 150, 165)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = scroll
end

local function syncToggle(btn, key, onText, offText)
    local on = Config[key]
    btn.Text = on and onText or offText
    btn.BackgroundColor3 = on and GREEN or DARK
    btn.TextColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(190, 190, 200)
end

local function toggle(key, onText, offText, onChanged)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -6, 0, 32)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    syncToggle(b, key, onText, offText)
    b.Activated:Connect(function()
        Config[key] = not Config[key]
        syncToggle(b, key, onText, offText)
        if onChanged then onChanged(Config[key]) end
    end)
    toggles[key] = function()
        syncToggle(b, key, onText, offText)
    end
end

local function slider(key, name, min, max, step, suffix)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -6, 0, 38)
    holder.BackgroundTransparency = 1
    holder.Parent = scroll

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -50, 0, 16)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(220, 220, 230)
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = holder

    local valueLbl = Instance.new("TextLabel")
    valueLbl.Size = UDim2.fromOffset(50, 16)
    valueLbl.Position = UDim2.new(1, -50, 0, 0)
    valueLbl.BackgroundTransparency = 1
    valueLbl.TextColor3 = Color3.fromRGB(0, 220, 140)
    valueLbl.Font = Enum.Font.GothamBold
    valueLbl.TextSize = 12
    valueLbl.TextXAlignment = Enum.TextXAlignment.Right
    valueLbl.Parent = holder

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -4, 0, 6)
    bar.Position = UDim2.new(0, 2, 0, 22)
    bar.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    bar.BorderSizePixel = 0
    bar.Parent = holder
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 200, 130)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(10, 10)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = bar
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function paint()
        local pct = (Config[key] - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        local txt = Config[key]
        if step < 1 then
            txt = string.format("%.1f", txt)
        else
            txt = tostring(math.floor(txt + 0.5))
        end
        valueLbl.Text = txt .. suffix
    end

    local holding = false

    local function apply(input)
        local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local raw = min + (max - min) * rel
        raw = math.floor(raw / step + 0.5) * step
        Config[key] = math.clamp(raw, min, max)
        paint()
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            holding = true
            apply(input)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not holding then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            apply(input)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            holding = false
        end
    end)

    sliders[key] = paint
    paint()
end

local function refreshUI()
    for key, fn in pairs(toggles) do fn() end
    for _, fn in pairs(sliders) do fn() end
    restoreAllSilent()
end

section("GENERAL")
toggle("ESP", "WALLHACK: ON", "WALLHACK: OFF")
toggle("Aim", "AIMBOT: ON", "AIMBOT: OFF")
toggle("Trigger", "TRIGGERBOT: ON", "TRIGGERBOT: OFF")
toggle("Silent", "SILENT: ON", "SILENT: OFF", function(on)
    if not on then restoreAllSilent() end
end)

section("AIMBOT")
slider("AimFov", "Rango del aimbot", 20, 300, 5, " px")
slider("SmoothSpeed", "Velocidad de respuesta", 1, 40, 1, "")

section("TRIGGERBOT")
slider("TriggerDelay", "Retardo de disparo", 0, 400, 10, " ms")
slider("TriggerRange", "Alcance del trigger", 10, 300, 10, " st")

section("SILENT")
slider("SilentSize", "Tamaño de la caja", 2, 40, 1, " st")

section("VISUALES")
slider("MaxDistance", "Distancia del wallhack", 50, 1000, 10, " st")
toggle("TeamCheck", "IGNORAR EQUIPO: SI", "IGNORAR EQUIPO: NO")

section("CONFIGURACIONES")
local fsOk = pcall(function()
    if not isfolder("MileiConfigs") then makefolder("MileiConfigs") end
end)

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -6, 0, 30)
nameBox.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
nameBox.TextColor3 = Color3.new(1, 1, 1)
nameBox.PlaceholderText = "nombre de la config"
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 12
nameBox.ClearTextOnFocus = false
nameBox.Text = ""
nameBox.Parent = scroll
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 7)

local saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(1, -6, 0, 30)
saveBtn.BackgroundColor3 = BLUE
saveBtn.TextColor3 = Color3.new(1, 1, 1)
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 12
saveBtn.Text = fsOk and "GUARDAR CONFIG" or "SIN ACCESO A ARCHIVOS"
saveBtn.Parent = scroll
Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 7)

local listFrame = Instance.new("Frame")
listFrame.Size = UDim2.new(1, -6, 0, 0)
listFrame.BackgroundTransparency = 1
listFrame.AutomaticSize = Enum.AutomaticSize.Y
listFrame.Parent = scroll

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local function cfgPath(name)
    return "MileiConfigs/" .. name .. ".json"
end

local function saveCfg(name)
    if not fsOk or name == "" then return end
    local data = {}
    for k in pairs(DEFAULTS) do data[k] = Config[k] end
    pcall(function()
        writefile(cfgPath(name), HttpService:JSONEncode(data))
    end)
end

local function loadCfg(name)
    if not fsOk then return end
    local ok, raw = pcall(readfile, cfgPath(name))
    if not ok or not raw then return end
    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okDecode or type(data) ~= "table" then return end
    for k in pairs(DEFAULTS) do
        if data[k] ~= nil then Config[k] = data[k] end
    end
    refreshUI()
end

local function buildList()
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then child:Destroy() end
    end
    if not fsOk then return end

    local ok, files = pcall(listfiles, "MileiConfigs")
    if not ok or not files then return end

    for _, path in ipairs(files) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 28)
            row.BackgroundTransparency = 1
            row.Parent = listFrame

            local load = Instance.new("TextButton")
            load.Size = UDim2.new(1, -34, 1, 0)
            load.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
            load.TextColor3 = Color3.new(1, 1, 1)
            load.Font = Enum.Font.GothamBold
            load.TextSize = 12
            load.Text = name
            load.Parent = row
            Instance.new("UICorner", load).CornerRadius = UDim.new(0, 7)

            local del = Instance.new("TextButton")
            del.Size = UDim2.fromOffset(30, 28)
            del.Position = UDim2.new(1, -30, 0, 0)
            del.BackgroundColor3 = Color3.fromRGB(120, 35, 35)
            del.TextColor3 = Color3.new(1, 1, 1)
            del.Font = Enum.Font.GothamBold
            del.TextSize = 12
            del.Text = "x"
            del.Parent = row
            Instance.new("UICorner", del).CornerRadius = UDim.new(0, 7)

            load.Activated:Connect(function() loadCfg(name) end)
            del.Activated:Connect(function()
                pcall(function() delfile(cfgPath(name)) end)
                buildList()
            end)
        end
    end
end

saveBtn.Activated:Connect(function()
    local name = nameBox.Text:gsub("[^%w_%- ]", "")
    if name == "" then return end
    saveCfg(name)
    buildList()
end)

buildList()

local reset = Instance.new("TextButton")
reset.Size = UDim2.new(1, -6, 0, 30)
reset.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
reset.TextColor3 = Color3.new(1, 1, 1)
reset.Font = Enum.Font.GothamBold
reset.TextSize = 12
reset.Text = "RESTABLECER"
reset.Parent = scroll
Instance.new("UICorner", reset).CornerRadius = UDim.new(0, 7)

reset.Activated:Connect(function()
    for k, v in pairs(DEFAULTS) do Config[k] = v end
    refreshUI()
end)