local module = {}

type Setting = {
	WeightAngleMultiplier: number, --Adds this * angle to the weight of a segment
}

local results = nil
local isFinished = false

function module:Execute(threadId: number, points: {Vector3}, pointweights: {number}, RayParams)
	results = {}
	isFinished = false

	local main = points[threadId]

	for i, point in ipairs(points) do
		if i == threadId then
			continue
		end

		local relative = point - main
		local magnitude = relative.Magnitude

		local rayResult = workspace:Raycast(main, relative, RayParams) 

		if not rayResult then--or (rayResult.Position-main).Magnitude / magnitude > 0.98 then
		
			local weight = (pointweights[i] + pointweights[threadId]) / 2

			table.insert(results, {
				id=i, 
				m=magnitude,
				o=main,
				r=relative, 
				w=magnitude * weight
			})
		end
	end

	isFinished = true

	return results
end

function module:IsFinished()
	return isFinished
end

function module:GetResults()
	return results
end
 
return module