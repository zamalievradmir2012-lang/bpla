-- ============================================================
--  DefenderController — клиент защитника:
--  АК-74М / Корд (автострельба), ПЗРК «Игла-С» (захват цели),
--  управление ЗУ-23-2 / «Панцирь-С1» / прожектором.
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local weaponFireEv = Remotes:WaitForChild(Config.REM.WeaponFire)
local iglaLaunchEv = Remotes:WaitForChild(Config.REM.IglaLaunch)
local gunAimEv = Remotes:WaitForChild(Config.REM.GunAim)
local gunFireEv = Remotes:WaitForChild(Config.REM.GunFire)
local gunLeaveEv = Remotes:WaitForChild(Config.REM.GunLeave)
local gunStateEv = Remotes:WaitForChild(Config.REM.GunState)
local operFXEv = Remotes:WaitForChild(Config.REM.OperFX)
local radarEv = Remotes:WaitForChild(Config.REM.Radar)

-- ------------------------------------------------------------
local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function toast(text, color)
	local pg = player:WaitForChild("PlayerGui")
	local t = mk("TextLabel", {
		Size = UDim2.new(0, 420, 0, 40), Position = UDim2.new(0.5, -210, 0.32, 0),
		BackgroundColor3 = Color3.fromRGB(15, 18, 22), BackgroundTransparency = 0.25,
		Font = Enum.Font.GothamBold, Text = text, TextSize = 18,
		TextColor3 = color or Color3.fromRGB(255, 220, 120), ZIndex = 50,
	}, pg)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, t)
	TweenService:Create(t, TweenInfo.new(2.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(t, 2.6)
end

-- ------------------------------------------------------------
-- СОСТОЯНИЕ
-- ------------------------------------------------------------
local mags = { AK74M = Config.WEAPONS.AK74M.Mag, KORD = Config.WEAPONS.KORD.Mag }
local reloading = false
local mouseDown = false
local rmbDown = false
local gun = nil            -- активная стационарная система {model, kind}
local gunYaw, gunPitch = 0, 0
local lockTarget = nil
local lockProgress = 0
local lastRadarBlips = {}

radarEv.OnClientEvent:Connect(function(blips) lastRadarBlips = blips or {} end)

-- ------------------------------------------------------------
-- ПЕРЕКРЕСТИЕ + ИНДИКАТОРЫ
-- ------------------------------------------------------------
local pg = player:WaitForChild("PlayerGui")
local crossGui = mk("ScreenGui", { Name = "DefenderCross", ResetOnSpawn = false }, pg)
local cross = mk("Frame", { Size = UDim2.new(0, 4, 0, 4), Position = UDim2.new(0.5, -2, 0.5, -2), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Rotation = 45 }, crossGui)
crossGui.Enabled = false
-- полоска захвата ПЗРК
local lockBack = mk("Frame", { Size = UDim2.new(0, 220, 0, 12), Position = UDim2.new(0.5, -110, 0.55, 0), BackgroundColor3 = Color3.fromRGB(20, 25, 20), Visible = false, BorderColor3 = Color3.fromRGB(255, 200, 60) }, crossGui)
local lockBar = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 200, 60), BorderSizePixel = 0 }, lockBack)
local lockLabel = mk("TextLabel", { Size = UDim2.new(0, 220, 0, 20), Position = UDim2.new(0.5, -110, 0.55, 14), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "ЗАХВАТ ЦЕЛИ...", TextSize = 14, TextColor3 = Color3.fromRGB(255, 200, 60) }, crossGui)
-- перегрев зенитки
local heatBack = mk("Frame", { Size = UDim2.new(0, 260, 0, 14), Position = UDim2.new(0.5, -130, 0.62, 0), BackgroundColor3 = Color3.fromRGB(30, 20, 15), Visible = false, BorderColor3 = Color3.fromRGB(255, 120, 60) }, crossGui)
local heatBar = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 120, 60), BorderSizePixel = 0 }, heatBack)
-- боезапас
local ammoLabel = mk("TextLabel", { Size = UDim2.new(0, 200, 0, 30), Position = UDim2.new(1, -220, 1, -60), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 20, TextColor3 = Color3.fromRGB(255, 240, 200), TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.5 }, crossGui)
-- радар «Панциря»
local radarGui = mk("Frame", { Size = UDim2.new(0, 220, 0, 220), Position = UDim2.new(1, -240, 0, 20), BackgroundColor3 = Color3.fromRGB(3, 12, 6), BackgroundTransparency = 0.2, BorderColor3 = Color3.fromRGB(60, 220, 110), Visible = false }, crossGui)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, radarGui)
local radarSweep = mk("Frame", { Size = UDim2.new(0, 2, 0.5, 0), Position = UDim2.new(0.5, -1, 0.5, 0), BackgroundColor3 = Color3.fromRGB(60, 220, 110), BorderSizePixel = 0 }, radarGui)
local radarDots = {}
for i = 1, 16 do
	local dot = mk("Frame", { Size = UDim2.new(0, 8, 0, 8), BackgroundColor3 = Color3.fromRGB(255, 60, 50), Visible = false, BorderSizePixel = 0, ZIndex = 3 }, radarGui)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	radarDots[i] = dot
