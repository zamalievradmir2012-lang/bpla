-- ============================================================
--  Economy — монеты, покупки, DataStore (СЕРВЕР)
-- ============================================================
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Economy = {}
local store
pcall(function() store = DataStoreService:GetDataStore("BespilotnikiCoins_v1") end)

local Remotes
function Economy.SetRemotes(folder) Remotes = folder end

local roundEarned = {} -- [player] = заработано за раунд
local kills = {}       -- [player] = сбито дронов
local unlocked = {}    -- [player] = { droneId = true, ... } — купленные НАВСЕГДА дроны

function Economy.UnlockedSet(pl) return unlocked[pl] or {} end

function Economy.IsUnlocked(pl, id)
	local u = unlocked[pl]
	return u ~= nil and u[id] == true
end

local function fireUnlocked(pl)
	if not Remotes or not pl.Parent then return end
	local ev = Remotes:FindFirstChild(Config.REM.DroneUnlocked)
	if ev then ev:FireClient(pl, Economy.UnlockedSet(pl)) end
end

function Economy.Unlock(pl, id)
	local u = unlocked[pl] or {}
	if u[id] then return end
	u[id] = true
	unlocked[pl] = u
	fireUnlocked(pl)
	saveSoon(pl) -- сохранить покупку сразу
end

function Economy.RoundEarned(pl) return roundEarned[pl] or 0 end
function Economy.Kills(pl) return kills[pl] or 0 end
function Economy.ResetRound()
	roundEarned = {}
	kills = {}
end

-- ------------------------------------------------------------
local function coinsStat(pl)
	local ls = pl:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Монеты")
end

function Economy.Coins(pl)
	local c = coinsStat(pl)
	return c and c.Value or 0
end

function Economy.Add(pl, amount, reason)
	if not pl or amount <= 0 then return end
	local c = coinsStat(pl)
	if not c then return end
	c.Value = c.Value + amount
	roundEarned[pl] = (roundEarned[pl] or 0) + amount
	if Remotes then
		local ev = Remotes:FindFirstChild(Config.REM.Award)
		if ev and reason then ev:FireClient(pl, amount, reason) end
	end
end

function Economy.TrySpend(pl, amount)
	local c = coinsStat(pl)
	if not c then return false end
	if c.Value < amount then return false end
	c.Value = c.Value - amount
	return true
end

function Economy.Set(pl, amount)
	local c = coinsStat(pl)
	if not c then return end
	c.Value = math.max(0, math.floor(amount))
end

function Economy.Adjust(pl, delta)
	local c = coinsStat(pl)
	if not c then return 0 end
	c.Value = math.max(0, c.Value + math.floor(delta))
	return c.Value
end

function Economy.IsAdmin(pl)
	if not pl then return false end
	if game:GetService("RunService"):IsStudio() then return true end
	if game.CreatorId ~= 0 and pl.UserId == game.CreatorId then return true end
	return pl:GetAttribute("Admin") == true
end

function Economy.AddScore(pl, score)
	if not pl then return end
	local ls = pl:FindFirstChild("leaderstats")
	local sc = ls and ls:FindFirstChild("Очки")
	if sc then sc.Value = sc.Value + score end
end

function Economy.AddKill(pl)
	if pl then kills[pl] = (kills[pl] or 0) + 1 end
end

-- ------------------------------------------------------------
-- DataStore (монеты + купленные навсегда дроны)
-- ------------------------------------------------------------
local save -- объявлено заранее: используется в saveSoon/Economy.Unlock

local pendingSave = {}
function saveSoon(pl) -- отложенное сохранение, чтобы не долбить DataStore
	pendingSave[pl] = true
	task.delay(2, function()
		if pendingSave[pl] then
			pendingSave[pl] = nil
			save(pl)
		end
	end)
end

local function load(pl)
	local ok, data = pcall(function() return store:GetAsync("u_" .. pl.UserId) end)
	if ok and type(data) == "table" then
		local c = coinsStat(pl)
		if c and type(data.c) == "number" then c.Value = data.c end
		if type(data.d) == "table" then
			local u = {}
			for _, id in ipairs(data.d) do u[id] = true end
			unlocked[pl] = u
		end
	elseif ok and type(data) == "number" then
		-- старый формат: только монеты
		local c = coinsStat(pl)
		if c then c.Value = data end
	end
	-- отправить клиенту список купленных дронов (с задержкой — скрипты клиента должны успеть подключиться)
	task.delay(5, function() fireUnlocked(pl) end)
end

