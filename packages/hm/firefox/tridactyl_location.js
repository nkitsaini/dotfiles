(function () {
	// This function contains the code that must run IN THE PAGE context
	// It cannot see variables defined outside of it.
	const spoofLogic = function () {
		// Modify these however you like
		// const FAKE_LAT = 48.8566; // Eiffel Tower
		// const FAKE_LON = 2.3522;
		const FAKE_LAT = 19.1162575; // Mumbai
		const FAKE_LON = 72.9109137;

		const FAKE_ACCURACY = 20;

		const makeCoords = () => ({
			latitude: FAKE_LAT,
			longitude: FAKE_LON,
			altitude: null,
			accuracy: FAKE_ACCURACY,
			altitudeAccuracy: null,
			heading: null,
			speed: null,
		});

		// 1. Mock Permissions
		const mockPermissions = {
			query: async function (descriptor) {
				// console.log("Spoofing permissions...");
				return { state: "granted", onchange: null, name: descriptor.name };
			},
		};

		// 2. Mock Geolocation
		const mockGeo = {
			getCurrentPosition: function (success, error, options) {
				// console.log("Spoofing getCurrentPosition...");
				setTimeout(() => {
					if (success) success({ coords: makeCoords(), timestamp: Date.now() });
				}, 100);
			},
			watchPosition: function (success, error, options) {
				// console.log("Spoofing watchPosition...");
				const id = Math.floor(Math.random() * 10000);
				setTimeout(() => {
					if (success) success({ coords: makeCoords(), timestamp: Date.now() });
				}, 100);
				setInterval(() => {
					if (success) success({ coords: makeCoords(), timestamp: Date.now() });
				}, 5000);
				return id;
			},
			clearWatch: function (id) {},
		};

		try {
			// Apply overrides
			if (navigator.permissions) {
				Object.defineProperty(navigator.permissions, "query", {
					value: mockPermissions.query,
					configurable: true,
				});
			}
			Object.defineProperty(navigator, "geolocation", {
				value: mockGeo,
				configurable: false,
				writable: false,
			});

			// console.log("Tridactyl: Spoof injected into PAGE context successfully.");
		} catch (e) {
			console.error("Tridactyl injection failed:", e);
		}
	};

	// --- INJECTOR CODE (Runs in Tridactyl Sandbox) ---
	// We convert the function above to a string and inject it into the DOM
	const script = document.createElement("script");
	script.textContent = "(" + spoofLogic.toString() + ")();";

	// Inject into documentElement because 'head' might not exist yet at DocStart
	(document.head || document.documentElement).appendChild(script);

	// Clean up the tag so it doesn't leave clutter
	script.remove();
})();
