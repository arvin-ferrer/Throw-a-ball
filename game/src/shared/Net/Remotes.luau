--!strict
--[[
	Remotes.luau
	Typed RemoteEvent & RemoteFunction contract shared by Server Services and Client Controllers.
	Remotes are created in code by the Server (never hand-placed in Explorer).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type RemoteBundle = {
	Folder: Folder,
	-- Client -> Server Gameplay & Combat
	ThrowBall: RemoteEvent,
	SetTrainingStance: RemoteEvent,
	DashRequest: RemoteEvent,
	OptInBoss: RemoteEvent,
	ClaimEggAction: RemoteEvent,
	TeleportZone: RemoteEvent,
	-- Client -> Server Hub Economy & Pets
	CollectCashPad: RemoteEvent,
	HatchEgg: RemoteEvent,
	PetAction: RemoteEvent,
	UpgradeAction: RemoteEvent,
	ShopRequest: RemoteEvent,
	-- Server -> Client State & VFX Broadcasts
	ProfileSync: RemoteEvent,
	ArenaStateSync: RemoteEvent,
	ProjectileBroadcast: RemoteEvent,
	BossTelegraph: RemoteEvent,
	HatchReveal: RemoteEvent,
	ToastNotify: RemoteEvent,
	-- Server -> Client Queries
	GetInitialState: RemoteFunction,
}

local Remotes = {}

local FOLDER_NAME = "BallBrawlRemotes"

local EVENT_NAMES = {
	"ThrowBall",
	"SetTrainingStance",
	"DashRequest",
	"OptInBoss",
	"ClaimEggAction",
	"TeleportZone",
	"CollectCashPad",
	"HatchEgg",
	"PetAction",
	"UpgradeAction",
	"ShopRequest",
	"ProfileSync",
	"ArenaStateSync",
	"ProjectileBroadcast",
	"BossTelegraph",
	"HatchReveal",
	"ToastNotify",
}

local cached: RemoteBundle? = nil

function Remotes.ensureServer(): RemoteBundle
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	local map: { [string]: any } = { Folder = folder }
	for _, name in ipairs(EVENT_NAMES) do
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			map[name] = existing
		else
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = folder
			map[name] = re
		end
	end
	local fn = folder:FindFirstChild("GetInitialState")
	if fn and fn:IsA("RemoteFunction") then
		map.GetInitialState = fn
	else
		local rf = Instance.new("RemoteFunction")
		rf.Name = "GetInitialState"
		rf.Parent = folder
		map.GetInitialState = rf
	end
	local bundle = map :: RemoteBundle
	cached = bundle
	return bundle
end

function Remotes.waitClient(): RemoteBundle
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 15)
	if not folder or not folder:IsA("Folder") then
		error("Timed out waiting for BallBrawlRemotes")
	end
	local map: { [string]: any } = { Folder = folder }
	for _, name in ipairs(EVENT_NAMES) do
		map[name] = folder:WaitForChild(name, 15)
	end
	map.GetInitialState = folder:WaitForChild("GetInitialState", 15)
	local bundle = map :: RemoteBundle
	cached = bundle
	return bundle
end

return Remotes
