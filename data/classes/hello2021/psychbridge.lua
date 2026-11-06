--[[
	Hello2021 - Light Engine port
	psychbridge.lua

	Installs the Psych Engine (FunkinLua) API used by this mod as ordinary
	globals of the calling script.

	Why a bridge instead of an interpreter?
	---------------------------------------
	Light Engine runs native scripts in a sandbox that blocks `load`,
	`loadstring`, `setfenv` and friends, and its own `funkin.backend.scripts.compat`
	exposes exactly this style of helper API (see funkin/backend/scripts/compat.lua).
	So the original Psych scripts keep their bodies untouched and only get a small
	header that borrows this bridge. Everything runs inside the native script,
	which means the engine's `state`/`game`/`paths` bindings are already present.

	Usage (first line of a ported script):

		local Psych = require("data.classes.hello2021.psychbridge")
		local api = Psych.install(state, "bpm-2021")   -- returns helpers
		Psych.installGlobals(api, getfenv(1) or _G)   -- Psych globals available now

	Then the original Psych body follows verbatim.
]]

local Psych = {}

-- captured before any script environment replaces the `math` global
local REAL_MATH = math

----------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------

local function num(v, default)
	local n = tonumber(v)
	if n == nil then return default end
	return n
end

local function hexColor(value, default)
	local hex = tostring(value or ""):gsub("^#", ""):gsub("^0[xX]", "")
	if #hex ~= 6 or not hex:match("^%x%x%x%x%x%x$") then
		return Color.fromHEX(default or 0xFFFFFF)
	end
	return Color.fromHEX(tonumber(hex, 16))
end

-- Psych easing names -> Light Engine's `Ease` table keys
local EASE_ALIASES = {
	linear = "linear", instant = "linear",
	quadin = "quadIn", quadout = "quadOut", quadinout = "quadInOut",
	cubein = "cubeIn", cubeout = "cubeOut", cubeinout = "cubeInOut",
	quartin = "quartIn", quartout = "quartOut", quartinout = "quartInOut",
	quintin = "quintIn", quintout = "quintOut", quintinout = "quintInOut",
	sinein = "sineIn", sineout = "sineOut", sineinout = "sineInOut",
	expoin = "expoIn", expoout = "expoOut", expoinout = "expoInOut",
	circin = "circIn", circout = "circOut", circinout = "circInOut",
	backin = "backIn", backout = "backOut", backinout = "backInOut",
	elasticin = "elasticIn", elasticout = "elasticOut", elasticinout = "elasticInOut",
	bouncein = "bounceIn", bounceout = "bounceOut", bounceinout = "bounceInOut",
	smoothstep = "smoothStep", smootherstep = "smootherStep",
}

--- Psych writes easings in many shapes ("expoOut", "EXPOIN", "QuartN").
--- Returns a key that exists in Light Engine's `Ease` table.
function Psych.ease(name)
	if type(name) ~= "string" or name == "" then return "linear" end
	local key = name:gsub("[%s_%-]", ""):lower()
	local resolved = EASE_ALIASES[key]
	if resolved and Ease[resolved] then return resolved end
	return "linear"
end

----------------------------------------------------------------------------
-- install
----------------------------------------------------------------------------

