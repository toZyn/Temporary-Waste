--[[
	BPM-2021 (Camellia) - Light Engine port
	songs/bpm-2021/script.lua

	Song script. The body below is the mod's ORIGINAL Psych modchart
	("data/BPM-2021/New Text Document.lua") kept verbatim; only the bridge
	header is new.

	Header rationale
	----------------
	Light Engine runs native scripts in a sandbox that forbids loading chunks at
	runtime (no `load`/`loadstring`/`setfenv`), and it already ships a Psych-style
	helper layer in funkin/backend/scripts/compat.lua. Following that idiom, the
	header installs the exact subset of the FunkinLua API this modchart uses as
	globals of this script. Cameras, receptors and tweens stay native.

	What the original modchart drives
	---------------------------------
	* 265 doTweenZoom, 105 doTweenAngle on camGame / camHUD / camOther
	* 83 noteTweenX + 69 noteTweenY + 33 noteTweenAngle + 29 noteTweenDirection
	  + 4 noteTweenAlpha on the 8 strum lines (Psych indices 0-7)
	* 46 cancelTween for its own choreography tags
	* setProperty('camZooming', false) every frame
]]

local bridge = require("data.classes.hello2021.psychbridge")
local env = getfenv(1) or _G

api = bridge.install(state, "bpm-2021")
bridge.installGlobals(api, env)

api.__onTweenCompleted = function(tag)
	if type(env.onTweenCompleted) == "function" then env.onTweenCompleted(tag) end
end

local function syncConductor()
	local c = state.conductor or (PlayState and PlayState.conductor)
	if not c then return end
	local step = c.currentStepFloat or (c.step and c.step.f) or 0
	env.curDecStep, env.curStep = step, math.floor(step + 0.000001)
	local beat = c.currentBeatFloat or (c.beat and c.beat.f) or (step / 4)
	env.curDecBeat, env.curBeat = beat, math.floor(beat + 0.000001)
	env.bpm = c.bpm or env.bpm
	env.crotchet = c.crotchet or env.crotchet
	env.stepCrochet = c.stepCrochet or env.stepCrochet
end

-- Light Engine callbacks -> Psych modchart callbacks
function create()
	syncConductor()
	if type(env.onCreate) == "function" then env.onCreate() end
end

function postCreate()
	if type(env.onPostCreate) == "function" then env.onPostCreate() end
end

function step(s)
	syncConductor()
	if type(env.onStepHit) == "function" then env.onStepHit() end
end

function beat(b)
	syncConductor()
	if type(env.onBeatHit) == "function" then env.onBeatHit() end
end

function onEvent(event)
	syncConductor()
	if type(env.onEvent) == "function" then
		env.onEvent(event.name, event.value1, event.value2)
	end
end

function update(dt)
	syncConductor()
	if type(env.onUpdate) == "function" then env.onUpdate(dt) end
	if type(env.updateShimmy) == "function" then env.updateShimmy(dt) end
	api:update(dt)
end

function leave()
	api:dispose()
end

-- ===========================================================================
-- Custom events
-- ===========================================================================
-- events.json drives four events. "Change Scroll Speed" and "Screen Shake"
-- are engine built-ins (Light Engine's scrollspeed/screenshake accept the same
-- Psych arguments). "noteShimmy" and "NoteBump" were Python/Lua events of the
-- original mod; the implementations below replace them with the same
-- behaviour, reading the values from settings.lua like the original did.

local eventSettings = require("data.classes.hello2021.settings")

--- noteShimmy(value1): toggles a continuous sine shimmy of the eight
--- receptors. value1 = "1" turns it on, "" / "0" snaps them back.
local function noteShimmy(value1)
	local on = not (value1 == nil or value1 == "" or value1 == "0" or value1 == false)

	if not on then
		api.shimmy = nil
		for i = 0, 3 do
			noteTweenX("shimmyEndE" .. i, i, 92 + i * 112, 0.25, "quadOut")
			noteTweenX("shimmyEndP" .. i, i + 4, 732 + i * 112, 0.25, "quadOut")
		end
		return
	end

	api.shimmy = {time = 0}
end

--- advances the shimmy every frame (in Psych this ran on a timer loop)
local function updateShimmy(dt)
	local data = api.shimmy
	if not data then return end

	local distance = eventSettings.get("Settings", "noteShimmyDistance")
	local speed = eventSettings.get("Settings", "noteShimmySpeed")
	data.time = data.time + dt * speed

	local offset = math.sin(data.time * math.pi * 2) * distance
	for i = 0, 3 do
		local enemy = state.enemyNotefield and state.enemyNotefield.lanes[i + 1]
		local player = state.playerNotefield and state.playerNotefield.lanes[i + 1]
		if enemy and enemy.receptor then enemy.receptor.x = enemy.x + offset end
		if player and player.receptor then player.receptor.x = player.x - offset end
	end
end

--- NoteBump(value1): pushes one lane towards the player and eases it back.
local function noteBump(value1)
	local lane = tonumber(value1)
	if not lane then
		lane = math.random(0, 7)
	end
	local distance = eventSettings.get("Settings", "NoteBumpDistance")
	local duration = eventSettings.get("Settings", "NoteBumpSpeed")
	local direction = state.downScroll and 1 or -1

	noteTweenY("bump" .. lane .. "a", lane, 50 + direction * distance, math.max(0.01, duration * 0.5), "quadOut")
	noteTweenY("bump" .. lane .. "b", lane, 50, math.max(0.02, duration), "quadIn")
end

function onEvent(name, value1)
	local event = tostring(name or ""):lower():gsub("%s", "")
	if event == "noteshimmy" then
		noteShimmy(value1)
	elseif event == "notebump" then
		noteBump(value1)
	end
end

-- ===========================================================================
-- ORIGINAL PSYCH MODCHART (verbatim from data/BPM-2021/New Text Document.lua)
-- ===========================================================================
local noteYPlace = {50,570}
local noteDirec = {-90,90}
local MidleNote = {412,524,636,748}
local noteXCenter = {412,524,636,748}
local SplitNote = {280,422,733,895}
local kiri = -100
local kanan = 100
local HUDY = {-200,200}

local scroll90 = {60,540}
local scroll180 = {300,300}
--local scroll45v1 = {200,400}
--local scroll45v2 = {400,200}

local scroll90d = {540,60}
local scroll180d = {300,300}
--local scroll45v1d = {200,400}
--local scroll45v2d = {400,200}

local scroll135 = {170,370} --
local scroll135d = {400,170} --
local scroll45 = {170,370} --
local scroll45d = {400,170} --

local direction180d = {0,-180}
local direction135d = {45,135}
local direction135 = {135,45}
local direction45d = {-45,-135}
local direction45 = {-135,-45}
function inTable(tbl, item)
    for key, value in pairs(tbl) do
        if value == item then return key end
    end
    return false
end
function HUDslideR()
    doTweenZoom('camGameZoom1234','camGame',0.75,1,'circOut')
        doTweenZoom('camHUDZoom1234','camHUD',0.75,1,'circOut')
    doTweenAngle('camHUDAngle','camHUD',-25,0.001)
    doTweenAngle('camHUDAngle1','camHUD',0,0.86,'circOut')
    doTweenAlpha('camHudAlpha12345','camHUD',1,0.001)
    setProperty('camHUD.x',-900)
    doTweenX('camHUDX123456Z','camHUD',0,0.86,'expoOut')
end
function HUDslideL()
    doTweenZoom('camGameZoom1234','camGame',0.75,1,'circOut')
        doTweenZoom('camHUDZoom1234','camHUD',0.75,1,'circOut')
    doTweenAngle('camHUDAngle','camHUD',25,0.001)
    doTweenAngle('camHUDAngle1','camHUD',0,0.86,'expoOut')
    doTweenAlpha('camHudAlpha12345','camHUD',1,0.001)
    setProperty('camHUD.x',900)
    doTweenX('camHUDX12345Z','camHUD',0,0.86,'expoOut')
