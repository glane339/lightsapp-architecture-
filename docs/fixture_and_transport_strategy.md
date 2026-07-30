# Fixture and Transport Strategy

**Status of this document:** TARGET ARCHITECTURE accepted by decisions D-16,
D-17, and D-20; PROPOSED implementation detail. Updated on branch
`docs/live-renderer-architecture`.

This document expands the fixture-definition, rendering, and transport layers
of the canonical
[live show-control architecture](show_control_architecture.md): how fixtures
are described as data, how semantic actions become channel values, and how
those values reach LedFx, WLED, and DMX devices.

**No fixture profile system, capability model, patch model, or injectable
transport exists in this repository today.** Part 1 records what does exist.

**This document contains no fixture channel numbers.** That is deliberate and
binding — see Part 5.

---

# Part 1 — What exists today

## VERIFIED CURRENT BEHAVIOR

### The device model

```python
class DMXDevice(BaseModel):        # backend/models/device.py:11-16
    id: str
    order: int
    channels: int
    active_channels: list[int]
    control_type: str              # "manual" | "scene based" (free string)
```

There is no manufacturer, no model, no mode, no universe, no start address, no
capability list, and no profile version. `control_type` is an unvalidated
string compared case-insensitively against `"manual"` at several call sites.

### How channels actually reach the wire

```text
devices.json
    │
    ▼
MAPPER.set_channel_values(devices)                backend/dmx/mapper.py:6-10
    sorted_devices = sorted(devices, key=lambda d: d.order)
    for device in sorted_devices:
        channels_in_order.extend(device.active_channels)
    │
    ▼
DMXFrame.set_values(values)                       backend/dmx/frame.py:7-11
    truncate to 512, or zero-pad to 512
    │
    ▼
sender[universe].dmx_data = tuple(...)            backend/dmx/sender.py:86
```

**A fixture's DMX start address is the cumulative length of every preceding
device's `active_channels` list.** CODE-INSPECTED ONLY. There is no patch table
and no address field. Three consequences follow, and all three are load-bearing
for the migration in Part 3:

1. **Address-collision validation is not currently possible**, because there are
   no addresses to compare — only positions in a concatenation. Collisions
   cannot occur, but neither can deliberate addressing, gaps, or a fixture at a
   fixed address.
2. **A wrong-length `active_channels` list silently shifts every downstream
   fixture.** `device.channels` is declared but never enforced against
   `len(active_channels)` (F11). Set one fixture's list one element short and
   every fixture after it in `order` is driven by the wrong channels — with no
   error, because `DMXFrame` simply pads to 512.
3. **Reordering devices re-patches the rig.** `order` is simultaneously the
   display order, the preset-association index (F15), and the address
   determinant. Three unrelated meanings on one integer field.

### Where fixture knowledge lives

| Location | What is hardcoded |
| --- | --- |
| `backend/routes/data.py:57-125` | Bootstrapping of `haze` (2 channels, manual), `gigbar` (24 channels, scene based), `keobin` (24 channels, scene based). Also rewrites `control_type` on the latter two if marked manual. Runs on *read* (F9). |
| `frontend/js/device_presets.js` | A `MODE_VALUES` table: named modes mapped to channel-number/value pairs, for `gigbar` sub-devices (`par_1`, `par_2`, `derby_1`, `derby_2`, `laser`, `strobe`) and `keobin` sub-devices (four lasers, a magic ball, a strobe block). Also two hardcoded channel-count loop bounds. |
| `frontend/js/active.js:16-21` | Classification: `haze` always gets sliders; `["gigbar","keobin"]` are treated as scene-based. |
| `frontend/js/presets.js` | Fixture-aware preset UI behavior. |

`MODE_VALUES` is the only fixture-profile-shaped data in the repository. It is
the natural migration source for a real profile system — and it is
**unverified against any manufacturer manual**, which is why Part 5 requires
re-derivation rather than a copy.

### Transports

