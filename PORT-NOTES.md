# Hello2021-2022 — Light Engine port

Original mod: **Hello2021-2022 / BPM-2021 (Camellia)** by Ashilluman and Verdi,
built for Psych Engine 0.6.x. This repository is the Light Engine port of the
same mod: same song, same chart, same stage art, same modchart choreography.

The original Psych structure is gone — there is no `pack.json`, no
`weeks/*.json`, no `data/<SONG>/Data.lua`. Everything now follows Light
Engine's layout and runs on Light Engine's own objects, cameras and tweens.

---

## 1. Layout

| Old (Psych)                              | New (Light Engine)                          |
| ---------------------------------------- | ------------------------------------------- |
| `pack.json`, `pack.xml`, `pack.png`      | `meta.json` (+ `icon.png`)                  |
| `weeks/BPM1.json`                        | `data/weeks/weeks/hello2021.json`           |
| `data/BPM-2021/BPM-2021-Impossible.json` | `songs/bpm-2021/charts/impossible.json`     |
| `data/BPM-2021/events.json`              | `songs/bpm-2021/events.json`                |
| `songs/BPM-2021/inst.ogg`                | `songs/bpm-2021/Inst.ogg`                   |
| `data/BPM-2021/Data.lua` (stage)         | `data/stages/hello2021/stage.lua`           |
| `data/BPM-2021/New Text Document.lua`    | `songs/bpm-2021/script.lua` (modchart)      |
| *(Psych hardcoded stage)*                | `data/stages/hello2021.json`                |
| *(Psych `Settings` class)*               | `data/classes/hello2021/settings.lua`       |
| `images/Hello2021/*`                     | unchanged (asset paths are engine agnostic) |
| `images/credits/*`, `data/credits.txt`   | unchanged                                   |

`shaders/*.frag` are kept for reference; the original scripts never bound them
(no `initLuaShader`/`setSpriteShader` calls anywhere in the mod), so they are
not loaded by the port.

## 2. How the Psych scripts run unchanged

Light Engine sandboxes native scripts: `load`, `loadstring`, `setfenv`, `io`
and `ffi` are denied, so a Psych script cannot be interpreted at runtime. The
engine ships exactly one sanctioned pattern for this: a native script that
calls a helper API itself (`funkin/backend/scripts/compat.lua`). This port
follows that pattern.

`data/classes/hello2021/psychbridge.lua` installs the FunkinLua subset this mod
uses as **globals of the calling script**, then the original Psych body runs
verbatim below it. Nothing is translated by hand and nothing is rewritten:

```
-- header (new)                        -- body (original, byte for byte)
local bridge = require(...)            function onStepHit()
api = bridge.install(state, ...)           if curStep == 24 then
bridge.installGlobals(api, env)                setProperty('plexusred.alpha', 0.3)
                                       ...
```

Both scripts keep their own API instance, exactly like the two Psych script
instances they used to be.

## 3. API implemented

Sprites / text
`makeLuaSprite`, `makeAnimatedLuaSprite`, `makeGraphic`, `makeLuaText`,
`addLuaSprite`, `addLuaText`, `removeLuaSprite`, `scaleObject`,
`setObjectCamera`, `setObjectOrder`, `setBlendMode`, `setScrollFactor`,
`objectPlayAnim`, `setTextString`, `setTextSize`, `setTextFont`,
`setTextColor`, `setTextAlignment`, `setTextWidth`

State
`getProperty`, `setProperty`, `getPropertyFromGroup`, `setPropertyFromGroup`,
`getPropertyFromClass`, `getSongPosition`, `getCurrentStep`, `getSongBpm`
plus the globals `curStep`, `curDecStep`, `curBeat`, `curDecBeat`, `bpm`,
`crotchet`, `stepCrochet`, `downscroll`, `songName`, `songLength`

Tweens
`doTweenX/Y/Angle/Alpha/Zoom`, `doTweenProperty`, `cancelTween`,
`noteTweenX/Y/Angle/Direction/Alpha`, `onTweenCompleted`

Cameras
`cameraShake`, `cameraFlash`, `cameraFade`

Audio
`playSound`, `precacheImage`, `precacheSound`, `precacheMusic`

## 4. Behaviour details that needed real work

