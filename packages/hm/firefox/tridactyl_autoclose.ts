// Register using:
// 
// autocmd TriStart .* js -s -r ./autoclose.js
// autocmd DocStart .* js -s -r ./autoclose.js

declare const tri: any;

function log(msg: string) {
	console.log(`[AutoTabCloser] ${msg}`);
}

type TimestampMs = number;
type TimeoutID = number;

function assert(value: any): asserts value {
	if (!value) {
		throw new Error("Assertion error");
	}
}

class AutoCloser {
	#openedAt: TimestampMs;
	#timeout: TimeoutID | null = null;
	#isInactive: boolean;
	#listener: () => void;
	lastActiveAt: TimestampMs | null;
	inactivityDuration: TimestampMs

	constructor(
		inactivityDuration: TimestampMs = 1000 * 60 * 20 /* 20 minutes */,
	) {
		this.#openedAt = Date.now();
		this.#isInactive = document.hidden;
		if (this.#isInactive) {
			this.lastActiveAt = this.#openedAt;
		} else {
			this.lastActiveAt = null;
		}
		this.inactivityDuration = inactivityDuration

		this.#listener = () => {
			this.#isInactive = document.hidden;
			log(`inactive: ${this.inactivityDuration}`);
			if (this.#isInactive && this.lastActiveAt === null) {
				this.lastActiveAt = Date.now();
			} else if (!document.hidden) {
				this.lastActiveAt = null;
			}
			this.#resetTimeout();
		};
		log(`Registering at ${new Date(this.#openedAt)}`);
		this.#attachListeners();
		this.#resetTimeout()
	}

	static register(inactivityDuration?: TimestampMs) {
		if (window.auto_tab_closer_tridactyl) {
			window.auto_tab_closer_tridactyl.delete()
			// throw new Error("[AutoTabCloser] Already Registered");
		}
		window.auto_tab_closer_tridactyl = new AutoCloser(inactivityDuration);
	}

	#attachListeners() {
		document.addEventListener("visibilitychange", this.#listener);
	}

	async #resetTimeout() {
		if (this.#timeout !== null) {
			clearTimeout(this.#timeout);
			this.#timeout = null;
		}
		if (!(await this.#safeToClose())) {
			log("Tab is not safe to close. Ignoring.")
			return
		}
		if (this.#isInactive) {
			assert(this.lastActiveAt !== null);
			let closeTime = this.lastActiveAt + this.inactivityDuration;
			let timeRemaining =
				this.lastActiveAt + this.inactivityDuration - Date.now();
			log(`Inactive. Will close at ${new Date(closeTime)}`);
			this.#timeout = setTimeout(() => this.#closeTab(), timeRemaining);
		} else {
			log(`Active. won't close`);
		}
	}

	async #ownTab() {
		return await tri.webext.ownTab();
	}

	async #safeToClose() {
		let tab = await this.#ownTab()

		let sharingState = tab.sharingState;
		if (tab.pinned || tab.audible || sharingState?.camera || sharingState?.micrphone || sharingState?.screen) {
			return false
		}
		return true
	}

	async #closeTab() {
		if (!(await this.#safeToClose())) {
			log("Tab is not safe to close. Ignoring.")
			return
		}
		tri.browserBg.tabs.remove((await this.#ownTab()).id);
	}

	delete() {
		if (this.#timeout !== null) {
			clearTimeout(this.#timeout);
		}
		document.removeEventListener("visibilitychange", this.#listener);
		delete window.auto_tab_closer_tridactyl;
	}
}

// for debugging
// window.AutoCloser = AutoCloser;
AutoCloser.register();

