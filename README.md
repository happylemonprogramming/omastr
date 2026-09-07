# omarchy-nostr

Nostr identity for [Omarchy](https://omarchy.org/), as an installable shell
plugin. Your nsec lives in the Secret Service keyring (gnome-keyring) —
encrypted at rest, unlocked with your login — instead of an `export NSEC=...`
that every process you launch can read.

Current (Phase 0): the `omarchy-nostr` core CLI plus a first-run nudge from
the shell. Planned on top of it: a mentions/zaps/reactions notifications
daemon, a NIP-89 app store TUI, and a NIP-07 browser signer via native
messaging — all thin clients of the same core, so key policy lives in one
file.

## Install

```sh
omarchy plugin add https://.../omarchy-nostr.git   # installs disabled; review it
omarchy plugin enable lemon.nostr
```

On the next shell start you'll get a one-time notification; clicking it opens
the setup wizard. Or run it directly:

```sh
~/.config/omarchy/plugins/lemon.nostr/bin/omarchy-nostr setup
```

Setup imports `$NSEC` from your environment if present (your migration path),
or prompts for the key, then derives your pubkey and fetches your published
kind 10002 relay list into `~/.config/omarchy-nostr/config.json`.

### Dependencies

`secret-tool`, `gum`, and `jq` ship with Omarchy. You also need
[`nak`](https://github.com/fiatjaf/nak) on your PATH
(`omarchy pkg aur add nak`, or `go install github.com/fiatjaf/nak@latest`).

## Usage

```sh
omarchy-nostr status                # health check (add --network to ping a relay)
omarchy-nostr pubkey --npub         # your npub
omarchy-nostr relays read           # configured relay URLs
omarchy-nostr req -k 1 -l 10        # nak req over your read relays, NIP-42 authed
echo '{"kind":1,"content":"hi"}' | omarchy-nostr sign      # sign, don't publish
echo '{"kind":1,"content":"hi"}' | omarchy-nostr publish   # sign + send to write relays
omarchy-nostr encrypt -p <pubkey> "secret"                  # NIP-44 (add --nip04 for legacy)
omarchy-nostr exec -- npx -y @shakespeare.diy/cli deploy my-app
```

`exec` is the escape hatch for tools that insist on a raw key in the
environment: it fetches the nsec from the keyring and sets it (as `NSEC`, or
`--var NOSTR_SECRET_KEY`) only on that one child process — not your whole
session.

No command ever prints the key, and it is never passed as an argument
(argv is world-readable via `ps`; a child's environment is not).

## File layout

| Path | Purpose |
|---|---|
| `~/.config/omarchy/plugins/lemon.nostr/` | this plugin (code only, replaced on update) |
| `~/.local/bin/omarchy-nostr` | symlink created by setup so the CLI is on PATH |
| gnome-keyring (`service=omarchy-nostr`) | the nsec |
| `~/.config/omarchy-nostr/config.json` | pubkey + relay list (public data) |
| `~/.local/state/omarchy-nostr/` | cursors, grants (later phases) |
| `~/.cache/omarchy-nostr/` | profile caches (later phases) |

## Uninstall

```sh
~/.config/omarchy/plugins/lemon.nostr/bin/omarchy-nostr uninstall
omarchy plugin remove lemon.nostr
```

The first removes the key and all config/state/cache; the second removes the
code. Nothing else on the system is touched.
