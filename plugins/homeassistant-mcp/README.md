# Home Assistant MCP server

Minimal MCP server for Home Assistant. Exposes entity state, service calls, and CRUD for automations, scripts, scenes, and input_* / timer / counter helpers, backed by the HA REST config API.

## Tools

**State & services**

| Tool | Purpose |
| --- | --- |
| `list_entities` | List entities (optional `domain` filter) |
| `get_state` | Full state + attributes for one `entity_id` |
| `call_service` | Call any HA service — **subject to deny-list** |

**Automations / scripts / scenes** — same six tools per domain:

`list_{plural}`, `get_{singular}`, `create_{singular}`, `update_{singular}`, `delete_{singular}`, `reload_{plural}`.

Covers: `automation`, `script`, `scene`.

**Helpers** — parametrized by `helper_type` (`input_boolean`, `input_number`, `input_text`, `input_select`, `input_datetime`, `input_button`, `timer`, `counter`):

`list_helpers`, `get_helper`, `create_helper`, `update_helper`, `delete_helper`, `reload_helpers`.

All writes go through HA's config API (lands in the corresponding `.yaml` / storage). **Always call the matching `reload_*` after create/update/delete** or changes won't take effect at runtime. Reload tools are exempt from the `call_service` deny-list.

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

Then build and configure from the installed plugin directory:

```bash
npm install
npm run build
cp .env.example .env                         # edit with your values
cp deny-list.example.json deny-list.json     # edit
```

The plugin's `.mcp.json` resolves `${CLAUDE_PLUGIN_ROOT}/dist/index.js` automatically — no manual `~/.claude.json` edits needed.

The server loads environment from `.env` next to itself via `dotenv` on every launch. Both `.env` and `deny-list.json` are gitignored.

Variables:

- `HA_URL` — e.g. `http://192.168.1.30:8123` (trailing slash tolerated)
- `HA_TOKEN` — long-lived access token from HA → profile → Security
- `HA_DENY_LIST_PATH` — optional, defaults to `./deny-list.json` next to the server