end
-- подсказка зенитки
local gunHelp = mk("TextLabel", { Size = UDim2.new(0, 500, 0, 60), Position = UDim2.new(0.5, -250, 1, -110), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 15, TextColor3 = Color3.fromRGB(255, 255, 255), TextStrokeTransparency = 0.5 }, crossGui)

-- ------------------------------------------------------------
-- СТРЕЛЬБА АК / КОРД
-- ------------------------------------------------------------
local function currentTool()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Tool")
end

local function shootLoop()
	while true do
		local dt = task.wait(0.05)
		if mouseDown and not gun then
			local tool = currentTool()
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if tool and hum and hum.Health > 0 and (tool.Name == "AK74M" or tool.Name == "KORD") then
				local wcfg = Config.WEAPONS[tool.Name]
				if not reloading then
					if (mags[tool.Name] or 0) > 0 then
						mags[tool.Name] = mags[tool.Name] - 1
						local head = char:FindFirstChild("Head")
						local origin = head and head.Position or char:GetPivot().Position
						weaponFireEv:FireServer(origin, camera.CFrame.LookVector)
						ammoLabel.Text = (tool.Name == "AK74M" and "АК-74М: " or "КОРД: ") .. mags[tool.Name] .. " / " .. wcfg.Mag
						task.wait(1 / wcfg.Rate)
					else
						-- перезарядка
						reloading = true
						ammoLabel.Text = "ПЕРЕЗАРЯДКА..."
						task.wait(wcfg.Reload)
						mags[tool.Name] = wcfg.Mag
						reloading = false
						ammoLabel.Text = (tool.Name == "AK74M" and "АК-74М: " or "КОРД: ") .. mags[tool.Name] .. " / " .. wcfg.Mag
					end
				end
			else
				ammoLabel.Text = ""
			end
		end
	end
end
task.spawn(shootLoop)

-- ------------------------------------------------------------
-- ЗАХВАТ ЦЕЛИ ПЗРК
-- ------------------------------------------------------------
local function findAimedDrone()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excl = { workspace.Debris, workspace.FX }
	if player.Character then table.insert(excl, player.Character) end
	rayParams.FilterDescendantsInstances = excl
	local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 500, rayParams)
	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		while model and not model:GetAttribute("DroneId") do
			model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
		end
		return model
	end
	return nil
end

