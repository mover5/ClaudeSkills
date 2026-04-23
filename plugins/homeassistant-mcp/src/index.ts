#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { config as loadEnv } from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

function resolveConfigDir(): string {
  if (process.env.HA_MCP_CONFIG_DIR) return process.env.HA_MCP_CONFIG_DIR;
  if (process.env.XDG_CONFIG_HOME)
    return resolve(process.env.XDG_CONFIG_HOME, 'homeassistant-mcp');
  const home = process.env.HOME ?? process.env.USERPROFILE;
  if (home) return resolve(home, '.config', 'homeassistant-mcp');
  return resolve(__dirname, '..');
}

const CONFIG_DIR = resolveConfigDir();
const CONFIG_ENV_PATH = resolve(CONFIG_DIR, '.env');
const LEGACY_ENV_PATH = resolve(__dirname, '..', '.env');

loadEnv({ path: CONFIG_ENV_PATH, quiet: true });
if ((!process.env.HA_URL || !process.env.HA_TOKEN) && CONFIG_ENV_PATH !== LEGACY_ENV_PATH) {
  loadEnv({ path: LEGACY_ENV_PATH, quiet: true });
}

const HA_URL_RAW = process.env.HA_URL;
const HA_TOKEN = process.env.HA_TOKEN;
const CONFIG_READY = Boolean(HA_URL_RAW && HA_TOKEN);
const HA_URL = HA_URL_RAW?.replace(/\/$/, '') ?? '';

function resolveDenyListPath(): string {
  if (process.env.HA_DENY_LIST_PATH) return process.env.HA_DENY_LIST_PATH;
  const primary = resolve(CONFIG_DIR, 'deny-list.json');
  if (existsSync(primary)) return primary;
  const legacy = resolve(__dirname, '..', 'deny-list.json');
  if (existsSync(legacy)) return legacy;
  return primary;
}

const DENY_LIST_PATH = resolveDenyListPath();

function setupRequiredMessage(): string {
  return [
    `Home Assistant MCP is not configured — HA_URL and HA_TOKEN are required.`,
    ``,
    `RECOMMENDED FIX (for the assistant): invoke the \`homeassistant-mcp:setup\` skill now.`,
    `It will prompt the user for their Home Assistant URL and a long-lived access`,
    `token, then write them to: ${CONFIG_ENV_PATH}`,
    ``,
    `Manual fix: create ${CONFIG_ENV_PATH} with:`,
    `  HA_URL=http://<your-ha-host>:8123`,
    `  HA_TOKEN=<long-lived-access-token>`,
    ``,
    `Generate a token in Home Assistant: profile icon (bottom-left) → Security tab`,
    `→ Long-Lived Access Tokens → Create Token.`,
    ``,
    `This path is stable across plugin version bumps, so you only set it once.`,
  ].join('\n');
}

