# Decisions and Open Questions

**Status of this document:** canonical. Accepted decisions are binding on
future work in this repository. Open questions require an owner decision and
must not be resolved by an agent acting alone.

Decisions are numbered `D-n`; open questions `OQ-n`. Neither is renumbered once
assigned.

---

## Accepted decisions

### D-1 — Incremental stabilization, not a rewrite

The codebase is small, coherent, and has a real domain model. It is stabilized
in dependency order rather than replaced.

*Why:* a rewrite discards the prototype's most valuable asset — a device preset
→ combined preset → scene → full scene → active show workflow that is
implemented end to end and coherent in code — in exchange for risk. (Whether
that workflow is usable for real shows is CODE-INSPECTED ONLY; no repository
evidence establishes real-show use.) The defects in
[audit_findings.md](audit_findings.md) are individually addressable.

### D-2 — Hardware is assumed unavailable

All development, inspection, and validation assumes no DMX, sACN, LedFx, ILDA,
or laser hardware is present. Fake, null, simulated, or injected adapters are
preferred everywhere.

*Why:* the repository's primary environment is WSL2, which cannot verify
hardware behavior, and accidental output to a real rig is not a recoverable
mistake.

### D-3 — `backend/main.py` is never imported or run for validation

*Why:* F1, F2, and F3 — importing it initializes data, starts sACN, and calls
`uvicorn.run`. This restriction lifts only when M1 is complete and verified.

### D-4 — Persistent JSON storage is retained

JSON files remain the persistence format. Atomicity, typed errors, and
validation are added around them (M3, M8). No database migration is planned.

*Why:* the data volumes are tiny, the files are human-inspectable and
hand-editable during a show, and the format is not the cause of any P0 finding.
F7 and F8 are defects in *how* JSON is written and read, not in the choice of
JSON.

### D-5 — Persistence stops being the control bus

Runtime state moves into memory (M5). Persistence continues to exist for
durable configuration but is removed from the high-frequency output path.

*Why:* F6. Using `devices.json` as inter-thread IPC is the cause of the
continuous re-parsing and of the output path's exposure to partially written
files. It is *not* the cause of the unpaced loop — F4 is an independent defect,
the absence of any application-level wait in the loop body. M5 fixes both,
because fixing either alone leaves the other in place.

### D-6 — ILDA output remains nonphysical until the M11 safety architecture exists

`LoggingSink` stays in place. A DAC adapter is added only behind a validated
library root, buffered output, watchdog, interlock, emergency stop, safe
shutdown, output-disabled-by-default, and native-Windows hardware testing.

*Why:* the current inability to emit laser output is a safety property. It is
given up deliberately and only once, with the full safety architecture in place
— never as a side effect of another change.

### D-7 — The deleted reinforcement-learning system is not restored

`stable-baselines3` and `gymnasium` stay out. Intelligent scene selection
proceeds rules-first (M12).

*Why:* F24 — the dependencies carry a large footprint and a transitive PyTorch
burden with no working code path, and no evidence has been presented that scene
selection requires reinforcement learning. Deterministic rules are testable
without hardware; a learned policy is not.

### D-8 — WSL2 develops, native Windows validates

No HARDWARE VERIFIED claim may originate from a WSL2 result. See
[platform_support.md](platform_support.md).

*Why:* WSL2's virtual network adapter, advisory file locking, and absent
Windows firewall make its results non-transferable for exactly the behaviors
that matter for a lighting rig.

### D-9 — Browser-side audio analysis is kept

Microphone capture and beat detection stay in the browser; the backend receives
derived beat events.

*Why:* raw audio never crosses a process boundary and the backend stays free of
an audio pipeline — both structural properties readable from the code. Whether
the browser microphone capture and beat detection actually work in the host
browser is CODE-INSPECTED ONLY and remains unverified; it is a row on the
native-Windows checklist in [platform_support.md](platform_support.md).

### D-10 — Evidence labels are mandatory

Every substantive claim in this documentation set carries one of the labels
defined in [project_overview.md](project_overview.md). Completion percentages
are prohibited.