local lockBeep
local function updateIglaLock(dt)
	local tool = currentTool()
	local isIgla = tool and tool.Name == "IGLA" and not gun
	local isPantsir = gun and gun.kind == "pantsir"
	local wantLock = isIgla or (isPantsir and rmbDown)
	local lockTime = isPantsir and Config.STATIONARY.PANTSIR.Missile.LockTime or Config.WEAPONS.IGLA.LockTime

	if wantLock then
		local drone = findAimedDrone()
		if drone then
			if lockTarget ~= drone then
				lockTarget = drone
				lockProgress = 0
			end
			lockProgress = lockProgress + dt / lockTime
			lockBack.Visible = true
			lockBar.Size = UDim2.new(math.min(lockProgress, 1), 0, 1, 0)
			lockLabel.Text = lockProgress >= 1 and "ПУСК: ЛКМ (Игла) / ЛКМ" or ("ЗАХВАТ ЦЕЛИ... " .. math.floor(lockProgress * 100) .. "%")
			-- нарастающий писк
			if not lockBeep or not lockBeep.Parent then
				lockBeep = Util.soundOn(workspace, Config.SOUNDS.Beep, { Volume = 0.5 })
			end
			lockBeep.PlaybackSpeed = 1 + lockProgress * 3
			if math.random() < 0.3 then lockBeep:Play() end
			if lockProgress >= 1 then
				if isIgla then
					iglaLaunchEv:FireServer(lockTarget)
					lockTarget = nil
					lockProgress = 0
					lockBack.Visible = false
				end
				-- Панцирь стреляет по ЛКМ при полном захвате (см. ниже)
			end
		else
			lockTarget = nil
			lockProgress = 0
			lockBack.Visible = false
		end
	else
		lockTarget = nil
		lockProgress = 0
		lockBack.Visible = false
	end
end

-- Панцирь: ЛКМ при полном захвате → пуск ракеты, иначе пушка
local function onGunFireInput()
	if gun and gun.kind == "pantsir" then
		if lockTarget and lockProgress >= 1 then
			iglaLaunchEv:FireServer(lockTarget)
			lockTarget = nil
			lockProgress = 0
			lockBack.Visible = false
		else
			gunFireEv:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
		end
	elseif gun then
		gunFireEv:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
	end
end

-- ------------------------------------------------------------
-- СТАЦИОНАРНЫЕ СИСТЕМЫ
-- ------------------------------------------------------------
gunStateEv.OnClientEvent:Connect(function(model)
	if model then
		local isSpot = model:GetAttribute("Spotlight") ~= nil or (model.Parent and model.Parent.Name:find("Gun_ZU") == nil and model:FindFirstChildOfClass("SpotLight") ~= nil)
		gun = { model = model, kind = "zu23" }
		if model.Name == "Gun_Pantsir" then gun.kind = "pantsir" end
		if model:IsA("Part") and model:GetAttribute("Spotlight") then gun.kind = "spot" end
		gunYaw = 0
		gunPitch = 0.2
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		camera.CameraType = Enum.CameraType.Scriptable
		crossGui.Enabled = true
		radarGui.Visible = (gun.kind == "pantsir")
		if gun.kind == "spot" then
			gunHelp.Text = "Мышь — наведение прожектора · X — выйти"
		elseif gun.kind == "pantsir" then
			gunHelp.Text = "ЛКМ — пушка / пуск ракеты при захвате · ПКМ (удерж.) — захват цели · X — выйти"
		else
			gunHelp.Text = "ЛКМ — огонь (23 мм) · мышь — наведение · X — выйти"
		end
	else
		gun = nil
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		camera.CameraType = Enum.CameraType.Custom
		crossGui.Enabled = false
		radarGui.Visible = false
		heatBack.Visible = false
		gunHelp.Text = ""
	end
end)