save = function(pl)
	if not store then return end
	local list = {}
	for id in pairs(unlocked[pl] or {}) do table.insert(list, id) end
	local data = { c = Economy.Coins(pl), d = list }
	pcall(function() store:SetAsync("u_" .. pl.UserId, data) end)
end

Players.PlayerRemoving:Connect(function(pl)
	save(pl)
	unlocked[pl] = nil
	pendingSave[pl] = nil
end)

game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do save(pl) end
	task.wait(2)
end)

-- автосейв
task.spawn(function()
	while true do
		task.wait(120)
		for _, pl in ipairs(Players:GetPlayers()) do save(pl) end
	end
end)

-- ------------------------------------------------------------
-- Покупки защитников
-- ------------------------------------------------------------
local ShieldHandler -- назначает WeaponService
function Economy.SetShieldHandler(fn) ShieldHandler = fn end
local RepairHandler
function Economy.SetRepairHandler(fn) RepairHandler = fn end

function Economy.BuyUpgrade(pl, itemId)
	local up = Config.UPGRADES[itemId]
	if not up then return false, "Неизвестный товар" end
	local char = pl.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if itemId == "hp" then
		if not hum then return false, "Нет персонажа" end
		if (pl:GetAttribute("HPLvl") or 0) >= 5 then return false, "Максимум 300 HP" end
		if not Economy.TrySpend(pl, up.Price) then return false, "Не хватает монет" end
		pl:SetAttribute("HPLvl", (pl:GetAttribute("HPLvl") or 0) + 1)
		hum.MaxHealth = hum.MaxHealth + 50
		hum.Health = hum.MaxHealth
		return true, "+50 HP"
	elseif itemId == "reload" then
		if pl:GetAttribute("FastIgla") then return false, "Уже куплено" end
		if not Economy.TrySpend(pl, up.Price) then return false, "Не хватает монет" end
		pl:SetAttribute("FastIgla", true)
		return true, "ПЗРК перезаряжается быстрее"
	elseif itemId == "shield" then
		if not ShieldHandler then return false, "Недоступно" end
		if not Economy.TrySpend(pl, up.Price) then return false, "Не хватает монет" end
		ShieldHandler(pl)
		return true, "Щит развёрнут"
	elseif itemId == "repair" then
		if not RepairHandler then return false, "Недоступно" end
		if not Economy.TrySpend(pl, up.Price) then return false, "Не хватает монет" end
		local ok, msg = RepairHandler(pl)
		if not ok then
			-- возврат денег
			Economy.Add(pl, up.Price, nil)
			return false, msg
		end
		return true, msg
	end
	return false, "?"
end

-- ------------------------------------------------------------
function Economy.Init()
	-- leaderstats
	local function setup(pl)
		local ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local coins = Instance.new("IntValue")
		coins.Name = "Монеты"
		coins.Parent = ls
		local score = Instance.new("IntValue")
		score.Name = "Очки"
		score.Parent = ls
		ls.Parent = pl
		load(pl)
		-- выживание защитника: +10 монет / 60 сек
		task.spawn(function()
			while pl.Parent do
				task.wait(Config.SURVIVAL_PERIOD)
				local char = pl.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local team = pl.Team and pl.Team.Name
				if hum and hum.Health > 0 and team == Config.TEAM_DEF then
					Economy.Add(pl, Config.SURVIVAL_COINS, "Выживание")
				end
			end
		end)
	end
	local function markAdmin(pl)
		if Economy.IsAdmin(pl) then pl:SetAttribute("Admin", true) end
	end
	Players.PlayerAdded:Connect(function(pl)
		setup(pl)
		markAdmin(pl)
	end)
	for _, pl in ipairs(Players:GetPlayers()) do
		setup(pl)
		markAdmin(pl)
	end

	if Remotes then
		local adminEv = Remotes:FindFirstChild("AdminCoins")
		if adminEv then
			adminEv.OnServerEvent:Connect(function(pl, action, amount)
				if not Economy.IsAdmin(pl) then return end
				amount = tonumber(amount) or 0
				if action == "add" then
					Economy.Adjust(pl, math.clamp(amount, 1, 1000000))
				elseif action == "sub" then
					Economy.Adjust(pl, -math.clamp(amount, 1, 1000000))
				elseif action == "zero" then
					Economy.Set(pl, 0)
				end
			end)
		end
	end

	if Remotes then
		local buyRF = Remotes:FindFirstChild(Config.REM.BuyUpgrade)
		if buyRF then
			buyRF.OnServerInvoke = function(pl, itemId)
				return Economy.BuyUpgrade(pl, itemId)
			end
		end
	end
end

return Economy
