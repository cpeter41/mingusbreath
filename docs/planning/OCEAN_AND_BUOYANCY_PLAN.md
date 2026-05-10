# Ocean & Buoyancy Plan — Wave Function, Unified Buoyancy, RigidBody3D Boat

## Status

Broad plan only. Each step section below is a sketch — details, file lists, and constants are filled in as we work through them one at a time.

---

## Context

Today the "ocean" is a single flat `MeshInstance3D` parented to `OceanFollower` that copies the player's XZ each frame; water height is the constant `OceanFollower.WATER_Y = -0.15`. Several systems consume this constant directly:

- [scripts/world/ocean_follower.gd:4](scripts/world/ocean_follower.gd:4) — owns the constant; pins ocean mesh Y.
- [scripts/player/movement_states/swim.gd:32](scripts/player/movement_states/swim.gd:32) — fakes "buoyancy" by spring-tracking `WATER_Y + sin(t * BOB_FREQ) * BOB_AMPLITUDE + SURFACE_OFFSET`. The bob is hardcoded animation, not physics — there is no actual displacement-driven force anywhere.
- [scripts/player/movement_states/fall.gd:14](scripts/player/movement_states/fall.gd:14) — uses `WATER_Y` as the trigger to enter swim.
- [scripts/ships/boat.gd:154](scripts/ships/boat.gd:154) — `CharacterBody3D` boat with `position.y = lerp(position.y, water_y, 0.4)` after `move_and_slide()`. The author already flagged this in [boat.gd:14–17](scripts/ships/boat.gd:14) as "the seam to fix when buoyancy + waves land."
- [scripts/dev/test_island.gd:10](scripts/dev/test_island.gd:10) — duplicates the constant locally.

There is no water shader yet (only [shaders/sky.gdshader](shaders/sky.gdshader)); the ocean mesh uses a placeholder material per the Phase 5 plan.

The architecture doc ([ARCHITECTURE.md:217–226](docs/planning/ARCHITECTURE.md:217)) anticipates this work as one paragraph: "RigidBody3D with a custom buoyancy script sampling water height (matches the ocean shader's wave function) at a few hull points." This plan expands that paragraph into a sequenced migration that also unifies the player's swim bob with the same wave function.

---

## Goals

1. **Single source of truth for wave height.** One function, evaluated identically in GDScript (physics) and the water shader (visuals). If the two ever drift, things float at the wrong height.
2. **Real buoyancy for boats.** Boat becomes a `RigidBody3D`; pitch and roll on waves emerge naturally from off-centre buoyancy points and angular drag, not from fake animation.
3. **Player swim bob driven by the same wave function.** No more local `sin(t)` in swim state — the player rises and falls with the actual water surface.
4. **Reusable buoyancy helper.** Any future floating object (debris, barrels, enemy ships) plugs in by listing N hull points; no per-object physics rewrites.
5. **No regressions.** Boat handles roughly as it does today (arcade throttle + rudder), mounted player stays welded to the deck, save/load round-trips, swim entry/exit thresholds still feel right.

Explicit non-goals:

- No fluid simulation (volumetric water, splash particles past trivial). Waves are analytic Gerstner only.
- No wind, sails, or sailing physics — throttle/rudder stays.
- No naval combat (cannons, enemy ships) — that's a later phase.
- No water-shader visual polish past "convincing enough to validate the wave function" — foam, SSR, depth fade can iterate after the physics is right.

---

## Architecture Edits (apply to `docs/planning/ARCHITECTURE.md` when this plan lands)

Sketch only — exact wording deferred until we've nailed the design in the per-step sections below.

1. **New autoload `Ocean`.** Add to the autoloads table in §"Global Services". Owns `get_height(x, z, t) -> float`, `roughness_at(x, z, t) -> float`, the Gerstner parameter set, and `WATER_BASE_Y`. Replaces the role currently played by `OceanFollower.WATER_Y`. Pushes shader uniforms each frame.
2. **Rewrite §"Boats & Naval Combat" boat paragraph.** Replace the stub-boat note with the new `RigidBody3D` + `Buoyancy` helper design. Pin hull-point count, drag coefficients, and steering-as-force model.
3. **Add §"Water" subsection** (or fold into §"World System"). Documents the Gerstner parameter set, the roughness factor, the autoload-pushes-uniforms contract, and the rule that physics and shader read from the same source. Note the future-extension path for spatially-varying roughness via shared noise texture.
4. **Update §"Save System"** — boat persists rotation + angular velocity in addition to position.

---

## Step-by-Step Plan (Broad)

Ordering is least-invasive → most-invasive. Each step should be playable / verifiable on its own.

### Step 1 — `Ocean` autoload + analytic wave function

Goal: stand up `globals/ocean.gd` as a registered autoload that owns the canonical wave parameters, the global time, and `WATER_BASE_Y`, and exposes `get_height(x, z, t) -> float` for any future caller. Nothing else in the codebase consumes it yet — that's Step 3.

#### API surface

```
Ocean.WATER_BASE_Y : float                                # const, -0.15 (matches today's WATER_Y)
Ocean.WAVES        : Array[Vector4]                       # const, 4 entries (see "Parameter set" below)
Ocean.GRAVITY      : float                                # const, 9.81

Ocean.global_roughness : float = 1.0                      # tunable runtime scalar
Ocean.time             : float                            # accumulated by _process

Ocean.get_height(x: float, z: float, t: float) -> float
Ocean.roughness_at(x: float, z: float, t: float) -> float # returns global_roughness; (x,z,t) currently unused
```

`get_normal(x, z, t)` is **not** added in Step 1. Step 4's buoyancy applies vertical force per submerged hull point and lets the asymmetric application produce torque — surface normals aren't actually needed for that. We add it later only if a consumer asks for it.

#### Wave math

A single Gerstner wave's vertical contribution at world position `(x, z)` and time `t`:

```
phase_i = k_i · (D_i · (x, z)) - ω_i · t
height_i = A_i · sin(phase_i)
```

Where:
- `D_i = (Dx, Dz)` is the unit direction of wave i
- `A_i` is amplitude (metres)
- `λ_i` is wavelength (metres); `k_i = 2π / λ_i` is wavenumber
- `ω_i = sqrt(g · k_i)` is the deep-water dispersion frequency (rad/s)

Total height at `(x, z, t)`:

```
get_height(x, z, t) = WATER_BASE_Y + roughness_at(x, z, t) * Σ_i height_i
```

GDScript implementation, with no early optimisation:

```gdscript
func get_height(x: float, z: float, t: float) -> float:
    var sum := 0.0
    for w in WAVES:
        var k := TAU / w.w           # wavenumber from wavelength
        var omega := sqrt(GRAVITY * k)
        var phase := k * (w.x * x + w.y * z) - omega * t
        sum += w.z * sin(phase)
    return WATER_BASE_Y + roughness_at(x, z, t) * sum
```

We pack each wave as `Vector4(dir.x, dir.y, amplitude, wavelength)` because Step 2 will push these to the shader as a `vec4[4]` uniform. One representation, both sides.

#### Parameter set (medium-calm starter)

Four waves: one long swell, two medium waves at offset angles, one short chop. All directions are unit vectors. **Treat these numbers as starting values — Step 9 will retune by feel.**

| # | Direction (Dx, Dz) | Amplitude (m) | Wavelength (m) | Period ≈ (s) | Role |
|---|---|---|---|---|---|
| 1 | ( 1.000,  0.000) | 0.30 | 30.0 | 4.4 | Primary swell, biggest wave |
| 2 | ( 0.866,  0.500) | 0.18 | 18.0 | 3.4 | Secondary swell, ~30° off primary |
| 3 | ( 0.500,  0.866) | 0.10 | 10.0 | 2.5 | Medium chop, ~60° off |
| 4 | (-0.500,  0.866) | 0.07 |  6.0 | 2.0 | Short chop, ~120° off (cross direction) |

