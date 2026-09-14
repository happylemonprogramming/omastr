# Omastr

Nostr identity for [Omarchy](https://omarchy.org/), as an installable shell
plugin. The computer holds your key — your nsec lives in the Secret Service
keyring (gnome-keyring), encrypted at rest, unlocked with your login — and
apps reach it through Omastr instead of ever seeing it.

Shipped so far:

- **`omastr` CLI** — keyring-backed signing, publishing, encryption, relay
  queries, and `omastr run` for tools that need the raw key in their
  environment.
- **The bar ostrich** — a tinted silhouette chip; click it to open the wall,
  right-click for a health check. Its badge shows whatever number any Omastr
  piece writes to `~/.local/state/omastr/badge` (write `0` to clear — the
  watch does not survive the file being deleted).
- **The wall** — a Tenna-style overlay of tiles for your installed Nostr apps
  and nsites. Number keys tune to a channel; the plus tile will open the
  catalog once that phase lands.

Planned on the same core: a mentions/zaps/reactions notifications daemon, a
NIP-89 + nsite catalog, a localhost nsite gateway, and NIP-07/NIP-46 signer
doors with per-app, per-kind grants.

## Install

```sh
omarchy plugin add https://.../omarchy-nostr.git   # installs disabled; review it
omarchy plugin enable lemon.omastr
omarchy bar put lemon.omastr                        # the ostrich chip
```

On the next shell start you'll get a one-time notification; clicking it opens
the setup wizard. Or run it directly:

```sh
~/.config/omarchy/plugins/lemon.omastr/bin/omastr setup
```

Setup imports `$NSEC` from your environment if present, or prompts for the
key, then derives your pubkey and fetches your published kind 10002 relay
list into `~/.config/omastr/config.json`. It also symlinks the CLI to
`~/.local/bin/omastr`.

For a keybind that opens the wall, add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + N", "Omastr", "omarchy-shell shell toggle lemon.omastr")
```

### Dependencies

`secret-tool`, `gum`, and `jq` ship with Omarchy. You also need
[`nak`](https://github.com/fiatjaf/nak):

```sh
omarchy pkg aur add nak-bin
```

## Usage

```sh
omastr status                # health check (add --network to ping a relay)
omastr pubkey --npub         # your npub
omastr relays read           # configured relay URLs
omastr req -k 1 -l 10        # nak req over your read relays, NIP-42 authed
echo '{"kind":1,"content":"hi"}' | omastr sign      # sign, don't publish
echo '{"kind":1,"content":"hi"}' | omastr publish   # sign + send to write relays
omastr encrypt -p <pubkey> "secret"                 # NIP-44 (add --nip04 for legacy)
omastr run -- npx -y @shakespeare.diy/cli deploy my-app
```

`run` is the escape hatch for tools that insist on a raw key in the
environment: it fetches the nsec from the keyring and sets it (as `NSEC`, or
`--var NOSTR_SECRET_KEY`) only on that one child process — not your whole
session. Bare `omastr run` prints usage and never the key.

No command ever prints the key, and it is never passed as an argument
(argv is world-readable via `ps`; a child's environment is not).

## The wall file

Tiles live in `~/.config/omastr/wall.json`, a JSON array in wall order:

```json
[
  { "id": "ditto", "name": "Ditto", "icon": "/path/or/https-url.png",
    "exec": ["omarchy-launch-webapp", "https://ditto.pub"] }
]
```

The overlay watches the file and redraws on change. The catalog phase will
write it for you; until then it's hand-editable.

## File layout

| Path | Purpose |
|---|---|
| `~/.config/omarchy/plugins/lemon.omastr/` | this plugin (code only, replaced on update) |
| `~/.local/bin/omastr` | symlink created by setup so the CLI is on PATH |
| gnome-keyring (`service=omastr`) | the nsec |
| `~/.config/omastr/config.json` | pubkey + relay list (public data) |
| `~/.config/omastr/wall.json` | the wall's tiles |
| `~/.local/state/omastr/` | badge, cursors, grants (later phases) |
| `~/.cache/omastr/` | profile/icon caches (later phases) |

Upgrading from the pre-rename `omarchy-nostr` layout is automatic: the first
`omastr` invocation moves the config/state/cache dirs and re-keys the keyring
entry.

## Uninstall

```sh
~/.config/omarchy/plugins/lemon.omastr/bin/omastr uninstall
omarchy plugin remove lemon.omastr
```

The first removes the key and all config/state/cache; the second removes the
code. Nothing else on the system is touched.
