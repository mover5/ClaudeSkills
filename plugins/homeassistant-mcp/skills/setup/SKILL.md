---
name: setup
description: Configure the homeassistant-mcp plugin — prompt the user for Home Assistant URL and a long-lived access token, write them to the persistent config file, and verify the connection. Use when the homeassistant-mcp server reports missing HA_URL/HA_TOKEN config, when Home Assistant tool calls fail due to missing credentials, when the user asks to set up / configure / install Home Assistant integration, or on first use of the plugin before any HA tools have been used.
allowed-tools: Bash, Read, Write
---

# Home Assistant MCP Setup

Configure the `homeassistant-mcp` plugin end-to-end: collect credentials from the user, write them to a stable config location outside the plugin install dir, and verify the server can reach Home Assistant.

**When this skill runs:** typically auto-invoked by Claude after an HA tool call returns a "setup required" error. May also be invoked directly by the user.

## Config location

The server looks for `.env` in this order:

1. `$HA_MCP_CONFIG_DIR` if set
2. `$XDG_CONFIG_HOME/homeassistant-mcp` if `XDG_CONFIG_HOME` is set
3. `~/.config/homeassistant-mcp` (default)

This path is **stable across plugin version bumps** — the user sets values once, not on every update.

## Steps

### 1. Compute the config directory

```bash
if [ -n "$HA_MCP_CONFIG_DIR" ]; then
  HA_CFG="$HA_MCP_CONFIG_DIR"
elif [ -n "$XDG_CONFIG_HOME" ]; then
  HA_CFG="$XDG_CONFIG_HOME/homeassistant-mcp"
else
  HA_CFG="$HOME/.config/homeassistant-mcp"
fi
echo "$HA_CFG"
```

Tell the user where the config will live.

### 2. Check for an existing config

If `$HA_CFG/.env` already exists and has `HA_URL` + `HA_TOKEN`, ask the user whether they want to keep it, overwrite it, or just verify it. If they want to verify only, skip to step 6.

### 3. Ask the user for values

Ask in chat, one value at a time:

1. **Home Assistant URL** — e.g. `http://192.168.1.30:8123` or `https://my-ha.example.com`. Trailing slash is tolerated.
2. **Long-lived access token** — give these instructions verbatim:

   > Open Home Assistant in a browser. Click your profile icon at the bottom-left → open the **Security** tab → scroll to **Long-Lived Access Tokens** → **Create Token** → name it e.g. "Claude Code MCP" → copy the token. It is only shown once.

Treat the token as secret: do not echo it back in plaintext, and do not include it in any summary.

### 4. Write the `.env`

```bash
mkdir -p "$HA_CFG"
umask 077
cat > "$HA_CFG/.env" <<EOF
HA_URL=<user-supplied-url>
HA_TOKEN=<user-supplied-token>
EOF
chmod 600 "$HA_CFG/.env"
```

Use the Write tool with `$HA_CFG/.env` as the absolute path. Do not let the token appear in tool-call descriptions.

### 5. Seed the deny-list (optional, if absent)

```bash
if [ ! -f "$HA_CFG/deny-list.json" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/deny-list.example.json" ]; then
  cp "${CLAUDE_PLUGIN_ROOT}/deny-list.example.json" "$HA_CFG/deny-list.json"
fi
```

Tell the user the default deny-list blocks `lock.*` entities and a couple of shutdown services, and point them at `$HA_CFG/deny-list.json` if they want to customize.

### 6. Verify the connection

```bash
# Use the values just written (do not echo the token).
. "$HA_CFG/.env"
code=$(curl -s -o /tmp/ha-setup-body -w "%{http_code}" \
  -H "Authorization: Bearer $HA_TOKEN" \
  "${HA_URL%/}/api/")
echo "HTTP $code"
head -c 200 /tmp/ha-setup-body; echo
rm -f /tmp/ha-setup-body
```

Interpret:

- `HTTP 200` with body `{"message":"API running."}` → success.
- `HTTP 401` → token rejected. Re-prompt for the token (HA_URL is probably fine).
- `HTTP 404` → URL is wrong (reaching a server but not HA's API).
- connection refused / timeout → URL host/port wrong or HA not reachable from this machine.

Re-prompt for whichever value is wrong and retry. Do not proceed until HTTP 200.

### 7. Tell the user what happens next

- Values are persisted at `$HA_CFG/.env` and will survive plugin version bumps.
- The MCP server reads env at process startup, so **the running server needs to reload** for the new config to take effect. Typical options:
  - Run `/mcp` in Claude Code and reconnect the `home-assistant` server, OR
  - Restart Claude Code.
- After that, Home Assistant tools (`list_entities`, `call_service`, etc.) are ready to use.

## Notes

- Never commit `.env` or `deny-list.json` to a git repo.
- The token has full HA access — treat it like a password.
- To change values later, re-run this skill or edit `$HA_CFG/.env` directly.