local aimAccum = 0
RunService.RenderStepped:Connect(function(dt)
	-- свип радара
	if radarGui.Visible then
		radarSweep.Rotation = (radarSweep.Rotation + dt * 180) % 360
		for i, dot in ipairs(radarDots) do
			local blip = lastRadarBlips[i]
			if blip then
				dot.Visible = true
				dot.Position = UDim2.new(0.5, math.clamp(blip.x * 0.09, -95, 95) - 4, 0.5, math.clamp(blip.z * 0.09, -95, 95) - 4)
			else
				dot.Visible = false
			end
		end
	end
	if not gun then return end
	-- камера за установкой
	local pivotPos
	if gun.kind == "spot" then
		pivotPos = gun.model.Position
	else
		pivotPos = gun.model:GetPivot().Position + Vector3.new(0, 6, 0)
	end
	local rot = CFrame.Angles(0, gunYaw, 0) * CFrame.Angles(gunPitch, 0, 0)
	local camOffset = rot:VectorToWorldSpace(Vector3.new(0, 6, 16))
	local shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * (mouseDown and 0.35 or 0)
	camera.CFrame = CFrame.lookAt(pivotPos + camOffset + shake, pivotPos + rot.LookVector * 50)
	-- перегрев
	if gun.kind ~= "spot" then
		local heat = gun.model:GetAttribute("Heat") or 0
		local ohUntil = gun.model:GetAttribute("OverheatUntil") or 0
		local maxHeat = gun.kind == "pantsir" and Config.STATIONARY.PANTSIR.Cannon.HeatShots or Config.STATIONARY.ZU23.HeatShots
		heatBack.Visible = heat > 5 or os.clock() < ohUntil
		if os.clock() < ohUntil then
			heatBar.BackgroundColor3 = Color3.fromRGB(255, 40, 30)
			heatBar.Size = UDim2.new(1, 0, 1, 0)
		else
			heatBar.BackgroundColor3 = Color3.fromRGB(255, 120, 60)
			heatBar.Size = UDim2.new(heat / maxHeat, 0, 1, 0)
		end
	end
	-- наведение на сервер (10 Гц)
	aimAccum = aimAccum + dt
	if aimAccum > 0.1 then
		aimAccum = 0
		gunAimEv:FireServer(gun.model, rot.LookVector)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and gun then
		gunYaw = gunYaw - math.rad(input.Delta.X) * 1.4
		gunPitch = math.clamp(gunPitch - math.rad(input.Delta.Y) * 1.2, math.rad(-5), math.rad(85))
	end
end)

-- ------------------------------------------------------------
-- ВВОД
-- ------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDown = true
		if gun then onGunFireInput() end
		-- Игла: полный захват → пуск по ЛКМ (обрабатывается в updateIglaLock)
		local tool = currentTool()
		if tool and tool.Name == "IGLA" and not gun and lockTarget and lockProgress >= 1 then
			iglaLaunchEv:FireServer(lockTarget)
			lockTarget = nil
			lockProgress = 0
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbDown = true
	elseif input.KeyCode == Enum.KeyCode.R then
		local tool = currentTool()
		if tool and (tool.Name == "AK74M" or tool.Name == "KORD") and not reloading then
			reloading = true
			ammoLabel.Text = "ПЕРЕЗАРЯДКА..."
			task.delay(Config.WEAPONS[tool.Name].Reload, function()
				mags[tool.Name] = Config.WEAPONS[tool.Name].Mag
				reloading = false
			end)
		end
	elseif input.KeyCode == Enum.KeyCode.X and gun then
		if gun.kind == "spot" then
			gunLeaveEv:FireServer()
		else
			-- встать с сиденья
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then hum.Jump = true end
			gunLeaveEv:FireServer()
		end
	elseif input.KeyCode == Enum.KeyCode.V then
		if player.CameraMode == Enum.CameraMode.Classic then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		else
			player.CameraMode = Enum.CameraMode.Classic
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then mouseDown = false end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then rmbDown = false end
end)

-- ------------------------------------------------------------
-- КИНЕМАТОГРАФИЧНЫЙ ПУСК ПЗРК: камера следит за ракетой 1 сек
-- ------------------------------------------------------------
operFXEv.OnClientEvent:Connect(function(payload)
	if payload.type == "missile" and payload.missile then
		local missile = payload.missile
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not missile.Parent or os.clock() - t0 > 1 then
				conn:Disconnect()
				camera.CameraType = Enum.CameraType.Custom
				return
			end
			camera.CameraType = Enum.CameraType.Scriptable
			local mcf = missile.CFrame
			camera.CFrame = CFrame.lookAt(mcf.Position - mcf.LookVector * 18 + Vector3.new(0, 6, 0), mcf.Position + mcf.LookVector * 30)
		end)
	elseif payload.type == "msg" then
		toast(payload.text or "")
	end
end)

-- ------------------------------------------------------------
-- Обновление захвата в общем цикле
-- ------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	crossGui.Enabled = (hum and hum.Health > 0) and (currentTool() ~= nil or gun ~= nil)
	if not gun then
		updateIglaLock(dt)
	end
	-- подсказка о перегреве
end)
