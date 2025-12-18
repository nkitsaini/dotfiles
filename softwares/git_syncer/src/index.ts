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

/** Main Sync Function */
async function syncChanges(log: Logger, repository: string, commitOnly = false) {
  log.info("[Sync] Processing changes...");
  try {
    if (!commitOnly) {
      await pullUpdates(log, repository);
    }

    // 1. Get Status
    const statusOutput = await runCommand(
      ["git", "status", "--porcelain"],
      repository,
    );
    if (!statusOutput.trim()) {
      log.info("[Sync] No changes to commit.");
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

    // 3. Handle Binaries
    if (binaryFiles.length > 0) {
      const msg = `Skipped ${binaryFiles.length} binary file(s):\n${binaryFiles.slice(0, 3).join("\n")}${binaryFiles.length > 3 ? "..." : ""}`;
      log.error(msg);
    }

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
  } catch (error) {
    log.error("[Sync] Error during sync:", {error});
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

function reportOnFailures(fn: () => Promise<void>): () => Promise<void> {
  const syncErrors: unknown[] = [];
  return async () => {
    try {
      await fn();
    } catch (e) {
      syncErrors.push(e);
      if (syncErrors.length >= 5) {
        logger.error(`Too many errors occurred during syncs.`, {e});
        syncErrors.length = 0;
      } else {
        logger.warn(`Error occurred during sync:`, {e});
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

  const sync = R.funnel(
    reportOnFailures(async () => {
      return await syncChanges(log, repository, config.commit_only);
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

function retryableEventSource(
  log: Logger,
  url: string,
  onMessage: () => void,
): () => void {
  let eventSource: EventSource | null = null;
  let retryTimeout: Timer | null = null;
  let cancelled = false;

  function connect() {
    if (cancelled) return;

    eventSource = new EventSource(url);

    eventSource.onmessage = () => {
      log.info(`[SSE] Message received from ${url}`);
      onMessage();
    };

    eventSource.onerror = (err) => {
      log.error(`[SSE] Connection error (will retry):`, { url, err});
      if (eventSource) {
        eventSource.close();
        eventSource = null;
      }
      if (!cancelled) {
        retryTimeout = setTimeout(connect, 5000); // Retry after 5 seconds
      }
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
    await runContinousSync(repo);
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
