local CollectionService = game:GetService("CollectionService")

local Nodes = require(script.Parent.Nodes)

local points = CollectionService:GetTagged("Points")

local pointsArray: {Vector3} = {}
local weightsArray: {number} = {}

for i, point in ipairs(points) do
	pointsArray[i] = point.Position
	weightsArray[i] = point:GetAttribute("Weight") or math.random()*15
end

local RayParams = RaycastParams.new()
RayParams.RespectCanCollide = true
RayParams.IgnoreWater = true
RayParams.FilterType = Enum.RaycastFilterType.Blacklist


local st = os.clock()

local PathFinder = Nodes.new({
	RayParams = RayParams
})

local nodes = PathFinder:FindConnections(pointsArray, weightsArray, RayParams)
 
print("Time to find connections: " .. os.clock() - st)


local numberOfSegments = 0
-- Draw lines between nodes
for i, node in ipairs(nodes) do
	for _, segment in ipairs(node) do
		numberOfSegments += 1

		local pointA = pointsArray[i]
		local pointB = pointsArray[segment.id]

		local line = Instance.new("Part")
		line.Anchored = true
		line.CanCollide = false
		line.Size = Vector3.new(0.1, 0.1, segment.m)
		line.CFrame = CFrame.new(pointA, pointB) * CFrame.new(0, 0, -line.Size.Z / 2)
		local weight = 1 - segment.w/segment.m/15
		line.Color = Color3.fromHSV(weight, 1, 1)
		line.Parent = workspace
	end
end

print("Number of segments: " .. numberOfSegments)


-- Find the shortest path between two points and then line-draw it
local start = workspace:FindFirstChild("Start")
local goal = workspace:FindFirstChild("Goal")

if start and goal then
	local folder = Instance.new("Folder", workspace)
	folder.Name = "Path"

	local timeMovingAverage = 300

	while true do

		local vectorPath, timeTook = PathFinder:FindPath(start.Position, goal.Position, true)

		timeMovingAverage = timeMovingAverage * 0.95 + (timeTook) * 1e6 * 0.05

		print("Time moving average: " .. math.round(timeMovingAverage) .. "us")

		folder:ClearAllChildren()

		for i = 1, #vectorPath - 1 do
			local pointA = vectorPath[i]
			local pointB = vectorPath[i + 1]

			local line = Instance.new("Part", folder)
			line.Anchored = true
			line.CanCollide = false
			line.Size = Vector3.new(1.0, 1.0, (pointA - pointB).Magnitude)
			line.CFrame = CFrame.new(pointB, pointA) * CFrame.new(0, 0, -line.Size.Z / 2) + Vector3.new(0, 1, 0)
			line.Color = Color3.fromRGB(0, 0, 0)
			line.Parent = folder
		end

		task.wait()
	end
end