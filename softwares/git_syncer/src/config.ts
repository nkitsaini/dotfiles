/* eslint-disable @typescript-eslint/naming-convention */
import * as v from "valibot";
import { toJsonSchema } from "@valibot/to-json-schema";
import { join } from "node:path";
import { parse } from "jsonc-parser";

const PullTriggersSchema = v.union([
  v.object({
    type: v.literal("sse"),
    channel: v.union([
      v.string(),
      v.object({
        ntfy_channel: v.string(),
      }),
    ]),
  }),
  v.object({
    type: v.literal("recurring"),
    after_every_seconds: v.optional(v.number(), 3600),
  }),
]);

const SyncConfigSchema = v.union([
  v.object({
    commit_only: v.pipe(
      v.optional(v.boolean(), false),
      v.description("If true, no pull or push will be attempted"),
    ),
    pull_debounce_period_ms: v.optional(v.number(), 1000),
    push_debounce_period_ms: v.optional(v.number(), 5000),
    pull_triggers: v.optional(v.array(PullTriggersSchema), [
      {
        type: "recurring",
        after_every_seconds: 3600,
      },
    ]),
  }),
]);

export type SyncConfig = v.InferOutput<typeof SyncConfigSchema>;
export type PullTriggers = v.InferOutput<typeof PullTriggersSchema>;

const defaultConfig: SyncConfig = v.parse(SyncConfigSchema, {});

const exampleConfig: SyncConfig = {
  ...defaultConfig,
  pull_triggers: [
    {
      type: "sse",
      channel: {
        ntfy_channel: "my-ntfy-channel",
      },
    },
    {
      type: "recurring",
      after_every_seconds: 1800,
    },
  ],
};

export function getJsonSchema() {
  const jsonSchema = toJsonSchema(SyncConfigSchema);
  return JSON.stringify(jsonSchema, null, 2);
}

export function getExampleConfig() {
  return {
    ...exampleConfig,
    $schema: "<path-or-url-to-schema-file>",
  };
}

export async function readConfigForRepo(repo: string): Promise<SyncConfig> {
  const configPath = join(repo, ".kit-sync.jsonc");
  if (!(await Bun.file(configPath).exists())) {
    return defaultConfig;
  }
  const configContent = await Bun.file(configPath).text();
  try {
    const parsed = parse(configContent);
    const validated = v.parse(SyncConfigSchema, parsed);
    return validated;
  } catch (e) {
    throw new Error(`Failed to parse config file: ${e}`);
  }
}

if (import.meta.main) {
  // eslint-disable-next-line no-console
  console.log(getJsonSchema());
}
