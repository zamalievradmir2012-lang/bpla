-- Запускается отдельно от Main. Даже если Main упадёт, персонаж появится
-- и камера Play начнёт слушаться мышь.
local Players = game:GetService("Players")

Players.CharacterAutoLoads = true

local function ensurePad()
	if workspace:FindFirstChild("EmergencyPad") then return end
	local pad = Instance.new("SpawnLocation")
	pad.Name = "EmergencyPad"
	pad.Anchored = true
	pad.Size = Vector3.new(64, 2, 64)
	pad.Position = Vector3.new(0, 3, 0)
	pad.Neutral = true
	pad.Duration = 0
	pad.Color = Color3.fromRGB(70, 180, 90)
	pad.Material = Enum.Material.Grass
	pad.Parent = workspace
end

local function spawn(pl)
	if pl.Character then return end
	local ok, err = pcall(function()
		pl:LoadCharacter()
	end)
	if not ok then
		warn("[БЕСПИЛОТНИКИ] LoadCharacter: " .. tostring(err))
	end
end

ensurePad()
Players.PlayerAdded:Connect(function(pl)
	task.defer(spawn, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.defer(spawn, pl)
end
print("[БЕСПИЛОТНИКИ] Bootstrap: спавн включён")