| Transport | State |
| --- | --- |
| sACN / E1.31, one universe, unicast | Exists (`backend/dmx/sender.py`). The `sacn` library's `SenderSocketUDP.send_packet` is monkey-patched to swallow `OSError` and log at most once per 10 s. |
| Art-Net | Does not exist |
| OLA | Does not exist |
| Multi-universe | Does not exist — one `activate_output()` call |
| Mock / recording DMX | Does not exist |
| Injectable DMX transport | Does not exist — `SENDER` is a module-global constructed at import (F3) |
| WLED direct (JSON / WebSocket / UDP / DDP) | Does not exist |
| LedFx HTTP | Exists (`backend/ledfx/client.py`); scene activation by name only |
| ILDA `PointSink` / `NullSink` / `LoggingSink` | **Exists, and is the correct pattern** (`backend/ilda/sink.py`) |

The ILDA sink protocol is the one piece of this architecture already present in
the codebase. DMX and WLED transports should be built in its image.

---

# Part 2 — The fixture-definition layer

## TARGET ARCHITECTURE

### Model shape

PROPOSED. Two levels, kept separate on purpose:

```python
# ---- Definition: what a product IS. Shared, versioned, reusable. ----------
class FixtureMode(BaseModel):
    name: str                      # e.g. the manufacturer's mode label
    channel_count: int
    channels: list[ChannelDef]     # ordered; index = offset from start address

class ChannelDef(BaseModel):
    offset: int                    # 0-based, within the mode
    name: str
    capability: CapabilityRef      # what this channel DOES
    ranges: list[ValueRange]       # named value windows, from the manual
    default: int
    highlight: int | None          # safe "find me" value
    snap: bool                     # discrete selector vs continuous

class FixtureDefinition(BaseModel):
    manufacturer: str
    model: str
    modes: list[FixtureMode]
    profile_version: int
    source: str                    # WHICH manual, WHICH revision
    verified: bool                 # False until checked against hardware

# ---- Instance: what is actually IN this rig. -----------------------------
class FixtureInstance(BaseModel):
    id: str
    definition: FixtureRef
    mode: str
    universe: int
    start_address: int             # 1-based, DMX convention
    groups: list[str]
    latency_ms: int = 0            # per-device compensation
    enabled: bool = True
```

WLED devices use the same instance model with a different definition kind —
their "channels" are segments and pixel ranges rather than DMX offsets, but
their *capabilities* (dimmer, colour, effect selection) are the same vocabulary.
This is what lets one cue target a mixed group of WLED strips and DMX PARs.

### Validation, and what fail-closed means

Validation runs at load, at patch time, and again in preflight before any output
is enabled. It rejects:

- **Address collisions** — two instances whose `[start_address,
  start_address + channel_count)` ranges intersect within the same universe.
- **Universe overflow** — `start_address + channel_count - 1 > 512`.
- **Unknown definition or mode references.**
- **Mode/channel mismatches** — `len(mode.channels) != mode.channel_count`.
- **Out-of-range defaults or named values.**

**Fail closed** means, specifically:

| Situation | Required behavior | Forbidden behavior |
| --- | --- | --- |
| Unknown fixture model | Reject the patch; name the fixture | Fall back to a "generic" profile |
| Unknown mode for a known model | Reject the patch | Guess the closest mode |
| Missing channel definition | Reject the profile | Assume a linear dimmer |
| Capability unsupported by this mode | Drop the cue and record it in diagnostics | Approximate it with a different channel |
| Profile marked `verified: false` | Allowed in simulation; **blocked from physical output** | Output anyway with a warning |

The last row is the one that will be argued about. It is also the one that keeps
an unverified GigBAR profile from firing a strobe into a room.

### Where profiles come from

Two sources, in order:

1. **The manufacturer manual for the exact model and mode.** Authoritative.
   Non-negotiable for any fixture that will receive physical output.
2. **An existing library — Open Fixture Library or QLC+ definitions — as an
   import accelerator.** Useful for the common PARs and bars. Imported profiles
   arrive with `verified: false` and must be checked against the manual and the
   physical fixture before that flag changes.

The existing `MODE_VALUES` table is a third source, but it is *evidence of what
the current rig does*, not a specification. It should be used to cross-check a
manual-derived profile — a disagreement between the two is a genuinely useful
signal — and never as the profile itself.

