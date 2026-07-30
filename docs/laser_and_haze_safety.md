# Laser and Haze Safety

**Status of this document:** TARGET ARCHITECTURE policy accepted by D-20;
PROPOSED implementation detail. Updated on branch
`docs/live-renderer-architecture`.

> ## Read this first
>
> **Software alone does not make laser operation safe.** Nothing in this
> document, and nothing that could be implemented from it, makes a laser
> installation safe. Laser safety is a function of the physical installation,
> the beam paths, the venue, the audience separation, the mounting, the
> hardware interlocks, the operator's training, and the applicable regulations
> in the jurisdiction — none of which this application can observe or enforce.
>
> The controls specified here reduce the ways *this application* can cause
> unintended emission. That is their entire scope. They are a necessary
> condition and not remotely a sufficient one.
>
> **Responsibility for safe and lawful laser operation rests with the operator
> and the venue, not with this software.**

**None of the controls in this document is implemented.** Part 1 records the
current split: the ILDA path cannot emit through a DAC, while DMX-attached laser
channels are reachable through ordinary presets without a dedicated gate.

---

# Part 1 — Current state

## VERIFIED CURRENT BEHAVIOR

### The ILDA path cannot emit

`IldaPlayer` streams parsed points into `LoggingSink`
(`backend/ilda/player.py:94`, `backend/ilda/sink.py:16-31`), which increments
counters and prints a total. There is no DAC driver, no USB or Ethernet laser
transport, and no interlock. Lights **cannot currently drive a physical laser
through the ILDA path.**

This is recorded as F22 and as decision D-6: the inability to emit is a safety
property, and it is given up deliberately and only once, with the full safety
architecture in place — never as a side effect of another change.

### The DMX path is a different story, and it is not covered by D-6

DMX-attached fixtures with laser sections — the Keobin lasers and the GigBAR
laser sub-device, both present in the current rig's hardcoded knowledge — are
driven through `backend/dmx/sender.py`, not through the ILDA path. D-6's safety
property does not extend to them.

**There is no laser gate, no master enable, no confirmation step, and no
emission-related validation anywhere in the DMX path.** A laser channel in a
device preset is an integer like any other, and applying that preset transmits
it. That is the current state, stated plainly because the rest of this document
is meaningless without it.

### Haze

The `haze` device is bootstrapped as a 2-channel manual device
(`backend/routes/data.py:57-72`). Its channel meanings are not recorded anywhere
and are not verified against a manual. There is no duty-cycle logic, no
warm-up handling, no minimum off period, and no cooldown.

### What is missing across both

No startup blackout. No disconnect blackout. No emergency stop. No watchdog. No
output duration limits. No safe-zone configuration. No audit log. No test mode.
No output-disabled-by-default state.

---

# Part 2 — System-wide output policy

## TARGET ARCHITECTURE — accepted by D-20

The live renderer requires policy controls that remain separate from creative
cue priority:

- an emergency blackout independent of audio capture, musical-state
  estimation, cue generation, and ordinary renderer state;
- a laser master enable that defaults off on every start;
- configurable strobe limits;
- global and per-fixture intensity ceilings;
- haze or atmosphere duty-cycle, minimum-off, and rate limits;
- a manual override with explicit precedence and audit behavior;
- separate freeze and hold semantics, so creative state retention is not
  confused with blackout;
- safe loss-of-signal behavior for missing audio, capture failure, renderer
  failure, transport failure, and fixture disconnect.

Freeze or hold may retain a restrained visual state when the audio source is
temporarily uncertain. It must not retain an unsafe laser, strobe, or atmosphere
command, and it must not prevent emergency blackout. Loss-of-signal policy must
define when output fades, holds, or blackouts; leaving the last energetic frame
latched indefinitely is not acceptable.

These are required architecture boundaries, not claims that controls exist.
Exact limits and transitions must be configured from verified fixture,
operator, and venue requirements and tested on supported hardware. They do not
constitute a legal or venue-compliance guarantee.

