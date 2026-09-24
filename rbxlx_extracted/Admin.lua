-- Тестовая панель монет. Видна в Studio и создателю места.
-- Сервер всё равно проверяет право, клиент только рисует кнопки.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

local function allowed()
	if RunService:IsStudio() then return true end
	if player:GetAttribute("Admin") == true then return true end
	return false
end

if not allowed() then
	player:GetAttributeChangedSignal("Admin"):Wait()
	if not allowed() then return end
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local ev = remotes and remotes:WaitForChild("AdminCoins", 30)
if not ev then return end

local pg = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "AdminCoins"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = pg

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 168, 0, 168)
panel.Position = UDim2.new(0, 12, 1, -186)
panel.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(255, 210, 80)
title.Text = "АДМИН · МОНЕТЫ"
title.Parent = panel

local function button(y, text, color, action, amount)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -16, 0, 30)
	b.Position = UDim2.new(0, 8, 0, y)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	b.MouseButton1Click:Connect(function()
		ev:FireServer(action, amount)
	end)
end

button(32, "+ 1 000", Color3.fromRGB(40, 140, 70), "add", 1000)
button(66, "+ 10 000", Color3.fromRGB(30, 110, 180), "add", 10000)
button(100, "− 1 000", Color3.fromRGB(160, 70, 50), "sub", 1000)
button(134, "Обнулить", Color3.fromRGB(70, 72, 80), "zero", 0)