async function ha(path: string, init: RequestInit = {}): Promise<unknown> {
  if (!CONFIG_READY) throw new Error(setupRequiredMessage());
  const res = await fetch(`${HA_URL}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${HA_TOKEN}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`HA API ${res.status} ${res.statusText}: ${body}`);
  }
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

type DenyList = { entities: string[]; services: string[] };

function loadDenyList(): DenyList {
  let raw: string;
  try {
    raw = readFileSync(DENY_LIST_PATH, 'utf8');
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      return { entities: [], services: [] };
    }
    throw new Error(
      `Deny-list at ${DENY_LIST_PATH} is unreadable: ${(err as Error).message}`,
    );
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(
      `Deny-list at ${DENY_LIST_PATH} is not valid JSON: ${(err as Error).message}`,
    );
  }
  const obj = parsed as { entities?: unknown; services?: unknown };
  return {
    entities: Array.isArray(obj.entities)
      ? obj.entities.filter((v): v is string => typeof v === 'string')
      : [],
    services: Array.isArray(obj.services)
      ? obj.services.filter((v): v is string => typeof v === 'string')
      : [],
  };
}

function globToRegex(pattern: string): RegExp {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
  return new RegExp(`^${escaped}$`);
}

function matchesAny(value: string, patterns: string[]): string | null {
  for (const p of patterns) {
    if (globToRegex(p).test(value)) return p;
  }
  return null;
}

function collectEntityIds(serviceData: unknown, target: unknown): string[] {
  const ids: string[] = [];
  const collect = (v: unknown) => {
    if (typeof v === 'string') ids.push(v);
    else if (Array.isArray(v)) v.forEach(collect);
  };
  collect((serviceData as { entity_id?: unknown } | undefined)?.entity_id);
  collect((target as { entity_id?: unknown } | undefined)?.entity_id);
  return ids;
}

function checkDenyList(
  domain: string,
  service: string,
  serviceData: unknown,
  target: unknown,
): { denied: false } | { denied: true; reason: string } {
  const deny = loadDenyList();
  const svcKey = `${domain}.${service}`;
  const svcMatch = matchesAny(svcKey, deny.services);
  if (svcMatch) {
    return {
      denied: true,
      reason: `service '${svcKey}' matches deny-list services pattern '${svcMatch}'`,
    };
  }
  for (const ent of collectEntityIds(serviceData, target)) {
    const entMatch = matchesAny(ent, deny.entities);
    if (entMatch) {
      return {
        denied: true,
        reason: `entity '${ent}' matches deny-list entities pattern '${entMatch}'`,
      };
    }
  }
  return { denied: false };
}

function textResult(data: unknown) {
  return { content: [{ type: 'text' as const, text: JSON.stringify(data, null, 2) }] };
}

/**
 * Walk a config payload and return every entity_id it references.
 *
 * Covers:
 *  - any `entity_id` key whose value is a string or array of strings
 *    (target.entity_id, data.entity_id, trigger.entity_id, condition.entity_id, ...)
 *  - the keys of a top-level `entities` map (scene config shape)
 *
 * Intentionally does NOT inspect `service:` / `action:` values, since those
 * are service names that happen to share the `domain.object` shape with
 * entity_ids. Conflating them produces false positives.
 */
function collectReferencedEntityIds(config: unknown): string[] {
  const refs = new Set<string>();
  const walk = (v: unknown) => {
    if (!v || typeof v !== 'object') return;
    if (Array.isArray(v)) {
      v.forEach(walk);
      return;
    }
    for (const [key, val] of Object.entries(v as Record<string, unknown>)) {
      if (key === 'entity_id') {
        if (typeof val === 'string') refs.add(val);
        else if (Array.isArray(val))
          for (const item of val) if (typeof item === 'string') refs.add(item);
      } else {
        walk(val);
      }
    }
  };
  walk(config);
  if (config && typeof config === 'object' && !Array.isArray(config)) {
    const ents = (config as Record<string, unknown>).entities;
    if (ents && typeof ents === 'object' && !Array.isArray(ents)) {
      for (const k of Object.keys(ents)) refs.add(k);
    }
  }
  return [...refs];
}

async function findMissingReferences(config: unknown): Promise<string[]> {
  const refs = collectReferencedEntityIds(config);
  if (refs.length === 0) return [];
  const states = (await ha('/api/states')) as Array<{ entity_id: string }>;
  const existing = new Set(states.map((s) => s.entity_id));
  return refs.filter((r) => !existing.has(r));
}

function missingReferencesError(missing: string[], op: string, label: string) {
  const list = missing.map((r) => `  - ${r}`).join('\n');
  return {
    content: [
      {
        type: 'text' as const,
        text:
          `Missing entity references — ${op} ${label} aborted. These entity_ids do not exist in Home Assistant:\n${list}\n\n` +
          `Common cause: referencing an automation/script by the id you set in the config API, ` +
          `instead of the entity_id HA slugifies from the alias. Use list_* to see the real entity_id, ` +
          `or create any forward-referenced entities first and then retry.`,
      },
    ],
    isError: true as const,
  };
}

const server = new McpServer(
  { name: 'home-assistant', version: '0.2.0' },
  {
    instructions:
      'Home Assistant MCP server. Discover with list_entities / get_state / get_logbook (recent events, noise-filtered by default). Act with call_service (subject to deny-list). Manage config-backed entities with the automation / script / scene / helper tools — always call the matching reload_* after create/update/delete.',
  },
);

// ---- General state & service tools ----

server.registerTool(
  'list_entities',
  {
    description:
      'List Home Assistant entities, optionally filtered by domain (e.g. "light", "sensor"). Returns entity_id, state, and friendly_name.',
    inputSchema: {
      domain: z
        .string()
        .optional()
        .describe('Filter to entities in this domain (e.g. "light")'),
    },
  },
  async ({ domain }) => {
    const states = (await ha('/api/states')) as Array<{
      entity_id: string;
      state: string;
      attributes?: { friendly_name?: string };
    }>;
    const filtered = domain
      ? states.filter((s) => s.entity_id.startsWith(`${domain}.`))
      : states;
    return textResult(
      filtered.map((s) => ({
        entity_id: s.entity_id,
        state: s.state,
        friendly_name: s.attributes?.friendly_name,
      })),
    );
  },
);

server.registerTool(
  'get_state',
  {
    description:
      'Get the full state (value + all attributes + timestamps) of a single Home Assistant entity.',
    inputSchema: {
      entity_id: z.string().describe('Full entity_id, e.g. "light.living_room"'),
    },
  },
  async ({ entity_id }) => {
    return textResult(await ha(`/api/states/${encodeURIComponent(entity_id)}`));
  },
);

// ---- Logbook ----

const LOGBOOK_EXCLUDED_DOMAINS = new Set([
  'sensor',
  'sun',
  'weather',
  'update',
  'zone',
  'device_tracker',
  'number',
  'select',
  'button',
  'scene',
]);

const LOGBOOK_EXCLUDED_STATES = new Set(['unavailable', 'unknown', 'None', '']);

const LOGBOOK_EXCLUDED_ENTITY_SUBSTRINGS = [
  '_battery',
  '_signal',
  '_rssi',
  '_lqi',
  '_linkquality',
  '_uptime',
  '_boot',
];

interface LogbookEntry {
  when?: string;
  name?: string;
  entity_id?: string;
  state?: string;
  domain?: string;
  message?: string;
}

function shouldIncludeLogbookEntry(entry: LogbookEntry): boolean {
  const entityId = entry.entity_id ?? '';
  const domain = entry.domain ?? entityId.split('.')[0] ?? '';
  const state = entry.state ?? '';
  if (LOGBOOK_EXCLUDED_DOMAINS.has(domain)) return false;
  if (LOGBOOK_EXCLUDED_STATES.has(state)) return false;
  if (LOGBOOK_EXCLUDED_ENTITY_SUBSTRINGS.some((s) => entityId.includes(s))) return false;
  return true;
}

server.registerTool(
  'get_logbook',
  {
    description:
      'Fetch Home Assistant logbook events over a recent window. Returns time-ordered events with entity_id, friendly_name, state, domain, and timestamp. By default applies noise filters (excludes sensors, weather, battery/signal entities, unavailable/unknown states) so the output is usable for pattern analysis; pass include_noisy=true for the raw stream. Optionally scope to a single entity_id.',
    inputSchema: {
      days_back: z
        .number()
        .int()
        .min(1)
        .max(30)
        .optional()
        .describe('How many days of history to fetch (default 7, max 30).'),
      entity_id: z
        .string()
        .optional()
        .describe('Restrict to events for this entity_id (e.g. "light.living_room").'),
      include_noisy: z
        .boolean()
        .optional()
        .describe(
          'If true, return all events without the default noise filters. Default false.',
        ),
    },
  },
  async ({ days_back, entity_id, include_noisy }) => {
    const days = days_back ?? 7;
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
    const now = new Date().toISOString();
    const params = new URLSearchParams({ end_time: now });
    if (entity_id) params.set('entity', entity_id);
    const raw = (await ha(
      `/api/logbook/${since}?${params.toString()}`,
    )) as LogbookEntry[];
    const filtered = include_noisy ? raw : raw.filter(shouldIncludeLogbookEntry);
    const events = filtered
      .map((e) => {
        const eid = e.entity_id ?? '';
        return {
          timestamp: e.when ?? '',
          entity_id: eid,
          friendly_name: e.name ?? eid,
          state: e.state ?? '',
          domain: e.domain ?? eid.split('.')[0] ?? '',
          message: e.message,
        };
      })
      .sort((a, b) => a.timestamp.localeCompare(b.timestamp));
    return textResult({
      period: { since, until: now, days_back: days },
      filtered: !include_noisy,
      count: events.length,
      events,
    });
  },
);

server.registerTool(
  'call_service',
  {
    description:
      'Call a Home Assistant service. Subject to deny-list enforcement (services by domain.service pattern, entities by entity_id pattern). Denied calls return isError without hitting HA.',
    inputSchema: {
      domain: z.string().describe('Service domain, e.g. "light"'),
      service: z.string().describe('Service name, e.g. "turn_on"'),
      service_data: z
        .record(z.any())
        .optional()
        .describe('Service data payload (e.g. { brightness: 200 })'),
      target: z
        .object({
          entity_id: z.union([z.string(), z.array(z.string())]).optional(),
          device_id: z.union([z.string(), z.array(z.string())]).optional(),
          area_id: z.union([z.string(), z.array(z.string())]).optional(),
        })
        .optional()
        .describe('Target selector (modern HA service call format)'),
    },
  },
  async ({ domain, service, service_data, target }) => {
    const check = checkDenyList(domain, service, service_data, target);
    if (check.denied) {
      return {
        content: [
          {
            type: 'text',
            text: `DENIED by deny-list: ${check.reason}. Edit ${DENY_LIST_PATH} to change this policy.`,
          },
        ],
        isError: true,
      };
    }
    const body: Record<string, unknown> = { ...(service_data ?? {}) };
    if (target) body.target = target;
    return textResult(
      await ha(`/api/services/${domain}/${service}`, {
        method: 'POST',
        body: JSON.stringify(body),
      }),
    );
  },
);

// ---- Config-entity CRUD factory ----

interface EntityCrudSpec {
  /** HA entity domain, used both as the state-filter prefix and config API path segment. */
  domain: string;
  /** Singular form used in tool names (get_X, create_X, update_X, delete_X). */
  singular: string;
  /** Plural form used in tool names (list_Xs, reload_Xs). */
  plural: string;
  /** Zod shape accepted by create/update. Use .passthrough() to allow future HA fields. */
  configSchema: z.ZodTypeAny;
  /** Optional extra state attributes to surface in list_* responses. */
  listExtraAttributes?: string[];
  /** User-facing label in tool descriptions (e.g. "automation", "script"). Defaults to singular. */
  label?: string;
}

function registerEntityCrud(spec: EntityCrudSpec): void {
  const { domain, singular, plural, configSchema } = spec;
  const label = spec.label ?? singular;
  const extras = spec.listExtraAttributes ?? [];

  server.registerTool(
    `list_${plural}`,
    {
      description: `List all ${plural} with entity_id, internal id (for the config API), friendly_name, and state${
        extras.length ? `, plus: ${extras.join(', ')}` : ''
      }.`,
      inputSchema: {},
    },
    async () => {
      const states = (await ha('/api/states')) as Array<{
        entity_id: string;
        state: string;
        attributes?: Record<string, unknown>;
      }>;
      const items = states
        .filter((s) => s.entity_id.startsWith(`${domain}.`))
        .map((s) => {
          const a = s.attributes ?? {};
          const row: Record<string, unknown> = {
            entity_id: s.entity_id,
            // Automations expose the config-API id as an attribute; scripts/scenes/helpers
            // don't, so fall back to the entity_id's object_id (the part after the dot).
            id: a.id ?? s.entity_id.slice(domain.length + 1),
            friendly_name: a.friendly_name,
            state: s.state,
          };
          for (const k of extras) row[k] = a[k];
          return row;
        });
      return textResult(items);
    },
  );

  server.registerTool(
    `get_${singular}`,
    {
      description: `Fetch the full config for one ${label} by its internal id (NOT entity_id). Get the id from list_${plural}.`,
      inputSchema: {
        id: z.string().describe(`The ${label}'s id attribute from list_${plural}.`),
      },
    },
    async ({ id }) => {
      return textResult(
        await ha(`/api/config/${domain}/config/${encodeURIComponent(id)}`),
      );
    },
  );

  server.registerTool(
    `create_${singular}`,
    {
      description: `Create a new ${label}. Specify a unique id. Call reload_${plural} after to activate. Validates entity_id references against HA state before writing; returns isError if any don't exist.`,
      inputSchema: {
        id: z
          .string()
          .describe(
            `Unique id for this ${label} (appears as the "id:" field in the YAML).`,
          ),
        config: configSchema,
      },
    },
    async ({ id, config }) => {
      const missing = await findMissingReferences(config);
      if (missing.length > 0) return missingReferencesError(missing, 'create', label);
      return textResult(
        await ha(`/api/config/${domain}/config/${encodeURIComponent(id)}`, {
          method: 'POST',
          body: JSON.stringify(config),
        }),
      );
    },
  );

  server.registerTool(
    `update_${singular}`,
    {
      description: `Update an existing ${label} by id (upsert, same endpoint as create). Call reload_${plural} after to activate. Validates entity_id references against HA state before writing; returns isError if any don't exist.`,
      inputSchema: {
        id: z.string().describe(`Existing ${label} id`),
        config: configSchema,
      },
    },
    async ({ id, config }) => {
      const missing = await findMissingReferences(config);
      if (missing.length > 0) return missingReferencesError(missing, 'update', label);
      return textResult(
        await ha(`/api/config/${domain}/config/${encodeURIComponent(id)}`, {
          method: 'POST',
          body: JSON.stringify(config),
        }),
      );
    },
  );

  server.registerTool(
    `delete_${singular}`,
    {
      description: `Delete a ${label} by id. Call reload_${plural} after to remove it from the active set.`,
      inputSchema: {
        id: z.string().describe(`${label} id to delete`),
      },
    },
    async ({ id }) => {
      return textResult(
        await ha(`/api/config/${domain}/config/${encodeURIComponent(id)}`, {
          method: 'DELETE',
        }),
      );
    },
  );

  server.registerTool(
    `reload_${plural}`,
    {
      description: `Reload ${plural} in Home Assistant to apply changes from create/update/delete. Not subject to the call_service deny-list.`,
      inputSchema: {},
    },
    async () => {
      const result = await ha(`/api/services/${domain}/reload`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
      return textResult(result ?? { ok: true });
    },
  );
}

