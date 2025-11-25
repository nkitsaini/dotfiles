import { spawn } from "bun";
import { join } from "path";
import chokidar from "chokidar"; // Standard for watching on Linux
import { EventSource } from "eventsource";

import {
	command,
	run,
	string,
	number,
	positional,
	oneOf,
	option,
	optional,
} from "cmd-ts";

// --- Helper Functions ---

type NotificationLevel = "critical" | "normal";
let NOTIFICATION_LEVEL: NotificationLevel = "critical";
/** Sends a desktop notification using notify-send */
async function sendNotification(
	title: string,
	message: string,
	level: NotificationLevel = "normal",
) {
	if (level !== "critical" || NOTIFICATION_LEVEL === "critical") {
		console.log("Ignoring non-critical notification.", {
			level,
			title,
			message,
		});

		return;
	}
	try {
		await spawn(["notify-send", "-u", level, title, message]).exited;
	} catch (e) {
		console.error("Failed to send notification:", e);
	}
}

/** execute a shell command and return stdout or throw error */
async function runCommand(cmd: string[], cwd?: string) {
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
async function syncChanges(directory: string) {
	console.log("[Sync] Processing changes...");
	try {
		await pullUpdates();

		// 1. Get Status
		const statusOutput = await runCommand(["git", "status", "--porcelain"]);
		if (!statusOutput.trim()) {
			console.log("[Sync] No changes to commit.");
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

			if (await isBinaryFile(join(directory, filePath))) {
				binaryFiles.push(filePath);
			} else {
				filesToAdd.push(filePath);
			}
		}

		// 3. Handle Binaries
		if (binaryFiles.length > 0) {
			const msg = `Skipped ${binaryFiles.length} binary file(s):\n${binaryFiles.slice(0, 3).join("\n")}${binaryFiles.length > 3 ? "..." : ""}`;
			console.warn(msg);
			await sendNotification("Binary Files Detected", msg, "critical");
		}

		// 4. Commit & Push
		if (filesToAdd.length > 0) {
			await runCommand(["git", "add", ...filesToAdd]);
			await runCommand([
				"git",
				"commit",
				"-m",
				`Auto-sync: ${new Date().toISOString()}`,
			]);
			console.log(`[Sync] Committed ${filesToAdd.length} files.`);

			await runCommand(["git", "push"]);
			console.log("[Sync] Pushed to remote.");
			await sendNotification("Git Sync", "Changes pushed successfully.");
		} else {
			console.log("[Sync] No non-binary files to add.");
		}
	} catch (error: any) {
		console.error(error);
		await sendNotification(
			"Git Sync Error",
			error.message || "Unknown error",
			"critical",
		);
	}
}

/** Pull updates from remote */
async function pullUpdates() {
	console.log("[Remote] Received update signal.");
	try {
		await runCommand(["git", "pull"]);
		console.log("[Remote] Pulled successfully.");
		await sendNotification("Git Sync", "Remote changes pulled.");
	} catch (error: any) {
		await sendNotification(
			"Git Pull Error",
			error.message || "Unknown error",
			"critical",
		);
	}
}

// --- Event Listeners ---

async function main(
	directory: string,
	cooldown_ms: number,
	ntfy_channel: string,
) {
	console.log(`[Watcher] Started in ${directory}`);
	console.log(`[Watcher] Listening to ntfy.sh/${ntfy_channel}`);

	// Change working directory to the git repo
	process.chdir(directory);

	// Verify it's a git repository
	await runCommand(["git", "rev-parse", "--is-inside-work-tree"]);

	let debounceTimer: Timer | null = null;

	// 1. Watch Directory
	const watcher = chokidar.watch(directory, {
		ignored: [
			/(^|[\/\\])\../, // ignore dotfiles
			"**/node_modules/**",
			"**/.git/**",
		],
		persistent: true,
		ignoreInitial: true,
	});

	function syncChangesDebounced() {
		// Debounce logic
		if (debounceTimer) clearTimeout(debounceTimer);

		debounceTimer = setTimeout(() => {
			syncChanges(directory);
			debounceTimer = null;
		}, cooldown_ms);
	}
	watcher.on("all", (event, path) => {
		console.log(`[Watch] ${event}: ${path}`);
		syncChangesDebounced();
	});

	// 2. Listen to ntfy.sh
	const eventSource = new EventSource(`https://ntfy.sh/${ntfy_channel}/sse`);

	eventSource.onmessage = (event) => {
		// ntfy sends data, we treat any message as a signal to pull
		const data = JSON.parse(event.data);
		// Ignore our own notifications if you were sending them to this topic
		// For now, just pull on any message
		pullUpdates();
	};

	eventSource.onerror = (err) => {
		console.error("[Ntfy] Connection error, retrying...", err);
	};

	syncChangesDebounced(); // Initial sync on startup
}

const cmd = command({
	name: "my-command",
	description: "print something to the screen",
	version: "1.0.0",
	args: {
		git_directory: positional({ type: string }),
		ntfy_channel: option({
			long: "ntfy-channel",
			type: optional(string),
			description: "ntfy.sh channel to listen to for remote updates",
		}),
		notification_level: option({
			long: "notification_level",
			type: oneOf(["normal", "critical"] as const),
			defaultValue: () => "critical" as const,
		}),
		ntfy_channel_file: option({
			long: "ntfy-channel-file",
			type: string,
			description: "File containing ntfy.sh channel name",
		}),
		cooldown_ms: option({
			long: "cooldown-ms",
			type: number,
			defaultValue: () => 5_000, // 5 second
			description: "Cooldown period in milliseconds to batch file changes",
		}),
	},
	handler: async (args) => {
		if (args.ntfy_channel_file && args.ntfy_channel) {
			throw new Error("Cannot specify both ntfy_channel and ntfy_channel_file");
		}
		if (args.ntfy_channel_file) {
			const file = Bun.file(args.ntfy_channel_file);
			if (!(await file.exists())) {
				throw new Error(
					`ntfy channel file '${args.ntfy_channel_file}' does not exist`,
				);
			}
			args.ntfy_channel = (await file.text()).trim();
		}
		if (!args.ntfy_channel) {
			throw new Error("ntfy channel must be specified (see help)");
		}
		NOTIFICATION_LEVEL = args.notification_level;
		main(args.git_directory, args.cooldown_ms, args.ntfy_channel);
	},
});

run(cmd, process.argv.slice(2));
