local actor

local Nodes
local Self

function Startup(NodesModule, nodes, rayParams)
	Nodes = require(NodesModule)
	Self = {
		Nodes = nodes,
		RayParams = rayParams,
	}
	setmetatable(Self, Nodes.Class)
end

function Execute(...)
	local pack = table.pack(...)

	task.desynchronize()

	local results = table.pack(Self:FindPath(unpack(pack)))

	task.synchronize()

	actor.Finished:Fire(unpack(results))
end

return function(_actor: {
	Execute:BindableEvent,
	Finished:BindableEvent,
	Startup:BindableEvent,
})
	actor = _actor
	actor.Startup.Event:Connect(Startup)
	actor.Execute.Event:Connect(Execute)
end