// ---- Config-entity schemas ----

const automationConfigSchema = z
  .object({
    alias: z.string().optional(),
    description: z.string().optional(),
    trigger: z.any().optional(),
    triggers: z.any().optional(),
    condition: z.any().optional(),
    conditions: z.any().optional(),
    action: z.any().optional(),
    actions: z.any().optional(),
    mode: z.enum(['single', 'restart', 'queued', 'parallel']).optional(),
    variables: z.record(z.any()).optional(),
  })
  .passthrough();

const scriptConfigSchema = z
  .object({
    alias: z.string().optional(),
    description: z.string().optional(),
    sequence: z.any().describe('List of action steps (required)'),
    mode: z.enum(['single', 'restart', 'queued', 'parallel']).optional(),
    variables: z.record(z.any()).optional(),
    icon: z.string().optional(),
    fields: z.record(z.any()).optional(),
  })
  .passthrough();

const sceneConfigSchema = z
  .object({
    name: z.string().describe('Scene name shown in the UI'),
    entities: z
      .record(z.any())
      .describe('Map of entity_id -> state or { state, ...attributes }'),
    icon: z.string().optional(),
  })
  .passthrough();

// ---- Register CRUD for automation, script, scene ----

registerEntityCrud({
  domain: 'automation',
  singular: 'automation',
  plural: 'automations',
  configSchema: automationConfigSchema,
  listExtraAttributes: ['last_triggered'],
});

