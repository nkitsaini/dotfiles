// Needs to be manually registered using:
// 
// autocmd TriStart .* js -s -r ./autoclose.js
// autocmd DocStart .* js -s -r ./autoclose.js

const TAB_LIMIT = 3;

declare const tri: any;
type CWindow = typeof window & {auto_tab_closer_tridactyl?: AutoCloser};

const win: CWindow = window;


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
		if (win.auto_tab_closer_tridactyl) {
			win.auto_tab_closer_tridactyl.delete()
			// throw new Error("[AutoTabCloser] Already Registered");
		}
		win.auto_tab_closer_tridactyl = new AutoCloser(inactivityDuration);
	}

	#attachListeners() {
		document.addEventListener("visibilitychange", this.#listener);
	}

	async currentWindowClosableTabs() {
		let windowTabs = await tri.browserBg.tabs.query({currentWindow: true,
		});
		let answer: any[] = [];
		for (const t of windowTabs) {
			if (await this.#safeToClose(t)) {
				answer.push(t);
			}
		}
		return answer.length;
		
	}

	async #resetTimeout() {
		if (this.#timeout !== null) {
			clearTimeout(this.#timeout);
			this.#timeout = null;
		}

		let tab = await this.#ownTab()
		if (!(await this.#safeToClose(tab))) {
			log("Tab is not safe to close. Ignoring.")
			return
		}
		if (this.#isInactive) {
			let openTabs = await this.currentWindowClosableTabs();
			if (openTabs <= TAB_LIMIT) {
				log(`Only ${openTabs} extra tabs open. Will recheck in 5 minutes.`);
			this.#timeout = setTimeout(() => this.#resetTimeout(), 5 * 1000);

				return
				
			}
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

	async #safeToClose(tab) {
		let sharingState = tab.sharingState;
		if (tab.pinned || tab.audible || sharingState?.camera || sharingState?.micrphone || sharingState?.screen) {
			return false
		}
		return true
	}

	async #closeTab() {
		let tab = await this.#ownTab()
		if (!(await this.#safeToClose(tab))) {
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
		delete win.auto_tab_closer_tridactyl;
	}
}

// for debugging
// window.AutoCloser = AutoCloser;
AutoCloser.register();

