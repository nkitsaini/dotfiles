import { spawn } from "bun";
import { join } from "path";
import chokidar from "chokidar"; // Standard for watching on Linux
import * as R from "remeda";
import { EventSource } from "eventsource";

import {
  command,
  run,
  string,
  oneOf,
  option,
  restPositionals,
  positional,
} from "cmd-ts";
import {
  configureLogging,
  LEVELS,
  logger,
  LogLevel,
  notifyUrgencyKey,
} from "./logger";
import { readConfigForRepo } from "./config";
import type { Logger } from "@logtape/logtape";

/** execute a shell command and return stdout or throw error */
async function runCommand(cmd: string[], cwd: string) {
  const proc = spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`Command '${cmd.join(" ")}' failed: ${stderr}`);
  }
  return await new Response(proc.stdout).text();
}

/** Check if a file is binary by reading the first 512 bytes for null characters */
async function isBinaryFile(filePath: string): Promise<boolean> {
  const file = Bun.file(filePath);
  if (!(await file.exists())) return false; // Deleted files are not binary

  // Heuristic: Read first 512 bytes. If it contains a null byte (0x00), it's likely binary.
  // Alternatively, use 'git diff --numstat' logic, but this is faster for new files.
  const buffer = await file.slice(0, 512).arrayBuffer();
  const view = new Uint8Array(buffer);
  return view.includes(0);
}

// --- Core Logic ---

/**
 * Main Sync Function.
 *
 * Note: this intentionally does NOT swallow errors. add/commit/push failures
 * propagate to the caller (reportOnFailures) which rate-limits notifications so
 * a flaky network / post-suspend blip doesn't bombard the user. `skippedBinaries`
 * tracks which binaries we've already reported so a lingering uncommitted binary
 * doesn't fire an error notification on every sync cycle.
 */
async function syncChanges(
  log: Logger,
  repository: string,
  commitOnly = false,
  skippedBinaries: Set<string> = new Set(),
) {
  log.info("[Sync] Processing changes...");

  if (!commitOnly) {
    // Best-effort pull: a failed pull (offline / just resumed from suspend)
    // must not block committing local work. errorOk=true logs at warn (below
    // the notification threshold) and continues; a persistent connectivity
    // problem is still surfaced by the push below via reportOnFailures.
    await pullUpdates(log, repository, true);
  }

  // 1. Get Status
  const statusOutput = await runCommand(
    ["git", "status", "--porcelain"],
    repository,
  );
  if (!statusOutput.trim()) {
    log.info("[Sync] No changes to commit.");
    skippedBinaries.clear();
    return;
  }

  const lines = statusOutput.split("\n").filter((l) => l);
  const filesToAdd: string[] = [];
  const binaryFiles: string[] = [];

  // 2. Filter Files
  for (const line of lines) {
    // Porcelain format: "XY path/to/file" -> We want the path (slice(3))
    const rawPath = line.substring(3);
    // Handle quoted paths if filename has spaces
    const filePath = rawPath.startsWith('"') ? rawPath.slice(1, -1) : rawPath;

    if (await isBinaryFile(join(repository, filePath))) {
      binaryFiles.push(filePath);
    } else {
      filesToAdd.push(filePath);
    }
  }

  // 3. Handle Binaries — notify only about *newly* skipped ones, then remember
  // the current set so we don't re-notify about the same file every cycle.
  const newBinaries = binaryFiles.filter((f) => !skippedBinaries.has(f));
  if (newBinaries.length > 0) {
    const msg = `Skipped ${newBinaries.length} binary file(s) (not synced):\n${newBinaries.slice(0, 3).join("\n")}${newBinaries.length > 3 ? "\n..." : ""}`;
    // Informational, not an emergency: surface it (error level clears the
    // default notify threshold) but at normal urgency, not critical.
    log.error(msg, { [notifyUrgencyKey]: "normal" });
  }
  skippedBinaries.clear();
  for (const f of binaryFiles) skippedBinaries.add(f);

  // 4. Commit & Push
  if (filesToAdd.length > 0) {
    await runCommand(["git", "add", ...filesToAdd], repository);
    await runCommand(
      ["git", "commit", "-m", `Auto-sync: ${new Date().toISOString()}`],
      repository,
    );
    log.info(`[Sync] Committed ${filesToAdd.length} files.`);

    if (!commitOnly) {
      await runCommand(["git", "push"], repository);
      log.info("[Sync] Pushed to remote.");
    } else {
      log.info(`[Sync] Committed ${filesToAdd.length} files (commit-only mode).`);
    }
  } else {
    log.info("[Sync] No files to add.");
  }
}