*Why:* the specific failure this guards against is a future reader mistaking
`ShowCatalog`, `RuntimeManager`, adapters, preflight, or atomic persistence for
implemented components. The existing documentation avoided that trap (F25) and
this set must not reintroduce it.

### D-11 — Stale documents are marked, not deleted

Superseded documentation gets a status banner identifying what is still
accurate and what replaced it.

*Why:* `RUN.md`, `QUICK_START.md`, and `BUILD_INSTRUCTIONS.md` contain
operational Windows knowledge that exists nowhere else in the repository. Their
inaccuracies are specific and can be flagged in place.

### D-12 — The first implementation branch is `architecture/safe-import-boundary`

Narrowly scoped to M1. See [current_sprint.md](current_sprint.md).

*Why:* nothing else can be tested until import is side-effect free, and a
narrow first branch establishes the review pattern for the milestones that
follow.

---

## Open questions

These require an owner decision. An agent may present analysis but must not
decide unilaterally.

### OQ-1 — Milestone numbering: M0–M12 or M0–M10?

Two milestone sequences were specified in the same instruction set. This
documentation uses the finer-grained M0–M12 range (13 numbered milestones). The
mapping to the M0–M10 range (11 numbered milestones) is recorded in
[roadmap.md](roadmap.md). No work is dropped either way — only the granularity
and numbering differ.

*Needed:* confirmation of M0–M12, or an instruction to renumber.

**Nonblocking follow-up.** This does not gate M0's completion and does not
block M1 or any later milestone. If the owner chooses the M0–M10 range, the
change is a mechanical renumbering across these documents using the mapping in
[roadmap.md](roadmap.md).

### OQ-2 — Is the catalog one `ShowCatalog` or several repositories?

PROPOSED, unresolved. A single authoritative catalog is the stated direction,
but a facade over smaller per-aggregate repositories (devices, presets, scenes,
ILDA definitions, config) may be a better fit. Deciding early risks a God
object; deciding late risks scattered access patterns.

*Needed:* a decision before M3 hardens the storage interface.

### OQ-3 — Authentication mechanism and threat model

F12 and F13 are verified, but the correct remedy depends on facts not in the
repository: is the rig on a trusted private network, a venue network, or
occasionally the open internet? Options range from binding to localhost only,
through a shared operator token, to full authentication.

*Needed:* the actual deployment context, before M9.

### OQ-4 — Fixture profile format and source

M10 replaces hardcoded fixture knowledge with data. Undecided: whether to adopt
an existing format such as GDTF or Open Fixture Library, or define a minimal
project-specific schema.

*Needed:* a decision before M10 begins. Not urgent, but it shapes the schema.

### OQ-5 — Migration path for existing installations

M4 removes read-time fixture bootstrapping. Real installations may depend on
that behavior having already created their `gigbar`, `keobin`, and `haze`
entries. An explicit migration is required, and it must not damage a working
rig configuration.

*Needed:* confirmation of which real data directories exist and must survive,
before M4.

### OQ-6 — Target DMX refresh rate

DESIGN INTENT indicates roughly 20 ms (about 50 Hz). Current code has no
application-level pacing at all (F4). The correct configurable default, and
whether it should adapt to fixture count, is unverified against real hardware.

*Needed:* a native-Windows measurement against the real rig, during M5.

### OQ-7 — Does the AI code get repaired or removed?

`backend/routes/ai_mode.py` and `frontend/html/ai_mode.html` remain, importing
a deleted package (F20, F23), alongside unused heavy dependencies (F24). Three
options: delete the orphaned code and dependencies; keep it as a placeholder
for M12; or rewrite it rules-first under M12.

*Needed:* a decision. Removing the unused dependencies is separable from the
question of the routes, and could be done earlier.

### OQ-8 — Scene `Sensitivity` and the audio-influence model

DESIGN INTENT describes a per-scene `Sensitivity` value and a "callable model
that is just a packet of information on how audio influences render". Neither
exists in code. It is UNKNOWN whether these remain wanted, and if so whether
they belong on `Scene`, on `Preset`, or in a separate audio-mapping object.

*Needed:* creator input, before M6 fixes the scene model's shape.