Sum-of-amplitudes ceiling: 0.65 m above base, 0.65 m below — i.e. an absolute peak-to-trough envelope of 1.30 m, but constructive alignment of all four waves at one point is rare; typical instantaneous range is 0.5–0.9 m peak-to-trough. That's "you can clearly see the boat rise and fall," not "the deck is going vertical."

The directions deliberately don't all line up — mixed-direction waves break up the visible regularity. The longest wave (#1) has the largest amplitude because real swells follow that pattern; it also dominates the boat's pitch axis.

#### Approximation: physics ignores horizontal Gerstner displacement

A full Gerstner wave displaces a surface point both vertically *and* horizontally — a rest position `(x0, z0)` ends up at `(x0 + Q·A·Dx·cos(phase), A·sin(phase), z0 + Q·A·Dz·cos(phase))` where `Q` is steepness. The vertex shader (Step 2) will use this full displacement so waves visually *roll* rather than just bobbing.

For physics, we ignore the horizontal component and evaluate `A · sin(phase)` directly at the queried `(x, z)`. This is the standard approximation:

- Inverting the horizontal displacement to find "what rest position ends up at this query (x, z)" has no closed form for a sum of waves and would require Newton-Raphson iteration per buoyancy point per frame.
- The error is bounded by total horizontal displacement: `Σ Q_i · A_i ≈ 0.20 m` worst case for our parameter set with `Q = 0.3`.
- On a ~5 m boat that's ~4% horizontal misalignment between where the visual surface "actually is" at a point and where physics thinks it is. Invisible in motion.

We document this in code so a future reader knows it's intentional, and so Step 5's boat tuning doesn't waste time chasing the discrepancy.

The shader does *not* use this approximation — it does full Gerstner displacement on the mesh. The acceptable disagreement is exactly the bounded horizontal error above.

#### Time source

`Ocean` accumulates its own time from `_process(delta)`, wrapping at `2^14 = 16384.0` seconds:

```gdscript
const TIME_MOD := 16384.0  # 2^14 — keeps shader-side float32 phase precision sub-millirad

func _process(delta: float) -> void:
    time = fmod(time + delta, TIME_MOD)
```

Every consumer (physics, shader, swim) reads `Ocean.time`. Three reasons:

1. `Engine.time_scale` and `get_tree().paused` both affect `delta` correctly — pause stops the waves, slow-mo slows them, fast-forward speeds them. Wall-clock alternatives like `Time.get_ticks_msec()` ignore both.
2. One number, one source — same value evaluated by physics this physics frame and the shader this render frame. Latency between the two is bounded at one render frame, which is invisible.
3. Trivially serializable if we ever want save/load to preserve wave phase (probably not worth it, but free if needed).

We do **not** also accumulate in `_physics_process` — that would double-count. Physics consumers read whatever `time` was at the most recent `_process`. The one-frame mismatch versus the shader's `time` at render isn't enough to matter visually.

**Why `2^14` specifically.** GDScript's `float` is 64-bit (overflow is academic), but the shader uniform is float32 — so the wrap exists to keep that single-precision value from drifting toward sloppy phase math. ulp(time) doubles at every power of 2; at `2^14` it's `2^-9 ≈ 0.002 s`, and after multiplication by `omega_max ≈ 3.21 rad/s` shader phase precision stays around `0.006 rad` (invisible). At `2^16` it would creep to `~1.4°`, marginally visible on the short chop. `2^12` would wrap during a typical play session.

**The wrap is a discontinuity** — `omega_i · TIME_MOD` doesn't align with TAU for any wave, so all four `sin(phase_i)` terms snap at the wrap. Worst-case visible: a one-frame ~0.3–0.5 m surface twitch, once every 4.5 hours of continuous play. Accepted. Mitigations exist (pick `TIME_MOD` as a multiple of wave #1's period; or per-wave time tracking) and remain available as drop-in fixes if the twitch ever surfaces in playtest.

#### Files

- `globals/ocean.gd` — new autoload script. Bare structure:
  ```gdscript
  extends Node
  
  const WATER_BASE_Y := -0.15
  const GRAVITY := 9.81
  const TIME_MOD := 16384.0  # 2^14, see "Time source" above
  const WAVES: Array[Vector4] = [
      Vector4( 1.000,  0.000, 0.30, 30.0),
      Vector4( 0.866,  0.500, 0.18, 18.0),
      Vector4( 0.500,  0.866, 0.10, 10.0),
      Vector4(-0.500,  0.866, 0.07,  6.0),
  ]
  
  var global_roughness: float = 1.0
  var time: float = 0.0
  
  func _process(delta: float) -> void:
      time = fmod(time + delta, TIME_MOD)
  
  func roughness_at(_x: float, _z: float, _t: float) -> float:
      return global_roughness
  
  func get_height(x: float, z: float, t: float) -> float:
      var sum := 0.0
      for w in WAVES:
          var k := TAU / w.w
          var omega := sqrt(GRAVITY * k)
          var phase := k * (w.x * x + w.y * z) - omega * t
          sum += w.z * sin(phase)
      return WATER_BASE_Y + roughness_at(x, z, t) * sum
  ```
- `project.godot` — register the autoload. Place after `EventBus` and before `SaveSystem` (autoloads above need no dependencies; `Ocean` has none either, but ordering it early keeps it conceptually grouped with the other "world fundamentals" — `EventBus`, `GameState`, etc.).

#### Verification

The autoload has no visible effect until Step 2 lands the shader and Step 3 wires consumers. Two ways to validate Step 1 in isolation:

1. **Static checks.** `get_height(0, 0, 0)` should equal `WATER_BASE_Y` exactly (every `sin(0) = 0`). `get_height(x, z, t)` for any inputs should fall within `WATER_BASE_Y ± Σ A_i · global_roughness` = `[-0.80, 0.50]` for the starter parameters and roughness 1.0.
2. **Print probe.** Add a temporary `_ready` line that prints `get_height(0, 0, 0)`, `get_height(15, 0, 0)`, `get_height(0, 0, 1.0)`, and confirm sensible values (none NaN, smoothly varying with input). Remove before commit.

GUT test only if [tests/](tests/) is already set up — checking now is part of the work; if not, skip rather than introducing the test framework as a side effect of this step.



### Step 2 — Water shader matching the autoload

Goal: visible ocean waves, driven entirely by uniforms pushed from `Ocean`. The shader has *zero* hardcoded wave parameters. Tweaking `Ocean.WAVES` or `Ocean.global_roughness` at runtime moves both visuals and physics together.

#### Uniform contract

`globals/ocean.gd` becomes responsible for pushing every parameter the shader needs. Two cadences:

- **Static** (pushed once when material is registered): `waves`, `gravity`, `steepness`, `time_mod`.
- **Dynamic** (pushed each `_process`): `wave_time`, `wave_roughness`.

```glsl
uniform vec4  waves[4];          // (dir.x, dir.y, amplitude, wavelength) per wave
uniform float gravity = 9.81;
uniform float steepness = 0.30;  // global Q multiplier; per-wave safety-capped in shader
uniform float wave_time = 0.0;
uniform float wave_roughness = 1.0;

// Surface appearance — tunable in editor, not driven by Ocean
uniform vec3  deep_color    : source_color = vec3(0.04, 0.16, 0.30);
uniform vec3  shallow_color : source_color = vec3(0.18, 0.42, 0.58);
uniform float fresnel_power : hint_range(1.0, 8.0) = 4.0;
uniform float specular_strength : hint_range(0.0, 4.0) = 1.5;
```

The first block is the canonical wave description — physics-side `Ocean.get_height` and shader-side `vertex()` evaluate identical math from these. The second block is artist-facing surface-appearance and lives in the material's saved parameters in `World.tscn`, not in `Ocean`. Drift across these is fine — they only affect colour, not geometry.

#### Vertex shader (full Gerstner)