end
function HUDslideU()
    doTweenZoom('camGameZoom1234','camGame',0.75,1,'circOut')
        doTweenZoom('camHUDZoom1234','camHUD',0.75,1,'circOut')
    doTweenAngle('camHUDAngle','camHUD',0,0.0001)
    doTweenAngle('camHUDAngle1','camHUD',0,1,'circOut')
    doTweenAlpha('camHudAlpha12345','camHUD',1,0.001)

    setProperty('camHUD.y',-900)
    doTweenY('camHUDX12345','camHUD',-900,0.001)
    doTweenY('camHUDX12345Z','camHUD',0,0.66,'expoOut')
end
function onUpdate()
    setProperty('camZooming',false)
end
function onStepHit()
    if curStep == 1 then
        doTweenAlpha('camGamelpha','camGame',0,0.0001)
    end
    if curStep == 20 then
        for i = 0,7 do
            noteTweenX('midlenote'..i, i, MidleNote[(i % 4) + 1], 0.5,'expoinOut')
        end
        doTweenZoom('camHUDz','camHUD',0.4,0.45,'Expoin')
    end
    if curStep == 24 then
        
        doTweenZoom('camGameZs','camGame',2,0.0001)
        doTweenZoom('camHudZ','camHUD',2,0.0001)
        doTweenZoom('camOtherZ','camOther',2,0.0001)
        doTweenZoom("camHUDZoom",'camHUD',0.5,20,'sineOut')
        doTweenZoom("camOtherZoom",'camOther',0.5,20,'sineOut')
        doTweenZoom('camGameZ','camGame',0.55,15,'sineOut')
        doTweenAlpha('camGamelpha','camGame',1,15,'sineOut')
        noteTweenX("0X",0,defaultOpponentStrumX0,20,'sineInOut')
        noteTweenX("1X",1,defaultOpponentStrumX1,20,'sineInOut')

        noteTweenX("2X",2,defaultPlayerStrumX2,20,'sineInOut')
        noteTweenX("3X",3,defaultPlayerStrumX3,20,'sineInOut')


        noteTweenAlpha("0Alpha",0,0.5,2,'expIn')
        noteTweenAlpha("1Alpha",1,0.5,2,'expIn')
        noteTweenAlpha("2Alpha",2,0.5,2,'expIn')
        noteTweenAlpha("3Alpha",3,0.5,2,'expIn')

    end
    if curStep == 392 then
        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camGamelpha')
        cancelTween('0X')
        cancelTween('1X')
        cancelTween('2X')
        cancelTween('3X')
        cancelTween('camHUDZoom')

    end

    if curStep == 400 then
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 360, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',18,0.7,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',1.2,0.0001)
        doTweenZoom('camHudZ','camHUD',1.2,0.0001)
        doTweenZoom('camOtherZ','camOther',1.2,0.0001)
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 416 then --2-- jarak ke1 > 16
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    if curStep == 440 then --3d-- jarak ke2 > 24
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',-250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',-18,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 455 then --2
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    if curStep == 479 then --3d-- jarak ke2 > 24
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 360, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',150,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',11,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 496 then --2
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    if curStep == 520 then --3d-- jarak ke2 > 24
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',-150,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',-11,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    --[[if curStep == 496 then --2
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    if curStep == 520 then --3d-- jarak ke2 > 24
        doTweenX("camHUDX",'camHUD',150,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',11,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end]]
    if curStep == 531 then --2
        doTweenX("camHUDX",'camHUD',0,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',0,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.37,'sineOut')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.37,'sineOut')
        doTweenZoom('camGameZ','camGame',0.95,0.37,'sineOut')
    end
    if curStep == 544 then --3d-- jarak ke2 > 24
        
        doTweenZoom("camHUDZoom",'camHUD',0.3,0.24,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',0.3,0.24,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.35,0.24,'EXPOIN')
    end

    if curStep == 552 then
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 360, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',15,0.7,'EXPOOUT')
        --[[cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')]]
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 567 then --2-- jarak ke1 > 16
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    --[[if curStep == 577 then
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',-250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',-15,0.7,'EXPOOUT')
    end]]
    if curStep == 593 then --3d-- jarak ke2 > 24
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i,0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',-250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',-15,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 607 then --2
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'sineinOut')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'sineinOut')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'sineinOut')
    end
    --[[if curStep == 617 then
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 360, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',15,0.7,'EXPOOUT')
    end]]
    if curStep == 631 then --3d-- jarak ke2 > 24
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 360, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',250,0.5,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',15,0.5,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 648 then 
        doTweenZoom("camHUDZoom",'camHUD',2,0.3,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',2,0.3,'EXPOIN')
        doTweenZoom('camGameZ','camGame',2,0.3,'EXPOIN')
    end
    --[[if curStep == 655 then
        --doTweenX('camHUDX','camHUD',600,0.26,'expoin')
        doTweenZoom("camHUDZoom",'camHUD',2,0.2,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',2,0.2,'EXPOIN')
        doTweenZoom('camGameZ','camGame',2,0.2,'EXPOIN')
    end]]
    if curStep == 662 then
        setProperty('camGame.zoom',0.3)
        setProperty('camHUD.zoom',0.3)
        setProperty('camOther.zoom',0.3)
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',0,0.7,'ElasticOUT')
        doTweenAngle('camHudAngle','camHUD',0,0.7,'ElasticOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'ElasticOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'BElasticUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'ElasticOUT')
    end
    
    if curStep == 664 then
       --[[ cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')]]
        --setProperty('camGame.zoom',1.2)
        --setProperty('camHUD.zoom',1.2)
        --[[setProperty('camOther.zoom',1.2)
        doTweenZoom("camHUDZooms",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.55,0.5,'EXPOOUT')]]
        doTweenX('camHUDX','camHUD',-900,0.001)
        doTweenX('camHUDXs','camHUD',0,0.66,'ElasticOut')
        doTweenZoom("camHUDZoom",'camHUD',0.8,0.9,'ElasticOut')
        doTweenZoom("camOtherZoom",'camOther',0.8,0.9,'ElasticOut')
        doTweenZoom('camGameZ','camGame',0.7,0.9,'ElasticOut')
    end
    if curStep == 684 then 
        doTweenZoom("camHUDZoom",'camHUD',0.4,0.3,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',0.4,0.3,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.4,0.3,'EXPOIN')
    end
    if curStep == 688 then --3d-- jarak ke2 > 24
        --[[setProperty('camGame.zoom',2)
        setProperty('camHUD.zoom',2)
        setProperty('camOther.zoom',2)
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOIN')]]
    end
    if curStep == 696 then
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 360, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',15,0.7,'EXPOOUT')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 712 then --2
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    if curStep == 736 then --3d-- jarak ke2 > 24
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 737 then
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',-250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',-15,0.7,'EXPOOUT')
    end
    if curStep == 751 then --2
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    if curStep == 761 then
        
        doTweenZoom("camHUDZoom",'camHUD',0.75,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.75,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.7,0.5,'EXPOOUT')
    end
    if curStep == 775 then --3d-- jarak ke2 > 24
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 360, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',15,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    
    if curStep == 791 then --2
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.95,0.5,'EXPOIN')
    end
    if curStep == 817 then
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',-250,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',-15,0.7,'EXPOOUT')
    end
    if curStep == 815 then --3d-- jarak ke2 > 24
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 831 then --2
        for i = 0,7 do
            noteTweenAngle('Anglen'..i, i, 0, 0.7,'EXPOOUT')
        end
        doTweenX("camHUDX",'camHUD',0,0.7,'EXPOOUT')
        doTweenAngle('camHudAngle','camHUD',0,0.7,'EXPOOUT')
        doTweenZoom("camHUDZoom",'camHUD',1.1,0.37,'sineOut')
        doTweenZoom("camOtherZoom",'camOther',1.1,0.37,'sineOut')
        doTweenZoom('camGameZ','camGame',0.95,0.37,'sineOut')
    end
    if curStep == 839 then --3d-- jarak ke2 > 24
        doTweenZoom("camHUDZoom",'camHUD',0.3,0.24,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',0.3,0.24,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.35,0.24,'EXPOIN')
    end

    if curStep == 847 then
        
        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOOUT')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOOUT')
        doTweenZoom('camGameZ','camGame',0.55,0.5,'EXPOOUT')
    end
    if curStep == 904 then
        noteTweenX("0X",0,defaultOpponentStrumX0 + 750,1.26,'Expoin')
        noteTweenX("1X",1,defaultOpponentStrumX1 + 750,1.26,'Expoin')
        noteTweenX("2X",2,defaultPlayerStrumX2 - 750,1.26,'Expoin')
        noteTweenX("3X",3,defaultPlayerStrumX3 - 750,1.26,'Expoin')

        noteTweenX("4X",4,defaultOpponentStrumX0 - 300,1.26,'Expoin')
        noteTweenX("5X",5,defaultOpponentStrumX1 - 300,1.26,'Expoin')
        noteTweenX("6X",6,defaultPlayerStrumX2 + 300,1.26,'Expoin')
        noteTweenX("7X",7,defaultPlayerStrumX3 + 300,1.26,'Expoin')
        --doTweenX('camHUDX','camHUD',-600,1.26,'expoin')
        doTweenZoom("camHUDZoom",'camHUD',2,1.2,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',2,1.2,'EXPOIN')
        doTweenZoom('camGameZ','camGame',2,1.2,'EXPOIN')
    end
    if curStep == 943 then
        for i = 0,7 do
            noteTweenX('midlenote'..i, i, MidleNote[(i % 4) + 1], 0.001)
        end
        setProperty('camHUD.x',600)
        doTweenX('camHUDX','camHUD',0,0.66,'expoOut')
        cancelTween('0X')
        cancelTween('1X')
        cancelTween('2X')
        cancelTween('3X')
        cancelTween('4X')
        cancelTween('5X')
        cancelTween('6X')
        cancelTween('7X')

        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        doTweenZoom("camHUDZooms",'camHUD',0.9,0.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.9,0.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.85,0.5,'EXPOOUT')
    end
    if curStep == 960 then --2
        doTweenZoom("camHUDZoom",'camHUD',0.6,0.5,'EXPOIN')
        doTweenZoom("camOtherZoom",'camOther',0.6,0.5,'EXPOIN')
        doTweenZoom('camGameZ','camGame',0.65,0.5,'EXPOIN')
    end
    if curStep == 1456 then
        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        setProperty('camGame.angle',25)
        setProperty('camHUD.angle',25)
        --setProperty('camOther.angle',25)

        doTweenZoom("camHUDZooms",'camHUD',0.6,1.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.6,1.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.55,1.5,'EXPOOUT')

        doTweenAngle("camHUDAngle",'camHUD',0,1.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,1.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,1.5,'EXPOOUT')
    end
    if curStep == 1477 then --2
        doTweenZoom("camHUDZoom",'camHUD',0.9,0.77,'Expoin')
        doTweenZoom("camOtherZoom",'camOther',0.9,0.77,'Expoin')
        doTweenZoom('camGameZ','camGame',0.85,0.77,'Expoin')
        doTweenAngle('camGameAngle','camGame',15,0.7,'Expoin')
        doTweenAngle("camHUDAngle",'camHUD',15,0.7,'Expoin')
        doTweenAngle("camOtherAngle",'camOther',15,0.7,'Expoin')

    end
    if curStep == 1511 then
        doTweenZoom("camHUDZooms",'camHUD',0.4,0.5,'EXPOIN')
        doTweenZoom("camOtherZooms",'camOther',0.4,0.5,'EXPOIN')
        doTweenZoom('camGameZs','camGame',0.35,0.5,'EXPOIN')
        doTweenAngle('camGameAngle','camGame',-15,0.5,'EXPOIN')
        doTweenAngle("camHUDAngle",'camHUD',-15,0.5,'EXPOIN')
        doTweenAngle("camOtherAngle",'camOther',-15,0.5,'EXPOIN')
    end
    if curStep == 1519 then
        for i = 0,7 do
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1],0.6,'QuartOut')
        end

        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        setProperty('camGame.angle',-25)
        setProperty('camHUD.angle',-25)
        --setProperty('camOther.angle',-25)

        doTweenZoom("camHUDZooms",'camHUD',0.7,0.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.7,0.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.65,0.5,'EXPOOUT')

        doTweenAngle("camHUDAngle",'camHUD',0,0.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,0.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,0.5,'EXPOOUT')
    end
    if curStep == 1543 then --2
        noteTweenY('5pY', 4, defaultPlayerStrumY0 - 100, 0.1,"ElasticOUt")
        noteTweenY('6pY', 5, defaultPlayerStrumY0 + 100, 0.1,"ElasticOUt")
        noteTweenY('7pY', 6, defaultPlayerStrumY0 - 100, 0.1,"ElasticOUt")
        noteTweenY('8pY', 7, defaultPlayerStrumY0 + 100, 0.1,"ElasticOUt")

        noteTweenY('5OpY', 0, defaultPlayerStrumY0 - 100, 0.1,"ElasticOUt")
        noteTweenY('6OpY', 1, defaultPlayerStrumY0 + 100, 0.1,"ElasticOUt")
        noteTweenY('7OpY', 2, defaultPlayerStrumY0 - 100, 0.1,"ElasticOUt")
        noteTweenY('8OpY', 3, defaultPlayerStrumY0 + 100, 0.1,"ElasticOUt")

        
        for i = 0,7 do
            noteTweenY('NoteYs'..i,i,defaultPlayerStrumY0,0.4,'elasticOut')
        end
        doTweenZoom("camHUDZoom",'camHUD',1.05,0.37,'Expoin')
        doTweenZoom("camOtherZoom",'camOther',1.05,0.37,'Expoin')
        doTweenZoom('camGameZ','camGame',0.95,0.37,'Expoin')
        doTweenAngle('camGameAngle','camGame',15,0.3,'Expoin')
        doTweenAngle("camHUDAngle",'camHUD',15,0.3,'Expoin')
        --doTweenAngle("camOtherAngle",'camOther',15,0.3,'Expoin')

    end
    if curStep >= 1543 and curStep < 1546 and curStep %1 == 0 then
        for i = 4,7 do
            val = {1,-1}
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1] +100*val[(Flippy and 1 or 2)],0.1,'QuartOut')
            flippy = not flippy
        end
        for i = 0,3 do
            val = {1,-1}
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1] -100*val[(Flippy and 1 or 2)],0.1,'QuartOut')
            flippy = not flippy
        end
    end

    
    if curStep == 1548 then
        for i = 0,7 do
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1],0.6,'QuartOut')
        end
        doTweenZoom("camHUDZooms",'camHUD',0.4,0.34,'EXPOIN')
        doTweenZoom("camOtherZooms",'camOther',0.4,0.34,'EXPOIN')
        doTweenZoom('camGameZs','camGame',0.35,0.34,'EXPOIN')
        doTweenAngle('camGameAngle','camGame',-15,0.34,'EXPOIN')
        doTweenAngle("camHUDAngle",'camHUD',-15,0.34,'EXPOIN')
        --doTweenAngle("camOtherAngle",'camOther',-15,0.34,'EXPOIN')
    end
    if curStep >= 1553 and curStep <= 1994 then
        songPos = getSongPosition()
        currentBeat = (songPos / 400) * (bpm / 10)
        --[[for i = 0,3 do 
            --setPropertyFromGroup('strumLineNotes', i, 'x', noteXCenter[(i % 4) + 1] + 16 * math.sin((currentBeat + i*0.25) * math.pi))
            --setPropertyFromGroup('strumLineNotes', i, 'y', noteYPlace[(downscroll and 2 or 1)] + 16 * math.cos((currentBeat + i*0.25) * math.pi))
            noteTweenX('aeiozsduy'..i, i, 605 + 1912 * math.sin(((currentBeat / 8) + i*0.25) * math.pi), 0.5)
            noteTweenY('aawezdfuy'..i, i, noteYPlace[(downscroll and 2 or 1)] + 324 * math.cos(((currentBeat / 8) + i*0.25) * math.pi), 0.5)
        end]]
        noteTweenX('aeiozsdu0', 0, 605 + 2212 * math.sin(((currentBeat / 2)) * math.pi), 0.1)
        noteTweenX('aeiozsdu1', 1, 605 + 2212 * math.sin(((currentBeat / 4)) * math.pi), 0.1)
        noteTweenX('aeiozsdu2', 2, 605 + 2212 * math.sin(((currentBeat / 6)) * math.pi), 0.1)
        noteTweenX('aeiozsdu3', 3, 605 + 2212 * math.sin(((currentBeat / 8)) * math.pi), 0.1)
        noteTweenY('aawezdfu0', 0, noteYPlace[(downscroll and 2 or 1)] + 624 * math.cos(((currentBeat / 8)) * math.pi), 0.2)
        noteTweenY('aawezdfu1', 1, noteYPlace[(downscroll and 1 or 2)] + 624 * math.cos(((currentBeat / 8)) * math.pi), 0.2)
        noteTweenY('aawezdfu2', 2, noteYPlace[(downscroll and 2 or 1)] + 624 * math.cos(((currentBeat / 8)) * math.pi), 0.2)
        noteTweenY('aawezdfu3', 3, noteYPlace[(downscroll and 1 or 2)] + 624 * math.cos(((currentBeat / 8)) * math.pi), 0.2)

        noteTweenDirection('aeiozsDirec0', 0, 90 + 2212 * math.sin(((currentBeat / 2)) * math.pi), 0.1)
        noteTweenDirection('aeiozsDirec1', 1, 90 + 2212 * math.sin(((currentBeat / 4)) * math.pi), 0.1)
        noteTweenDirection('aeiozsDirec2', 2, 90 + 2212 * math.sin(((currentBeat / 6)) * math.pi), 0.1)
        noteTweenDirection('aeiozsDirec3', 3, 90 + 2212 * math.sin(((currentBeat / 8)) * math.pi), 0.1)


    end
    if curStep == 1553 then
        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        setProperty('camGame.angle',-25)
        setProperty('camHUD.angle',-25)
        --setProperty('camOther.angle',-25)

        doTweenZoom("camHUDZooms",'camHUD',0.7,0.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',1,0.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.85,0.5,'EXPOOUT')

        doTweenAngle("camHUDAngle",'camHUD',0,0.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,0.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,0.5,'EXPOOUT')
    end
    if curStep == 1559
    or curStep == 1566
    or curStep == 1572
    or curStep == 1579
    or curStep == 1584------
    or curStep == 1587
    or curStep == 1590
    or curStep == 1593
    or curStep == 1596
    or curStep == 1599------
    or curStep == 1603
    or curStep == 1610
    or curStep == 1615
    or curStep > 1621 and curStep < 1647 and curStep %3 == 0
    or curStep > 1648 and curStep < 1755 and curStep %5 == 0
    or curStep == 1780
    or curStep == 1785
    or curStep == 1793
    or curStep == 1799
    or curStep > 1800 and curStep < 1818 and curStep %3 == 0
    or curStep == 1824
    or curStep == 1831
    or curStep == 1837
    or curStep > 1838 and curStep < 1867 and curStep %3 == 0
    or curStep > 1869 and curStep < 1930 and curStep %5 == 0 then
        setProperty('camGame.zoom',1)
        setProperty('camHUD.zoom',1)
        setProperty('camOther.zoom',1)
        doTweenZoom("camHUDZooms",'camHUD',0.85,0.3,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',1.0,0.3,'EXPOOUT')        
        doTweenZoom('camGameZs','camGame',0.75,0.3,'EXPOOUT')
    end        
    if curStep == 1763 then
        doTweenZoom("camHUDZooms",'camHUD',0.5,0.45,'EXPOIN')
        doTweenZoom("camOtherZooms",'camOther',0.7,0.45,'EXPOIN')
        doTweenZoom('camGameZs','camGame',0.45,0.45,'EXPOIN')
        doTweenAngle('camGameAngle','camGame',180,0.6,'EXPOIN')
        doTweenAngle("camHUDAngle",'camHUD',180,0.6,'EXPOIN')
        doTweenAngle("camOtherAngle",'camOther',180,0.6,'EXPOIN')
    end
    if curStep == 1777 then
        setProperty('camGame.zoom',2)
        setProperty('camHUD.zoom',2)
        setProperty('camOther.zoom',2)
        doTweenZoom("camHUDZooms",'camHUD',0.7,0.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',1,0.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.85,0.5,'EXPOOUT')

        setProperty('camGame.angle',-25)
        setProperty('camHUD.angle',-25)
        --setProperty('camOther.angle',-25)
        doTweenAngle("camHUDAngle",'camHUD',0,1.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,1.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,1.5,'EXPOOUT')

    end
    if curStep == 1963 then
        doTweenZoom("camHUDZooms",'camHUD',0.4,1.0,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',0.4,1.0,'QuartIN')
        doTweenZoom('camGameZs','camGame',0.35,1.0,'QuartIN')
        doTweenAngle('camGameAngle','camGame',180,2,'QuartIN')
        doTweenAngle("camHUDAngle",'camHUD',180,1.0,'QuartIN')
        doTweenAngle("camOtherAngle",'camOther',180,1.5,'QuartIN')
    end
    if curStep == 1996 then
        
        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        setProperty('camGame.angle',-25)
        setProperty('camHUD.angle',-25)
        --setProperty('camOther.angle',-25)

        doTweenZoom("camHUDZooms",'camHUD',0.7,1.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',1,1.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.85,1.5,'EXPOOUT')

        doTweenAngle("camHUDAngle",'camHUD',0,1.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,1.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,1.5,'EXPOOUT')
    end
    if curStep == 1998 then
        for i = 0,7 do
            noteTweenDirection('direct'..i, i, 90, 0.6,'QuartOut')
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1],0.6,'QuartOut')
        end
        noteTweenY('5pY', 4, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6pY', 5, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7pY', 6, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8pY', 7, defaultPlayerStrumY0, 0.1,"ElasticOut")

        noteTweenY('5OpY', 0, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6OpY', 1, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7OpY', 2, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8OpY', 3, defaultPlayerStrumY0, 0.1,"ElasticOut")
    end
    if curStep == 2003 then
        doTweenY("camHUDY",'camHUD',600,1,'expoin')
    end
    if curStep == 2004 then
        doTweenY("camGameY",'camGame',(-getPropertyFromClass('flixel.FlxG', 'y')) + 100,0.5,'QUARTIN')
        doTweenZoom("camHUDZooms",'camHUD',2,1,'QUARTIN')
        doTweenZoom("camOtherZooms",'camOther',2,1,'QUARTIN')
        doTweenZoom('camGameZs','camGame',1.9,1,'QUARTIN')
    end
    if curStep == 2011 then
        setProperty('camGame.y',-200)
        setProperty('camHUD.y',-600)
        setProperty('camGame.zoom',0.4)
        setProperty('camHUD.zoom',0.4)
        setProperty('camOther.zoom',0.4)
        doTweenZoom("camHUDZooms",'camHUD',0.9,1.3,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.9,1.4,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.85,1.5,'EXPOOUT')
        doTweenY("camGameY",'camGame',0,1.3,'EXPOOUT')
        doTweenY("camHUDY",'camHUD',0,1.3,'EXPOOUT')
    end
    if curStep == 2036 then
        doTweenZoom("camHUDZooms",'camHUD',0.4,0.65,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',0.4,0.65,'QuartIN')
        doTweenZoom('camGameZs','camGame',0.15,0.5,'QuartIN')
        doTweenAngle('camGameAngle','camGame',-180,1.5,'QuartIN')
        doTweenAngle("camHUDAngle",'camHUD',-180,0.6,'QuartIN')
        --doTweenAngle("camOtherAngle",'camOther',-180,1.5,'QuartIN')
    end
    if curStep == 2044 then
        cancelTween('camOtherZoom')
        cancelTween('camGameZ')
        cancelTween('camHUDZoom')
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        setProperty('camGame.angle',25)
        setProperty('camHUD.angle',25)
        --setProperty('camOther.angle',25)

        doTweenZoom("camHUDZooms",'camHUD',0.9,1.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.9,1.5,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.85,1.5,'EXPOOUT')

        doTweenAngle("camHUDAngle",'camHUD',0,1.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,1.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,1.5,'EXPOOUT')
    end
    if curStep == 2052 then
        doTweenZoom("camHUDZooms",'camHUD',0.4,1,'QUARTIN')
        doTweenZoom("camOtherZooms",'camOther',0.4,1,'QUARTIN')
        doTweenZoom('camGameZs','camGame',0.4,1,'QUARTIN')
    end
    if curStep == 2059 then
        setProperty('camGame.zoom',2)
        setProperty('camHUD.zoom',2)
        setProperty('camOther.zoom',2)
        doTweenZoom("camHUDZooms",'camHUD',0.8,0.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.8,0.6,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.75,0.7,'EXPOOUT')
    end
    if curStep == 2076 then
        doTweenZoom("camHUDZooms",'camHUD',0.9,0.7,'QuartOut')
        doTweenZoom("camOtherZooms",'camOther',1.05,0.7,'QuartOut')
        doTweenZoom('camGameZs','camGame',1.05,0.7,'QuartOut')
        doTweenAngle('camGameAngle','camGame',20,0.7,'QuartOut')
        doTweenAngle("camHUDAngle",'camHUD',20,0.7,'QuartOut')
        --doTweenAngle("camOtherAngle",'camOther',20,0.7,'QuartOut')
    end
    if curStep == 2084 then
        doTweenZoom("camHUDZooms",'camHUD',0.4,0.6,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',0.4,0.6,'QuartIN')
        doTweenZoom('camGameZs','camGame',0.35,0.6,'QuartIN')
        doTweenAngle('camGameAngle','camGame',-180,0.6,'QuartIN')
        doTweenAngle("camHUDAngle",'camHUD',-180,0.8,'QuartIN')
        --doTweenAngle("camOtherAngle",'camOther',-180,0.6,'QuartIN')
    end
    if curStep == 2092 then
        setProperty('camGame.zoom',1.2)
        setProperty('camHUD.zoom',1.2)
        setProperty('camOther.zoom',1.2)
        setProperty('camGame.angle',25)
        setProperty('camHUD.angle',25)
        setProperty('camOther.angle',25)

        doTweenZoom("camHUDZooms",'camHUD',0.6,1.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.9,1.8,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.9,1.1,'EXPOOUT')

        doTweenAngle("camHUDAngle",'camHUD',0,1.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,1.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,1.5,'EXPOOUT')
    end
    if curStep == 2105 
    or curStep == 2120
    or curStep == 2136
    or curStep == 2152
    or curStep == 2167
    or curStep == 2183 then
        cancelTween('camHUDZooms')
        doTweenZoom("324873279843298732",'camHUD',1.05,0.7,'Quartin')
        doTweenZoom("camOtherZooms",'camOther',1.3,0.9,'Quartin')
        doTweenZoom('camGameZs','camGame',1.1,0.8,'Quartin')
    end
    if curStep == 2200 then
        doTweenZoom("camHUDZooms",'camHUD',2,0.6,'QUARTIN')
        doTweenZoom("camOtherZooms",'camOther',2.3,0.6,'QUARTIN')
        doTweenZoom('camGameZs','camGame',2,0.6,'QUARTIN')
    end
    if curStep == 2208 then
        setProperty('camGame.zoom',0.4)
        setProperty('camHUD.zoom',0.4)
        setProperty('camOther.zoom',0.4)
        doTweenZoom("camHUDZooms",'camHUD',0.8,0.5,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.8,0.6,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.75,0.7,'EXPOOUT')
    end
    if curStep == 2210
    or curStep == 2218
    or curStep == 2231
    or curStep == 2242
    or curStep == 2252
    or curStep == 2261
    or curStep == 2268
    or curStep == 2273
    or curStep == 2285
    or curStep == 2295
    or curStep == 2307
    or curStep == 2315
    or curStep == 2332
    or curStep == 2336 then
        for i = 0,7 do
            noteTweenAngle('angle'..i, i, 360, 0.25,'ElasticOut')
            noteTweenX('midlenote'..i, i, MidleNote[(i % 4) + 1], 0.25,'ElasticOut')
            noteTweenDirection('aeiozsDirec0'..i, i, -90, 0.35,'ElasticOut')
            noteTweenY('Notey'..i, i, noteYPlace[(downscroll and 1 or 2)], 0.001,'ElasticOut')
        end
    end
    if curStep == 2212
    or curStep == 2222
    or curStep == 2234
    or curStep == 2245
    or curStep == 2256
    or curStep == 2266
    or curStep == 2271
    or curStep == 2276
    or curStep == 2289
    or curStep == 2299
    or curStep == 2311
    or curStep == 2330
    or curStep == 2334
    or curStep == 2340 then
        for i = 0,7 do
            noteTweenAngle('angle'..i, i, 0, 0.25,'ElasticOut')
            noteTweenDirection('aeiozsDirec0'..i, i, 90, 0.35,'ElasticOut')
            noteTweenY('Notey'..i, i, noteYPlace[(downscroll and 2 or 1)], 0.001,'ElasticOut')
        end
        noteTweenX('5pX', 4, defaultPlayerStrumX0, 0.25,'ElasticOut')
        noteTweenX('6pX', 5, defaultPlayerStrumX1, 0.25,'ElasticOut')
        noteTweenX('7pX', 6, defaultPlayerStrumX2, 0.25,'ElasticOut')
        noteTweenX('8pX', 7, defaultPlayerStrumX3, 0.25,'ElasticOut')

        noteTweenX('5OpX', 0, defaultOpponentStrumX0, 0.25,'ElasticOut')
        noteTweenX('6OpX', 1, defaultOpponentStrumX1, 0.25,'ElasticOut')
        noteTweenX('7OpX', 2, defaultOpponentStrumX2, 0.25,'ElasticOut')
        noteTweenX('8OpX', 3, defaultOpponentStrumX3, 0.25,'ElasticOut')
    end
    if curStep == 2216 
    or curStep == 2221
    or curStep == 2230
    or curStep == 2237
    or curStep == 2245
    or curStep == 2249
    or curStep == 2256
    or curStep == 2265
    or curStep == 2267
    or curStep == 2268
    or curStep == 2269
    or curStep == 2270
    or curStep == 2274
    or curStep == 2278
    or curStep == 2286
    or curStep == 2291
    or curStep == 2296
    or curStep == 2299
    or curStep == 2302
    or curStep == 2308
    or curStep == 2310
    or curStep == 2311
    or curStep == 2312
    or curStep == 2315
    or curStep == 2323
    --or curStep == 2328
    --or curStep == 2331
    --or curStep == 2333
    --or curStep == 2335
    --or curStep == 2337
     then
        setProperty('camGame.zoom',1.25)
        setProperty('camHUD.zoom',1.25)
        setProperty('camOther.zoom',1.25)
        doTweenZoom("camHUDZooms",'camHUD',0.85,0.3,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',1.0,0.3,'EXPOOUT')        
        doTweenZoom('camGameZs','camGame',0.75,0.3,'EXPOOUT')
    end  
    if curStep == 2324 then
        doTweenZoom("camHUDZooms",'camHUD',2,0.3,'QUARTIN')
        doTweenZoom("camOtherZooms",'camOther',2.3,0.3,'QUARTIN')
        doTweenZoom('camGameZs','camGame',2,0.3,'QUARTIN')
    end
    if curStep == 2337 then
        setProperty('camGame.zoom',0.4)
        setProperty('camHUD.zoom',0.4)
        setProperty('camOther.zoom',0.4)
        doTweenZoom("camHUDZooms",'camHUD',1.05,2,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',1.0,2,'EXPOOUT')        
        doTweenZoom('camGameZs','camGame',0.95,2,'EXPOOUT')
    end
    if curStep == 2363 then
        doTweenZoom("camHUDZooms",'camHUD',0.55,2.5,'SineIn')
        doTweenZoom("camOtherZooms",'camOther',0.5,2.5,'SineIn')        
        doTweenZoom('camGameZs','camGame',0.75,2.5,'SineIn')
    end----------------------------------------UnusedModechart
    --[[if curStep == 2444 then
        noteTweenY('NoteY0',0,550,0.45,'expoOut')
        noteTweenY('NoteY1',1,550,0.45,'expoOut')
        noteTweenY('NoteY2',2,550,0.45,'expoOut')
        noteTweenY('NoteY3',3,550,0.45,'expoOut')

        noteTweenY('NoteY4',4,550,0.45,'expoOut')
        noteTweenY('NoteY5',5,550,0.45,'expoOut')
        noteTweenY('NoteY6',6,550,0.45,'expoOut')
        noteTweenY('NoteY7',7,550,0.45,'expoOut')

        noteTweenDirection('NoteDirect0',0,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')
        noteTweenDirection('NoteDirect1',1,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')
        noteTweenDirection('NoteDirect2',2,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')
        noteTweenDirection('NoteDirect3',3,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')

        noteTweenDirection('NoteDirect4',4,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')
        noteTweenDirection('NoteDirect5',5,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')
        noteTweenDirection('NoteDirect6',6,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')
        noteTweenDirection('NoteDirect7',7,noteDirec[(downscroll and 2 or 1)],0.45,'expoOut')
    end]]
    if curStep == 2428 then
        for i = 0,7 do
            noteTweenX('midlenote'..i, i, MidleNote[(i % 4) + 1], 0.55,'elasticOut')
        end
        doTweenZoom("camHUDZooms",'camHUD',1.05,2,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',1.0,2,'EXPOOUT')        
        doTweenZoom('camGameZs','camGame',0.95,2,'EXPOOUT')
    end
    if curStep == 2435 then
        doTweenZoom("camHUDZooms",'camHUD',0.4,0.7,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',0.4,0.7,'QuartIN')
        doTweenZoom('camGameZs','camGame',0.35,0.7,'QuartIN')
        doTweenAngle('camGameAngle','camGame',180,0.8,'QuartIN')
        doTweenAngle("camHUDAngle",'camHUD',180,0.8,'QuartIN')
        --doTweenAngle("camOtherAngle",'camOther',180,0.8,'QuartIN')
    end
    if curStep == 2444 then
        noteTweenX('5pX', 4, defaultPlayerStrumX0, 0.6,'quartOut')
        noteTweenX('6pX', 5, defaultPlayerStrumX1, 0.6,'quartOut')
        noteTweenX('7pX', 6, defaultPlayerStrumX2, 0.6,'quartOut')
        noteTweenX('8pX', 7, defaultPlayerStrumX3, 0.6,'quartOut')

        noteTweenX('5OpX', 0, defaultOpponentStrumX0, 0.6,'quartOut')
        noteTweenX('6OpX', 1, defaultOpponentStrumX1, 0.6,'quartOut')
        noteTweenX('7OpX', 2, defaultOpponentStrumX2, 0.6,'quartOut')
        noteTweenX('8OpX', 3, defaultOpponentStrumX3, 0.6,'quartOut')
        --[[noteTweenX('pFlyX5', 0, -650,0.45) UnusedModechart2
        noteTweenX('pXFlyX6', 1, -650,0.65)
        noteTweenX('pFlyX7', 2, -650,0.85)
        noteTweenX('pXFlyX8', 3, -650,1.05)

        noteTweenX('OpFlyX5', 4, -650,0.35)
        noteTweenX('OpXFlyX6', 5, -650,0.55)
        noteTweenX('OpFlyX7', 6, -650,0.75)
        noteTweenX('OpXFlyX8', 7, -650,0.95)]]
        setProperty('camGame.angle',-25)
        setProperty('camHUD.angle',-25)
        --setProperty('camOther.angle',-25)
        setProperty('camGame.zoom',0.1)
        setProperty('camHUD.zoom',0.1)
        setProperty('camOther.zoom',0.1)
        doTweenZoom("camHUDZooms",'camHUD',0.3,2.5,'BackOut')
        doTweenZoom("camOtherZooms",'camOther',1,2.8,'BackOut')
        doTweenZoom('camGameZs','camGame',0.55,2.1,'BackOut')
        doTweenAngle("camHUDAngle",'camHUD',0,2.5,'BackOut')
        doTweenAngle("camOtherAngle",'camOther',0,2.5,'BackOut')
        doTweenAngle('camGameAngle','camGame',0,2.5,'BackOut')
        --doTweenAngle('camNotes', 'camOther', (-getPropertyFromClass('flixel.FlxG', 'rotate')) + 40, 0.23, 'QuadOut')
        --doTweenAngle('camGame', 'camGame', (-getPropertyFromClass('flixel.FlxG', 'rotate')) + 40, 0.23, 'QuadOut')
    end
    if curStep == 2492
    or curStep == 2556
    or curStep == 2621
    or curStep == 2747
    or curStep == 2812
    or curStep == 0 then
        doTweenZoom("camHUDZooms",'camHUD',0.75,0.85,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',1.55,0.85,'QuartN')
        doTweenZoom('camGameZs','camGame',0.95,0.85,'QuartIN')
        doTweenAngle('camGameAngle','camGame',50,0.85,'QuartIN')
        doTweenAngle("camHUDAngle",'camHUD',50,0.85,'QuartIN')
        --doTweenAngle("camOtherAngle",'camOther',50,0.85,'QuartIN')
    end
    if curStep == 2514 
    or curStep == 2578
    or curStep == 2643
    or curStep == 2769
    or curStep == 2836 then
        
        doTweenZoom("camHUDZooms",'camHUD',0.3,1.1,'BackOut')
        doTweenZoom("camOtherZooms",'camOther',1,1.1,'BackOut')
        doTweenZoom('camGameZs','camGame',0.55,1.1,'BackOut')
        doTweenAngle('camGameAngle','camGame',0,1.1,'BackOut')
        doTweenAngle("camHUDAngle",'camHUD',0,1.1,'BackOut')
        doTweenAngle("camOtherAngle",'camOther',0,1.1,'BackOut')
    end
    if curStep == 2668 then
        doTweenZoom("camHUDZooms",'camHUD',0.65,1,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',2,1,'EXPOOUT')        
        doTweenZoom('camGameZs','camGame',0.75,1,'EXPOOUT')
    end
    if curStep == 2689 then
        doTweenZoom("camHUDZooms",'camHUD',0.4,0.6,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',1.05,0.6,'QuartIN')
        doTweenZoom('camGameZs','camGame',0.35,0.6,'QuartIN')
        doTweenAngle('camGameAngle','camGame',180,0.6,'QuartIN')
        doTweenAngle("camHUDAngle",'camHUD',180,0.6,'QuartIN')
        --doTweenAngle("camOtherAngle",'camOther',180,0.6,'QuartIN')
    end
    if curStep == 2700 then
        setProperty('camGame.angle',-25)
        setProperty('camHUD.angle',-25)
        --setProperty('camOther.angle',-25)
        setProperty('camGame.zoom',0.1)
        setProperty('camHUD.zoom',0.01)
        --setProperty('camOther.zoom',0.5)
        doTweenZoom("camHUDZooms",'camHUD',0.3,2.2,'BackOut')
        --doTweenZoom("camOtherZooms",'camOther',1,2.2,'BackOut')
        doTweenZoom('camGameZs','camGame',0.55,2.2,'BackOut')
        doTweenAngle("camHUDAngle",'camHUD',0,2.5,'BackOut')
        --doTweenAngle("camOtherAngle",'camOther',0,2.5,'BackOut')
        doTweenAngle('camGameAngle','camGame',0,2.5,'BackOut')
    end
    if curStep == 2908 then
        doTweenY("camHUDY",'camHUD',400,0.5,'quartin')
        --doTweenY("camOtherY",'camOther',100,0.5,'quartin')
        --doTweenY('camGameY','camGame',100,2.1,'quartin')
    end

    if curStep == 2924 then
        --setProperty('camGame.y',-300)
        setProperty('camHUD.y',-600)
        setProperty('camOther.y',-300)
        doTweenY("camHUDY",'camHUD',0,0.4,'quartOut')
        doTweenY("camOtherY",'camOther',0,0.4,'quartOut')
    end
    if curStep == 2932 then
        for i = 4,7 do
            noteTweenX('midlenote'..i, i, MidleNote[(i % 4) + 1], 0.5,'expoinOut')
        end
        doTweenZoom("camHUDZooms",'camHUD',2.0,0.4,'Quartin')
        doTweenZoom("camOtherZooms",'camOther',2.0,0.4,'Quartin')
        doTweenZoom('camGameZs','camGame',2.05,0.4,'Quartin')
        doTweenAngle("camHUDAngle",'camHUD',-90,1.2,'Quartin')
        doTweenAngle("camOtherAngle",'camOther',-90,1.2,'Quartin')
        doTweenAngle('camGameAngle','camGame',-90,1.2,'Quartin')
    end
    if curStep >= 2938 and curStep <= 3448 then
        songPos = getSongPosition()
        currentBeat = (songPos / 400) * (bpm / 10)
        --[[for i = 0,3 do 
            --setPropertyFromGroup('strumLineNotes', i, 'x', noteXCenter[(i % 4) + 1] + 16 * math.sin((currentBeat + i*0.25) * math.pi))
            --setPropertyFromGroup('strumLineNotes', i, 'y', noteYPlace[(downscroll and 2 or 1)] + 16 * math.cos((currentBeat + i*0.25) * math.pi))
            noteTweenX('aeiozsduy'..i, i, 605 + 1912 * math.sin(((currentBeat / 8) + i*0.25) * math.pi), 0.5)
            noteTweenY('aawezdfuy'..i, i, noteYPlace[(downscroll and 2 or 1)] + 324 * math.cos(((currentBeat / 8) + i*0.25) * math.pi), 0.5)
        end]]
        noteTweenX('aeiozsdu0', 0, 605 + 2212 * math.sin(((currentBeat / 2)) * math.pi), 0.1)
        noteTweenX('aeiozsdu1', 1, 605 + 2212 * math.sin(((currentBeat / 4)) * math.pi), 0.1)
        noteTweenX('aeiozsdu2', 2, 605 + 2212 * math.sin(((currentBeat / 6)) * math.pi), 0.1)
        noteTweenX('aeiozsdu3', 3, 605 + 2212 * math.sin(((currentBeat / 8)) * math.pi), 0.1)
        noteTweenY('aawezdfu0', 0, noteYPlace[(downscroll and 2 or 1)] + 624 * math.cos(((currentBeat / 5)) * math.pi), 0.2)
        noteTweenY('aawezdfu1', 1, noteYPlace[(downscroll and 1 or 2)] + 624 * math.cos(((currentBeat / 6)) * math.pi), 0.2)
        noteTweenY('aawezdfu2', 2, noteYPlace[(downscroll and 2 or 1)] + 624 * math.cos(((currentBeat / 7)) * math.pi), 0.2)
        noteTweenY('aawezdfu3', 3, noteYPlace[(downscroll and 1 or 2)] + 624 * math.cos(((currentBeat / 8)) * math.pi), 0.2)

        noteTweenDirection('aeiozsDirec0', 0, 90 + 2212 * math.sin(((currentBeat / 2)) * math.pi), 0.1)
        noteTweenDirection('aeiozsDirec1', 1, 90 + 2212 * math.sin(((currentBeat / 4)) * math.pi), 0.1)
        noteTweenDirection('aeiozsDirec2', 2, 90 + 2212 * math.sin(((currentBeat / 6)) * math.pi), 0.1)
        noteTweenDirection('aeiozsDirec3', 3, 90 + 2212 * math.sin(((currentBeat / 8)) * math.pi), 0.1)


    end
    if curStep == 2931 then
        doTweenZoom("camHUDZooms",'camHUD',0.3,0.5,'QuartinOut')
        doTweenZoom("camOtherZooms",'camOther',1,0.5,'QuartinOut')
        doTweenZoom('camGameZs','camGame',0.75,0.5,'QuartinOut')
    end
    if curStep == 2943 then
        
        setProperty('camGame.zoom',0.4)
        setProperty('camHUD.zoom',0.4)
        setProperty('camOther.zoom',1)
        doTweenZoom("camHUDZooms",'camHUD',0.65,2,'ExpoOut')
        doTweenZoom("camOtherZooms",'camOther',1,2,'ExpoOut')        
        doTweenZoom('camGameZs','camGame',0.85,2,'ExpoOut')
        setProperty('camGame.angle',25)
        setProperty('camHUD.angle',25)
        --setProperty('camOther.angle',25)
        doTweenAngle("camHUDAngle",'camHUD',0,2.5,'EXPOOUT')
        doTweenAngle("camOtherAngle",'camOther',0,2.5,'EXPOOUT')
        doTweenAngle('camGameAngle','camGame',0,2.5,'EXPOOUT')
    end
    if curStep == 3156 then
        ---doTweenX('camGameX','camGame',-200,1.1,'quartin')
        doTweenX("camHUDX",'camHUD',-600,1.1,'quartin')
        --doTweenX("camOtherX",'camOther',-600,1.1,'quartin')
    end
    if curStep == 3220 then
        --setProperty('camGame.x',100)
        setProperty('camHUD.x',600)
        --setProperty('camOther.x',600)
        doTweenX("camHUDX",'camHUD',0,0.6,'quartOut')
        --doTweenX("camOtherX",'camOther',0,0.6,'quartOut')
        --doTweenX('camGameX','camGame',0,0.6,'quartOut')

    end
    
    if curStep == 3436 then
        doTweenZoom("camHUDZooms",'camHUD',0.2,0.6,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',1.05,0.6,'QuartIN')
        doTweenZoom('camGameZs','camGame',0.35,0.6,'QuartIN')
        --doTweenAngle('camGameAngle','camGame',180,0.6,'QuartIN')
        --doTweenAngle("camHUDAngle",'camHUD',180,0.6,'QuartIN')
        --doTweenAngle("camOtherAngle",'camOther',180,0.6,'QuartIN')
    end
    if curStep == 3452 then
        for i = 0,7 do
            noteTweenDirection('direct'..i, i, 90, 0.6,'QuartOut')
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1],0.6,'QuartOut')
        end
        noteTweenY('5pY', 4, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6pY', 5, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7pY', 6, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8pY', 7, defaultPlayerStrumY0, 0.1,"ElasticOut")

        noteTweenY('5OpY', 0, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6OpY', 1, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7OpY', 2, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8OpY', 3, defaultPlayerStrumY0, 0.1,"ElasticOut")
        --setProperty('camGame.angle',-25)
        --setProperty('camHUD.angle',-25)
        --setProperty('camOther.angle',-25)
        setProperty('camGame.zoom',2)
        setProperty('camHUD.zoom',2)
        setProperty('camOther.zoom',2)
        doTweenZoom("camHUDZooms",'camHUD',0.5,3.2,'BackOut')
        doTweenZoom("camOtherZooms",'camOther',1,3.2,'BackOut')
        doTweenZoom('camGameZs','camGame',0.55,3.2,'BackOut')
        --doTweenAngle("camHUDAngle",'camHUD',0,2.5,'BackOut')
        --doTweenAngle("camOtherAngle",'camOther',0,2.5,'BackOut')
        --doTweenAngle('camGameAngle','camGame',0,2.5,'BackOut')
    end
    if curStep == 3460 then
        for i = 0,7 do
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1],0.6,'QuartOut')
        end
        for i = 0,3 do
            noteTweenDirection('direct'..i, i, -90, 0.6,'QuartOut')
        end
        noteTweenY('5pY', 4, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6pY', 5, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7pY', 6, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8pY', 7, defaultPlayerStrumY0, 0.1,"ElasticOut")

        noteTweenY('5OpY', 0, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6OpY', 1, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7OpY', 2, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8OpY', 3, defaultPlayerStrumY0, 0.1,"ElasticOut")
    end
    if curStep == 3477 then
        for i = 0,7 do
            noteTweenX('NoteXs'..i,i,noteXCenter[(i % 4)+1],0.6,'QuartOut')
        end
        noteTweenY('5pY', 4, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6pY', 5, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7pY', 6, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8pY', 7, defaultPlayerStrumY0, 0.1,"ElasticOut")

        noteTweenY('5OpY', 0, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('6OpY', 1, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('7OpY', 2, defaultPlayerStrumY0, 0.1,"ElasticOut")
        noteTweenY('8OpY', 3, defaultPlayerStrumY0, 0.1,"ElasticOut")
        doTweenZoom("camHUDZooms",'camHUD',2,0.4,'QuartIN')
        doTweenZoom("camOtherZooms",'camOther',2,0.4,'QuartIN')
        doTweenZoom('camGameZs','camGame',2,0.4,'QuartIN')

    end

    if curStep == 3485 then
        setProperty('camGame.zoom',2)
        setProperty('camHUD.zoom',0.2)
        setProperty('camOther.zoom',1)
        setProperty('camGame.y',-500)
        doTweenY("camGameY",'camGame', 0,2,'expoOut')

        doTweenZoom("camHUDZooms",'camHUD',0.6,1.2,'expoOut')
        doTweenZoom("camOtherZooms",'camOther',1,1.2,'expoOut')
        doTweenZoom('camGameZs','camGame',0.35,1.2,'expoOut')

    end
    if curStep == 3605 then
        doTweenX("camHUDX",'camHUD',600,0.1,'quartin')
        --doTweenX('camGameX','camGame',200,1,'quartin')
        --doTweenX("camOtherX",'camOther',-600,1,'quartin')
    end
    if curStep == 3612 then
        setProperty('camGame.x',0)
        setProperty('camHUD.x',0)
        cancelTween('camGameX')
        cancelTween('camHUDX')
        doTweenX('camGameX','camGame',0,0.001)
        doTweenX("camHUDX",'camHUD',0,0.001)
        noteTweenX('5pX', 4, 340, 0.001,'quartOut')
        noteTweenX('6pX', 5, 570, 0.001,'quartOut')
        noteTweenX('7pX', 6, 570, 0.001,'quartOut')
        noteTweenX('8pX', 7, 815, 0.001,'quartOut')

        noteTweenX('5OpX', 0, 440, 0.001,'quartOut')
        noteTweenX('6OpX', 1, 700, 0.001,'quartOut')
        noteTweenX('7OpX', 2, 440, 0.001,'quartOut')
        noteTweenX('8OpX', 3, 700, 0.001,'quartOut')

        noteTweenY('5pY', 4, scroll180[(downscroll and 2 or 1)], 0.001,'quartOut')
        noteTweenY('6pY', 5, scroll90d[(downscroll and 2 or 1)], 0.001,'quartOut')
        noteTweenY('7pY', 6, scroll90[(downscroll and 2 or 1)], 0.001,'quartOut')
        noteTweenY('8pY', 7, scroll180[(downscroll and 2 or 1)], 0.001,'quartOut')

        noteTweenY('5OpY', 0, scroll135d[(downscroll and 2 or 1)], 0.001,'quartOut')
        noteTweenY('6OpY', 1, scroll45d[(downscroll and 2 or 1)], 0.001,'quartOut')
        noteTweenY('7OpY', 2, scroll135[(downscroll and 2 or 1)], 0.001,'quartOut')
        noteTweenY('8OpY', 3, scroll45[(downscroll and 2 or 1)], 0.001,'quartOut')

        noteTweenDirection("noteFlippy0", 4, direction180d[(downscroll and 1 or 2)], 0.001, 'expoOut')
        noteTweenDirection("noteFlippy1", 5, 90, 0.3, 'expoOut')
        noteTweenDirection("noteFlippy2", 6, -90, 0.3, 'expoOut')
        noteTweenDirection("noteFlippy3", 7, direction180d[(downscroll and 2 or 1)], 0.001, 'expoOut')

        noteTweenDirection("noteFlipy0", 0, direction135d[(downscroll and 1 or 2)], 0.001, 'expoOut')
        noteTweenDirection("noteFlipy1", 1, direction135[(downscroll and 1 or 2)], 0.001, 'expoOut')
        noteTweenDirection("noteFlipy2", 2, direction45d[(downscroll and 1 or 2)], 0.001, 'expoOut')
        noteTweenDirection("noteFlipy3", 3, direction45[(downscroll and 1 or 2)],0.001, 'expoOut')
        
    end
    if curStep == 3620 then
        setProperty('camGame.zoom',0.55)
    end
    if curStep == 3655 then
        doTweenZoom("camOtherZooms",'camOther',5,0.00001,'expoOut')
        doTweenZoom("camHUDZooms",'camHUD',2,1.8,'QuartinOut')
        doTweenZoom("camOtherZooms",'camOther',2,1.8,'QuartinOut')
        doTweenZoom('camGameZs','camGame',2,1.8,'QuartinOut')
        doTweenAngle("camHUDAngle",'camHUD',720,2.5,'QuartinOut')
    end
    if curStep == 3748 then
        doTweenAngle("camHUDAngle",'camHUD',1080,7.5,'QuartOut')
        setProperty('camGame.zoom',0.4)
        setProperty('camHUD.zoom',0.4)
        setProperty('camOther.zoom',0.75)
        doTweenZoom("camHUDZooms",'camHUD',0.65,6,'QuadinOut')
        doTweenZoom('camGameZs','camGame',0.85,6,'QuadinOut')
    end
end

function onTweenCompleted(tag)

    if tag == '324873279843298732' then
        doTweenZoom("camHUDZooms",'camHUD',0.7,1.3,'EXPOOUT')
        doTweenZoom("camOtherZooms",'camOther',0.9,1.6,'EXPOOUT')
        doTweenZoom('camGameZs','camGame',0.95,0.9,'EXPOOUT')
    end


    if tag == 'pFlyX5' then
        noteTweenX('pFlyXDone5', 4,1400,0.0001)
        noteTweenAngle('pFlyAngleDone5', 4,360,0.0001)
    end
    if tag == 'pFlyXDone5' then
        noteTweenX('pFlyX5', 4,-1200,0.7)
        noteTweenAngle('pFlyAngle5', 4,0,0.4)
    end

    if tag == 'pXFlyX6' then
        noteTweenX('pXFlyX6Done', 5,1400,0.0001)
        noteTweenAngle('pFlyAngleDone6', 5,360,0.0001)

    end
    if tag == 'pXFlyX6Done' then
        noteTweenX('pXFlyX6', 5,-1200,0.7)
        noteTweenAngle('pFlyAngle6', 5,0,0.4)
    end

    if tag == 'pFlyX7' then
        noteTweenX('pFlyX7Done', 6,1400,0.0001)
        noteTweenAngle('pFlyAngleDone7', 6,360,0.0001)
    end
    if tag == 'pFlyX7Done' then
        noteTweenX('pFlyX7', 6,-1200,0.7)
        noteTweenAngle('pFlyAngle7', 6,0,0.4)

    end

    if tag == 'pXFlyX8' then
        noteTweenX('pXFlyX8Done', 7,1400,0.0001)
        noteTweenAngle('pFlyAngleDone8', 7,360,0.0001)

    end
    if tag == 'pXFlyX8Done' then
        noteTweenX('pXFlyX8', 7,-1200,0.7)
        noteTweenAngle('pFlyAngle8', 7,0,0.4)

    end

    if tag == 'OpFlyX5' then
        noteTweenX('OpFlyXDone5', 0,1400,0.0001)
        noteTweenAngle('OpFlyAngleDone5', 0,360,0.0001)

    end
    if tag == 'OpFlyXDone5' then
        noteTweenX('OpFlyX5', 0,-1200,0.7)
        noteTweenAngle('OpFlyAngle5', 0,0,0.4)

    end

    if tag == 'OpXFlyX6' then
        noteTweenX('OpXFlyX6Done', 1,1400,0.0001)
        noteTweenAngle('OpFlyAngleDone6', 1,360,0.0001)

    end
    if tag == 'OpXFlyX6Done' then
        noteTweenX('OpXFlyX6', 1,-1200,0.7)
        noteTweenAngle('OpFlyAngle6', 1,0,0.4)
    end

    if tag == 'OpFlyX7' then
        noteTweenX('OpFlyX7Done', 2,1400,0.0001)
        noteTweenAngle('OpFlyAngleDone7', 2,360,0.0001)
    end
    if tag == 'OpFlyX7Done' then
        noteTweenX('OpFlyX7', 2,-1200,0.7)
        noteTweenAngle('OpFlyAngle7', 2,0,0.4)

    end

    if tag == 'OpXFlyX8' then
        noteTweenX('OpXFlyX8Done', 3,1400,0.0001)
        noteTweenAngle('OpFlyAngleDone8', 3,360,0.0001)
    end
    if tag == 'OpXFlyX8Done' then
        noteTweenX('OpXFlyX8', 3,-1200,0.7)
        noteTweenAngle('OpFlyAngle8', 3,0,0.4)

    end
end