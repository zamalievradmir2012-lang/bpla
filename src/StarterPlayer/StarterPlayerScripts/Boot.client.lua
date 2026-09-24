-- Сразу показывает, что клиент жив, и привязывает камеру к персонажу.
-- Не ждёт Remotes: если сервер упал, эта надпись всё равно должна быть видна.
local Players = game:GetService("Players")
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

local function bindCamera(char)
	local cam = workspace.CurrentCamera
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 8)
	if cam and hum then
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = hum
	end
end

if player.Character then
	task.spawn(bindCamera, player.Character)
end
player.CharacterAdded:Connect(bindCamera)

local pg = player:WaitForChild("PlayerGui", 15)
if not pg then return end

local gui = Instance.new("ScreenGui")
gui.Name = "BootStatus"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.IgnoreGuiInset = true

local label = Instance.new("TextLabel")
label.Name = "Status"
label.Size = UDim2.new(0, 640, 0, 44)
label.Position = UDim2.new(0.5, -320, 0, 8)
label.BackgroundColor3 = Color3.fromRGB(12, 28, 18)
label.BackgroundTransparency = 0.15
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.TextColor3 = Color3.fromRGB(140, 255, 170)
label.Text = "БЕСПИЛОТНИКИ: клиент запущен, ждём персонажа..."
label.Parent = gui
gui.Parent = pg

task.spawn(function()
	local started = os.clock()
	while gui.Parent do
		task.wait(0.4)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local city = workspace:FindFirstChild("City")
		if hum then
			local team = player.Team and player.Team.Name
			if team then
				label.Text = "БЕСПИЛОТНИКИ: команда «" .. team .. "». " .. (city and "Город готов." or "Город строится...")
			else
				label.Text = city and "БЕСПИЛОТНИКИ: город на месте. Выбери сторону." or "БЕСПИЛОТНИКИ: персонаж есть, город строится..."
			end
			label.TextColor3 = Color3.fromRGB(140, 255, 170)
		else
			label.Text = string.format("БЕСПИЛОТНИКИ: персонажа нет уже %d с. Открой View → Output.", math.floor(os.clock() - started))
			label.TextColor3 = Color3.fromRGB(255, 180, 80)
		end
	end
end)
