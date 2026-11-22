--!strict
--[[
	ArenaHUDController (Issue #7): wires server remotes into ArenaHUDViewModel and draws its
	display every frame. All HUD rules live in the tested view-model; this only renders.
	Init/Start shape matches the ClientLifecycle loader from PR #21.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaHUDViewModel = require(Shared.Utils.ArenaHUDViewModel)
local ArenaHUDView = require(script.Parent.Parent.UI.ArenaHUDView)

local ZONE_CHECK_INTERVAL = 0.25
local ROOM_HEIGHT_STUDS = 80

local ArenaHUDController = { Name = "ArenaHUDController", Priority = 50 }

local player = Players.LocalPlayer
local state = ArenaHUDViewModel.new(player.UserId)
local view: ArenaHUDView.View? = nil
local remotes: Instance? = nil
local nextZoneCheck = 0

local function fire(remoteName: string, payload: any)
	local remote = remotes and remotes:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(payload)
	end
end

-- Which biome (and whether its locked room) the character stands over, mirroring the server.
local function overDisc(part: Instance?, position: Vector3, checkHeight: boolean): boolean
	if not (part and part:IsA("BasePart")) then
		return false
	end
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2 + 6
	local flat = Vector3.new(position.X - part.Position.X, 0, position.Z - part.Position.Z)
	return flat.Magnitude <= radius
		and (not checkHeight or math.abs(position.Y - part.Position.Y) <= ROOM_HEIGHT_STUDS)
end

local function detectZone()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local biomes = Workspace:FindFirstChild("BallBrawl_Map_v2")
	biomes = biomes and biomes:FindFirstChild("Biomes")
	if not (root and root:IsA("BasePart") and biomes) then
		ArenaHUDViewModel.setActiveBiome(state, nil)
		return
	end
	for _, biome in biomes:GetChildren() do
		local arena, pve = biome:FindFirstChild("BossPvPArena"), biome:FindFirstChild("PvELayer")
		if overDisc(arena and arena:FindFirstChild("ArenaFloor"), root.Position, true) then
			ArenaHUDViewModel.setActiveBiome(state, biome.Name, true)
			return
		elseif overDisc(pve and pve:FindFirstChild("PvEGround"), root.Position, false) then
			ArenaHUDViewModel.setActiveBiome(state, biome.Name, false)
			return
		end
	end
	ArenaHUDViewModel.setActiveBiome(state, nil)
end

local function renderBanner(v: ArenaHUDView.View, b: any)
	local phaseText = (b.phase :: string):gsub("_", " ")
	v.bannerTitle.Text = if b.phase == "Hub" then "Hub Plaza" else `{b.biomeName} — {phaseText}`
	v.bannerTimer.Text = b.countdownText
	v.banner.BackgroundColor3 = ArenaHUDView.TONES[b.accentTone] or ArenaHUDView.TONES.Safe
	v.bossBar.Visible = b.showBossHpBar
	v.bossFill.Size = UDim2.fromScale(b.bossHpRatio, 1)
	v.bossText.Text = b.bossHpText
	v.stormPill.Visible = b.showSuddenDeathWarning
	v.stormPill.Text = b.suddenDeathText
end

local function renderModal(v: ArenaHUDView.View, m: any)
	v.modal.Visible = m.visible
	v.modal.BackgroundColor3 = if m.isOvercharged
		then ArenaHUDView.TONES.Overcharged
		else Color3.fromRGB(20, 22, 30)
	v.modalTitle.Text = if m.isOvercharged
		then "⚡ OVERCHARGED BOSS ⚡"
		else "BOSS FIGHT STARTING"
	v.modalTimer.Text = m.countdownText
	v.modalDetails.Text = `{m.queuedText} · {m.highestPowerText} · {m.recommendedText}`
	v.queuedPill.Visible = m.showQueuedPill
	v.queuedPill.Text = `QUEUED ({m.countdownText}) — tap to leave`
end

local function renderClaim(v: ArenaHUDView.View, c: any)
	v.claim.Visible = c.visible
	v.claimFill.Size = UDim2.fromScale(math.clamp(c.progressRatio, 0, 1), 1)
	v.claimFill.BackgroundColor3 = if c.flashInterrupt
		then Color3.fromRGB(230, 60, 60)
		else Color3.fromRGB(120, 255, 140)
	v.claimText.Text = if c.flashInterrupt
		then c.interruptReasonText
		else if c.isLocalClaimer
			then `CLAIMING… {c.countdownText}`
			else `{c.claimerLabel} {c.countdownText}`
	v.claimButton.Visible = c.showHoldPromptButton
end

local function render()
	local v = view
	if not v then
		return
	end
	local display = ArenaHUDViewModel.getDisplay(state)
	renderBanner(v, display.banner)
	renderModal(v, display.optInModal)
	renderClaim(v, display.claimRing)
	v.alert.Visible = display.overchargedAlert.visible
end

local function onHeartbeat(dt: number)
	local now = os.clock()
	if now >= nextZoneCheck then
		nextZoneCheck = now + ZONE_CHECK_INTERVAL
		detectZone()
	end
	ArenaHUDViewModel.step(state, dt)
	render()
end

local function sendOptIn(accept: boolean)
	local ok, payload = ArenaHUDViewModel.buildOptInIntent(state, accept)
	if ok then
		fire("OptIn", payload)
	end
end

local function sendClaim(holding: boolean)
	local ok, payload = ArenaHUDViewModel.buildClaimEggIntent(state, holding)
	if ok then
		fire("ClaimEgg", payload)
	end
end

local function bindButtons(v: ArenaHUDView.View)
	v.joinButton.Activated:Connect(function()
		sendOptIn(true)
	end)
	v.stayButton.Activated:Connect(function()
		sendOptIn(false)
	end)
	v.queuedPill.Activated:Connect(function()
		sendOptIn(false)
	end)
	-- Hold semantics for touch: press starts, release (or sliding off) cancels.
	v.claimButton.MouseButton1Down:Connect(function()
		sendClaim(true)
	end)
	v.claimButton.MouseButton1Up:Connect(function()
		sendClaim(false)
	end)
	v.claimButton.MouseLeave:Connect(function()
		sendClaim(false)
	end)
end

local function bindRemotes(folder: Instance)
	local handlers: { [string]: (any, unknown) -> () } = {
		ArenaStateChanged = ArenaHUDViewModel.onArenaStateChanged,
		OptInPrompt = ArenaHUDViewModel.onOptInPrompt,
		EggClaimUpdated = ArenaHUDViewModel.onEggClaimUpdated,
	}
	for name, handler in handlers do
		local remote = folder:WaitForChild(name, 30)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(function(payload)
				handler(state, payload)
			end)
		end
	end
end

function ArenaHUDController.Init(_self: any, _ctx: any)
	view = ArenaHUDView.build(player:WaitForChild("PlayerGui"))
	local v = view :: ArenaHUDView.View
	bindButtons(v)
end

function ArenaHUDController.Start(_self: any, _ctx: any)
	remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if remotes then
		bindRemotes(remotes)
	end
	RunService.Heartbeat:Connect(onHeartbeat)
end

-- For portal billboards (Hub) and debugging.
function ArenaHUDController.getState()
	return state
end

return ArenaHUDController
