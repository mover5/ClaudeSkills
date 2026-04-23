# Home Assistant MCP server

Minimal MCP server for Home Assistant. Exposes entity state, service calls, and CRUD for automations, scripts, scenes, and input_* / timer / counter helpers, backed by the HA REST config API.

## Tools

**State & services**

| Tool | Purpose |
| --- | --- |
| `list_entities` | List entities (optional `domain` filter) |
| `get_state` | Full state + attributes for one `entity_id` |
| `get_logbook` | Recent logbook events (default last 7 days, noise-filtered); `include_noisy: true` for raw |
| `call_service` | Call any HA service — **subject to deny-list** |

**Automations / scripts / scenes** — same six tools per domain:

`list_{plural}`, `get_{singular}`, `create_{singular}`, `update_{singular}`, `delete_{singular}`, `reload_{plural}`.

Covers: `automation`, `script`, `scene`.

**Helpers** — parametrized by `helper_type` (`input_boolean`, `input_number`, `input_text`, `input_select`, `input_datetime`, `input_button`, `timer`, `counter`):

`list_helpers`, `get_helper`, `create_helper`, `update_helper`, `delete_helper`, `reload_helpers`.

All writes go through HA's config API (lands in the corresponding `.yaml` / storage). **Always call the matching `reload_*` after create/update/delete** or changes won't take effect at runtime. Reload tools are exempt from the `call_service` deny-list.

## Skills

- **`homeassistant-mcp:setup`** — first-run config (HA URL + token) with connection verification. Auto-invoked by Claude when the server reports missing credentials.
- **`homeassistant-mcp:analyze-logbook`** — pulls recent logbook activity, finds repeated behavior patterns (time-of-day, device correlations, manual-routine-looking actions), and proposes automations Claude can create directly via `create_automation` — no YAML editing.

## Deny-list

`call_service` enforces a deny-list read from `deny-list.json` on every invocation (no restart to update). If the file is missing the list is empty; if the file exists but is malformed, calls fail closed.

```json
{
  "entities": ["cover.garage_door", "lock.*"],
  "services": ["homeassistant.restart", "hassio.host_shutdown"]
}
```

- `entities` — glob-matched against `entity_id` in `service_data` or `target`.
- `services` — glob-matched against `${domain}.${service}`.

`*` is the only wildcard, matches any run of characters.

Deny-list path: `./deny-list.json` next to the server, or set `HA_DENY_LIST_PATH`.

**Known gap:** the deny-list does NOT scan automations written via `create_automation` / `update_automation`. An automation whose action calls a deny-listed service will still be created and will fire later via HA's engine. Scanning automation action trees is a v2 item.

## Install

This plugin ships via the `mover-skillz` marketplace. In Claude Code:

```
/plugin marketplace add mover5/ClaudeSkills
/plugin install homeassistant-mcp@mover-skillz
```

Claude Code runs `npm install` on plugin install to pull runtime deps (including `tsx`, which runs the TypeScript source directly — no build step).

### Configuration — no manual steps required

On first use, if no config is found, the server will tell Claude to invoke the `homeassistant-mcp:setup` skill. That skill walks you through entering your HA URL and token, writes them to a persistent location, and verifies the connection.

You can also trigger setup manually at any time:

```
/homeassistant-mcp:setup
```

Config is stored **outside** the plugin install dir so it survives version bumps. Lookup order:

1. `$HA_MCP_CONFIG_DIR/.env` if set
2. `$XDG_CONFIG_HOME/homeassistant-mcp/.env` if `XDG_CONFIG_HOME` is set
3. `~/.config/homeassistant-mcp/.env` (default)

### Manual configuration (if you prefer)

```bash
mkdir -p ~/.config/homeassistant-mcp
cat > ~/.config/homeassistant-mcp/.env <<'EOF'
HA_URL=http://192.168.1.30:8123
HA_TOKEN=your_long_lived_access_token
EOF
chmod 600 ~/.config/homeassistant-mcp/.env
```

Optional: drop a `deny-list.json` in the same dir (see `deny-list.example.json` in the plugin install).

Variables:

- `HA_URL` — e.g. `http://192.168.1.30:8123` (trailing slash tolerated)
- `HA_TOKEN` — long-lived access token from HA → profile → Security → Long-Lived Access Tokens
- `HA_MCP_CONFIG_DIR` — optional override for the whole config dir
- `HA_DENY_LIST_PATH` — optional override for the deny-list file path; otherwise defaults to `<config-dir>/deny-list.json`, falling back to a legacy `deny-list.json` next to the server if present

## Developing

The runtime entry point is `src/index.ts` — there's no build step and no `dist/`, so source is always what runs. `tsx` (a runtime TS loader) is a regular dependency; `typescript` is kept as a devDep for type-checking only.

```bash
npm install
npm run dev          # tsx watch mode against src/index.ts
npm run typecheck    # tsc --noEmit, no output artifacts
```
