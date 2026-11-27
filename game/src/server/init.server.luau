--!strict
--[[
	init.server.luau
	Ordered 2-phase server bootstrap (Init then Start) for Ball Brawl: Boss Eggs (v1.1).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

Remotes.ensureServer()

local ServicesFolder = script:WaitForChild("Services")
local WorldMapBootstrapService = require(ServicesFolder.WorldMapBootstrapService)
local DataService = require(ServicesFolder.DataService)
local PolicyGuardService = require(ServicesFolder.PolicyGuardService)
local PlotService = require(ServicesFolder.PlotService)
local ArenaCycleService = require(ServicesFolder.ArenaCycleService)
local BossAIService = require(ServicesFolder.BossAIService)
local CombatService = require(ServicesFolder.CombatService)
local PetIncomeService = require(ServicesFolder.PetIncomeService)
local EconomyService = require(ServicesFolder.EconomyService)
local VaultHeistService = require(ServicesFolder.VaultHeistService)
local ViralSocialService = require(ServicesFolder.ViralSocialService)
local TelemetryService = require(ServicesFolder.TelemetryService)

local orderedServices: { { name: string, mod: any } } = {
	{ name = "WorldMapBootstrapService", mod = WorldMapBootstrapService },
	{ name = "DataService", mod = DataService },
	{ name = "PolicyGuardService", mod = PolicyGuardService },
	{ name = "PlotService", mod = PlotService },
	{ name = "ArenaCycleService", mod = ArenaCycleService },
	{ name = "BossAIService", mod = BossAIService },
	{ name = "CombatService", mod = CombatService },
	{ name = "PetIncomeService", mod = PetIncomeService },
	{ name = "EconomyService", mod = EconomyService },
	{ name = "VaultHeistService", mod = VaultHeistService },
	{ name = "ViralSocialService", mod = ViralSocialService },
	{ name = "TelemetryService", mod = TelemetryService },
}

local function onVaultCompleted(player: Player, chamberCleared: number, extracted: boolean)
	if extracted then
		local profile = DataService.getProfile(player)
		if profile then
			profile.deepestVaultChamber = math.max(profile.deepestVaultChamber or 0, chamberCleared)
		end
		ViralSocialService.recordProgress(player, "VaultExtract", 1, { chamber = 1 })
	else
		ViralSocialService.recordProgress(player, "VaultWipe", 1)
		Remotes.ensureServer().CombatJuiceEvent:FireAllClients({
			kind = "StreakUpdate",
			userId = player.UserId,
			killerName = player.DisplayName,
			streak = 0,
		})
	end
	DataService.syncToClient(player)
end

local function wireVaultHeistHooks()
	VaultHeistService.setAnnouncementHook(
		function(
			_player: Player,
			headline: string,
			detail: string,
			accent: { number },
			suggestClip: boolean
		)
			ViralSocialService.announce(
				"VaultExtract",
				headline,
				detail,
				accent,
				suggestClip,
				"Save Vault Clip"
			)
		end
	)
	VaultHeistService.setJuiceHook(
		function(
			kind: string,
			worldPos: Vector3?,
			amount: number?,
			label: string?,
			accent: { number }?
		)
			Remotes.ensureServer().CombatJuiceEvent:FireAllClients({
				kind = kind,
				worldPos = worldPos,
				amount = amount,
				label = label,
				accent = accent,
			})
		end
	)
	VaultHeistService.setCompletionHook(onVaultCompleted)
end

for _, entry in ipairs(orderedServices) do
	local ok, err = pcall(entry.mod.init)
	if not ok then
		warn(`[BallBrawlServer] Init error in {entry.name}: {err}`)
	end
end

wireVaultHeistHooks()

for _, entry in ipairs(orderedServices) do
	local ok, err = pcall(entry.mod.start)
	if not ok then
		warn(`[BallBrawlServer] Start error in {entry.name}: {err}`)
	end
end

script:SetAttribute("BootOk", true)
print(`[BallBrawlServer] All {#orderedServices} services initialized & started.`)
