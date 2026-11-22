--!strict
--[[
	DataService (Issue #9): one ProfileStore session per player (session-locked, so a player
	open on two servers can never duplicate items). Uses the vetted PlayerData kit:
	StartSessionAsync -> migrate (EconomyLedger) -> Reconcile -> kick on session loss.
	Profiles are only ever changed through EconomyService transactions.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyLedger = require(Shared.Utils.EconomyLedger)
local Packages = script.Parent.Parent.Packages
local ProfileStore = require(Packages.ProfileStore) :: any
local PlayerData = require(Packages.PlayerData) :: any

type Ledger = EconomyLedger.PlayerData

local STORE_NAME = "PlayerData_v2"
local LOAD_TIMEOUT = 15

local DataService = {}

local session: any = nil

-- Adapter for the kit: migrate profile.Data in place and report what happened.
local migrator = {
	run = function(_self: any, data: { [string]: any }): string
		local version = data.SchemaVersion or data.schemaVersion
		if type(version) == "number" and version > EconomyLedger.SCHEMA_VERSION then
			return "newer" -- an updated server wrote this; never downgrade it
		end
		local result = EconomyLedger.migrate(data)
		if not result.ok or not result.data then
			return "error"
		end
		local wasCurrent = version == EconomyLedger.SCHEMA_VERSION
		table.clear(data)
		for key, value in result.data :: any do
			data[key] = value
		end
		return if wasCurrent then "current" else "migrated"
	end,
}

function DataService.start(onLoaded: (player: Player, data: Ledger) -> ())
	session = PlayerData.new({
		ProfileStore = ProfileStore,
		Players = Players,
		storeName = STORE_NAME,
		template = EconomyLedger.new(), -- brand-new profiles get the starter egg
		migrate = migrator,
		-- Studio playtests never touch live keys (the place is published); live servers persist.
		useMock = RunService:IsStudio(),
		onLoaded = function(player: Player, profile: any)
			onLoaded(player, profile.Data)
		end,
		beforeEnd = function(_player: Player, profile: any)
			profile.Data.lastLogoutTime = os.time() -- offline accrual (#10) starts from here
		end,
	})
	session:Start()
end

-- The live profile table, or nil while loading / after leaving. Mutate only via EconomyService.
function DataService.get(player: Player): Ledger?
	local profile = session and session.Profiles[player]
	return if profile then profile.Data else nil
end

function DataService.waitFor(player: Player): Ledger?
	local profile = session and session:WaitForProfile(player, LOAD_TIMEOUT)
	return if profile then profile.Data else nil
end

return DataService
