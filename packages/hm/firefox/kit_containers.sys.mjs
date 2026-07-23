// Injected into browser/omni.ja as resource:///modules/KitContainers.sys.mjs
// by the firefox_patched derivation in ./default.nix.
//
// Resolves this machine's default container (pref "kit.containers.default",
// holding a container *name*, set per host via the home-manager option
// `kit.firefox.defaultContainer`) to a numeric userContextId.
//
// Returns 0 ("no container") whenever the feature should stay inert: pref
// unset, containers disabled, private window, or the name not found
// unambiguously. A 0 produces stock Firefox behavior, and a missing container
// is immediately visible as a badge-less tab (fail visible, never fail wrong).

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  ContextualIdentityService:
    "resource://gre/modules/ContextualIdentityService.sys.mjs",
  PrivateBrowsingUtils: "resource://gre/modules/PrivateBrowsingUtils.sys.mjs",
});

export const KitContainers = {
  defaultUserContextId(win = null) {
    try {
      const name = Services.prefs.getStringPref("kit.containers.default", "");
      if (!name) {
        return 0;
      }
      if (!Services.prefs.getBoolPref("privacy.userContext.enabled", false)) {
        return 0;
      }
      if (win && lazy.PrivateBrowsingUtils.isWindowPrivate(win)) {
        return 0;
      }
      // getUserContextLabel returns the user-set name for user-created
      // containers and the localized label for built-in ones (Personal, ...).
      const label = identity =>
        lazy.ContextualIdentityService.getUserContextLabel(
          identity.userContextId
        );
      const identities = lazy.ContextualIdentityService.getPublicIdentities();
      let matches = identities.filter(i => label(i) === name);
      if (matches.length === 0) {
        matches = identities.filter(
          i => label(i).toLowerCase() === name.toLowerCase()
        );
      }
      // Ambiguous (e.g. both "work" and "Work" exist) -> 0, not a guess.
      return matches.length === 1 ? matches[0].userContextId : 0;
    } catch (e) {
      console.error("KitContainers: failed to resolve default container", e);
      return 0;
    }
  },
};
