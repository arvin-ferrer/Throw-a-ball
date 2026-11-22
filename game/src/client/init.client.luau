--!strict
--[[
	Minimal client bootstrap: Init every controller, then Start them (same two-phase order as
	PR #21's ClientLifecycle, which replaces this loader when it merges).
]]
local controllers = {}
for _, module in script.Controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		table.insert(controllers, (require :: any)(module))
	end
end
table.sort(controllers, function(a, b)
	return (a.Priority or 100) < (b.Priority or 100)
end)
for _, controller in controllers do
	if controller.Init then
		controller:Init({})
	end
end
for _, controller in controllers do
	if controller.Start then
		task.spawn(controller.Start, controller, {})
	end
end
print("[BallBrawlClient] Bootstrapped")
