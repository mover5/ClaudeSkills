---
name: analyze-logbook
description: Analyze Home Assistant logbook history for repeated behavior patterns and propose automations. Use when the user asks to review HA activity, find automation opportunities, do a weekly/monthly smart-home review, or "what should I automate?". Calls get_logbook, groups events into patterns, then offers to create each accepted automation directly via create_automation — no YAML handoff.
allowed-tools: mcp__homeassistant-mcp__get_logbook, mcp__homeassistant-mcp__list_entities, mcp__homeassistant-mcp__get_state, mcp__homeassistant-mcp__list_automations, mcp__homeassistant-mcp__create_automation, mcp__homeassistant-mcp__reload_automations, Read, Write
---

# Analyze Home Assistant logbook for automation opportunities

Pull recent Home Assistant activity, find repeated patterns, and propose automations the user can accept with a single yes — this skill creates them directly rather than handing over YAML.

## When this runs

Typical triggers:
- "review my HA logbook"
- "what should I automate in Home Assistant?"
- "weekly home assistant review"
- "analyze my smart home usage"
- "find patterns in my HA data"

## Steps

### 1. Pick the time window

Ask the user how far back to look, defaulting to **7 days**. Accept 1–30. If they just say "go" or "the usual", use 7.

### 2. Fetch the logbook

Call `get_logbook` with `days_back` set. Leave `include_noisy` unset (the default filter drops sensor/weather/battery noise — that's what you want for pattern-finding). If the response `count` is under ~30 events, tell the user the window is too thin to find real patterns and offer to extend it to 14 or 30 days.

### 3. Check existing automations

Call `list_automations` once. You'll use this to avoid proposing automations that already exist.

### 4. Analyze for patterns

Scan the events for:

- **Repeated sequences** — event A followed by event B within a short window, happening multiple times. Example: `person.alice` → `home` consistently followed by `light.hallway` → `on` within 2 minutes.
- **Time-of-day patterns** — the same entity changing to the same state around the same wall-clock time on most days. Example: `light.bedroom` → `off` between 22:45 and 23:15 on 6 of 7 days.
- **Device correlations** — two entities whose state changes cluster together in time. Example: `media_player.tv` → `playing` coincides with `light.living_room` brightness dropping.
- **Manual actions that look like routines** — a single-user action (light, switch, climate) repeated at similar times or in similar contexts, with no corresponding automation in `list_automations`.

Ignore anything that only happened once or twice. A pattern needs at least 3 occurrences across the window, or a clear daily cadence, before you propose it.

Reference actual `entity_id`s and timestamps from the data — no hand-waving.

### 5. Present findings

Give the user a brief summary first: "Looked at N events over D days. Found K patterns worth automating."

Then, for each pattern, output a short block:

```
## Pattern <n>: <short title>

Observed: <1–2 sentences describing the pattern with example timestamps and entity_ids>
Proposed automation: <plain-English description of trigger + action>
```

Do NOT paste YAML. Do NOT dump full automation configs. The user has said they don't work in YAML.

At the end, ask: **"Want me to create any of these? Say which numbers (e.g. '1 and 3') or 'all'."**

### 6. Create the chosen automations

For each accepted pattern:

1. Build the HA automation config object in JavaScript/JSON form (the `create_automation` tool accepts the same shape as HA's config API — see the schema notes below).
2. Pick a stable `id` — slugify the pattern title (lowercase, alphanumeric + underscores, e.g. `evening_bedroom_lights_off`).
3. Call `create_automation` with `{ id, config }`.
4. After all creates succeed, call `reload_automations` **once** at the end to activate them.
5. Report back: "Created N automations and reloaded. They're live now."

If `create_automation` returns a missing-entity error, tell the user which entity_id was missing — don't silently retry.

### 7. Offer to save a report (optional)

If the user wants a written record, offer to save the summary as markdown to a path of their choice (e.g. `~/ha-reviews/review-<date>.md`). Only do this if they ask — don't write files by default.

## Automation config shape

`create_automation` takes `{ id, config }`. The `config` uses HA's standard automation schema. Build it as an object, not a YAML string.

Common triggers:

```js
// State change
{ platform: 'state', entity_id: 'person.alice', to: 'home' }

// Time-of-day (wall clock)
{ platform: 'time', at: '22:45:00' }

// Sun-relative
{ platform: 'sun', event: 'sunset', offset: '-00:30:00' }

// Numeric state threshold
{ platform: 'numeric_state', entity_id: 'sensor.temperature', above: 25 }
```

Common actions (use the `action:` field, a list):

```js
[
  {
    service: 'light.turn_on',
    target: { entity_id: 'light.hallway' },
    data: { brightness_pct: 60 },
  },
]
```

Minimal automation config example:

```js
{
  alias: 'Turn off bedroom lights at bedtime',
  description: 'Auto-created from logbook pattern 2026-04-22',
  trigger: [{ platform: 'time', at: '23:00:00' }],
  action: [
    { service: 'light.turn_off', target: { entity_id: 'light.bedroom' } },
  ],
  mode: 'single',
}
```

## Guardrails

- **Don't propose an automation that duplicates an existing one.** Check `list_automations` aliases and triggers before suggesting.
- **Don't propose automations for deny-listed entities.** If the user's pattern involves a `lock.*` or other denied entity, mention the pattern but flag that the deny-list blocks it — don't try to create it.
- **Prefer conservative actions.** If the pattern is "TV on → living room lights dim to 40%", propose exactly that. Don't extrapolate to "and close the blinds and start the fireplace" from one observation.
- **Single `reload_automations` call at the end**, not one per create. Reloading is cheap but noisy in the HA logs.
