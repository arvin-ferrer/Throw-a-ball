--!strict
--[[
	ClientLifecycle.luau
	Deterministic two-phase client controller bootstrapper:
	  Phase 1: Init(ctx) across all controllers (ordered by Priority, then Name)
	  Phase 2: Start(ctx) across all successfully initialized controllers
]]

export type ClientContext = {
	net: any,
	economyConfigs: any,
	isStudio: boolean,
	getController: (name: string) -> ClientController?,
	connectHeartbeat: ((callback: (dt: number) -> ()) -> any)?,
	mountStudioPanel: ((harness: any) -> (() -> ())?)?,
}

export type BaseContextInput = {
	net: any,
	economyConfigs: any,
	isStudio: boolean,
	connectHeartbeat: ((callback: (dt: number) -> ()) -> any)?,
	mountStudioPanel: ((harness: any) -> (() -> ())?)?,
}

export type ClientController = {
	Name: string,
	Priority: number?,
	Init: ((self: ClientController, ctx: ClientContext) -> ())?,
	Start: ((self: ClientController, ctx: ClientContext) -> ())?,
}

export type BootstrapError = {
	controllerName: string,
	phase: "Register" | "Init" | "Start",
	message: string,
}

export type BootstrapOptions = {
	onError: ((controllerName: string, phase: "Register" | "Init" | "Start", err: string) -> ())?,
	spawnStart: ((fn: () -> ()) -> ())?,
}

export type BootstrapResult = {
	initializedCount: number,
	startedCount: number,
	orderedNames: { string },
	errors: { BootstrapError },
}

local DEFAULT_PRIORITY = 100

local ClientLifecycle = {}

local function recordError(
	errors: { BootstrapError },
	options: BootstrapOptions,
	name: string,
	phase: "Register" | "Init" | "Start",
	message: string
)
	table.insert(errors, {
		controllerName = name,
		phase = phase,
		message = message,
	})
	if options.onError then
		options.onError(name, phase, message)
	end
end

local function sortControllers(controllers: { ClientController }): { ClientController }
	local ordered = table.clone(controllers)
	table.sort(ordered, function(a: ClientController, b: ClientController): boolean
		local priorityA = a.Priority or DEFAULT_PRIORITY
		local priorityB = b.Priority or DEFAULT_PRIORITY
		if priorityA ~= priorityB then
			return priorityA < priorityB
		end
		return a.Name < b.Name
	end)
	return ordered
end

local function runInitPhase(
	ordered: { ClientController },
	ctx: ClientContext,
	errors: { BootstrapError },
	options: BootstrapOptions
): { ClientController }
	local initialized: { ClientController } = {}
	for _, controller in ipairs(ordered) do
		if type(controller.Init) == "function" then
			local initFn = controller.Init :: (self: ClientController, ctx: ClientContext) -> ()
			local ok, err = pcall(initFn, controller, ctx)
			if ok then
				table.insert(initialized, controller)
			else
				recordError(errors, options, controller.Name, "Init", tostring(err))
			end
		else
			table.insert(initialized, controller)
		end
	end
	return initialized
end

local function runStartPhase(
	initialized: { ClientController },
	ctx: ClientContext,
	errors: { BootstrapError },
	options: BootstrapOptions
): number
	local startedCount = 0
	for _, controller in ipairs(initialized) do
		if type(controller.Start) ~= "function" then
			startedCount += 1
			continue
		end
		local startFn = controller.Start :: (self: ClientController, ctx: ClientContext) -> ()
		local function invokeStart()
			local ok, err = pcall(startFn, controller, ctx)
			if not ok then
				recordError(errors, options, controller.Name, "Start", tostring(err))
			end
		end
		if options.spawnStart then
			options.spawnStart(invokeStart)
			startedCount += 1
		else
			local ok, err = pcall(startFn, controller, ctx)
			if ok then
				startedCount += 1
			else
				recordError(errors, options, controller.Name, "Start", tostring(err))
			end
		end
	end
	return startedCount
end

function ClientLifecycle.bootstrap(
	controllers: { ClientController },
	baseCtx: BaseContextInput,
	options: BootstrapOptions?
): BootstrapResult
	local opts = options or {}
	local errors: { BootstrapError } = {}
	local byName: { [string]: ClientController } = {}
	local uniqueControllers: { ClientController } = {}

	for _, controller in ipairs(controllers) do
		if byName[controller.Name] then
			recordError(errors, opts, controller.Name, "Register", "Duplicate controller name")
		else
			byName[controller.Name] = controller
			table.insert(uniqueControllers, controller)
		end
	end

	local ordered = sortControllers(uniqueControllers)
	local ctx: ClientContext = {
		net = baseCtx.net,
		economyConfigs = baseCtx.economyConfigs,
		isStudio = baseCtx.isStudio,
		getController = function(name: string): ClientController?
			return byName[name]
		end,
		connectHeartbeat = baseCtx.connectHeartbeat,
		mountStudioPanel = baseCtx.mountStudioPanel,
	}

	local initialized = runInitPhase(ordered, ctx, errors, opts)
	local startedCount = runStartPhase(initialized, ctx, errors, opts)

	local orderedNames: { string } = {}
	for _, controller in ipairs(ordered) do
		table.insert(orderedNames, controller.Name)
	end

	return {
		initializedCount = #initialized,
		startedCount = startedCount,
		orderedNames = orderedNames,
		errors = errors,
	}
end

return ClientLifecycle