registerEntityCrud({
  domain: 'script',
  singular: 'script',
  plural: 'scripts',
  configSchema: scriptConfigSchema,
  listExtraAttributes: ['last_triggered'],
});

registerEntityCrud({
  domain: 'scene',
  singular: 'scene',
  plural: 'scenes',
  configSchema: sceneConfigSchema,
});

// ---- Generalized helper tools (input_*, timer, counter) ----

const HELPER_TYPES = [
  'input_boolean',
  'input_number',
  'input_text',
  'input_select',
  'input_datetime',
  'input_button',
  'timer',
  'counter',
] as const;
const helperTypeSchema = z.enum(HELPER_TYPES);

server.registerTool(
  'list_helpers',
  {
    description: `List helper entities. Types: ${HELPER_TYPES.join(', ')}. Pass helper_type to filter to one kind; omit for all.`,
    inputSchema: {
      helper_type: helperTypeSchema
        .optional()
        .describe('Restrict to one helper type'),
    },
  },
  async ({ helper_type }) => {
    const states = (await ha('/api/states')) as Array<{
      entity_id: string;
      state: string;
      attributes?: Record<string, unknown>;
    }>;
    const types = helper_type ? [helper_type] : [...HELPER_TYPES];
    const items = states
      .filter((s) => types.some((t) => s.entity_id.startsWith(`${t}.`)))
      .map((s) => {
        const a = s.attributes ?? {};
        const type = s.entity_id.split('.')[0];
        return {
          entity_id: s.entity_id,
          type,
          id: a.id ?? s.entity_id.slice(type.length + 1),
          friendly_name: a.friendly_name,
          state: s.state,
        };
      });
    return textResult(items);
  },
);