/** Pull updates from remote */
async function pullUpdates(
  log: Logger,
  respository: string,
  errorOk = false,
) {
  log.info("[Remote] Received update signal.");
  try {
    await runCommand(["git", "pull"], respository);
    log.info("[Remote] Pulled successfully.");
  } catch (error) {
    log.warn("[Remote] Pull failed (ignored):", {error});
    if (!errorOk) {
      throw error;
    }
  }
}

// --- Event Listeners ---
//

class NonRetryableError extends Error {}

async function verifyGitRepository(repo: string) {
  try {
    await runCommand(["git", "rev-parse", "--is-inside-work-tree"], repo);
  } catch (e) {
    throw new NonRetryableError(`Not a git repository: ${repo}: ${e}`);
  }
}

// Consecutive-failure backoff shared by the sync wrapper and the SSE reconnect
// loop. Both go quiet during a burst of failures and only surface a persistent
// problem, with the gap between notifications growing so a long outage doesn't
// produce a steady drip of popups.
const NOTIFY_FIRST_AFTER = 5; // consecutive failures before the first notification
const NOTIFY_BACKOFF_FACTOR = 4; // then notify at 5, 20, 80, ... failures

// True only when `n` is one of the geometric backoff points (5, 20, 80, ...).
function isBackoffNotifyPoint(n: number): boolean {
  let point = NOTIFY_FIRST_AFTER;
  while (point < n) point *= NOTIFY_BACKOFF_FACTOR;
  return point === n;
}

// Wrap a sync/pull task so transient failures don't spam notifications.
// Connectivity blips (offline, just-resumed-from-suspend, flaky wifi) make git
// pull/push fail in bursts. We stay quiet through those (console-only `warn`,
// below the notification threshold) and only surface a *persistent* problem —
// and even then at `normal` urgency (it's almost always "you're offline", not
// an emergency), with exponential backoff between notifications. The counter
// resets on any success.
function reportOnFailures(fn: () => Promise<void>): () => Promise<void> {
  let consecutiveFailures = 0;
  return async () => {
    try {
      await fn();
      consecutiveFailures = 0;
    } catch (e) {
      consecutiveFailures++;
      if (isBackoffNotifyPoint(consecutiveFailures)) {
        logger.error(
          `Sync failing after ${consecutiveFailures} consecutive attempts (likely offline). Will keep retrying.`,
          { e, [notifyUrgencyKey]: "normal" },
        );
      } else {
        logger.warn(
          `Error occurred during sync (attempt ${consecutiveFailures}):`,
          { e },
        );
      }
    }
  };
}

async function runContinousSync(repository: string): Promise<() => void> {
  const log = logger.with({ repository });
  await verifyGitRepository(repository);

  const config = await readConfigForRepo(repository);

  // 1. Watch Directory
  const watcher = chokidar.watch(repository, {
    ignored: [
      /(^|[/\\])\../, // ignore dotfiles
      "**/node_modules/**",
      "**/.git/**",
    ],
    persistent: true,
    ignoreInitial: true,
  });

  // Persist across sync cycles so we only notify once per newly-skipped binary.
  const skippedBinaries = new Set<string>();

  const sync = R.funnel(
    reportOnFailures(async () => {
      return await syncChanges(log, repository, config.commit_only, skippedBinaries);
    }),
    {
      minQuietPeriodMs: config.push_debounce_period_ms,
    },
  );

  watcher.on("all", (event, path) => {
    log.info(`[Watch] ${event}: ${path}`);
    sync.call();
  });

  // Initial Sync
  sync.call()

  const triggerCancels: (() => void)[] = [];

  const cancel = () => {
    watcher.close();
    for (const cancel of triggerCancels) {
      cancel();
    }
  };

  if (config.commit_only) {
    return cancel;
  }

  const pull = R.funnel(
    reportOnFailures(async () => {
      return await pullUpdates(log, repository, true);
    }),
    {
      minQuietPeriodMs: config.pull_debounce_period_ms,
    },
  );

  for (const trigger of config.pull_triggers) {
    if (trigger.type === "recurring") {
      const internvalID = setInterval(() => {
        log.info(`[Trigger] Recurring pull trigger fired.`);
        pull.call();
      }, trigger.after_every_seconds * 1000);
      triggerCancels.push(() => clearInterval(internvalID));
    } else if (trigger.type === "sse") {
      let url: string;
      if (R.isString(trigger.channel)) {
        url = trigger.channel;
      } else if ("ntfy_channel" in trigger.channel) {
        url = `https://ntfy.sh/${trigger.channel.ntfy_channel}/sse`;
      } else {
        throw new Error("Unimplemented");
      }

      triggerCancels.push(retryableEventSource(log, url, pull.call));
    }
  }


  log.info(`[Setup] Initialized watch for repository: ${repository}`);
  return cancel
}

