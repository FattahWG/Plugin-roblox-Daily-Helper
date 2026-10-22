-- Performance: the big costs that a place tree shows before a playtest.

local Workspace = game:GetService("Workspace")

local Util = require(script.Parent.Util)

local Check = {
	id = "performance",
	name = "Performance",
	desc = "Parts, physics, lights, particles, sounds",
}

local LIMITS = {
	parts = 25000,
	looseAssemblies = 150,
	shadowLights = 8,
	particleRate = 200,
	loopingSounds = 12,
}

local function cap(list: { Instance }, size: number): { Instance }
	local result = table.create(math.min(#list, size))
	for i = 1, math.min(#list, size) do
		result[i] = list[i]
	end
	return result
end

function Check.run(ctx)
	local parts, loose, lights, particles, sounds, precise = 0, {}, {}, {}, {}, {}
	local seenRoots = {}
	for index, item in ctx.instances do
		if item:IsA("BasePart") then
			if item:IsDescendantOf(Workspace) then
				parts += 1
				local root = item.AssemblyRootPart
				if root and not root.Anchored and not seenRoots[root] then
					seenRoots[root] = true
					local model = root:FindFirstAncestorWhichIsA("Model")
					if not (model and model:FindFirstChildOfClass("Humanoid")) then
						table.insert(loose, root)
					end
				end
			end
			if item:IsA("PartOperation") and item.CollisionFidelity == Enum.CollisionFidelity.PreciseConvexDecomposition then
				table.insert(precise, item)
			end
		elseif item:IsA("Light") then
			if item.Enabled and item.Shadows then
				table.insert(lights, item)
			end
		elseif item:IsA("ParticleEmitter") then
			if item.Enabled and item.Rate > LIMITS.particleRate then
				table.insert(particles, item)
			end
		elseif item:IsA("Sound") then
			if item.Playing and item.Looped then
				table.insert(sounds, item)
			end
		end
		if index % 2000 == 0 then
			ctx.yield()
		end
	end

	if parts > LIMITS.parts then
		ctx.add({
			severity = "Warning",
			title = string.format("%d parts in Workspace", parts),
			path = "Workspace",
			target = Workspace,
			text = "Phones slow down with many parts. Merge small detail parts into meshes, and turn on "
				.. "StreamingEnabled for a large map.",
		})
	end
	if #loose > LIMITS.looseAssemblies then
		ctx.add({
			severity = "Warning",
			title = Util.plural(#loose, "unanchored assembly", "unanchored assemblies"),
			path = "Press Select to see them",
			target = cap(loose, 500),
			text = "Each one runs physics all the time. Anchor the parts that never move.",
		})
	end
	if #lights > LIMITS.shadowLights then
		ctx.add({
			severity = "Warning",
			title = Util.plural(#lights, "light casts", "lights cast") .. " shadows",
			path = "Press Select to see them",
			target = lights,
			text = "Each shadow light costs a lot on phones. Keep shadows only on the lights that the player sees most.",
			fix = {
				label = "Shadows off on " .. Util.plural(#lights, "light"),
				risky = true,
				apply = function()
					for _, light in lights do
						light.Shadows = false
					end
					return true
				end,
			},
		})
	end
	if #particles > 0 then
		ctx.add({
			severity = "Info",
			title = Util.plural(#particles, "emitter") .. " above " .. LIMITS.particleRate .. " per second",
			path = "Press Select to see them",
			target = particles,
			text = "A high Rate fills the screen with particles on a weak device. Lower the Rate and use "
				.. "bigger particles for the same look.",
		})
	end
	if #sounds > LIMITS.loopingSounds then
		ctx.add({
			severity = "Info",
			title = Util.plural(#sounds, "looping sound") .. " play at start",
			path = "Press Select to see them",
			target = sounds,
			text = "Many looping sounds play at the same time. Start a sound only near its place.",
		})
	end
	if #precise > 0 then
		ctx.add({
			severity = "Info",
			title = Util.plural(#precise, "union") .. " with precise collision",
			path = "Press Select to see them",
			target = cap(precise, 500),
			text = "PreciseConvexDecomposition costs the most physics. Use Box or Hull for a union that a "
				.. "player does not touch closely.",
		})
	end
end

return Check