* **camGame zoom.** Light Engine recomputes `game.camera.zoom` from
  `state.camZoom` every frame, so a tween on the camera object would be
  overwritten instantly. `doTweenZoom(tag,'camGame',…)` now drives
  `state.camZoom`, which is the same knob Psych called `defaultCamZoom`.
* **camHUD / camNotes zoom.** Light Engine lerps these back to 1 every frame
  (the beat bop). The port records the authored value and re-applies it each
  frame, matching the original running with `camZooming` off.
* **The eight strums.** Psych exposes a flat `strumLineNotes` group (0–3
  opponent, 4–7 player). Light Engine keeps two notefields with their own
  lanes, so `noteTween*` maps indices onto `enemyNotefield`/`playerNotefield`
  and converts Psych's screen coordinates into per-receptor offsets. Relative
  motion (waves, pinches, snaps, scrolls) is preserved pixel for pixel;
  absolute X/Y values are re-based on the lane, which is what makes them
  survive any window size or downscroll.
* **noteTweenDirection / noteTweenAngle.** Implemented with the native
  `NoteModifier` stack: a custom modifier writes `receptor.noteAngles` and
  shifts each note along `(cos d, sin d) * distance` in `applyPath`, exactly
  where Psych placed them. Psych's `angle = direction - 90` rotation is applied
  too, so notes spin as they travel.
* **`doTweenX('tag','sprite.scale',…)`.** Psych resolves the path and then
  tweens `x` **inside** the resolved object, so this means `sprite.scale.x`.
  Implemented the same way (`tweenPath`).
* **camOther / camHUD layers.** Psych keeps one display list per camera; the
  port creates matching `SpriteGroup`s so `setObjectCamera` +
  `setObjectOrder` compose identically instead of all landing in one list.
* **`math.random` with many seeds.** The original `onUpdate` calls
  `math.random(a,b,c,…)` (nine arguments). LuaJIT — the runtime both engines
  use — raises on that, which aborted the callback every single frame in the
  original. The bridge proxies `math.random` to keep the 1–2 argument
  behaviour identical and pick one of the given values for the rest, so the
  fragments jitter as intended.
* **`cambria.ttc`.** The original `setTextFont('text1','cambria.ttc')` names a
  font neither engine ships. `setTextFont` falls back to `vcr.ttf` (the font
  the mod's other text uses).
* **Psych HUD hiding.** The stage script hides `healthBar`, `iconP1/P2`,
  `timeBar…` and the characters every frame. Light Engine has no `timeBar` at
  all and keeps `healthBar` as one object, so those properties are accepted and
  the play state HUD group is hidden natively instead.

## 5. Custom events

`events.json` drives four events:

| Event                 | Count | Implementation                                    |
| --------------------- | ----- | ------------------------------------------------- |
| `Change Scroll Speed` | 21    | built-in `scrollspeed` (same Psych args)          |
| `noteShimmy`          | 81    | `onEvent` in `songs/bpm-2021/script.lua`          |
| `NoteBump`            | 31    | same                                              |
| `Screen Shake`        | 3     | built-in `screenshake` (`0.2,0.05` args)          |

`noteShimmy` and `NoteBump` read their tuning from
`data/classes/hello2021/settings.lua`, mirroring the `Settings` class the
original mod exposed.

## 6. Verified

The port was executed in a Lua VM against a stubbed Light Engine API:

* `data/stages/hello2021/stage.lua` — 58 objects created; 900 frames of the
  timeline (10 s) with no error. `solid`, `plexusred`, `gridD`, `dark`,
  `Vignette`, `MountainMove1`, `text1`, `TwentyONE`, `fragments`, `blueG`,
  `white` all reach the alphas/positions the script asks for at those steps;
  8 sprites land on the `camOther` layer as authored.
* `songs/bpm-2021/script.lua` — 3000 frames (50 s) with no error; cameras and
  receptors end up at the values the script sets for that step.
* `noteTweenDirection`/`noteTweenAngle` — a direction of 45° maps a note at
  `pos = 100` to `(70.7, 70.7)`; 90° (the default) leaves it at `(0, 100)`.
* The real Light Engine vanilla chart parser reads the chart: 4128 player notes,
  4128 opponent notes, 53 time changes, 129 events.

## 7. Credits

Original mod by **Ashilluman** (mod creator, visual FX) and **Verdi** (charter),
with **A9_AriXx / No** as charter. Music: **Camellia** — *BPM-2021*.
See `data/credits.txt` and the credits menu art in `images/credits/`.