---

# Part 3 — Laser safety controls

## PROPOSED. Every control below is required before any laser capability is enabled.

These are specified as a set. Implementing a subset produces a system that
*appears* gated and is not, which is worse than the current state where the
absence of controls is obvious.

### 3.1 Separate laser master enable

A single, explicit, persisted-off-by-default flag that gates **all** laser
emission — ILDA DAC output and DMX laser channels alike.

Requirements:

- Default is **disabled**, on every start, regardless of stored state. A
  persisted "enabled" value must not survive a restart.
- It is a **separate** control from show playback, output enable, or blackout
  release. Starting a show must never enable lasers as a side effect.
- It gates at **two** independent points: the renderer refuses to produce laser
  channel values, and the transport refuses to transmit them. A single gate is a
  single point of failure.
- It is **not priority-resolvable.** A cue's priority, a style, a manual
  override, or a generated timeline cannot open it. Cue priority is a creative
  mechanism; this is not.
- Disabling it takes effect immediately and forces laser channels to their
  documented safe values — which come from the manual, per fixture, and are part
  of the profile.

### 3.2 Manual confirmation

Enabling laser output requires a deliberate operator action in the current
session that cannot be automated, scripted, or triggered by a show timeline.

- The confirmation states what will be enabled, which fixtures, and in which
  universe.
- It is not a checkbox that persists. It is per-session.
- It cannot be satisfied by an API call from a show file, a generated cue, or a
  scheduled task. If the API exposes it, that endpoint must be
  authentication-gated (M9) and must be excluded from anything a show can invoke.

### 3.3 Startup blackout

On every application start, before any output path is opened:

- all laser channels are set to their safe values;
- the laser master enable is off;
- the blackout is transmitted, not merely assumed, once the transport opens.

The current architecture makes this impossible to guarantee — `SENDER` is
constructed at import (F3) before any application logic runs. M1 is a hard
prerequisite.

### 3.4 Disconnect blackout

Loss of contact with a fixture, a node, or a DAC must drive laser output to safe
values rather than leaving the last commanded state latched.

- A DMX node that stops acknowledging, a DAC that disconnects, or a transport
  error triggers laser-safe state and disables the master enable.
- Re-enabling requires manual confirmation again (3.2). Reconnection is **not**
  automatic re-enablement.
- Note the current contrary behavior: `backend/dmx/sender.py:19-30` patches the
  sacn library to *swallow* `OSError` on send and log at most once per ten
  seconds. Unreachability is currently invisible to the application. That patch
  must be revisited when the transport becomes injectable — an error the
  application cannot see is an error it cannot respond to.

### 3.5 Unknown-channel fail-closed behavior

- A fixture profile marked `verified: false` may not receive laser output at all.
- An unknown mode, an unknown channel meaning, or a capability the mode does not
  declare produces **no output** and a diagnostic — never an approximation.
- A laser capability with no explicit safe value in the profile is an invalid
  profile. It fails validation; it does not default to zero and hope.

### 3.6 Output duration limits

- A maximum continuous emission duration per fixture, configured per profile.
- Exceeding it forces safe values and requires re-confirmation.
- A watchdog independent of the show engine enforces this. If the show engine
  hangs, stalls, or crashes, the watchdog still fires — a limit enforced only by
  the component that might have failed is not a limit.

### 3.7 Safe-zone configuration

Where the hardware supports beam-region or scan-angle constraints, they are
configured in Lights, validated in preflight, and applied before emission.

**Stated plainly:** software safe zones are a convenience and a
defence-in-depth measure. They are not a substitute for physical beam
containment, correct fixture aiming and mounting, audience separation, or
hardware scan-fail protection. A software safe zone assumes the fixture is where
the configuration says it is, and the software cannot verify that.

### 3.8 Test mode that excludes emission

A mode in which the entire laser path — cue generation, rendering, channel
assignment, timing, duration accounting — executes and is recorded, while
emission is suppressed at the transport.

