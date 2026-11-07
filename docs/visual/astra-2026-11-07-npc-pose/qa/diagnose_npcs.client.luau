--!nonstrict
-- Run once in Studio CLIENT Command Bar, or as a temporary LocalScript.
-- Read-only, bounded to 10 seconds. Do not include in the published game.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local DURATION = 10
local VIEW_DISTANCE = 120
local observed = {}

local function joint(model, name)
	local legacy
	for _, item in model:GetDescendants() do
		if item:IsA("AnimationConstraint") then
			local at = item.Attachment0
			if
				item.Name == name
				or item.Name == name .. "AnimationConstraint"
				or (at and at.Name == name .. "RigAttachment")
			then
				return item
			end
		elseif item:IsA("Motor6D") and item.Name == name then
			legacy = item
		end
	end
	return legacy
end

local function xAngle(item)
	if not item or not item.Parent then
		return nil
	end
	local angle = item.Transform:ToOrientation()
	return math.deg(angle)
end

local function candidate(model)
	if not model:IsA("Model") or observed[model] then
		return
	end
	local motors, constraints, meshes, badAnchors = 0, 0, 0, {}
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") then
			motors += 1
		elseif item:IsA("AnimationConstraint") then
			constraints += 1
		elseif item:IsA("MeshPart") then
			meshes += 1
		end
		if
			item:IsA("BasePart")
			and item ~= root
			and item.Anchored
			and item:GetAttribute("Loose") ~= true
			and not item:FindFirstAncestorWhichIsA("Accessory")
		then
			table.insert(badAnchors, item.Name)
		end
	end
	print(
		"[NpcPoseQA]",
		model:GetFullName(),
		"BodySource",
		model:GetAttribute("BodySource"),
		"Motor6D",
		motors,
		"AnimationConstraint",
		constraints,
		"MeshParts",
		meshes,
		"Anchored body parts except root",
		table.concat(badAnchors, ",")
	)
	observed[model] = {
		sittingFrames = 0,
		expectedSitFrames = 0,
		walkFrames = 0,
		kneeMoved = false,
		missing = {},
		leftMin = math.huge,
		leftMax = -math.huge,
		rightMin = math.huge,
		rightMax = -math.huge,
	}
end

local started = os.clock()
repeat
	RunService.PostSimulation:Wait()
	for _, model in CollectionService:GetTagged("NpcSitter") do
		candidate(model)
	end
	for _, model in CollectionService:GetTagged("NpcWalker") do
		candidate(model)
	end
	local camera = workspace.CurrentCamera
	for model, result in observed do
		local root = model:FindFirstChild("HumanoidRootPart")
		if
			not model.Parent
			or not root
			or not camera
			or (model:GetPivot().Position - camera.CFrame.Position).Magnitude > VIEW_DISTANCE
		then
			continue
		end
		local lh, rh = joint(model, "LeftHip"), joint(model, "RightHip")
		local lk, rk = joint(model, "LeftKnee"), joint(model, "RightKnee")
		for name, item in { LeftHip = lh, RightHip = rh, LeftKnee = lk, RightKnee = rk } do
			if not item then
				result.missing[name] = true
			end
		end
		-- Nil entries do not appear in the table above, so check all four explicitly.
		if not lh then
			result.missing.LeftHip = true
		end
		if not rh then
			result.missing.RightHip = true
		end
		if not lk then
			result.missing.LeftKnee = true
		end
		if not rk then
			result.missing.RightKnee = true
		end
		local a, b, c, d = xAngle(lh), xAngle(rh), xAngle(lk), xAngle(rk)
		if model:GetAttribute("Sitting") == true then
			result.sittingFrames += 1
			if
				a
				and b
				and c
				and d
				and math.abs(a - 90) < 5
				and math.abs(b - 90) < 5
				and math.abs(c + 90) < 5
				and math.abs(d + 90) < 5
			then
				result.expectedSitFrames += 1
			end
		elseif model:GetAttribute("Walking") == true then
			result.walkFrames += 1
			if (c and math.abs(c) > 10) or (d and math.abs(d) > 10) then
				result.kneeMoved = true
			end
			for prefix, partName in { left = "LeftFoot", right = "RightFoot" } do
				local foot = model:FindFirstChild(partName, true)
				if foot and foot:IsA("BasePart") then
					local height = foot.Position.Y - root.Position.Y
					result[prefix .. "Min"] = math.min(result[prefix .. "Min"], height)
					result[prefix .. "Max"] = math.max(result[prefix .. "Max"], height)
				end
			end
		end
	end
until os.clock() - started >= DURATION

local count = 0
for model, result in observed do
	count += 1
	local absent = {}
	for name in result.missing do
		table.insert(absent, name)
	end
	print(
		"[NpcPoseQA] RESULT",
		model.Name,
		"missing observed during window",
		table.concat(absent, ","),
		"seated frames / correct pose",
		result.sittingFrames,
		result.expectedSitFrames
	)
	if result.walkFrames > 0 then
		local left = if result.leftMin < math.huge then result.leftMax - result.leftMin else nil
		local right = if result.rightMin < math.huge then result.rightMax - result.rightMin else nil
		print(
			"[NpcPoseQA] WALK",
			model.Name,
			"frames",
			result.walkFrames,
			"knee >10deg",
			result.kneeMoved,
			"left/right foot Y range relative to root",
			left,
			right
		)
	else
		print("[NpcPoseQA] WALK NOT OBSERVED", model.Name, "trigger a real break and rerun; this is not a pass")
	end
end
if count == 0 then
	warn("[NpcPoseQA] No NpcSitter/NpcWalker models observed. Check server tags, published version and client context.")
end
