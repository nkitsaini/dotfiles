# radioctl

`radioctl` is a fast Linux terminal interface for Wi-Fi and Bluetooth. It talks
to the system daemons over their native D-Bus APIs and treats those daemons as
the authority: a request being accepted is never displayed as a successful
connection until the daemon reports the final state.

## Everyday use

- `Enter` connects the selected item; on an already connected item it
  disconnects. During a pending connection, `Enter` reverses the request.
- `j`/`k` or the arrow keys move, `g`/`G` select the first/last row, and `Tab`
  changes radio panes.
- `s` scans or toggles Bluetooth discovery, `/` filters, `Ctrl-P` opens the
  capability-aware command palette, `l` opens the activity journal, and `e`
  explains the current error and its recovery steps.
- Focus follows the stable network/device identity even when connection state
  or signal changes move its row. Mouse clicks use the actual scrolled offset.
- No patched font is required.

The list separates observed state (`connected`, `getting IP`, and so on) from a
pending request (`waiting→connected`). Saved Wi-Fi networks and paired or trusted
Bluetooth devices remain visible as `out of range` and sort below devices that
are currently present. Unsaved transient entries receive a short grace period,
which prevents scan snapshots from making the list flicker.

## Backends

`--backend auto` selects the highest-level daemon that exposes a usable Wi-Fi
interface and fails over when its owner disappears:

| Backend | D-Bus service | Notes |
| --- | --- | --- |
| NetworkManager | `org.freedesktop.NetworkManager` | Preferred; connectivity checks, saved profiles, radio control |
| ConnMan | `net.connman` | Native Technology/Service APIs and temporary credential agent |
| iwd | `net.connman.iwd` | Native Station/Network APIs and non-displacing credential agent |
| wpa_supplicant + networkd | `fi.w1.wpa_supplicant1`, `org.freedesktop.network1` | Association and IP configuration are reported separately |
| BlueZ | `org.bluez` | Bluetooth adapters/devices through ObjectManager |

Use `--backend network-manager`, `iwd`, `wpa-networkd`, or `conn-man` to require
one Wi-Fi implementation. `--wifi-interface wlan0` and
`--bluetooth-adapter hci0` disambiguate multi-radio machines.

The implementation follows the upstream [iwd Station and Network
APIs](https://kernel.googlesource.com/pub/scm/network/wireless/iwd/+/master/doc/station-api.txt),
[wpa_supplicant D-Bus API](https://w1.fi/wpa_supplicant/devel/dbus.html), and
[ConnMan Service API](https://kernel.googlesource.com/pub/scm/network/connman/connman/+/master/doc/service-api.txt).

Known constraints are surfaced instead of guessed:

- Creating a new enterprise/802.1X profile needs identity, EAP, and certificate
  choices. Provision it with the owning daemon first; radioctl can then activate
  it.
- iwd exposes SSIDs as D-Bus strings, so iwd cannot preserve invalid UTF-8 SSID
  bytes. NetworkManager, wpa_supplicant, and ConnMan identities preserve raw
  bytes.
- networkd route state is not an Internet probe. The combined backend reports
  it as local/limited, never as verified Internet.
- wpa_supplicant has no radio-power D-Bus method; that command is omitted from
  the palette for that backend.

## Diagnostics and logs

Run:

```console
radioctl diagnose
radioctl diagnose --json
```

Diagnostics show D-Bus owners, versions when exposed, backend epochs, interface
filters, and actionable warnings. The TUI exposes the same report through
`Ctrl-P` → `Open diagnostics`.

Every invocation writes a unique per-session log below
`$XDG_STATE_HOME/radioctl/logs` (normally
`~/.local/state/radioctl/logs`). Ten sessions are retained. `--log-file PATH`
overrides the destination. Credentials use zeroizing storage, redact `Debug`,
and low-level D-Bus trace bodies are forcibly disabled even with a broad tracing
filter.

Optional configuration lives at `$XDG_CONFIG_HOME/radioctl/config.toml`:

```toml
backend = "auto"
wifi_interface = "wlan0"
bluetooth_adapter = "hci0"
auto_scan = true
log_level = "radioctl=info"
```

Unknown configuration keys are rejected rather than silently ignored.

## Build and verification

```console
nix develop
cargo test --all-features --all-targets
cargo clippy --all-features --all-targets -- -D warnings
cargo run --release
```

`nix build` produces the release binary. A focused local NixOS/QEMU test boots
real NetworkManager and BlueZ services and validates the machine-readable
diagnostics path:

```console
nix build .#checks.x86_64-linux.daemon-integration
```

The deterministic simulator and reducer tests cover stale/reordered events,
daemon epochs, superseded operations, confirmation timeouts, stable focus,
credential redaction, tiny terminals, and backend selection failover.

## Architecture

The UI emits intents. A runtime routes them to one owning backend. Backends emit
versioned snapshots and health events. A pure reducer rejects stale revisions,
reconciles operations against facts, and owns the state rendered by the TUI.
Signal bursts are coalesced before bounded-concurrency snapshots; a lagged event
consumer forces a fresh authoritative snapshot. Service owner changes increment
an epoch so replies from a previous daemon process cannot win a race.