This is the mode in which laser show development happens. It is the direct
analogue of the existing `NullSink` (`backend/ilda/sink.py:11-13`), which is
already the right shape and should be the model.

### 3.9 Audit logging

Append-only, timestamped, persisted outside the show data:

- master enable transitions, with the confirming action;
- every emission window: start, end, fixture, duration;
- duration-limit and watchdog trips;
- disconnect events and the resulting blackouts;
- emergency-stop activations;
- profile-validation rejections that blocked laser output.

The log exists to answer "what did the system command, and when" after an
incident. It is written atomically (M3) and is not truncated by ordinary
operation.

### 3.10 Emergency blackout

- Reachable at all times, from the operator's primary surface, in one action.
- Drives **all** output — laser, DMX, WLED — to safe values.
- Disables the laser master enable.
- Does not depend on the show engine, the scheduler, or the timeline being in a
  valid state. It must work when the show engine is the thing that has failed.
- Recovery requires manual confirmation (3.2).

**A software emergency stop is not a substitute for a physical emergency stop.**
Any installation where a physical e-stop is appropriate must have one, and it
must cut power or emission independently of this application.

---

# Part 4 — Haze machine safety and behavior

## PROPOSED

Haze risks are different in kind from laser risks: equipment damage, fire-alarm
activation, and venue-policy violation rather than direct injury. They are not
smaller, and alarm activation in a full venue is a serious event.

### 4.1 Manual override

Haze output is always directly controllable by the operator, and manual control
takes precedence over any generated cue. The operator must be able to stop haze
immediately without stopping the show.

### 4.2 Warm-up

Most haze machines require a heater warm-up before producing output, and command
during warm-up either does nothing or is queued by the machine.

- Warm-up duration is a per-machine profile value, from the manual.
- The system tracks warm-up state and reports it. A cue issued during warm-up is
  recorded as not-yet-effective rather than assumed to have taken effect.
- Show generation accounts for warm-up when placing the first haze cue.

### 4.3 Output and fan separation

Where the machine exposes separate output and fan channels, they are **separate
capabilities** (`haze_output`, `fan_speed`).

Running the fan without output is a legitimate and useful state — distributing
existing haze, clearing it, or moving air. Conflating the two makes that state
unreachable. Where a machine has only one channel, the profile declares only
`haze_output`; it does not synthesize a fan capability.

### 4.4 Maximum duty cycle

- A maximum on-time within a rolling window, configured per machine.
- The scheduler enforces it. A generated show that violates it is **rejected at
  generation time**, not silently clamped at runtime — an operator who asked for
  more haze than the machine can safely produce should be told, not quietly
  overruled.
- Runtime enforcement exists as well, as the backstop for manual control.

### 4.5 Minimum off period

An enforced minimum interval between output bursts, from the machine's manual.
This is the control that prevents the specific failure mode of rapid on/off
cycling, and it is enforced independently of the duty-cycle window.

### 4.6 Early cue scheduling

Haze takes time to fill a space. The visual effect lags the command by seconds
to tens of seconds depending on the room and the machine.

Prepared-show generation may place haze cues **ahead of** the moment the effect
is wanted, using a configured per-venue lead time. Live party mode does not know
future track structure reliably and must not pretend otherwise; it can adjust
atmosphere only through slow, rate-limited policy using current state and
operator intent. Offline analysis is therefore an optional enhancement for
planned atmosphere, not a prerequisite for safe live operation.

### 4.7 Cooldown

Machines with a cooldown requirement must not be commanded during it, and
shutdown must respect it where the machine requires a cooldown before power
removal. The profile records the requirement; the runtime honors it.

### 4.8 Disconnect behavior

Loss of contact drives haze output to off. Unlike laser re-enablement, haze may
resume automatically on reconnection **if** the duty-cycle and minimum-off
accounting is preserved across the gap — the safety property here is cumulative
output, not the connection state.

### 4.9 Section-level control