```glsl
void vertex() {
    // Local mesh vertex → world XZ (the plane has no rotation/scale, so MODEL just translates).
    vec3 world_rest = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    float total_y = 0.0;
    vec2  total_xz = vec2(0.0);
    vec2  d_dx = vec2(0.0);  // ∂y/∂x accumulator for normal
    vec2  d_dz = vec2(0.0);  // ∂y/∂z accumulator for normal

    for (int i = 0; i < 4; i++) {
        vec2  dir   = waves[i].xy;
        float amp   = waves[i].z;
        float wlen  = waves[i].w;
        float k     = TAU / wlen;
        float omega = sqrt(gravity * k);
        float Q     = min(steepness, 1.0 / max(k * amp, 1e-6));  // per-wave self-intersection cap
        float phase = k * dot(dir, world_rest.xz) - omega * wave_time;
        float s     = sin(phase);
        float c     = cos(phase);

        total_y  += amp * s;
        total_xz += dir * (Q * amp * c);

        // Analytic gradient of total_y wrt world (x, z) — needed for the normal.
        d_dx.x += amp * dir.x * k * c;
        d_dz.x += amp * dir.y * k * c;
    }

    total_y  *= wave_roughness;
    total_xz *= wave_roughness;

    VERTEX.x += total_xz.x;
    VERTEX.y += total_y;
    VERTEX.z += total_xz.y;

    // Normal from vertical-only height gradient. Slightly inconsistent with the horizontally-
    // displaced position, but error is bounded by steepness*amplitude — invisible at our scales.
    NORMAL = normalize(vec3(-d_dx.x * wave_roughness, 1.0, -d_dz.x * wave_roughness));
}
```

The two analytic gradient accumulators look light because we only need `∂y/∂x` and `∂y/∂z`; that's what their `.x` slots hold. Keeping them as `vec2` leaves room to extend (full bitangent analytic computation) without churning the structure if we want.

#### Fragment shader (simple, sufficient)

```glsl
void fragment() {
    // Fresnel for shallow→deep blend
    float fres = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), fresnel_power);
    ALBEDO = mix(shallow_color, deep_color, 1.0 - fres);
    ROUGHNESS = 0.10;                  // wet, mostly mirror-ish
    METALLIC = 0.0;
    SPECULAR = specular_strength;
}
```

No foam, no SSR, no depth fade, no caustics. Step 2's job is "the wave function is visible and lit"; that's it. Visual polish belongs in a later phase.

#### Wiring `Ocean` to the material

`Ocean` exposes a setter; the consumer (the water mesh) registers itself. Same pattern `TimeOfDay` uses for `set_sun` / `set_world_environment`.

```gdscript
# globals/ocean.gd — additions to Step 1's skeleton

const STEEPNESS := 0.30

var _material: ShaderMaterial = null

func set_water_material(mat: ShaderMaterial) -> void:
    _material = mat
    if _material == null:
        return
    _material.set_shader_parameter("waves", WAVES)
    _material.set_shader_parameter("gravity", GRAVITY)
    _material.set_shader_parameter("steepness", STEEPNESS)
    _material.set_shader_parameter("time_mod", TIME_MOD)

func _process(delta: float) -> void:
    time = fmod(time + delta, TIME_MOD)
    if _material != null:
        _material.set_shader_parameter("wave_time", time)
        _material.set_shader_parameter("wave_roughness", global_roughness)
```

[scripts/world/ocean_follower.gd](scripts/world/ocean_follower.gd) registers the material in `set_target` (the existing entry point already called from `WorldRoot._ready`):

```gdscript
func set_target(node: Node3D) -> void:
    _target = node
    var mesh := $WaterMesh as MeshInstance3D
    Ocean.set_water_material(mesh.material_override as ShaderMaterial)
```

If `_material` is freed (scene reload), `set_shader_parameter` on a stale ref errors — `Ocean.set_water_material(null)` is the cleanup path, called from `OceanFollower._exit_tree` if needed. In practice the autoload outlives the scene and the next `set_target` overwrites it.

#### Scene edits to `World.tscn`

Three changes:

1. **Replace the placeholder `StandardMaterial3D`** ([World.tscn:10–11](scenes/world/World.tscn:10)) with a `ShaderMaterial` referencing `res://shaders/water.gdshader`. The artist-facing uniforms (`deep_color`, `shallow_color`, `fresnel_power`, `specular_strength`) get saved on the material in the scene; the wave/time/roughness uniforms are ignored (overwritten by `Ocean` at runtime).

2. **Bump `PlaneMesh` subdivisions** from 32×32 to **512×512** ([World.tscn:13–16](scenes/world/World.tscn:13)). On the 4096 m plane this gives 8 m vertex spacing — enough to render waves 1–3 cleanly. Wave 4 (6 m wavelength) is below Nyquist at this spacing and will alias; it has the smallest amplitude (0.07 m) so the visible artifact is mild. Step 9 either bumps wave 4's wavelength up to ≥ 16 m or accepts it. 263k vertices total — well within Forward+ comfort on any modern GPU.

3. **Normalize the `WaterMesh` y-offset.** Today `WaterMesh.transform.origin.y = -0.15` *and* `OceanFollower.global_position.y = -0.15`, stacking to give a visual surface at y = -0.30 — quietly mismatched with the swim trigger at y = -0.15 ([fall.gd:14](scripts/player/movement_states/fall.gd:14)). Set `WaterMesh.transform.origin.y = 0`. The follower alone is responsible for placing the surface at `WATER_BASE_Y`. `Ocean.WATER_BASE_Y = -0.15` then matches the visible surface, and Step 3's swim-threshold update lines up cleanly.

Constant cleanup follow-on: [ocean_follower.gd:4](scripts/world/ocean_follower.gd:4)'s `const WATER_Y := -0.15` becomes a thin wrapper `Ocean.WATER_BASE_Y` (Step 3) — that's where consumers stop reading the local constant.

#### Files

- `shaders/water.gdshader` — new. Full vertex + fragment as above.
- `globals/ocean.gd` — extend Step 1's skeleton with `set_water_material` and the per-process push.
- `scripts/world/ocean_follower.gd` — add the `set_water_material` call inside `set_target`.
- `scenes/world/World.tscn` — material swap, subdivision bump, y-offset normalization.

#### Verification

1. **F5 the project.** Ocean should visibly undulate around the player. No lock-step regular pattern (4 mixed-direction waves break that up).
2. **Pause the game** (`get_tree().paused = true`). Waves freeze. Unpause: motion resumes from the same phase. This is the `_process(delta)` time accumulation respecting pause — the proof that we did *not* use `Time.get_ticks_msec()` or `TIME` in the shader.
3. **Crank `Ocean.global_roughness` to 2.0** in a debug toggle. Waves should double in amplitude (and horizontal sway) without any other visible change. Set it to `0.0` — surface goes glassy flat at `WATER_BASE_Y`. This validates the roughness factor works the same way in shader and (eventually) physics.
4. **Eyeball test against Step 1's print probe.** From the temporary `_ready` print, we know `Ocean.get_height(0, 0, 0) = -0.15`. Stand the player at world origin, check that the visual surface at the camera's reticle reads `≈ -0.15`. If they disagree by more than ~0.2 m, something's mis-wired (most likely uniform names or the model-matrix transform in the shader).

Boats and swimming still don't yet consume the wave function — that's Step 3. After Step 2, the only consumer is the eye.

### Step 3 — Migrate `WATER_Y` consumers to `Ocean.get_height`

Goal: every consumer that today reads the flat `OceanFollower.WATER_Y` constant now samples `Ocean.get_height(x, z, t)` instead. After this step, the player's swim bob, the fall→swim trigger, the test-island helper, and the boat all *physically* respond to the same wave function the shader is rendering. No new architecture — pure migration.

The boat stays on its existing soft-pin lerp this step (still a `CharacterBody3D`); only its target height changes. RigidBody conversion is Step 5. Rationale below.

#### swim.gd

[scripts/player/movement_states/swim.gd:32](scripts/player/movement_states/swim.gd:32) currently fakes a bob with a local `sin(_t)`. After migration, the spring tracks the real surface — no separate bob.

