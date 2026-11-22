--!strict
--[[
	Remote contract (Issue #1). Names match ClientNet.Remotes (PR #21) so the client wrapper
	resolves them by FindFirstChild on the ReplicatedStorage.Remotes folder.
	Server creates the folder once; clients WaitForChild it.
]]

local Remotes = {}

Remotes.FOLDER_NAME = "Remotes"

-- RemoteEvents unless listed in FUNCTIONS.
Remotes.Names = table.freeze({
	-- Client -> Server
	ThrowBall = "ThrowBall",
	OptIn = "OptIn",
	ClaimEgg = "ClaimEgg",
	CollectPad = "CollectPad",
	UpgradePet = "UpgradePet",
	Ascend = "Ascend",
	GetPolicyState = "GetPolicyState",
	-- Server -> Client
	ArenaStateChanged = "ArenaStateChanged",
	OptInPrompt = "OptInPrompt",
	EggClaimUpdated = "EggClaimUpdated",
	CashPadUpdated = "CashPadUpdated",
	CurrencyUpdated = "CurrencyUpdated",
	PolicyStateUpdated = "PolicyStateUpdated",
	HatchReveal = "HatchReveal",
	BallHit = "BallHit",
})

Remotes.FUNCTIONS = table.freeze({ GetPolicyState = true })

-- Server only: build (or reuse) the folder with one remote per name.
function Remotes.setupServer(parent: Instance): Folder
	local folder = parent:FindFirstChild(Remotes.FOLDER_NAME) :: Folder?
	if not folder then
		local created = Instance.new("Folder")
		created.Name = Remotes.FOLDER_NAME
		created.Parent = parent
		folder = created
	end
	assert(folder, "Remotes folder could not be created")
	for _, name: string in Remotes.Names :: { [string]: string } do
		if not folder:FindFirstChild(name) then
			local remote =
				Instance.new(if Remotes.FUNCTIONS[name] then "RemoteFunction" else "RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	return folder
end

function Remotes.getEvent(folder: Instance, name: string): RemoteEvent
	local remote = folder:FindFirstChild(name)
	assert(remote and remote:IsA("RemoteEvent"), `RemoteEvent {name} missing`)
	return remote
end

return Remotes
