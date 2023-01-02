local ParallelWorker = require(script.Parent.ParallelWorker)

local module = {}

export type Segment = {
	id: number,
	m: number,
	o: Vector3,
	r: Vector3,
	w: number
}

export type Node = {Segment}

export type Nodes = {
	[number]: Node
}

local LineWorker = require(script.LineWorker)
local workerFindConnections = ParallelWorker.new(script.LineWorker)

local RunService = game:GetService("RunService")

local IS_PARALLEL = true

local class = {}
class.__index = class

export type Settings = {
	RayParams: RaycastParams,
}

function module.new(Settings: Settings) : typeof(class)
	local self = setmetatable({}, class)

	self.RayParams = Settings.RayParams

	local baseWorker = script:WaitForChild("Worker")
	local finderWorker = script:WaitForChild("FinderWorker")
	baseWorker.Parent = finderWorker

	local parent:Instance = nil

	if RunService:IsClient() then
		local Players = game:GetService("Players")
		local player = assert(Players.LocalPlayer)

		parent = player:WaitForChild("PlayerScripts")

		local run = script:WaitForChild("Client")
		run.Name = "Runner"
		run.Parent = baseWorker
	else
		parent = game:GetService("ServerScriptService")
		
		local run = script:WaitForChild("Server")
		run.Name = "Runner"
		run.Parent = baseWorker
	end

	self.Worker = finderWorker:Clone()
	self.Worker.Worker.Runner.Disabled = false
	self.Worker.Parent = parent

	return self
end

--[[
	Computes the nodes between all points in the given array.
	Returns: {
		nodeId = {
			{
				id = nodeId,
				m = distance,
				o = origin,
				r = relative,
				w = weightedDistance
			},
			...
		},
	}

	YIELDS
]]
function class:FindConnections(points: {Vector3}, weights: {number}): Nodes
	local nodes = {}
	
	local RayParams = self.RayParams

	local finished = 0

	for i in ipairs(points) do
		if IS_PARALLEL then
			task.spawn(function()
				local _completed, results = workerFindConnections:Invoke(i, points, weights, RayParams)

				nodes[i] = results
				finished += 1
			end)
		else
			nodes[i] = LineWorker:Execute(i, points, weights, RayParams)
			finished += 1
		end
	end

	while finished < #points do
		task.wait()
	end

	self.Nodes = nodes

	self.Worker.Worker.Startup:Fire(script, self.Nodes, self.RayParams)

	self.ExecuteEvent = self.Worker.Worker.Execute
	self.FinishedEvent = self.Worker.Worker.Finished

	return nodes
end

function class:GetClosestNodeId(point: Vector3): number
	local closestNode = nil
	local closestDistance = math.huge

	local nodes = self.Nodes

	for i, node in ipairs(nodes) do
		local distance = (point - node[1].o).Magnitude

		if distance < closestDistance then
			closestNode = i
			closestDistance = distance
		end
	end

	return closestNode
end

--[[
	Returns the closest segment and the point on the segment to the given point.
]]
function class:GetClosestSegmentPointOnNode(node: Node, point: Vector3): (Segment, Vector3)
	local closestSegment = nil
	local closestDistance = math.huge
	local pointOnSegment = nil


	for i, segment in ipairs(node) do
		local o = segment.o
		local r = segment.r
		local m = segment.m

		local t = (point - o):Dot(r) / m / m

		local _t = t

		if t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end

		local closest = o + r * t
		local distance = (point - closest).Magnitude

		--putPart(closest).CFrame += Vector3.new(0, _t * 10, 0)

		if distance < closestDistance then
			closestSegment = segment
			closestDistance = distance
			pointOnSegment = closest
		end
	end

	return closestSegment, pointOnSegment
end

--[[
	Computes the shortest path between two points using the A* algorithm.

	Returns an array of node ids that represent the shortest path between the two nodes.
]]
function class:AStarPathFind(startId: number, goalId: number): {number}
	local nodes = self.Nodes

	local startNode = nodes[startId]
	local goalNode = nodes[goalId]

	local hashNode = {}

	for i, node in ipairs(nodes) do
		hashNode[node[1].id] = i
	end

	local openSet:{number} = {startId}
	local closedSet:{number} = {}

	local openSetHash = {}
	local closedSetHash = {}

	local cameFrom:{[number]: number} = {}

	local gScore:{[number]: number} = {}
	local fScore:{[number]: number} = {} 

	gScore[startId] = 0
	fScore[startId] = gScore[startId] + (startNode[1].o - goalNode[1].o).Magnitude

	while #openSet > 0 do
		local currentId = nil
		local currentScore = math.huge

		for _, id in ipairs(openSet) do
			if fScore[id] < currentScore then
				currentId = id
				currentScore = fScore[id]
			end
		end

		if currentId == goalId then
			local path = {}
			local current = currentId

			while current ~= startId do
				table.insert(path, 1, current)
				current = cameFrom[current]
			end

			table.insert(path, 1, startId)

			return path
		end

		table.remove(openSet, table.find(openSet, currentId))
		openSetHash[currentId] = nil
		table.insert(closedSet, currentId)
		closedSetHash[currentId] = true

		local current = nodes[currentId]

		for _, neighbor in ipairs(current) do
			if closedSetHash[neighbor.id] then
				continue
			end

			local tentativeGScore = gScore[currentId] + neighbor.w

			if not openSetHash[neighbor.id] then
				table.insert(openSet, neighbor.id)
				openSetHash[neighbor.id] = true
			elseif tentativeGScore >= gScore[neighbor.id] then
				continue
			end

			cameFrom[neighbor.id] = currentId
			gScore[neighbor.id] = tentativeGScore
			fScore[neighbor.id] = gScore[neighbor.id] + (neighbor.o - goalNode[1].o).Magnitude
		end
	end

	return {}
