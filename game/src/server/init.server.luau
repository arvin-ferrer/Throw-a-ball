--!strict
--[[
	Minimal placeholder server bootstrap so Rojo builds cleanly from Day 1.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfigs = require(Shared.Configs.EconomyConfigs)

print(`[BallBrawlServer] Bootstrapped (MaxOfflineSeconds={EconomyConfigs.MAX_OFFLINE_SECONDS})`)