Haze is an **atmosphere** control operating at a slow musical and operational
timescale: a prepared section-level wash, a gradual response to a stabilized
live state, an operator-requested clear, or a planned pre-charge before a drop.
Live estimates do not claim definitive verse or chorus labels.

### 4.10 The prohibition

> **Haze must never be mapped directly to beat-level or onset-level audio
> features.**

This is normative, and D-20 records it as an accepted decision. The reasons:

- haze does not respond on beat timescales, so the mapping produces no visual
  effect;
- rapid on/off cycling stresses the pump and heater;
- it defeats duty-cycle and minimum-off accounting;
- and in a venue with smoke detection, unpredictable bursts are exactly the
  pattern most likely to trip an alarm.

A style definition that maps `haze_output` to `beats`, `onsets`, or
`percussive_energy` must fail validation. Documenting the prohibition is not
enough — the generator must enforce it.

---

# Part 5 — Venue, regulatory, and operator responsibility

## Scope of this software

Lights is a control application. It commands fixtures. It does not, and cannot:

- know where beams actually go;
- know where the audience is;
- verify that a fixture is mounted, aimed, or terminated as configured;
- detect a scan failure;
- verify that a profile matches the physical fixture;
- know the applicable regulations, permits, or venue policies;
- substitute for hardware interlocks, physical e-stops, beam blocks, or trained
  supervision.

## Operator responsibilities

Not exhaustive, and not legal advice:

- Determine and comply with the laser regulations and permitting requirements in
  the jurisdiction of the performance.
- Ensure audience-scanning rules are met, or that audience scanning does not
  occur.
- Ensure physical beam containment, correct aiming, and secure mounting.
- Provide hardware interlocks and a physical emergency stop where appropriate.
- Verify every fixture profile against the physical fixture before a show.
- Confirm venue policy on haze and the state of smoke detection before use.
- Supervise the rig during operation.

## What this documentation must never say

Binding on all future documentation in this repository, in the same spirit as
the "statements that must not be repeated" table in
[audit_findings.md](audit_findings.md):

| Do not say | Say instead |
| --- | --- |
| "Lights makes laser output safe." | "Lights implements software controls that reduce the ways the application can cause unintended emission. Safety depends on the physical installation and the operator." |
| "The safe-zone configuration prevents audience exposure." | "Software safe zones are defence in depth and assume the fixture is where the configuration says it is. They do not replace physical containment." |
| "The emergency stop cuts the laser." | "The software emergency blackout commands safe values and disables the master enable. It does not cut power and does not replace a physical e-stop." |
| "Haze is safe because the duty cycle is enforced." | "Duty-cycle enforcement protects the machine and reduces alarm risk. Venue policy and smoke-detection state remain the operator's responsibility." |
| "Lights is laser-safety compliant." | Nothing. Compliance is a property of an installation and an operator, not of an application. |

---

# Part 6 — Prerequisites

No laser or haze safety work should begin before these exist. Each is a genuine
blocker, not a formality:

| Prerequisite | Milestone | Why it blocks |
| --- | --- | --- |
| Import produces no side effects | M1 | A startup blackout is impossible when the sender is constructed at import (F3) |
| Injectable transports with null implementations | M2 | Test mode (3.8) and the gate's second enforcement point both require it |
| Atomic writes | M3 | The audit log must survive a crash |
| Preflight validation | M8 | Profile validation must run before output is enabled |
| Authentication | M9 | The laser-enable endpoint must not be callable by anything that can reach the port (F12) |
| Verified fixture profiles | M10 | An unverified profile may not receive laser output |
| Full safety architecture | M11 | D-6 — the ILDA DAC is attached only once all of it exists |

**One gap in the existing roadmap.** M11 covers safe *physical ILDA* output. It
does not cover DMX-attached laser fixtures, which are already in the rig and
already reachable through the existing DMX path. That gap is real and is raised
as D-20 in [decisions.md](decisions.md): the laser gate must cover the DMX path,
and it must be in place before fixture profiles expose laser capabilities in
M10 — which sits *earlier* in the dependency order than M11.