---

# Part 3 — Migration from positional addressing

This is the highest-risk change in the entire programme, because it changes what
bytes go on the wire for a rig that (per D-1's reasoning) has been used.

**The invariant to preserve:** for the existing rig configuration, the 512-byte
universe frame produced after migration must be **byte-identical** to the one
produced before it, for every existing device preset.

Proposed sequence:

1. **Characterize first.** Before touching anything, write tests that record the
   exact 512-byte frame produced by every stored device preset under the current
   `MAPPER` concatenation. These are the regression oracle. This is M2 work and
   is why Phase 1 depends on it.
2. **Derive the implied patch.** Compute each device's current implicit start
   address from the cumulative concatenation. This is a pure function of the
   stored `devices.json`.
3. **Introduce explicit addresses, unused.** Add `universe` and `start_address`
   to the device/instance model, populated from step 2. The mapper still uses
   concatenation. Nothing changes on the wire.
4. **Switch the mapper to address-based rendering.** Now the frames must match
   the step 1 oracle exactly. Any mismatch is a bug in steps 2–3, caught before
   hardware.
5. **Only then** allow addresses to be edited, gaps to exist, and validation to
   reject collisions.
6. **Native-Windows rig validation** before the migration is called complete —
   [platform_support.md](platform_support.md) governs, and no WSL2 result
   substitutes.

Steps 3 and 4 must be separate commits. The whole point is that step 4's diff is
reviewable in isolation and its test failure, if any, is unambiguous.

**Migration and OQ-5.** OQ-5 already asks which real installations must survive
M4. The same answer governs here, and the risk is higher: M4 risks losing
device *records*, this risks silently re-patching a working rig.

---

# Part 4 — Rendering layer

## Capability-based rendering

A capability is a verb the show generator understands. PROPOSED starting
vocabulary — deliberately small, extended only when a real fixture needs it:

`dimmer` · `color_rgb` · `color_rgbw` · `color_temperature` · `strobe` ·
`pan` · `tilt` · `pattern_select` · `speed` · `laser_enable` ·
`laser_pattern` · `haze_output` · `fan_speed` · `effect_select` ·
`macro_select` · `pixel_frame`

A renderer maps `(capability, params, FixtureMode) → channel assignments`, and
is a **pure function**: no clock, no socket, no disk, no globals.

```python
class CapabilityRenderer(Protocol):
    capability: str
    def render(
        self,
        params: dict[str, float | str],
        mode: FixtureMode,
    ) -> dict[int, int]:            # {offset: value}, offsets within the mode
        ...
```

Two properties follow directly from purity, and both are the point:

- **Golden-frame tests are trivial.** For every profile and every mode, assert
  that each capability produces exactly the expected offsets and values. This is
  the "fixture conformance test" from
  [show_control_recommendations.md](show_control_recommendations.md), and it is
  rated Transformative for safety because it is the only mechanism that catches
  a bad profile before a fixture does.
- **Renderers are shared across fixtures.** One `dimmer` renderer serves every
  fixture whose mode declares a dimmer channel. The count of fixture-specific
  code paths drops to the genuinely unusual cases — which, for a GigBAR-class
  fixture, will still be several.

## Rendering to WLED

Two distinct render targets, and conflating them is the classic mistake:

- **State rendering** — `dimmer`, `color_*`, `effect_select` become a WLED JSON
  state object (power, brightness, presets, segments, colour, palette, effect).
  Low rate, request/response, idempotent.
- **Pixel rendering** — `pixel_frame` produces a raw pixel buffer for realtime
  UDP/DDP streaming. High rate, fire-and-forget, stateless.

They use different transports, different rates, and different failure semantics.
A cue that sets a palette goes through state; a cue that drives a chase at 40 fps
goes through pixels. Sending pixel-rate updates through the JSON API is the
failure mode this separation exists to prevent.

DDP is a likely realtime option, not a locked transport decision. The selected
protocol must be supported by the actual WLED firmware and validated at
representative pixel counts, frame rates, and network conditions. Initial WLED
rendering targets of approximately 30–60 frames per second are nonbinding
budgets and must be measured on the supported rig.

## Rendering complete DMX universes

The future DMX renderer is a fixed-rate, latest-state-wins loop. On each tick it:

1. reads the latest musical state and active semantic effects;
2. evaluates semantic effects at the current render time;
3. resolves fixture targets, layers, and priorities;
4. builds a complete frame for each universe from explicit fixture patches;
5. applies safety policy and documented safe values;
6. sends through an injected real, null, or recording `DmxTransport`.

It does not concatenate fixture arrays, read durable JSON in the high-frequency
path, or accumulate a queue of stale frames. A missed render deadline skips the
obsolete frame. An initial DMX output budget of approximately 30–44 frames per
second is nonbinding and must be measured on the real node and fixtures.

Renderer output is still subject to safety gates after creative priority
resolution. Laser enable, strobe limits, intensity ceilings, atmosphere rate
limits, emergency blackout, and loss-of-signal policy cannot be overridden by
a high-priority cue.

---

# Part 5 — Fixture-specific planning

## The rules that apply to every fixture below

These are binding and are repeated because every one of them is a way to damage
equipment or people:

1. **Every fixture must be associated with an exact manufacturer manual** —
   model *and* revision. "A GigBAR" is not a fixture identity; a specific
   GigBAR model in a specific DMX mode is.
2. **Every supported DMX mode requires its own profile.** Modes differ in
   channel count and channel meaning. A profile that "works in most modes" is a
   profile that is wrong in some of them.
3. **Channel behavior must be verified before output** — against the manual,
   then against the physical fixture on native Windows.
4. **Unknown fixtures and unknown modes fail closed.** No generic fallback, ever.
5. **No channel numbers appear in this documentation.** They belong in profile
   data derived from manuals, not in prose that cannot be validated.

## WLED LED strips and matrices

Not currently addressed directly at all — only through LedFx scene names. Two
capabilities are needed and they are separable: **state control** (power,
brightness, segments, palettes, effects) and **realtime pixel streaming**.

Planning notes: segment topology is part of the instance definition, not the
product definition — the same strip cut differently is a different instance.
Matrices additionally need a width/height and a mapping order, and a
`pixel_frame` renderer for a matrix is meaningfully different from one for a
linear strip. Device discovery, firmware version, and pixel count should be read
from the device rather than configured by hand where WLED exposes them.

**Approved migration direction:** Lights incrementally adds direct WLED control
while retaining LedFx as a compatibility adapter. Native state control covers
lower-rate changes; native pixel streaming covers new custom effects; LedFx
continues serving existing scenes until native behavior is reliable and parity
has been evaluated. Exact per-device ownership and the validated realtime
transport remain implementation decisions.

## Generic RGB / RGBW PARs

The simplest and best-supported case, and the right first target for the
profile system. Capabilities: `dimmer`, `color_rgb` or `color_rgbw`, `strobe`,
often `macro_select`.

Planning notes: RGB and RGBW are **different profiles**, not a parameter — a
white channel is not derivable. Many PARs offer several modes with different
channel counts, and the mode is a property of the physical fixture's menu
setting, so a profile mismatch here is silent and produces confidently wrong
output. Open Fixture Library import is most likely to pay off for this class.

## DMX light bars

Capabilities: `dimmer`, per-segment `color_rgb`, `strobe`, `effect_select`.

Planning notes: bars are usually **multi-segment**, and segment count is the
defining property of the profile. A bar in a segmented mode is closer to a WLED
strip than to a PAR, and should be modelled with per-segment targets so a chase
cue can address segments individually. Whether segments are addressed as
sub-fixtures or as an array within one instance is a modelling decision worth
making once, for all bars.

## Keobin fixtures

Currently present as a 24-channel scene-based device with a `MODE_VALUES` block
covering four laser sub-devices, a magic ball, and a strobe block.

Planning notes: **this fixture contains laser emitters.** Everything in
[laser_and_haze_safety.md](laser_and_haze_safety.md) applies to it, including
the master enable and the manual confirmation, and it applies *before* the
fixture is profiled rather than after. The sub-device structure in the existing
table suggests the fixture is best modelled as several logical fixtures sharing
one address block, which the instance model supports and which keeps laser
capabilities isolated behind their own gate rather than mixed into a general
profile. The existing table's channel assignments must be re-derived from the
Keobin manual for the exact model, and any disagreement investigated rather than
reconciled toward either side.

## Chauvet GigBAR-family multi-effect fixtures

Currently a 24-channel scene-based device with sub-devices for two PARs, two
derbies, a laser, and a strobe.

Planning notes: the GigBAR family spans several generations with **different
channel layouts and different mode sets**, so "GigBAR" is not sufficient
identity — the exact model and mode must be recorded in the profile `source`
field. It is genuinely a **composite fixture**: modelling it as one flat
24-channel device is what forces the current design's sub-device tables into the
frontend. Modelling it as several logical fixtures over one address block lets
the PARs use the shared PAR renderers, the derbies use pattern/speed renderers,
and the laser section sit behind the laser gate.

The laser section is why this fixture cannot be treated as ordinary lighting.
Its `laser` sub-device must map to `laser_enable` / `laser_pattern`
capabilities, and those are gated.

## Laser channels

Capabilities: `laser_enable`, `laser_pattern`, `speed`, and possibly colour
selection.

Planning notes: `laser_enable` is not an ordinary capability. It is subject to a
separate master enable, manual confirmation, startup blackout, disconnect
blackout, duration limits, and safe-zone configuration — all specified in
[laser_and_haze_safety.md](laser_and_haze_safety.md), which must be read before
any laser profile is written. A profile that exposes laser channels without the
gate in place is a defect regardless of how correct its channel mapping is.

Note the current state: Lights **cannot presently emit laser output** through
the ILDA path, because `IldaPlayer` drives `LoggingSink` (F22, D-6). DMX-attached
laser fixtures such as those in the GigBAR and Keobin are a **different path**
and are not covered by that safety property. Adding a laser capability to a DMX
profile is therefore the first point at which Lights could command laser
emission, and it deserves the same gate D-6 reserves for the DAC.

## Haze output and fan channels

Capabilities: `haze_output`, and `fan_speed` where the machine separates them.

Planning notes: the existing `haze` device is 2-channel and manual-controlled,
which is consistent with an output/fan pair but is **not** verified against a
manual. Where output and fan are separate channels they must be separate
capabilities — running the fan without output is a legitimate and useful state
(clearing haze, air movement), and conflating them makes it unreachable.

Haze is governed by duty-cycle rules, minimum off periods, warm-up, and
cooldown, all in [laser_and_haze_safety.md](laser_and_haze_safety.md). It is
**never** driven by beat- or onset-level features (D-20).

---

# Part 6 — Transport strategy

## Incremental LedFx compatibility

LedFx remains part of the migration:

```text
current scene activation
        ↓
custom live analyzer and semantic cue engine
        ↓
├── LedFx compatibility adapter for existing WLED scenes
├── native WLED state and pixel renderers
└── fixture-aware DMX renderer
```

The current `LEDFXClient` is not injectable and couples its destination to the
FastAPI bind host. M2 and M7 must first turn it into a configured adapter with
explicit failure behavior. Existing scenes remain usable through that adapter
while native effects are developed and compared. Immediate LedFx removal is not
a goal; removal can be considered only after native rendering is demonstrably
reliable and required scene behavior has a supported replacement.

LedFx and native output must not control the same WLED device concurrently.
Ownership is explicit per device and changes through a controlled transition,
including a defined safe state.

## DMX transports

| Option | Fit for this repository | Trade-off |
| --- | --- | --- |
| **sACN (current)** | Already working, already the deployment path | Standards-based, network-only. The existing monkey-patch of the library's socket send should be revisited when the transport becomes injectable |
| **Art-Net** | Straightforward addition alongside sACN | Widely supported by nodes; some rigs only speak one of the two |
| **OLA (`olad`)** | Strong option if USB-DMX interfaces are ever used | Adds a daemon to the deployment; largely a Linux-first story, which matters given Windows deployment (see below) |
| **Mock / recording** | **Required, not optional** | Enables deterministic capture or timeline replay and regression testing with no rig |

**The OLA caveat specific to this repository.** Lights deploys on native Windows
(`build_exe.py`, `run.bat`, [platform_support.md](platform_support.md)). OLA's
Windows story is materially weaker than its Linux one. Introducing an
`olad`-backed transport therefore means either accepting a Linux show host — a
significant change to the deployment model — or treating OLA as a
development-and-Linux option while Windows uses sACN or Art-Net directly. That
choice should be made explicitly rather than discovered during Phase 2.

**Recording transport design.** Records `(show_time, universe, 512-byte frame)`
tuples, plus a monotonic timestamp, to a file the tests and future visualizer
both read. This single component is what makes "run the whole show and diff it"
possible, and it is the highest-leverage item in Phase 1.

## WLED transports

Two output modes, represented by separate transport responsibilities:

| Transport | Use | Rate |
| --- | --- | --- |
| JSON API over HTTP | Power, brightness, segments, presets, effects | Low; per cue |
| Realtime pixel protocol, such as DDP if validated | Custom pixel frames | High; per frame |

A WebSocket may later provide state updates or another supported control path,
but it is an implementation option rather than a required third output mode.
The realtime transport must **not** be reached through the JSON path, and the
JSON path must not be used to push per-frame updates. Keeping state and pixel
responsibilities separate makes the mistake impossible rather than merely
discouraged.

## Transport lifecycle, shared

The only interface elements genuinely common to all transports:

```python
def open(self) -> None: ...
def close(self) -> None: ...
def blackout(self) -> None: ...      # MUST be safe to call at any time
def is_connected(self) -> bool: ...
latency_ms: int
```

`blackout()` is required on every transport, must be idempotent, must be
callable from a shutdown handler, and must not depend on the show engine being
in a valid state. It is the mechanism the safety document relies on.

These lifecycle concepts do not imply that LedFx, WLED state, WLED pixels, and
DMX share one artificial data-plane interface. Their payloads, rates, and
failure semantics remain protocol-appropriate.

---

# Part 7 — Prerequisites and risks

## Prerequisites

| Work | Requires | Why |
| --- | --- | --- |
| Injectable DMX transport | **M1**, then **M2** | `SENDER` is a module-global built at import (F3); it cannot be replaced until import is safe |
| Recording transport | M2 | Needs the injection seam to exist |
| Fixture profiles as data | M3, M8 | Needs typed read outcomes and a validation layer |
| Explicit addressing migration | M2 characterization tests | The byte-identical invariant is unprovable without them |
| Address-collision validation | Explicit addressing | Meaningless before it |
| WLED direct control | M7 (host/port decoupling) | F17 makes any second network destination inexpressible today |
| Laser capabilities | M8, M9, and the full safety architecture | [laser_and_haze_safety.md](laser_and_haze_safety.md) |
| Multi-universe | Explicit addressing | Universe is currently a single config scalar |

## Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Migration silently re-patches a working rig | **Highest in this document** | Byte-identical characterization tests; split commits; native-Windows rig validation; OQ-5 answered first |
| An unverified profile drives a real fixture | High | `verified: false` blocks physical output; profiles carry their manual source |
| Imported OFL/QLC+ profiles are wrong for the exact model | High | Import sets `verified: false`; manual check required before output |
| Laser capability added without the gate | **Safety-critical** | Laser capabilities are gated at the renderer *and* the transport, and the gate is not priority-resolvable |
| Haze mapped to beats | High (equipment + venue) | Normative prohibition, D-20; enforced in the generator, not just documented |
| OLA adopted without resolving the Windows story | Moderate | Decide the deployment model before Phase 2, not during |
| WLED realtime pushed through the JSON path | Moderate | Separate transport types |
| Fixture library licensing restricts redistribution | Moderate | Verify OFL and QLC+ licence terms before shipping any imported profile in the packaged executable |