```gdscript
# Drop these constants and the _t member entirely:
#   const BOB_FREQ      := 1.6
#   const BOB_AMPLITUDE := 0.12
#   var _t: float = 0.0
#
# enter() no longer resets _t (delete or leave empty).

func physics_update(delta: float) -> void:
    if player.is_on_floor():
        ...  # unchanged
        return

    var p := player.global_position
    var target_y := Ocean.get_height(p.x, p.z, Ocean.time) + SURFACE_OFFSET

    if Controls.jump_just_pressed() and player.consume_stamina(15.0):
        ...  # unchanged
        return

    var dy := target_y - p.y
    player.velocity.y += (SPRING_K * dy - DAMPING * player.velocity.y) * delta
    ...  # unchanged below
```

`SURFACE_OFFSET = -1.0` keeps its meaning: the player's body root sits 1 m below the visible water surface so head/eyes read at water level. With waves, "1 m below the surface" is now a moving target — the whole body bobs with the wave. Correct.

`SPRING_K` and `DAMPING` were tuned against a 0.12 m sinusoid at 1.6 rad/s. They're now driving against a sum of waves with mixed periods (2–4 s) and up-to-0.65 m amplitude. Expect the spring to feel a little sluggish or buzzy — Step 7 retunes. For Step 3 we leave the constants alone and observe.

#### fall.gd

[scripts/player/movement_states/fall.gd:14](scripts/player/movement_states/fall.gd:14) — swim-entry threshold becomes the actual surface at player XZ.

```gdscript
func physics_update(_delta: float) -> void:
    var p := player.global_position
    if p.y <= Ocean.get_height(p.x, p.z, Ocean.time):
        movementSM.transition_to("swim")
        return
    ...  # unchanged
```