end

--[[
	FindPath
		Find a path between two positions using the given nodes

	Parameters:
		nodes: Nodes
			The nodes to use for pathfinding
		startPos: Vector3
			The start position
		goalPos: Vector3
			The goal position
		RayParams: RaycastParams
			The raycast parameters to use for pathfinding
		truncatePath: boolean
			Whether or not to truncate the path to remove nodes that are already visible from the start or goal

	Returns:
		{Vector3}, number
			The path and the time it took to find the path
]]
function class:FindPath(startPos: Vector3, goalPos: Vector3, truncatePath: boolean): ({Vector3}, number)
	local startTime = os.clock()

	local nodes = self.Nodes
	local RayParams = self.RayParams

	--If there are no nodes, just return the start and goal positions
	if #nodes == 0 then
		return {startPos, goalPos}, os.clock() - startTime
	end

	--If the start and goal positions are mutual, just return them
	if not workspace:Raycast(startPos, goalPos - startPos, RayParams) then
		return {startPos, goalPos}, os.clock() - startTime
	end

	local startId = self:GetClosestNodeId(startPos)
	local goalId = self:GetClosestNodeId(goalPos)

	local _startSegment, startSegmentPoint = self:GetClosestSegmentPointOnNode(nodes[startId], startPos)
	local _goalSegment, goalSegmentPoint = self:GetClosestSegmentPointOnNode(nodes[goalId], goalPos)

	local path = self:AStarPathFind(startId, goalId)

	--Convert path to vector path
	local vectorPath: {Vector3} = {}

	for i, nodeId in ipairs(path) do
		vectorPath[i] = nodes[nodeId][1].o
	end

	--Trivial cases
	if #vectorPath == 0 then
		return {startPos, goalPos}, os.clock() - startTime
	end

	if #vectorPath == 1 then
		return {startPos, startSegmentPoint, vectorPath[1], goalSegmentPoint, goalPos}, os.clock() - startTime
	end

	--Remove opposing nodes from the segment starts
	if (vectorPath[1] - startSegmentPoint).Unit:Dot((vectorPath[2] - startSegmentPoint).Unit) < -0.975 then
		table.remove(vectorPath, 1)
	end

	table.insert(vectorPath, 1, startSegmentPoint)

	if (vectorPath[#vectorPath] - goalSegmentPoint).Unit:Dot((vectorPath[#vectorPath - 1] - goalSegmentPoint).Unit) < -0.975 then
		table.remove(vectorPath, #vectorPath)
	end

	table.insert(vectorPath, goalSegmentPoint)

	if truncatePath then
		--Remove nodes that are already visible from the start or goal
		local removals = {}
		local last = nil

		for i = 1, #vectorPath do
			local rayResult = workspace:Raycast(startPos, vectorPath[i] - startPos, RayParams)

			if not rayResult then
				removals[i] = true
				last = i
			else
				break
			end
		end

		if last then
			removals[last] = nil
			last = nil
		end

		for i = #vectorPath, 1, -1 do
			local rayResult = workspace:Raycast(goalPos, vectorPath[i] - goalPos, RayParams)

			if not rayResult then
				removals[i] = true
				last = i
			else
				break
			end
		end
		
		if last then
			removals[last] = nil
		end

		for i = #vectorPath, 1, -1 do
			if removals[i] then
				table.remove(vectorPath, i)
			end
		end
	end

	--Add start and goal positions
	table.insert(vectorPath, 1, startPos)
	table.insert(vectorPath, goalPos)

	return vectorPath, os.clock() - startTime
end 

--FindPath but runs in parallel. YIELDS
function class:FindPathParallel(startPos: Vector3, goalPos: Vector3, truncatePath: boolean): ({Vector3}, number)
	self.ExecuteEvent:Fire(startPos, goalPos, truncatePath)
	return self.FinishedEvent.Event:Wait()
end

module.Class = class

return module