// Reconnecting SSE stream for pull triggers. This used to log an `error`
// (→ critical notification) on *every* 5s retry, which was the single biggest
// source of "network down" spam: offline for an hour meant ~720 critical
// popups. Now failed reconnects use exponential backoff (capped) and are
// console-only `warn`; a notification is raised only once the stream has been
// down for a while (and then backs off further), at `normal` urgency. Any
// successful (re)connection or message resets everything.
const SSE_BASE_RETRY_MS = 5000;
const SSE_MAX_RETRY_MS = 5 * 60 * 1000; // cap backoff at 5 minutes

function retryableEventSource(
  log: Logger,
  url: string,
  onMessage: () => void,
): () => void {
  let eventSource: EventSource | null = null;
  let retryTimeout: Timer | null = null;
  let cancelled = false;
  let consecutiveErrors = 0;

  function connect() {
    if (cancelled) return;

    eventSource = new EventSource(url);

    eventSource.onopen = () => {
      if (consecutiveErrors > 0) {
        log.info(`[SSE] Reconnected to ${url}`);
      }
      consecutiveErrors = 0;
    };

    eventSource.onmessage = () => {
      log.info(`[SSE] Message received from ${url}`);
      consecutiveErrors = 0;
      onMessage();
    };

    eventSource.onerror = (err) => {
      if (eventSource) {
        eventSource.close();
        eventSource = null;
      }
      if (cancelled) return;

      consecutiveErrors++;
      const delay = Math.min(
        SSE_BASE_RETRY_MS * 2 ** (consecutiveErrors - 1),
        SSE_MAX_RETRY_MS,
      );

      if (isBackoffNotifyPoint(consecutiveErrors)) {
        // Persistent outage: surface once at normal urgency, then keep backing
        // off. Almost always "you're offline", so not critical.
        logger.error(
          `Pull-trigger stream down after ${consecutiveErrors} attempts (likely offline): ${url}`,
          { err, [notifyUrgencyKey]: "normal" },
        );
      } else {
        log.warn(`[SSE] Connection error (will retry in ${delay}ms):`, {
          url,
          err,
        });
      }

      retryTimeout = setTimeout(connect, delay);
    };
  }

  connect();

  // Return cancel function
  return () => {
    cancelled = true;
    if (retryTimeout) {
      clearTimeout(retryTimeout);
      retryTimeout = null;
    }
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }
  };
}

async function main(repositories: string[]) {
  logger.info(`Watching repositories:`);
  for (const repo of repositories) {
    logger.info(` - ${repo}`);
  }
  for (const repo of repositories) {
    try {
      await runContinousSync(repo);
    } catch (e) {
      if (e instanceof NonRetryableError) {
        // Misconfiguration (e.g. not a git repo). This genuinely needs the user
        // to act, so it *is* critical. Skip just this repo rather than letting
        // the rejection crash the daemon (which would stop syncing every other
        // repo and get restarted into the same failure by systemd).
        logger.error(`Cannot sync ${repo}: ${e.message}`, {
          [notifyUrgencyKey]: "critical",
        });
      } else {
        logger.error(`Failed to initialize sync for ${repo}:`, { e });
      }
    }
  }
}

const cmd = command({
  name: "git_syncer",
  description: "sync git repositories. You can configure sync by adding a .kit-sync.jsonc at root of git repository. See schema at root of this project.",
  version: "1.0.0",
  args: {
    mainRepository: positional({
      type: string,
      displayName: "respository",
      description: "Paths to git repositorie to sync",
    }),
    repositories: restPositionals({
      type: string,
      displayName: "...repositories",
    }),
    // eslint-disable-next-line @typescript-eslint/naming-convention
    notification_level: option({
      long: "notification_level",
      type: oneOf(LEVELS),
      description: "Logs above this level will be sent as notification",
      defaultValue: () => "error" as const,
    }),
  },
  handler: async (args) => {
    configureLogging(LogLevel[args.notification_level]);
    main([args.mainRepository, ...args.repositories]);
  },
});

run(cmd, process.argv.slice(2));