function Psych.install(state, songSlug, homeGroup)
	local self = {
		state = state,
		homeGroup = homeGroup,
		song = songSlug or "bpm-2021",
		objects = {},     -- tag -> native object
		textures = {},    -- tag -> generated texture (makeGraphic)
		groups = {},      -- camera name -> SpriteGroup
		tweens = {},      -- tag -> tween data
		timers = {},      -- tag -> Timer
		animAngles = {},  -- notefield -> {lane -> angle}
		mods = {},        -- notefield -> NoteModifier
		objectCam = {},   -- tag -> camera key
		hudZoom = {},     -- camera -> authored zoom (re-applied every frame)
		warned = {},
	}
	setmetatable(self, {__index = Psych})

	-- `state` fields that Psych scripts address by name
	self.state.camZooming = self.state.camZooming ~= false

	----------------------------------------------------------------------
	-- diagnostics
	----------------------------------------------------------------------
	function self.warn(_, msg)
		msg = tostring(msg)
		if self.warned[msg] then return end
		self.warned[msg] = true
		Logger.log("warn", "[Hello2021] " .. msg)
	end

	----------------------------------------------------------------------
	-- property paths
	----------------------------------------------------------------------
	self.pathAliases = {
		camgame = "camGame", camhud = "camHUD", camother = "camOther",
		camnotes = "camNotes", healthbar = "healthBar", scoretxt = "scoreText",
		iconp1 = "healthBar.iconP1", iconp2 = "healthBar.iconP2",
		timebar = "timeBar", timebarbg = "timeBarBG", timebartext = "timeTxt",
		healthbarbg = "healthBar.bg",
	}

	--- Splits "a.b[0].c" into tokens, converting indexes to Lua's 1-based.
	local function tokenize(path)
		local tokens = {}
		for token in tostring(path):gmatch("[^%.]+") do
			local name, index = token:match("^([^%[]+)%[(%-?%d+)%]$")
			if name then
				tokens[#tokens + 1] = name
				tokens[#tokens + 1] = num(index, 0) + 1
			else
				local n = tonumber(token)
				tokens[#tokens + 1] = n and (n + 1) or token
			end
		end
		return tokens
	end

	local function isObj(v)
		return type(v) == "table" or type(v) == "userdata"
	end

	--- Root resolution: lua objects, then state fields, then characters,
	--- then cameras.
	function self.root(_, name)
		if self.objects[name] ~= nil then return self.objects[name] end
		local s = self.state
		if isObj(s[name]) then return s[name] end
		if s.characters and isObj(s.characters[name]) then return s.characters[name] end
		local lower = tostring(name):lower()
		if lower == "camgame" then return s.camGame or game.camera end
		if lower == "camhud" then return s.camHUD end
		if lower == "camother" then return s.camOther end
		if lower == "camnotes" then return s.camNotes end
		return nil
	end

	function self.resolve(_, path)
		if type(path) ~= "string" or path == "" then return nil end
		local tokens = tokenize(path)
		if #tokens == 0 then return nil end

		local first = tostring(tokens[1])
		local alias = self.pathAliases[first:lower()]
		if alias then
			local expanded = {}
			for part in alias:gmatch("[^%.]+") do expanded[#expanded + 1] = part end
			for i = 2, #tokens do expanded[#expanded + 1] = tokens[i] end
			tokens = expanded
		end

		local current = self:root(tostring(tokens[1]))
		if current == nil then return nil end
		for i = 2, #tokens - 1 do
			if not isObj(current) then return nil end
			current = current[tokens[i]]
			if current == nil then return nil end
		end
		return current, tokens[#tokens]
	end

	function self.get(_, path)
		if path == nil then return nil end
		local object, key = self:resolve(tostring(path))
		if object == nil then return nil end
		return object[key]
	end

	function self.set(_, path, value)
		if path == nil then return false end
		local object, key = self:resolve(tostring(path))
		if (type(object) == "table" or type(object) == "userdata") and key ~= nil then
			object[key] = value
			return true
		end
		-- values Light Engine simply does not draw (Psych HUD pieces)
		local root = tostring(path):match("^([%w_]+)")
		if root and Psych.VIRTUAL[root:lower()] then return true end
		self:warn("setProperty: unknown path '" .. tostring(path) .. "'")
		return false
	end

	----------------------------------------------------------------------
	-- mod settings (the original mod shipped the values its custom events
	-- read through Psych's `Settings` instance)
	----------------------------------------------------------------------
	function self.objectSetting(_, class, variable)
		local ok, settings = pcall(require, "data.classes.hello2021.settings")
		if not ok or not settings then return 0 end
		return settings.get(class, variable)
	end

	----------------------------------------------------------------------
	-- cameras
	----------------------------------------------------------------------
	function self.camera(_, name)
		local n = tostring(name or "game"):lower()
		if n == "game" or n == "camgame" then return self.state.camGame or game.camera end
		if n == "hud" or n == "camhud" then return self.state.camHUD end
		if n == "other" or n == "camother" then return self.state.camOther end
		if n == "notes" or n == "camnotes" then return self.state.camNotes end
	end

	--- Group drawn by a camera. Psych sprites sent to `camOther` live in
	--- their own layer; Light Engine has no such container, so we make one.
	function self.group(_, name)
		local n = tostring(name or "game"):lower()
		if n == "game" or n == "camgame" then
			return self.state.stage
		end
		local key = (n == "hud" and "hud") or (n == "notes" and "notes") or "other"
		local group = self.groups[key]
		if group then return group end

		local cam = self:camera(key)
		if not cam then return self.state.stage end

		group = SpriteGroup(self.state)
		group.cameras = {cam}
		group.zIndex = (key == "notes" and 900) or (key == "hud" and 100) or 50
		self.state:add(group)
		self.groups[key] = group
		return group
	end

	----------------------------------------------------------------------
	-- object creation
	----------------------------------------------------------------------

	local function resetAnchor(obj)
		obj.origin.x, obj.origin.y = 0, 0
		obj.offset.x, obj.offset.y = 0, 0
	end

	function self.sprite(_, tag, image, x, y, animated)
		tag = tostring(tag or "")
		if tag == "" then return nil end
		if self.objects[tag] then self:destroy(tag) end

		local obj = Sprite(x or 0, y or 0)
		if image ~= nil and image ~= "" then
			local clean = tostring(image):gsub("^images/", ""):gsub("%.png$", "")
			if animated then
				local atlas = paths.getAtlas(clean)
				if atlas then
					obj:setFrames(atlas)
					if obj.animation:has("idle") then obj.animation:play("idle", true) end
				else
					local tex = paths.getImage(clean)
					if tex then obj:loadTexture(tex) else self:warn("missing atlas '" .. clean .. "'") end
				end
			else
				local tex = paths.getImage(clean)
				if tex then obj:loadTexture(tex) else self:warn("missing image '" .. clean .. "'") end
			end
		end
		resetAnchor(obj)
		self.objects[tag] = obj
		return obj
	end

	function self.graphic(_, tag, width, height, color)
		tag = tostring(tag or "")
		if tag == "" then return nil end
		width = math.max(1, math.floor(num(width, 1)))
		height = math.max(1, math.floor(num(height, 1)))

		local obj = self.objects[tag]
		if not obj then
			obj = Sprite(0, 0)
			self.objects[tag] = obj
		end

		local data = love.image.newImageData(width, height)
		data:mapPixel(function() return 1, 1, 1, 1 end)
		local texture = love.graphics.newImage(data)
		data:release()
		if self.textures[tag] and self.textures[tag].release then self.textures[tag]:release() end
		self.textures[tag] = texture

		obj.frames = nil
		obj:loadTexture(texture)
		obj.color = hexColor(color, 0xFFFFFF)
		obj.scale:set(1, 1)
		resetAnchor(obj)
		return obj
	end

	function self.text(_, tag, content, width, x, y)
		tag = tostring(tag or "")
		local font = paths.getFont("vcr.ttf", 16) or love.graphics.getFont()
		local limit = (num(width, 0) > 0) and num(width) or nil
		local obj = Text(x or 0, y or 0, tostring(content or ""), font, Color.WHITE, "center", limit)
		if obj.outline then
			obj.outline.style = "simple"
			obj.outline.width = 1
		end
		self.objects[tag] = obj
		return obj
	end

	----------------------------------------------------------------------
	-- membership
	----------------------------------------------------------------------
	--- Group that receives camGame sprites: the stage script's own Stage when
	--- running as a stage, otherwise the play state stage.
	function self.home(_, name)
		local n = tostring(name or "game"):lower()
		if n ~= "game" and n ~= "camgame" then return self:group(n) end
		if self.homeGroup then return self.homeGroup end
		return self.state.stage or self.state
	end

	function self.add(_, tag, front)
		local obj = self.objects[tag]
		if not obj then return false end
		local group = self:home(self.objectCam[tag] or "game")
		if not group then return false end
		if obj.__helloParent then
			obj.__helloParent:remove(obj)
			obj.__helloParent = nil
		end
		if front then group:add(obj) else group:insert(1, obj) end
		obj.__helloParent = group
		return true
	end

	function self.order(_, tag, index)
		local obj = self.objects[tag]
		if not obj or not obj.__helloParent then return false end
		local group = obj.__helloParent
		local size = #group.members
		group:remove(obj)
		group:insert(math.min(math.max(1, math.floor(num(index, 0)) + 1), size), obj)
		return true
	end

	function self.cameraOn(_, tag, camera)
		local cam = self:camera(camera)
		if not cam then return false end
		local key = tostring(camera or "game"):lower()
		self.objectCam[tag] = key

		local obj = self.objects[tag]
		if not obj then return true end
		obj.cameras = {cam}

		-- Psych keeps one display list per camera; mirror that so
		-- setObjectOrder/setObjectCamera compose the same way.
		if obj.__helloParent then
			obj.__helloParent:remove(obj)
			obj.__helloParent = nil
			local group = self:home(key)
			if group then
				group:add(obj)
				obj.__helloParent = group
			end
		end
		return true
	end

	function self.destroy(_, tag, destroyObject)
		local obj = self.objects[tag]
		self.objects[tag] = nil
		self.objectCam[tag] = nil
		if obj and obj.__helloParent then
			obj.__helloParent:remove(obj)
			obj.__helloParent = nil
		end
		if obj and destroyObject ~= false and obj.destroy then
			pcall(obj.destroy, obj)
		end
		local tex = self.textures[tag]
		self.textures[tag] = nil
		if tex and tex.release then pcall(tex.release, tex) end
		return obj ~= nil
	end

	----------------------------------------------------------------------
	-- tweens (Psych tags + onTweenCompleted)
	----------------------------------------------------------------------
	function self.tweenTarget(_, ref)
		if type(ref) ~= "string" then return ref end
		return self.objects[ref] or self:camera(ref)
	end

	function self.cancelTween(_, tag)
		local data = self.tweens[tag]
		if not data then return false end
		self.tweens[tag] = nil
		if data.instance then
			if data.instance.destroy then pcall(data.instance.destroy, data.instance)
			elseif data.instance.cancel then pcall(data.instance.cancel, data.instance) end
		end
		return true
	end

	--- Light Engine recomputes `game.camera.zoom` every frame from
	--- `state.camZoom`, so tweening the camera object would be overwritten.
	--- Psych drove `defaultCamZoom` the same way.
	function self.zoomTarget(_, ref, property)
		if property ~= "zoom" then return nil end
		local name = tostring(ref or ""):lower()
		if name == "camgame" or name == "game" then
			return self.state, "camZoom"
		end
		return nil
	end

	function self.tween(_, tag, object, property, value, duration, ease)
		if object == nil then return false end
		tag = tostring(tag or ("__tw" .. tostring(#self.tweens)))
		value = tonumber(value)
		if value == nil then return false end
		duration = math.max(0, num(duration, 0))
		self:cancelTween(tag)

		if duration <= 0 then
			object[property] = value
			self:onTweenCompleted(tag)
			return true
		end

		local data = {object = object, property = property}
		local manager = self.state.tween or Tween.new()
		data.instance = manager:tween(object, {[property] = value}, duration, {
			ease = Psych.ease(ease),
			onComplete = function()
				if self.tweens[tag] ~= data then return end
				self.tweens[tag] = nil
				self:onTweenCompleted(tag)
			end,
		})
		self.tweens[tag] = data
		return true
	end

	function self.onTweenCompleted(_, tag)
		if self.__onTweenCompleted then
			pcall(self.__onTweenCompleted, tag)
		end
	end

	--- Psych tweenShit(): "obj" targets the object, "obj.scale" the Scale
	--- inside it, so doTweenX('tag','obj.scale',2) means obj.scale.x = 2.
	function self.tweenPath(_, tag, ref, property, value, duration, ease)
		-- camGame zoom lives on the state (see zoomTarget)
		local specialHolder, specialKey = self:zoomTarget(ref, property)
		if specialHolder then
			return self:tween(tag, specialHolder, specialKey, value, duration, ease)
		end

		local base, member
		if type(ref) == "string" then base, member = ref:match("^(.-)%.([%w_]+)$") end
		if not base then
			return self:tween(tag, self:tweenTarget(ref), property, value, duration, ease)
		end
		local root = self:tweenTarget(base)
		if not root or root[member] == nil then
			self:warn("doTween: unknown object '" .. tostring(ref) .. "'")
			return false
		end
		local target = root[member]
		-- Vector2/Point member: its own components are x/y
		if type(target) == "table" and target.x ~= nil then
			if property == "x" or property == "y" then
				return self:tween(tag, target, property, value, duration, ease)
			elseif property == "angle" or property == "alpha" then
				return self:tween(tag, root, property, value, duration, ease)
			end
		end
		return self:tween(tag, target, property, value, duration, ease)
	end

	----------------------------------------------------------------------
	-- group access (Psych's *FromGroup)
	----------------------------------------------------------------------
	function self.groupMember(_, group, index)
		local name = tostring(group or ""):lower()
		index = math.floor(num(index, 0)) + 1

		if name == "strumlinenotes" or name == "playerstrums" or name == "opponentstrums" then
			local members = {}
			local fields
			if name == "playerstrums" then fields = {self:field(true)}
			elseif name == "opponentstrums" then fields = {self:field(false)}
			else fields = {self:field(false), self:field(true)} end
			for _, field in ipairs(fields) do
				if field and field.lanes then
					for i = 1, #field.lanes do members[#members + 1] = field.lanes[i].receptor end
				end
			end
			return members[index]
		end

		local obj = self.objects[group]
		if obj and obj.members then return obj.members[index] end
		return nil
	end

	local RELATIVE = {
		x = "x", y = "y", angle = "angle", alpha = "alpha", visible = "visible",
		zoom = "zoom", width = "width", height = "height", scale = "scale",
		offset = "offset", origin = "origin", color = "color", blend = "blend",
	}

	function self.getOn(_, object, property)
		if object == nil or property == nil then return nil end
		if type(property) == "number" then return object[property + 1] end
		local current = object
		for token in tostring(property):gmatch("[^%.]+") do
			local key = RELATIVE[token:lower()] or token
			if not isObj(current) then return nil end
			current = current[key]
			if current == nil then return nil end
		end
		return current
	end

	function self.setOn(_, object, property, value)
		if object == nil or property == nil then return false end
		local tokens = {}
		for token in tostring(property):gmatch("[^%.]+") do
			tokens[#tokens + 1] = RELATIVE[token:lower()] or token
		end
		if #tokens == 0 then return false end
		local current = object
		for i = 1, #tokens - 1 do
			if not isObj(current) then return false end
			current = current[tokens[i]]
			if current == nil then return false end
		end
		current[tokens[#tokens]] = value
		return true
	end

	----------------------------------------------------------------------
	-- HUD helpers
	----------------------------------------------------------------------
	function self.hideHUD(_)
		local s = self.state
		local list = {"healthBar", "scoreText", "judgeSprites", "countdown"}
		for _, field in ipairs(list) do
			local obj = s[field]
			if obj then
				obj.visible = false
				if obj.members then
					for _, child in ipairs(obj.members) do child.visible = false end
				end
			end
		end
	end

	----------------------------------------------------------------------
	-- note tweens (Psych strum indices: 0-3 opponent, 4-7 player)
	----------------------------------------------------------------------
	local PSYCH_STRUM_X = 92   -- Psych: opponent lane 0
	local PSYCH_STRUM_Y = 50   -- Psych: upscroll strum line
	local NOTE_W = 112

	function self.field(_, forPlayer)
		local s = self.state
		if forPlayer then return s.playerNotefield end
		return s.enemyNotefield
	end

	function self.downscroll(_)
		if self.state.downScroll ~= nil then return self.state.downScroll == true end
		return ClientPrefs and ClientPrefs.data and ClientPrefs.data.downScroll == true
	end

	-- Psych's noteTween* names -> internal property keys
	local NOTE_PROP = {
		x = "x", y = "y", alpha = "alpha",
		angle = "noteAngle", direction = "direction",
	}

	function self.noteTween(_, tag, note, property, value, duration, ease)
		property = NOTE_PROP[property] or property
		note = math.floor(num(note, 0))
		local forPlayer = note >= 4
		local laneIndex = (note % 4) + 1
		local field = self:field(forPlayer)
		if not field or not field.lanes or not field.lanes[laneIndex] then return false end

		local receptor = field.lanes[laneIndex].receptor
		if not receptor then return false end

		value = tonumber(value) or 0
		tag = tostring(tag or (property .. tostring(note)))
		self:cancelTween(tag)

		local from
		if property == "direction" or property == "noteAngle" then
			from = self:angleMod(field)[property == "direction" and "direction" or "offset"]
		else
			from = receptor[property] or 0
		end

		if num(duration, 0) <= 0 then
			self:applyNoteTween(field, laneIndex, receptor, property, forPlayer, value)
			self:onTweenCompleted(tag)
			return true
		end

		local data = {noteTween = true, field = field, lane = laneIndex,
			receptor = receptor, property = property, forPlayer = forPlayer,
			from = from, to = value, time = 0, duration = num(duration, 0),
			ease = Psych.ease(ease)}
		self.tweens[tag] = data
		return true
	end

	function self.applyNoteTween(_, field, laneIndex, receptor, property, forPlayer, value)
		if property == "direction" then
			self:angleMod(field).direction = value
		elseif property == "noteAngle" then
			local mod = self:angleMod(field)
			mod.offset = value
			self.animAngles[field] = self.animAngles[field] or {}
			self.animAngles[field][laneIndex] = value
			receptor.angle = value
		elseif property == "y" then
			-- Psych's screen Y -> Light Engine receptor offset
			local delta = value - PSYCH_STRUM_Y
			receptor.y = self:downscroll() and -delta or delta
		elseif property == "x" then
			local lane = field.lanes[laneIndex]
			local psychDefault = PSYCH_STRUM_X + (laneIndex - 1) * NOTE_W + (forPlayer and 640 or 0)
			receptor.x = (lane and lane.x or receptor.x) + (value - psychDefault)
		else
			receptor[property] = value
		end
	end

	--- Psych "direction" (90 = straight down) and "angle" for the notes.
	--- Implemented with the native NoteModifier stack.
	function self.angleMod(_, field)
		local mod = self.mods[field]
		if mod then return mod end

		local DirectionMod = NoteModifier:extend("Hello2021NoteAngle")
		function DirectionMod:new()
			DirectionMod.super.new(self)
			self:setModifier(1, 1, true)
			self.direction = 90
			self.offset = 0
		end
		function DirectionMod:apply(notefield)
			local rotation = self.direction - 90 + self.offset
			for _, lane in ipairs(notefield.lanes or {}) do
				local receptor = lane.receptor
				NoteModifier.prepare(receptor, "noteAngles", receptor.noteAngles)
				receptor.noteAngles = rotation
			end
		end
		-- Psych places notes at (cos dir, sin dir) * distance; Light Engine
		-- already uses (0, distance), so add the difference.
		-- Psych sets note.angle = direction - 90, so the sprite is rotated as
		-- well as displaced. `values.y` already starts at `pos` (the engine
		-- default for the y axis), so only the delta is added.
		function DirectionMod:applyPath(values, curBeat, pos, notefield, direction)
			local rotation = self.direction - 90
			if rotation == 0 and self.offset == 0 then return end

			local rad = math.rad(self.direction)
			values.x = values.x + math.cos(rad) * pos
			values.y = values.y + (math.sin(rad) - 1) * pos
			values.rotZ = (values.rotZ or 0) + rotation + self.offset
		end

		mod = DirectionMod()
		field.modifiers = field.modifiers or {}
		field.modifiers["Hello2021NoteAngle"] = mod
		self.mods[field] = mod
		return mod
	end

	--- Advances tagged tweens every frame (note tweens are not engine tweens).
	function self.update(_, dt)
		local finished
		for tag, data in pairs(self.tweens) do
			if data.noteTween then
				data.time = data.time + dt
				local p = data.duration > 0 and math.min(1, data.time / data.duration) or 1
				local ease = Ease[data.ease] or Ease.linear
				local value = data.from + (data.to - data.from) * ease(p)
				self:applyNoteTween(data.field, data.lane, data.receptor,
					data.property, data.forPlayer, value)
				if p >= 1 then
					finished = finished or {}
					finished[#finished + 1] = tag
				end
			end
		end
		if finished then
			for _, tag in ipairs(finished) do
				if self.tweens[tag] then
					self.tweens[tag] = nil
					self:onTweenCompleted(tag)
				end
			end
		end

		-- Light Engine lerps camHUD/camNotes zoom back to 1 every frame (the beat
	-- bop). Psych scripts that author a HUD zoom expect it to stick, so we
	-- re-apply the last authored value, exactly like the original ran with
	-- camZooming disabled.
	for camera, value in pairs(self.hudZoom or {}) do
		camera.zoom = value
	end

	-- the notefield restores receptor rotation after every render
		for field, angles in pairs(self.animAngles) do
			for laneIndex, angle in pairs(angles) do
				local lane = field.lanes and field.lanes[laneIndex]
				if lane and lane.receptor and lane.receptor.angle ~= angle then
					lane.receptor.angle = angle
				end
			end
		end
	end

	function self.dispose(_)
		for tag in pairs(self.tweens) do self:cancelTween(tag) end
		for tag in pairs(self.objects) do self:destroy(tag) end
		for _, group in pairs(self.groups) do
			self.state:remove(group)
			if group.destroy then pcall(group.destroy, group) end
		end
		self.groups = {}
		for field in pairs(self.mods) do
			field.modifiers["Hello2021NoteAngle"] = nil
		end
		self.mods = {}
	end

	return self
end

-- Psych HUD members Light Engine does not render; writing to them is a no-op.
Psych.VIRTUAL = {
	camzooming = true, curbpm = true, middlescroll = true, downscroll = true,
	camzoom = true, timebar = true, timebarbg = true, timebartext = true,
	healthbarbg = true, scoretext = true, render = true, camhudzoom = true,
}

----------------------------------------------------------------------------
-- global installation
----------------------------------------------------------------------------

--- Defines the Psych globals as fields of `env`, which must be the calling
--- script's own environment (`_ENV` in LuaJIT or `getfenv(1)`), so the original
--- Psych body can use them as plain globals.
function Psych.installGlobals(api, env)
	local state = api.state

	local function define(name, value) env[name] = value end

	-- Psych ran on LuaJIT, whose math.random() raises on more than two
	-- arguments. The original mod calls math.random(a, b, c, ...) in onUpdate,
	-- which aborted that callback every frame. Keep one/two argument behaviour
	-- identical and let the multi-value form pick one of the given values
	-- (what the author clearly intended). `REAL_MATH` is captured once so the
	-- proxy can never call itself.
	local mathProxy = setmetatable({}, {__index = REAL_MATH})
	function mathProxy.random(...)
		local argc = select("#", ...)
		if argc <= 2 then return REAL_MATH.random(...) end
		local values = {...}
		return values[REAL_MATH.random(1, argc)]
	end
	define("math", mathProxy)

	define("curStep", 0)
	define("curDecStep", 0)
	define("curBeat", 0)
	define("curDecBeat", 0)
	define("bpm", 100)
	define("crotchet", 600)
	define("stepCrochet", 150)
	define("downscroll", false)
	define("songName", (PlayState and PlayState.SONG and PlayState.SONG.song) or "BPM-2021")
	define("songLength", 0)

	define("getProperty", function(path) return api:get(path) end)
	define("setProperty", function(path, value) return api:set(path, value) end)

	define("getPropertyFromGroup", function(group, index, property)
		local object = api:groupMember(group, index)
		if not object then return nil end
		return api:getOn(object, property)
	end)

	define("setPropertyFromGroup", function(group, index, property, value)
		local object = api:groupMember(group, index)
		if not object then return false end
		return api:setOn(object, property, value)
	end)

	define("getPropertyFromClass", function(class, variable)
		local c, v = tostring(class or ""):lower(), tostring(variable or "")
		if c:find("settings") then
			return api.objectSetting(class, variable)
		elseif c:find("clientprefs") then
			local data = ClientPrefs and ClientPrefs.data or {}
			if v == "downScroll" then return data.downScroll == true end
			if v == "middleScroll" then return data.middleScroll == true end
			if v == "globalAntialiasing" then return data.antialiasing ~= false end
			if v == "flashingLights" then return data.flashingLights ~= false end
			if v == "botPlay" or v == "botplay" then return data.botplayMode == true end
			if v == "lowQuality" then return data.lowQuality == true end
		elseif c:find("flxg") then
			if v == "width" then return game.width end
			if v == "height" then return game.height end
			if v == "x" or v == "y" or v == "rotate" then return 0 end
		end
		return 0
	end)

	-- sprites ------------------------------------------------------------
	-- Psych creates the object only; it is drawn once addLuaSprite runs.
	define("makeLuaSprite", function(tag, image, x, y)
		return api:sprite(tag, image, x, y, false)
	end)
	define("makeAnimatedLuaSprite", function(tag, image, x, y)
		return api:sprite(tag, image, x, y, true)
	end)
	define("makeGraphic", function(tag, width, height, color) return api:graphic(tag, width, height, color) end)
	define("makeLuaGraphic", function(tag, width, height, color) return api:graphic(tag, width, height, color) end)
	define("makeLuaText", function(tag, content, width, x, y) return api:text(tag, content, width, x, y) end)

	define("addLuaSprite", function(tag, front) return api:add(tag, front == true) end)
	define("addLuaText", function(tag, front) return api:add(tag, front == true) end)
	define("removeLuaSprite", function(tag) return api:destroy(tag) end)
	define("removeLuaText", function(tag) return api:destroy(tag) end)

	define("scaleObject", function(tag, x, y, updateHitbox)
		local obj = api.objects[tag]
		if not obj then return false end
		obj.scale:set(num(x, 1), num(y, x))
		if updateHitbox ~= false and obj.updateHitbox then obj:updateHitbox() end
		return true
	end)

	define("setObjectCamera", function(tag, camera) return api:cameraOn(tag, camera) end)
	define("setObjectOrder", function(tag, index) return api:order(tag, index) end)
	define("setBlendMode", function(tag, blend)
		local obj = api.objects[tag]
		if not obj then return false end
		local mode = tostring(blend or "alpha"):lower()
		if mode == "invert" then mode = "screen" end
		obj.blend = mode
		return true
	end)

	define("setScrollFactor", function(tag, x, y)
		local obj = api.objects[tag]
		if not obj or not obj.scrollFactor then return false end
		obj.scrollFactor.x = num(x, 1)
		obj.scrollFactor.y = num(y, x or 1)
		return true
	end)

	define("objectPlayAnim", function(tag, name, forced)
		local obj = api.objects[tag]
		if not obj or not obj.animation then return false end
		if obj.animation:has(name) then
			obj.animation:play(name, forced == true)
			return true
		end
		return false
	end)

	-- text ---------------------------------------------------------------
	define("setTextString", function(tag, content)
		local obj = api.objects[tag]
		if not obj then return false end
		obj.content = tostring(content)
		return true
	end)
	define("setTextSize", function(tag, size)
		local obj = api.objects[tag]
		if not obj then return false end
		local font = paths.getFont(obj.__helloFont or "vcr.ttf", math.floor(num(size, 16)))
		if font then obj.font = font end
		return true
	end)
	define("setTextFont", function(tag, font)
		local obj = api.objects[tag]
		if not obj then return false end
		obj.__helloFont = font
		local size = obj.__helloSize or 16
		local resolved = paths.getFont(tostring(font), size)
		if not resolved then
			api:warn("font '" .. tostring(font) .. "' not found, keeping vcr.ttf")
			resolved = paths.getFont("vcr.ttf", size)
		end
		if resolved then obj.font = resolved end
		return true
	end)
	define("setTextColor", function(tag, color)
		local obj = api.objects[tag]
		if not obj then return false end
		obj.color = hexColor(color, 0xFFFFFF)
		return true
	end)
	define("setTextAlignment", function(tag, align)
		local obj = api.objects[tag]
		if not obj then return false end
		local a = tostring(align or "center"):lower()
		if a ~= "left" and a ~= "center" and a ~= "right" and a ~= "justify" then a = "center" end
		obj.alignment = a
		return true
	end)
	define("setTextWidth", function(tag, width)
		local obj = api.objects[tag]
		if not obj then return false end
		obj.limit = num(width, 0) > 0 and num(width) or nil
		return true
	end)

	-- tweens -------------------------------------------------------------
	define("doTweenX", function(tag, ref, value, duration, ease) return api:tweenPath(tag, ref, "x", value, duration, ease) end)
	define("doTweenY", function(tag, ref, value, duration, ease) return api:tweenPath(tag, ref, "y", value, duration, ease) end)
	define("doTweenAngle", function(tag, ref, value, duration, ease) return api:tweenPath(tag, ref, "angle", value, duration, ease) end)
	define("doTweenAlpha", function(tag, ref, value, duration, ease) return api:tweenPath(tag, ref, "alpha", value, duration, ease) end)
	define("doTweenZoom", function(tag, ref, value, duration, ease) return api:tweenPath(tag, ref, "zoom", value, duration, ease) end)
	define("doTweenProperty", function(tag, ref, property, value, duration, ease)
		return api:tweenPath(tag, ref, tostring(property), value, duration, ease)
	end)
	define("cancelTween", function(tag) return api:cancelTween(tag) end)

	-- note tweens --------------------------------------------------------
	for _, name in ipairs({"noteTweenX", "noteTweenY", "noteTweenAngle", "noteTweenDirection", "noteTweenAlpha"}) do
		local property = name:sub(10):gsub("^%u", string.lower)
		if property == "x" or property == "y" or property == "alpha" then
			-- same names as the receptor fields
		elseif property == "angle" then property = "noteAngle"
		elseif property == "direction" then property = "direction" end
		define(name, function(tag, note, value, duration, ease)
			return api:noteTween(tag, note, property, value, duration, ease)
		end)
	end

	-- cameras ------------------------------------------------------------
	define("cameraShake", function(camera, intensity, duration)
		local cam = api:camera(camera)
		if not cam then return false end
		-- Psych multiplies by FlxG.width/height internally in Light Engine, so
		-- authored values are already window relative: keep them small.
		cam:shake(num(intensity, 0.05), num(duration, 0.5))
		return true
	end)
	define("cameraFlash", function(camera, color, duration)
		local cam = api:camera(camera)
		if not cam then return false end
		cam:flash(hexColor(color, 0xFFFFFF), num(duration, 1))
		return true
	end)
	define("cameraFade", function(camera, color, duration, fadeIn)
		local cam = api:camera(camera)
		if not cam then return false end
		cam:fade(hexColor(color, 0x000000), num(duration, 1), fadeIn == true)
		return true
	end)

	-- audio --------------------------------------------------------------
	define("playSound", function(key, volume)
		local clean = tostring(key or ""):gsub("^sounds/", ""):gsub("%.ogg$", ""):gsub("%.mp3$", "")
		local asset = paths.getSound(clean)
		if not asset then return false end
		util.playSfx(asset, num(volume, 1), false, true)
		return true
	end)
	define("precacheImage", function() return true end)
	define("precacheSound", function() return true end)
	define("precacheMusic", function() return true end)

	-- song state ---------------------------------------------------------
	define("getSongPosition", function()
		local music = game.sound and game.sound.music
		return music and music.time and music.time * 1000 or 0
	end)
	define("getCurrentStep", function() return num(env.curStep, 0) end)
	define("getSongBpm", function() return num(env.bpm, 100) end)
	define("runTimer", function() return false end)   -- unused by this mod
	define("cancelTimer", function() return false end)
	define("runHaxeCode", function() return false end)
	define("runHaxeFunction", function() return false end)

	return api
end

return Psych