server.registerTool(
  'get_helper',
  {
    description:
      'Fetch the full config for one helper by type + internal id. Config shape varies by helper type — see HA docs for the exact keys each type accepts.',
    inputSchema: {
      helper_type: helperTypeSchema,
      id: z.string().describe("The helper's id attribute (not entity_id)"),
    },
  },
  async ({ helper_type, id }) => {
    return textResult(
      await ha(`/api/config/${helper_type}/config/${encodeURIComponent(id)}`),
    );
  },
);

server.registerTool(
  'create_helper',
  {
    description:
      'Create a new helper of a given type. Config shape varies by helper type (e.g. input_number takes {name, min, max, step, initial, mode, unit_of_measurement}; input_boolean takes {name, initial, icon}; timer takes {name, duration}; counter takes {name, initial, step, minimum, maximum}). Call reload_helpers with the same type after to activate.',
    inputSchema: {
      helper_type: helperTypeSchema,
      id: z.string().describe('Unique id for the new helper'),
      config: z
        .record(z.any())
        .describe('Type-specific config (see HA docs for each helper type)'),
    },
  },
  async ({ helper_type, id, config }) => {
    return textResult(
      await ha(`/api/config/${helper_type}/config/${encodeURIComponent(id)}`, {
        method: 'POST',
        body: JSON.stringify(config),
      }),
    );
  },
);

