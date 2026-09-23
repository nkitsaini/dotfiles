// Execute the actual patched handler with mocked services: team defaults must
// not write model state; personal defaults must still validate and apply.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

for (const name of ["workbench.desktop.main.js", "workbench.glass.main.js"]) {
  const source = readFileSync(join(process.argv[2], "out/vs/workbench", name), "utf8");
  const method = source.match(/async setDefaultModel\([^]*?(?=performDefaultModelRequest\()/)?.[0];
  assert.ok(method, `${name}: missing default-model handler`);
  const handler = Function(`return ({${method}}).setDefaultModel`)();
  for (const teamId of [123, undefined]) {
    const writes = [];
    let validations = 0;
    const context = {
      _cursorAuthenticationService: { getTeamId: () => teamId },
      getValidatedDefaultModel: async ({ thinkingModel, model }) => {
        validations++;
        return thinkingModel || model;
      },
      _modelConfigService: {
        setModelConfig: (...args) => writes.push(args),
        doesModelSupportMaxMode: () => true,
      },
    };
    const result = await handler.call(context, "thinking-model", "main-model", true, []);
    if (teamId) {
      assert.equal(result, false);
      assert.equal(validations, 0);
      assert.deepEqual(writes, []);
    } else {
      assert.equal(result, true);
      assert.equal(validations, 2);
      assert.deepEqual(writes, [
        ["composer", { modelName: "thinking-model", maxMode: true, selectedModels: [{ modelId: "thinking-model", parameters: [] }] }],
        ["cmd-k", { modelName: "main-model", maxMode: false }],
        ["composer", { modelName: "thinking-model", maxMode: true }],
      ]);
      writes.length = 0;
      context.getValidatedDefaultModel = async () => undefined;
      assert.equal(await handler.call(context, "invalid", "invalid", false, []), false);
      assert.deepEqual(writes, []);
    }
  }
  const gateMatch = source.match(/function ([\w$]+)\(([\w$]+)\)\{return !([\w$]+)\(\2.experimentName\)&&\2.modelNudgesEnabled\}/);
  assert.ok(gateMatch, `${name}: missing team-nudge gate`);
  const predicateName = gateMatch[3];
  const predicate = source.match(new RegExp(`function ${predicateName.replaceAll("$", "\\$")}\\(([\\w$]+)\\)\\{return \\1!==void 0&&([\\w$]+)\\.has\\(\\1\\)\\}`));
  assert.ok(predicate, `${name}: missing team-nudge predicate`);
  const policies = source.match(/(?<![\w$])[\w$]+="team_admin_model_reset_nudges",[\w$]+="team_admin_smart_auto_nudge",[\w$]+="team_admin_latest_cursor_model_impose",[\w$]+=new Set\(\[[\w$,]+\]\)/);
  assert.ok(policies, `${name}: missing team-nudge policies`);
  const scope = `const ${policies[0]};${predicate[0]};`;
  const gate = Function(`${scope}return (${gateMatch[0]})`)();
  const startupMethod = source.match(/async applyApplicationOpenModelSwitch\([^]*?(?=async getCurrentAuthId\()/)?.[0];
  assert.ok(startupMethod, `${name}: missing startup model-switch handler`);
  const startup = Function(`${scope}return ({${startupMethod}}).applyApplicationOpenModelSwitch`)();
  const teamNudges = [
    "team_admin_model_reset_nudges",
    "team_admin_smart_auto_nudge",
    "team_admin_latest_cursor_model_impose",
  ];
  for (const experimentName of teamNudges) {
    for (const modelNudgesEnabled of [true, false]) {
      assert.equal(gate({ experimentName, modelNudgesEnabled }), false);
    }
    // No service access is possible: a delayed team switch must stop before
    // validation, analytics, storage, or selected-conversation updates.
    const context = new Proxy({}, { get: (_, key) => assert.fail(`Unexpected service access: ${String(key)}`) });
    await startup.call(context, { experimentName, nudgeId: "team-reset", targetModel: { modelId: "team-model" } });
  }
  for (const experimentName of [undefined, "ordinary_recommendation"]) {
    for (const modelNudgesEnabled of [true, false]) {
      assert.equal(gate({ experimentName, modelNudgesEnabled }), modelNudgesEnabled);
    }
    let inspectedTarget = false;
    await startup.call({}, { experimentName, get targetModel() { inspectedTarget = true; } });
    assert.equal(inspectedTarget, true, "Ordinary startup nudges must reach original handler");
  }
  console.log(`${name}: team defaults and asynchronous nudges skipped; personal behavior preserved`);
}