Behavior change: a player falling toward a wave *crest* enters swim slightly earlier (above today's flat threshold); falling toward a *trough* slightly later. This is correct — the threshold is the actual surface, not an idealised plane. No edge cases; the player can't get stuck because every frame re-samples `Ocean.get_height` at the player's current XZ.

#### ocean_follower.gd

[scripts/world/ocean_follower.gd](scripts/world/ocean_follower.gd) loses its local constant. The follower's job is purely horizontal tracking; vertical stays pinned at `Ocean.WATER_BASE_Y` (the *rest plane* — Gerstner displacement is added per-vertex on the GPU).

```gdscript
class_name OceanFollower
extends Node3D

var _target: Node3D = null

func set_target(node: Node3D) -> void:
    _target = node
    var mesh := $WaterMesh as MeshInstance3D
    Ocean.set_water_material(mesh.material_override as ShaderMaterial)  # added in Step 2

func _process(_dt: float) -> void:
    if _target == null:
        return
    var t := _target.global_position
    global_position = Vector3(t.x, Ocean.WATER_BASE_Y, t.z)
```

The `const WATER_Y := -0.15` is deleted. After this step nothing in the codebase reads `OceanFollower.WATER_Y` — confirm with grep before deleting.

No shader-displacement compensation needed here. The mesh root is the rest plane; the GPU paints the surface above/below it; physics queries `Ocean.get_height` for the same value. Three layers, one source of truth.

#### test_island.gd

[scripts/dev/test_island.gd:10](scripts/dev/test_island.gd:10) drops the local `const WATER_Y`, replaces with `Ocean.WATER_BASE_Y`. The line `boat.water_y = WATER_Y` is deleted entirely (the export goes away — see boat.gd below).

```gdscript
# Before:
#   const WATER_Y := -0.15
#   ...
#   water.position.y = WATER_Y
#   ...
#   boat.water_y = WATER_Y
#   boat.position = Vector3(62.0, WATER_Y, 0.0)
#
# After: drop the const; replace usages with Ocean.WATER_BASE_Y; drop the boat.water_y line.

water.position.y = Ocean.WATER_BASE_Y
...
boat.position = Vector3(62.0, Ocean.WATER_BASE_Y, 0.0)
```

The placeholder water mesh in test_island still uses a flat StandardMaterial3D — this dev sandbox does *not* get the new shader. It's only kept for regression-poking; the production scene is `World.tscn` (Phase 5 deliverable #12). Updating it would require duplicating the Step 2 wiring; not worth it.

#### boat.gd (interim)

[scripts/ships/boat.gd](scripts/ships/boat.gd) — the export `water_y` is deleted now (no caller assigns it after the test_island edit). The soft-pin lerp keeps its shape but reads `Ocean.get_height` for the target.

```gdscript
# Drop:  @export var water_y: float = 0.0

func _physics_process(delta: float) -> void:
    ...  # mounted-input handling unchanged
    move_and_slide()
    var target_y := Ocean.get_height(global_position.x, global_position.z, Ocean.time)
    position.y = lerp(position.y, target_y, 0.4)
    if _player != null:
        _player.global_position = _deck_spawn.global_position
        _player.rotation.y = rotation.y + _mount_rotation_offset
```

After Step 3 the boat *visually* bobs along with the waves at the correct vertical position (no rotation yet — flat-bottom on a curved surface). The mounted player snaps to the deck per frame as before. Step 5 deletes this entire `_physics_process` and replaces it with RigidBody force application.

**Why not jump straight to RigidBody here?** Three reasons to keep the interim:

1. *De-risks Step 5.* After Step 3 you can see waves working while every other system (mount/dismount, camera rig, save/load, deck-spawn snap) still runs on the known-good `CharacterBody3D` path. If Step 5 hits trouble, Step 3 is a clean fallback to ship.
2. *The interim cost is tiny.* One existing line modified (`position.y = lerp(...)` reads from `Ocean.get_height` instead of `water_y`); `move_and_slide` and the rest of the body stay. We're not building real interim code, we're just updating the data source.
3. *Two visible milestones beats one big bang.* "Boat bobs on waves but is otherwise the same" is a satisfying playable state to commit and stress-test before tackling pitch/roll dynamics.

#### Files changed

- `scripts/player/movement_states/swim.gd` — drop local `sin(t)` bob and bob constants; spring targets `Ocean.get_height(...) + SURFACE_OFFSET`.
- `scripts/player/movement_states/fall.gd` — threshold reads `Ocean.get_height(...)` at player XZ.
- `scripts/world/ocean_follower.gd` — delete `const WATER_Y`; `_process` uses `Ocean.WATER_BASE_Y`.
- `scripts/dev/test_island.gd` — delete `const WATER_Y`; replace usages; delete `boat.water_y` assignment.
- `scripts/ships/boat.gd` — delete `@export water_y`; soft-pin lerp targets `Ocean.get_height(...)`.

No new files. No scene edits (Step 2 already covered `World.tscn`).

#### Verification

After this step the codebase has zero references to `OceanFollower.WATER_Y` or `boat.water_y`. Grep:

```
OceanFollower.WATER_Y      → 0 hits
boat.water_y               → 0 hits
const WATER_Y              → 0 hits in scripts/ (only in OCEAN_AND_BUOYANCY_PLAN.md)
```

Playtest:

1. **Walk to shore, jump in.** Player should fall through the wave surface (entering swim at the actual wave height, not the flat -0.15) and bob with real waves once swimming. Jump out — splash exit still works.
2. **Stand on shore at the waterline.** As waves crest into the shore, the player should *not* enter swim from a wave climbing over them while they're standing on land — `is_on_floor()` is checked before the threshold. Confirms swim-entry is a fall thing, not a "water touched me" thing.
3. **Mount the boat.** Boat visibly rises and falls with passing waves. Mounted player rides the deck. Throttle/rudder still steer normally. No new bugs in mount/dismount.
4. **Stress-test pause.** Pause mid-bob — both player swim spring and boat lerp freeze. Unpause: motion continues from same phase. (Already proven in Step 2; reconfirm now that physics consumers are wired.)
5. **Visual-physics agreement.** Stand the player at world origin, watch the camera at the waterline. The visual shader surface and the physics-felt surface should agree to within ~0.2 m worst case (the documented Gerstner-horizontal-displacement approximation). If you see the player's body penetrating a clearly-visible wave crest by more than that, the uniform pipeline is mis-wired.

#### Risks

- **`Ocean.time` cadence.** `Ocean._process` runs at render rate; physics consumers in `_physics_process` may run several steps between renders, all reading the same `time`. Worst-case staleness is one render frame (~16 ms at 60 fps); the surface doesn't visibly snap because both physics steps within a render-frame interval evaluate against the same wave snapshot. Within a physics frame, every consumer sees the same `time` — internally consistent.
- **Spring tuning will feel off.** Acknowledged. Don't retune in Step 3; collect notes for Step 7.
- **Boat penetrating waves in extreme conditions.** With `global_roughness = 1.0` and four waves stacking, the soft-pin lerp lags the wave by ~0.4 frames worth of difference each step. Worst case the boat visibly clips through a fast crest momentarily. Acceptable interim — Step 5's RigidBody buoyancy responds force-correctly, no lerp lag.

### Step 4 — `Buoyancy` helper component

Goal: a self-contained `Node3D` that any `RigidBody3D` can adopt as a child to float on the wave function. Single consumer this phase (the boat in Step 5); designed so future debris/barrels drop in by adding the script as a child and exporting hull points.

#### Force model

Per submerged hull point, apply an upward force scaled by submersion depth:

```
depth = Ocean.get_height(world_point.x, world_point.z, Ocean.time) - world_point.y
submersion = clamp(depth / submersion_scale, 0.0, 1.0)
force_y = per_point_max_force * submersion
```

This is the simplified-clamped-spring formulation — equivalent to Archimedes assuming uniform density and a smoothstep volume curve. Not picking the full `ρ·g·V_submerged` integral because:

1. The exact volume per point is fictitious (we picked N points; "volume per point" is just total/N).
2. The clamp does the same thing physically (linear lift below saturation depth, constant lift when submerged past it).
3. It exposes one tunable per parent (`per_point_max_force`) instead of three (density, displaced volume, point count), which is easier to feel-tune.

Apply the force at `world_point - body.global_position` (not at the body centre) so off-centre points produce the torque that makes the boat pitch and roll naturally as the wave passes under it. This is the entire mechanism for "boat feels alive on waves" — no separate roll/pitch logic needed.

#### Drag

Two layers:

- **Body-level damping** via `RigidBody3D.linear_damp` and `angular_damp` set on the parent. Cheap, framework-native, handles "boat coasts to a stop." Tuned in Step 5.
- **Optional per-point horizontal drag** in the helper, only on submerged points:
  ```
  point_vel = body.linear_velocity + body.angular_velocity.cross(offset)
  drag = -Vector3(point_vel.x, 0, point_vel.z) * per_point_linear_drag * submersion
  ```
  Off by default (`per_point_linear_drag = 0`). Useful if waves should *push* the boat sideways (currently they don't — vertical buoyancy only). Step 9 turns it on if the boat feels too detached from the water.

#### API

```gdscript
class_name Buoyancy
extends Node3D

@export var hull_points: Array[Vector3] = []        # local-space, per-parent
@export var per_point_max_force: float = 1000.0     # tuned per parent
@export var submersion_scale: float = 0.5           # depth at which force saturates
@export var per_point_linear_drag: float = 0.0      # off by default

var _body: RigidBody3D = null

func _ready() -> void:
    _body = get_parent() as RigidBody3D
    assert(_body != null, "Buoyancy must be a child of a RigidBody3D")

func _physics_process(_delta: float) -> void:
    if _body == null:
        return
    var t := _body.global_transform
    for local_point in hull_points:
        var world_point := t * local_point
        var surface_y := Ocean.get_height(world_point.x, world_point.z, Ocean.time)
        var depth := surface_y - world_point.y
        if depth <= 0.0:
            continue
        var submersion := clampf(depth / submersion_scale, 0.0, 1.0)
        var offset := world_point - _body.global_position
        _body.apply_force(Vector3(0.0, per_point_max_force * submersion, 0.0), offset)
        if per_point_linear_drag > 0.0:
            var pv := _body.linear_velocity + _body.angular_velocity.cross(offset)
            var horiz := Vector3(pv.x, 0.0, pv.z)
            _body.apply_force(-horiz * per_point_linear_drag * submersion, offset)
```

Configuration approach: exported `Array[Vector3]` set programmatically by the parent (the boat does this in `_ready` based on its hull dimensions). We *don't* use child Marker3D nodes because the boat is built procedurally in code today — adding scene-editable markers is a refactor not justified by one consumer.

#### Files

- `scripts/ships/buoyancy.gd` — new, the script above. ~30 lines.

#### Verification

Cannot fully verify without Step 5 (no rigidbody to attach to). Smoke test: temporarily attach `Buoyancy` to a `RigidBody3D` cube in a scratch dev scene with `hull_points = [Vector3(0,0,0)]` and `per_point_max_force = mass*9.81*2`. Drop the cube; it should sink halfway, oscillate, settle at half-submersion. If it floats away or sinks completely, the force/depth scaling is wrong.

Real verification happens at the end of Step 5.

---

### Step 5 — Migrate boat to `RigidBody3D`

The high-risk step. [scripts/ships/boat.gd](scripts/ships/boat.gd) changes class, control inputs become forces/torques, the soft-pin lerp dies, and Buoyancy lifts. Mounting/camera ride along but their wiring shifts.

#### Class change and physics setup

```gdscript
class_name Boat
extends RigidBody3D  # was CharacterBody3D
```

Body properties (set in `_ready`, since boat is built procedurally):

- `mass = 500.0`                   # ~half-tonne wooden hull, starter value
- `linear_damp = 1.5`              # coasts but slows; water is thick
- `angular_damp = 5.0`             # turns decay quickly so rudder feels responsive
- `gravity_scale = 1.0`            # default; buoyancy fights gravity directly
- `can_sleep = false`              # waves keep it alive permanently
- `lock_rotation` flags untouched (free 3-axis rotation)

Hull collider stays the same shape and offset as today ([boat.gd:39–55](scripts/ships/boat.gd:39)). RigidBody auto-uses child CollisionShape3D the same way CharacterBody3D did.

#### Buoyancy point layout

Four points at the bottom corners of the hull, in local space:

```
HULL_COLLIDER_SIZE = Vector3(2.0, 1.4, 5.0)  # existing constant
hp_y = -0.7   # bottom of collider (existing offset puts collider centre below origin)

hull_points = [
    Vector3(-1.0, hp_y, -2.5),  # stern port
    Vector3( 1.0, hp_y, -2.5),  # stern starboard
    Vector3(-1.0, hp_y,  2.5),  # bow port
    Vector3( 1.0, hp_y,  2.5),  # bow starboard
]
```

(The boat's local +Z is forward — `velocity = -global_transform.basis.z * ...` in today's code, so "bow" is actually local -Z. Sign conventions get verified in playtest; the four points being symmetric about both axes makes the math forgiving.)

`per_point_max_force = (mass * 9.81 / 4) * 2.0 = 2452.5 N` — over-lift factor 2.0 means when fully submerged the boat experiences 2× weight upward, settling at ~50% submersion.

`submersion_scale = HULL_COLLIDER_SIZE.y * 0.5 = 0.7` — full lift kicks in at half-collider depth, matching the resting waterline.

These values ride together — bumping `mass` requires recomputing `per_point_max_force` to stay at the same waterline. The boat's `_ready` derives all four from `mass`:

```gdscript
func _setup_buoyancy() -> void:
    _buoyancy = Buoyancy.new()
    _buoyancy.hull_points = [
        Vector3(-1.0, -0.7, -2.5), Vector3( 1.0, -0.7, -2.5),
        Vector3(-1.0, -0.7,  2.5), Vector3( 1.0, -0.7,  2.5),
    ]
    _buoyancy.per_point_max_force = (mass * 9.81 / 4.0) * 2.0
    _buoyancy.submersion_scale = HULL_COLLIDER_SIZE.y * 0.5
    add_child(_buoyancy)
```

#### Steering as forces

The existing `_physics_process` block ([boat.gd:133–157](scripts/ships/boat.gd:133)) is rewritten. Throttle becomes a forward force at the centre of mass; rudder becomes a yaw torque scaled by forward speed.

```gdscript
const MAX_THRUST := 6000.0       # N — tuned so MAX_THRUST / (mass*linear_damp) ≈ desired top speed
const MAX_RUDDER_TORQUE := 8000.0  # N·m — tuned for "feels responsive"
const RUDDER_MIN_SPEED := 0.5    # m/s — below this, rudder authority is zero
const RUDDER_FULL_SPEED := 6.0   # m/s — above this, full authority

func _physics_process(delta: float) -> void:
    if not mounted:
        throttle = move_toward(throttle, 0.0, accel * delta)
        return
    
    var t_in := Controls.throttle_axis()
    var r_in := Controls.rudder_axis()
    throttle = move_toward(throttle, t_in, accel * delta)

    # Forward thrust at centre of mass. -basis.z is forward (existing convention).
    var fwd := -global_transform.basis.z
    apply_central_force(fwd * throttle * MAX_THRUST)

    # Rudder torque around world-up, scaled by forward speed so stationary boat doesn't spin.
    var fwd_speed := absf(linear_velocity.dot(fwd))
    var rudder_authority := clampf(
        (fwd_speed - RUDDER_MIN_SPEED) / (RUDDER_FULL_SPEED - RUDDER_MIN_SPEED),
        0.0, 1.0
    )
    apply_torque(Vector3.UP * (-r_in * MAX_RUDDER_TORQUE * rudder_authority))
```

Notes on the steering model:

- **Forward thrust at centre of mass** — *not* at the stern. Stern thrust is more realistic but produces unwanted pitch (force-down at stern → bow lifts). Arcade feel calls for centre-of-mass thrust = pure forward acceleration, no spurious pitch.
- **Rudder authority scales with speed** — stationary boat ignores rudder, full-speed boat turns sharply. Matches the feel you want for sailing: anchored = stuck, moving = manoeuvrable.
- **`max_speed` is no longer pinned** — top speed emerges from `MAX_THRUST / (mass * linear_damp)` ≈ `6000 / (500 * 1.5) = 8 m/s`. The existing `max_speed = 12.0` constant is deleted (or kept as an unused export for tuning reference).
- **No `move_and_slide`** — RigidBody integrates everything internally. Collision response is automatic.

#### Soft-pin lerp deletion

The `position.y = lerp(position.y, Ocean.get_height(...), 0.4)` line from Step 3 is **deleted**. Buoyancy now does the vertical work. If the boat has been lerp-pinned for testing and then transitions to RigidBody, the first frame after deletion may show a small settle motion as buoyancy finds equilibrium — expected.

#### Camera rig: kill pitch/roll, keep yaw

Per Decision #3 (no camera roll), the camera pivot must not inherit the boat's pitch and roll. Today `_camera_pivot` is a child of the boat ([boat.gd:78](scripts/ships/boat.gd:78)) and inherits its full transform. The fix: keep the parent relationship for position-tracking convenience, but override the pivot's global rotation each frame to use only the boat's yaw plus the player's mouse input.

```gdscript
var _yaw_input: float = 0.0  # player mouse contribution, accumulated separately

func _on_mouse_look(delta: Vector2) -> void:
    if not mounted: return
    _yaw_input -= delta.x * MOUSE_SENSITIVITY
    _spring_arm.rotate_x(-delta.y * MOUSE_SENSITIVITY)
    _spring_arm.rotation.x = clamp(_spring_arm.rotation.x, deg_to_rad(-50.0), deg_to_rad(20.0))

func _process(_delta: float) -> void:
    if not mounted: return
    _camera_pivot.global_position = global_position + Vector3(0, 1.6, 0)
    _camera_pivot.global_rotation = Vector3(0, global_rotation.y + _yaw_input, 0)
```

Spring arm is still a child of pivot, so its X-rotation (mouse pitch) is now world-X (since pivot is held world-up). Camera child of spring arm is unchanged. Result: camera yaws with boat heading, follows mouse, never rolls or pitches with the hull.

The previous `_camera_pivot.rotate_y(...)` on mouse look is replaced by accumulating `_yaw_input` so it can be added to boat yaw cleanly.

#### Files

- `scripts/ships/boat.gd` — class change, `_setup_buoyancy`, rewritten `_physics_process`, rewritten camera rig, deleted soft-pin lerp.
- `scripts/ships/buoyancy.gd` — already created in Step 4, no changes here.
- No scene edits.

#### Verification

After Step 5 the boat should pitch/roll on waves (small bobbing motion), respond to throttle/rudder feeling roughly like before but with momentum, and the camera should stay world-level while tracking heading.

Smoke tests:

1. **Idle on calm water** (`Ocean.global_roughness = 0.0`). Boat sits flat at rest, doesn't drift. Mount/dismount works.
2. **Idle on waves** (`global_roughness = 1.0`). Boat bobs gently, pitches/rolls with passing waves. No runaway oscillation.
3. **Throttle full forward.** Boat accelerates, reaches steady speed (~8 m/s), no rudder input → straight line.
4. **Hard rudder at speed.** Boat turns smoothly, throttle response feels normal.
5. **Hard rudder at rest.** Boat doesn't yaw (rudder authority is gated).
6. **Camera test.** Look around while on rough water → image yaws with boat heading and pitches with mouse, but never rolls. No motion sickness.

Step 6 will fix the *mounted player* sliding around on the now-tilting deck — that's a known regression after Step 5 lands.

#### Risks

- **Tuning is going to take a pass.** Mass, damps, thrust, torque, buoyancy force all interact. Don't expect first-pass numbers to feel right.
- **Boat at shore.** RigidBody hitting shore-wall collider can produce surprising bounces. Today's CharacterBody3D used `move_and_slide` which is collide-and-slide; RigidBody is fully physical. May need to clamp angular velocity on collision or tune restitution.
- **Multiple boats.** Each gets its own Buoyancy. No cross-boat interaction concerns.

---

### Step 6 — Mounted-player coupling on a rotating boat

Once the boat tilts, today's `player.global_position = _deck_spawn.global_position` snap (positional only, [boat.gd:156](scripts/ships/boat.gd:156)) leaves the player upright on a tilted deck — feet float above, body penetrates. This step makes the player ride the boat's full transform.

#### Approach: full-transform copy, skip player physics while mounted

The player remains a top-level `CharacterBody3D` (no reparenting). Each physics frame, the boat overwrites the player's `global_transform` with the deck spawn's `global_transform`. The player's own `_physics_process` early-returns while mounted, so there's no `move_and_slide` fighting the snap.

Reparenting (player → child of boat) was rejected because:

- The player runs scripts, signals, and receives input as a top-level node — children of physics bodies have subtle gotchas with `_physics_process` ordering and `move_and_slide` against parent transforms.
- Reparent / unparent is a state change to undo on dismount, with corner cases (boat freed mid-mount, etc.).
- Transform copy gives the same visual result with strictly less coupling.

#### Player-side change

[scripts/player/player.gd:146–153](scripts/player/player.gd:146):

```gdscript
func _physics_process(delta: float) -> void:
    _regen_stamina(delta)
    if on_boat:
        return  # Boat owns transform; skip movement, action, and move_and_slide.
    movementSM.physics_update(delta)
    actionSM.physics_update(delta)
    move_and_slide()
```

This is a small simplification of the existing logic: today `move_and_slide()` runs unconditionally with `velocity = ZERO` while mounted, which is wasted work. Skipping it entirely also prevents the player's `move_and_slide` from clobbering the boat's transform copy in tricky tree-order scenarios.

`actionSM` was already a no-op while on_boat (every state checks `not player.on_boat` before transitioning) — skipping it saves one no-op call per frame.

#### Boat-side change

[scripts/ships/boat.gd:155–157](scripts/ships/boat.gd:155) — replace the position-only snap with a full transform copy:

```gdscript
func _physics_process(delta: float) -> void:
    ...  # steering forces, throttle ramp
    if mounted and _player != null:
        _player.global_transform = _deck_spawn.global_transform
        _player.velocity = Vector3.ZERO
```

Player's body now tilts/rolls with the deck. Camera (boat-owned) stays world-level per Step 5, so the *view* doesn't roll — only the player's character mesh does, and only as much as the boat does.

#### Mount and dismount

Mount ([boat.gd:107–118](scripts/ships/boat.gd:107)) — capture old yaw, snap player to deck transform on first frame:

```gdscript
func _mount(player: Node) -> void:
    _player = player
    mounted = true
    _yaw_input = 0.0  # reset camera yaw input accumulator (Step 5)
    var old_yaw: float = player.rotation.y
    player.global_transform = _deck_spawn.global_transform
    player.on_boat = true
    _camera_pivot.global_rotation = Vector3(0, global_rotation.y + (old_yaw - global_rotation.y), 0)
    _spring_arm.rotation.x = player.camera_pivot.rotation.x
    _camera.current = true
    Controls.capture_mouse()
```

Dismount ([boat.gd:120–131](scripts/ships/boat.gd:120)) — restore world-up player rotation, transfer camera yaw back to the player's facing:

```gdscript
func _dismount() -> void:
    if _player != null:
        var dismount_pos := _deck_spawn.global_position
        _player.global_position = dismount_pos
        _player.global_rotation = Vector3(0, global_rotation.y + _yaw_input, 0)
        _player.camera_pivot.rotation.x = _spring_arm.rotation.x
        _player.velocity = Vector3.ZERO
        _player.on_boat = false
    _camera.current = false
    mounted = false
    throttle = 0.0
    _player = null
```

Player leaves upright, facing wherever the camera was pointing. A subtle UX win — today's dismount restores the player at the boat's yaw-only rotation regardless of where the camera was looking.

#### Files

- `scripts/player/player.gd` — `_physics_process` early-returns when `on_boat`.
- `scripts/ships/boat.gd` — full transform copy in `_physics_process`; mount/dismount tweaks.

#### Verification

1. **Mount on calm water.** Player snaps to deck cleanly. View doesn't jolt.
2. **Mount on rough water.** Player rides the deck through pitch and roll. No clipping into the deck or floating above it.
3. **Sail at speed.** Mounted player stays glued through course changes.
4. **Dismount mid-roll.** Player exits upright, facing camera direction. Doesn't inherit boat tilt.
5. **Mount-dismount loop.** No accumulated drift in player position or rotation.

#### Risks

- **Tree-order edge case.** If `Boat._physics_process` happens to run before `Player._physics_process` on a given frame (unusual, but possible if scene structure changes), player's early-return prevents conflict. Verified by the early-return guard.
- **Animation playback.** Player anims continue running while mounted (if any). They should play in the boat's rotated frame because the player's transform is set at the rotated deck. No expected issue but worth a glance during playtest.

---

### Step 7 — Player swim, refined

After Step 3 the swim spring tracks `Ocean.get_height` instead of `sin(t)`. The constants `SPRING_K = 14.0`, `DAMPING = 5.0` were tuned against a 0.12 m / 1.6 rad·s sinusoid — they may feel sluggish or buzzy on real waves with mixed periods 2–4 s and amplitudes up to ~0.65 m.

Goal: retune by feel. No architectural change.

#### What to retune

- **`SPRING_K`** — restoring force toward surface. Higher = player follows surface tightly (snappy), lower = player floats through waves (loose). Today's 14.0 is on the looser side for our wave amplitudes.
- **`DAMPING`** — opposes velocity. For critical damping at K=14, target ≈ 7.5; today's 5.0 is mildly under-damped (slight overshoot). With real waves, under-damped means the player slowly oscillates around the surface instead of riding it.
- **`SURFACE_OFFSET = -1.0`** — how far below the visible surface the player root sits. Probably fine; revisit only if the player visually pokes their head above wave crests when they shouldn't.

Suggested starting points for retune: `SPRING_K = 20.0`, `DAMPING = 9.0` (slightly above critical for K=20). Adjust by feel until "swim on a wave" looks like a person being lifted by water, not a marionette.

#### What to keep

The kinematic-spring approach itself stays (Decision #3). The character body does not roll with waves. `BOB_FREQ`/`BOB_AMPLITUDE` deleted in Step 3 stay deleted — no stylized over-bob on top of real waves.

#### Files

- `scripts/player/movement_states/swim.gd` — adjust `SPRING_K` and `DAMPING` constants.

#### Verification

1. **Idle in calm water.** Player floats steady at `Ocean.WATER_BASE_Y + SURFACE_OFFSET`, no drift.
2. **Idle in choppy water.** Player rises and falls with waves, head stays roughly at surface — not bobbing 2 m above or sinking 1 m below.
3. **Swim with input.** Lateral motion still feels like today's swim. Vertical tracking doesn't fight horizontal control.
4. **Jump out of water.** Splash exit triggers cleanly at the wave-aware threshold. No "stuck on surface" oscillation when launching.

---

### Step 8 — Save/load updates

Persist the boat's full motion state, not just position + yaw. With RigidBody, restoring at velocity zero in the middle of a voyage means the boat arrives dead in the water — fine but mildly jarring. Saving velocities is cheap.

#### Schema change

[globals/boat_manager.gd:23–27](globals/boat_manager.gd:23) — extend the saved per-boat dict:

```gdscript
out.append({
    "position": V3Codec.encode(boat.position),
    "rotation_y": boat.rotation.y,
    "linear_velocity": V3Codec.encode(boat.linear_velocity),    # new
    "angular_velocity": V3Codec.encode(boat.angular_velocity),  # new
})
```

[globals/boat_manager.gd:39–45](globals/boat_manager.gd:39) — restore in `_on_world_loaded`:

```gdscript
for bd in _pending:
    var boat := Boat.new()
    boat.rotation.y = float(bd.get("rotation_y", 0.0))
    scene.add_child(boat)
    boat.global_position = V3Codec.decode(bd["position"])
    if bd.has("linear_velocity"):
        boat.linear_velocity = V3Codec.decode(bd["linear_velocity"])
    if bd.has("angular_velocity"):
        boat.angular_velocity = V3Codec.decode(bd["angular_velocity"])
    register_boat(boat)
```

Backwards-compat via `bd.has(...)` — old saves (Schema v2) without these fields default to zero velocity. No explicit migration function needed.

We **don't** save full rotation (pitch/roll). Equilibrium is reached within a second of buoyancy resolving the boat's pose; saving only yaw means the boat respawns level and settles into wave bobbing immediately. Saving full quat would capture the moment exactly but is largely cosmetic given how fast equilibrium is reached.

#### Schema version bump

Per [ARCHITECTURE.md:269](docs/planning/ARCHITECTURE.md:269), current `SCHEMA_VERSION = 2`. Bump to **3** in [globals/save_system.gd](globals/save_system.gd) and add a no-op migration entry — `BoatManager.load_data` already handles missing fields via `bd.has()`, so no in-place rewrite is needed; the version bump is bookkeeping.

#### Files

- `globals/boat_manager.gd` — save/load extended.
- `globals/save_system.gd` — `SCHEMA_VERSION = 3`, add migration stub `_migrate_v2_to_v3` (no-op).

#### Verification

1. **Save mid-voyage at speed.** Quit, relaunch. Boat respawns at its previous position, moving in the previous direction.
2. **Save while idle.** Quit, relaunch. Boat respawns level and at rest.
3. **Load an existing v2 save.** No crash, no missing-field warnings; boat respawns at last position, dead in water.
4. **`SCHEMA_VERSION` round-trip.** Save under v3, load — version reads as 3.

#### Risks

- **Velocity snapshot accuracy.** Save happens during a frame; the velocity captured may be from mid-bob. Restoring it produces a slight visual nudge as buoyancy reasserts. Negligible.
- **Save during a collision.** Velocity captured during a shore-wall bounce could relaunch the boat away from shore on load. Edge case; not worth handling unless playtest shows it.

---

### Step 9 — Tuning + verification

Final integration pass. No new code; iteration on constants until the system feels right. Time budget for this step is open-ended — expect at least one full playtest session.

#### Tuning surfaces (in priority order)

1. **Boat handling.** `mass`, `linear_damp`, `angular_damp`, `MAX_THRUST`, `MAX_RUDDER_TORQUE`, `RUDDER_FULL_SPEED`. Tune until throttle feels responsive but the boat has weight, rudder turns smoothly without spinning out, top speed feels appropriate (~6–10 m/s).
2. **Buoyancy feel.** `per_point_max_force` (via over-lift factor), `submersion_scale`. Tune until the boat floats at a believable waterline, pitches/rolls visibly on waves without violent oscillation. If oscillation is too long, increase `linear_damp` or reduce over-lift.
3. **Wave parameter set.** The Step 1 starter parameters are starting values. After all systems are integrated, the visible roughness might feel too tame or too dramatic. Adjust amplitudes/wavelengths in `Ocean.WAVES`. If shortest wave (#4, 6 m wavelength) is unacceptably aliased on the 8 m-spaced mesh, bump its wavelength to ≥ 16 m or accept it.
4. **Swim spring.** `SPRING_K`, `DAMPING` (Step 7). Final pass with all wave dynamics in place.
5. **Camera offsets.** Spring length, vertical offset, FOV — only if the new pitch/roll dynamics expose any awkwardness.

#### Verification checklist (against the original goals)

Goal 1 — single source of truth for wave height. Confirmed by:
- Code grep: only `globals/ocean.gd` defines wave parameters; `shaders/water.gdshader` reads them via uniforms.
- Visual-physics agreement test from Step 3 verification.

Goal 2 — real buoyancy for boats. Confirmed by:
- Boat visibly pitches/rolls on waves without scripted animation.
- Boat at rest sits at a stable waterline (not slowly sinking or rising).

Goal 3 — player swim driven by wave function. Confirmed by:
- Player surface position correlates with visible waves at player XZ.
- No `sin(t)` reference remains in `swim.gd`.

Goal 4 — reusable buoyancy helper. Confirmed by:
- `Buoyancy` script attaches to any RigidBody3D with one config call.
- Smoke-test cube floats correctly.

Goal 5 — no regressions. Confirmed by:
- Mount/dismount loop, save/load, swim entry/exit thresholds, throttle/rudder feel, multi-boat scene — all behave as before or better.

#### Architecture doc update

After verification passes, apply the architecture edits sketched at the top of this plan to [docs/planning/ARCHITECTURE.md](docs/planning/ARCHITECTURE.md):

1. Add `Ocean` to the Global Services autoload table.
2. Rewrite §"Boats & Naval Combat" first paragraph with the RigidBody3D + Buoyancy design.
3. Add a §"Water" subsection (or fold into §"World System") documenting the Gerstner parameter set, the autoload-pushes-uniforms contract, and the future-extension path for spatially-varying roughness.
4. Update §"Save System" to mention boat velocities are persisted, schema bumped to v3.

#### What this step does *not* include

- Foam, SSR, depth fade, caustics, or any other water-shader visual polish.
- Wind, sails, or sailing physics.
- Naval combat, cannons, or enemy ships.
- Spatially-varying roughness (the texture-based approach).
- A noise-texture-based roughness map.

These are explicitly out of scope per the Goals section. Each is a clean follow-up phase that consumes (but does not modify) what this plan ships.

### Step 5 — Migrate boat to `RigidBody3D`

Convert [scripts/ships/boat.gd](scripts/ships/boat.gd) from `CharacterBody3D` to `RigidBody3D`. Throttle becomes forward force at the stern; rudder becomes yaw torque. `move_and_slide` and the soft-pin lerp are deleted; buoyancy + drag handle the vertical and rotational motion. Hull collider geometry stays. Add 4 buoyancy points (bow/stern × port/starboard).

This is the high-risk step — it touches mount/dismount, deck-spawn parenting, and the camera rig. Expect the boat to feel different and need tuning.

*Details TBD: force application points, mass, linear/angular damp values, how the camera spring-arm survives the boat's new rotation, whether rudder needs speed-dependent scaling.*

### Step 6 — Mounted-player coupling on a rotating boat

Today the player is teleported to `_deck_spawn.global_position` each physics frame ([boat.gd:156](scripts/ships/boat.gd:156)). With a pitching/rolling boat, that snap won't carry the player's local rotation, and the camera will jitter. Likely fix: re-parent player to the deck spawn while mounted (player as child of the boat), or apply boat's full transform to the player's transform each frame. Camera pivot reads boat orientation.

*Details TBD: parent-vs-transform-copy, what happens to player physics body while mounted, how dismount restores world-space transform cleanly.*

### Step 7 — Player swim, refined

Per Decision #3, kinematic spring stays — no architecture change. Step 3 already moved the spring's target from `WATER_Y + sin(t)` to `Ocean.get_height(player.x, player.z, t)`. Revisit now that real Gerstner waves exist: `SPRING_K` and `DAMPING` were tuned against a fixed-frequency sin; on a sum of waves with mixed periods they may feel sluggish or buzzy. Likely just a tuning pass.

The character body does not roll with the waves (Decision #3 — no camera roll). The spring tracks vertical surface position only.

*Details TBD: retuned SPRING_K/DAMPING values, whether `BOB_FREQ`/`BOB_AMPLITUDE` constants are deleted entirely or kept for stylized over-bob on top of the real wave.*

### Step 8 — Save/load updates

Boat rotation already round-trips (it's a `Transform3D` save). With RigidBody3D we additionally persist `linear_velocity` and `angular_velocity` so reloading mid-voyage doesn't drop the boat dead in the water. Schema bump if the boat save dictionary changes shape.

*Details TBD: whether velocities are worth persisting (vs zeroing on load), schema version handling.*

### Step 9 — Tuning + verification

Playtest pass against the goals: does the boat pitch convincingly on waves, does the player bob match the boat's waterline, does mount/dismount feel clean, does save/load not break anything? Likely surface 1–2 follow-up tuning tickets but no new architecture.

*Details TBD: concrete checklist, what counts as "good enough to ship."*

---

## Decisions

1. **Wave roughness — start medium-calm, design for variability.** Initial parameter set: 4 Gerstner waves, amplitudes ~0.15–0.4 m, mixed periods. *But* the wave function carries an explicit `roughness` factor from day one so storms, weather systems, or per-region calmness can ride on top later. See Step 1 for the design.
2. **Shader↔GDScript sync — autoload pushes uniforms.** Single source of truth lives in `Ocean`. Drift bugs are silent and expensive; the wiring cost is small.
3. **Player swim — keep kinematic spring.** Just feed it `Ocean.get_height(player.x, player.z, t)` instead of `sin(t)`. RigidBody character control fights Godot's kinematic-controller patterns; no upside given swim isn't featured gameplay. Camera roll explicitly not wanted.
4. **Boat caller coupling — clean.** Confirmed by inspection. [player.gd:193](scripts/player/player.gd:193) and [boat_manager.gd:40](globals/boat_manager.gd:40) just `Boat.new()` + register; no CharacterBody3D assumption. Mounting checks `player.is_on_floor()` ([boat.gd:94](scripts/ships/boat.gd:94)) which is a check on the *player*, not the boat. The behavioral coupling is on the player side ([player.gd:146–153](scripts/player/player.gd:146): mounted player skips movementSM but still calls `move_and_slide()` with zero velocity, relying on the boat's per-frame deck-snap to stay attached). Step 6's problem.
5. **`water_y` export — delete in Step 5.** Two writers ([boat.gd:12](scripts/ships/boat.gd:12) default + [test_island.gd:131](scripts/dev/test_island.gd:131) explicit). Five internal reads, all replaced by `Ocean.get_height(...)`. Test island line goes too.