server.registerTool(
  'update_helper',
  {
    description:
      'Update an existing helper by type + id (upsert). Call reload_helpers with the same type after.',
    inputSchema: {
      helper_type: helperTypeSchema,
      id: z.string(),
      config: z.record(z.any()),
    },
  },
  async ({ helper_type, id, config }) => {
    return textResult(
      await ha(`/api/config/${helper_type}/config/${encodeURIComponent(id)}`, {
        method: 'POST',
        body: JSON.stringify(config),
      }),
    );
  },
);

server.registerTool(
  'delete_helper',
  {
    description:
      'Delete a helper by type + id. Call reload_helpers with the same type after.',
    inputSchema: {
      helper_type: helperTypeSchema,
      id: z.string(),
    },
  },
  async ({ helper_type, id }) => {
    return textResult(
      await ha(`/api/config/${helper_type}/config/${encodeURIComponent(id)}`, {
        method: 'DELETE',
      }),
    );
  },
);

server.registerTool(
  'reload_helpers',
  {
    description:
      'Reload helpers of one type in Home Assistant to apply changes. Call this with the matching helper_type after create/update/delete_helper. Not subject to the call_service deny-list.',
    inputSchema: {
      helper_type: helperTypeSchema,
    },
  },
  async ({ helper_type }) => {
    const result = await ha(`/api/services/${helper_type}/reload`, {
      method: 'POST',
      body: JSON.stringify({}),
    });
    return textResult(result ?? { ok: true });
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
if (!CONFIG_READY) {
  console.error(
    `[ha-mcp] WARNING: no HA_URL/HA_TOKEN — tools will error until setup runs. ` +
      `Expected config at: ${CONFIG_ENV_PATH}. ` +
      `Invoke the homeassistant-mcp:setup skill to configure.`,
  );
}
console.error('[ha-mcp] connected on stdio');
