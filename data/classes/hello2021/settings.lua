--[[
	BPM-2021 (Camellia) - Light Engine port
	settings.lua

	The original Psych mod read its custom event parameters through Psych's
	`Settings` static class (hardcoded here, since the values only ever had one
	valid configuration for this song):

		Settings.noteShimmySpeed      -- how fast the shimmy oscillates
		Settings.noteShimmyDistance   -- how far each lane travels
		Settings.NoteBumpDistance     -- how much a lane bumps on NoteBump
		Settings.NoteBumpSpeed        -- bump duration in beats

	Keeping this table in one place makes the custom events tweakable without
	touching the charts, and mirrors how a Psych modder edited settings.json.
]]

local Settings = {
	noteShimmySpeed = 1.0,
	noteShimmyDistance = 40,
	NoteBumpDistance = 60,
	NoteBumpSpeed = 0.15,
}

local ALIASES = {
	noteshimmy = "noteShimmy",
	noteshimmySpeed = "noteShimmySpeed",
	noteshimmyDistance = "noteShimmyDistance",
	notebump = "NoteBump",
	notebumpdistance = "NoteBumpDistance",
	notebumpspeed = "NoteBumpSpeed",
}

function Settings.get(class, variable)
	local v = tostring(variable or "")
	if Settings[v] ~= nil then return Settings[v] end
	local alias = ALIASES[tostring(v):lower()]
	if alias and Settings[alias] ~= nil then return Settings[alias] end
	return 0
end

return Settings
