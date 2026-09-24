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
-- DataStore
-- ------------------------------------------------------------
local function load(pl)
	local ok, data = pcall(function() return store:GetAsync("u_" .. pl.UserId) end)
	if ok and type(data) == "number" then
		local c = coinsStat(pl)
		if c then c.Value = data end
	end
end

local function save(pl)
	if not store then return end
	local coins = Economy.Coins(pl)
	pcall(function() store:SetAsync("u_" .. pl.UserId, coins) end)
end

Players.PlayerRemoving:Connect(save)

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
	Players.PlayerAdded:Connect(setup)
	for _, pl in ipairs(Players:GetPlayers()) do setup(pl) end

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
