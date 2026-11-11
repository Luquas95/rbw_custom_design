# rbw_custom_design

[![Release](https://img.shields.io/github/v/release/Luquas95/rbw_custom_design)](https://github.com/Luquas95/rbw_custom_design/releases)
[![Platform](https://img.shields.io/badge/platform-Sway%20%2F%20wlroots-blue?logo=linux&logoColor=white)](https://swaywm.org/)
[![Shell](https://img.shields.io/badge/language-bash-green)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-yellow)](https://opensource.org/license/MIT)
[![Stars](https://img.shields.io/github/stars/Luquas95/rbw_custom_design?style=social)](https://github.com/Luquas95/rbw_custom_design)

A custom Bitwarden menu built on top of [`rbw`](https://github.com/doy/rbw) (the
unofficial Bitwarden CLI) for Sway/wlroots, using
[`walker`](https://github.com/abenz1267/walker) +
[`elephant`](https://github.com/abenz1267/elephant) (the `elephant-bitwarden`
provider), with a black-and-green "retro" look.

A keybinding opens a floating window listing folders, with live fuzzy search
across the whole vault; from an entry you can copy the password/username/TOTP,
edit it, or delete it. `rbw` stays the single source of truth (vault, sync,
locking) — this repo is just a UI layer on top of it.

![Screenshot of the menu (folder view, fake demo data)](docs/screenshot.png)

## Architecture

```
$mod+b (Sway)
  -> bin/bitwarden-launcher
       -> bin/bitwarden-generate-menus   (rbw unlock; rbw list --raw -> TOML menu
                                          files for elephant; then restarts
                                          elephant.service — see "Known issues")
       -> walker -s bitwarden
            - empty field  = static menu (folders, generated above)
            - typing       = fuzzy search in the flat `bitwarden-all` menu (also
                             generated above), so Enter on a hit opens the same
                             per-entry submenu (copy password/username/TOTP,
                             edit, delete) as in the folder view
```

Actions on an entry (copy password/username/TOTP, edit, delete) call
`bin/bitwarden-menu-copy <id> <action>`, which does a direct `rbw get`/
`rbw code`/`rbw remove` call and sends the password to the clipboard via
`wl-copy` (auto-clearing the clipboard after 45s for passwords).

`bin/rbw-rofi-menu` is an older alternative frontend (rofi script-mode
instead of walker) — functional, but currently not wired to any keybinding.
Kept for reference/completeness.

## Dependencies

- `rbw` (Bitwarden CLI) + `pinentry-gtk`
- `walker` + `elephant` (`elephant.service` as a `systemctl --user` service)
  + the AUR package `elephant-bitwarden` (provides the `bitwarden` provider)
- `jq`, `wl-clipboard`, `iconv` (`glibc`)
- Sway/wlroots (the floating rule in `sway/rbw-bitwarden.conf` is Sway-specific)

## Installation

1. Copy `bin/*` to `~/.local/bin/` (keep them executable; `.bitwarden-lib.sh`
   and `.bitwarden-editor-fill` must keep their leading dot — they're sourced
   by exact name).
2. Copy `themes/pinentry-green/gtk-3.0/gtk.css` to
   `~/.themes/pinentry-green/gtk-3.0/gtk.css`.
3. Add `sway/rbw-bitwarden.conf` to `~/.config/sway/config` (include it or
   copy its contents in manually).
4. Use `rbw/config.example.json` as a template for `~/.config/rbw/config.json`
   (fill in your own email; `"pinentry": "pinentry-rbw"` is the important
   part — see below).
5. Copy `systemd/rbw-agent.service` to `~/.config/systemd/user/` and
   `systemd/elephant.service.d/rbw-agent.conf` to
   `~/.config/systemd/user/elephant.service.d/`. **Don't skip this** — without
   its own unit, `rbw-agent` ends up inside `elephant.service`'s cgroup and
   gets killed on every elephant restart (issue 1 below).
6. In `~/.config/walker/config.toml`, make typing search the flat menu:

   ```toml
   [providers.sets.bitwarden]
   default = ["menus:bitwarden-all"]
   empty = ["menus:bitwarden-folders"]
   ```

   (Pointing `default` at the `bitwarden` provider instead gives search
   results without the submenu: Enter on a hit does nothing unless you bind
   it to a provider action yourself.)
7. `rbw config set email <your-email>`, `rbw login`, then
   `systemctl --user daemon-reload` and
   `systemctl --user enable --now rbw-agent.service elephant.service`.

## Known issues, and why the scripts look the way they do

Four independent bugs that all looked the same from the outside ("after
unlocking rbw, search/login stops working"):

### 1. `rbw-agent` inherits `elephant.service`'s cgroup and dies with it

**Symptom:** the master password prompt keeps reappearing. You type the
correct password, it's rejected, and after a few attempts it finally works —
with *another* password prompt visible behind the unlocked window.

**Cause:** `rbw-agent` is auto-started on the first `rbw` call and inherits
the **cgroup of whoever started it**. The first `rbw` call after login is
usually `rbw list` from the elephant `bitwarden` provider's init, so the agent
lands in `elephant.service`'s cgroup — which uses the default
`KillMode=control-group`. Every `systemctl --user restart elephant.service`
therefore kills `rbw-agent`. Verify with:

```
systemctl --user status elephant.service   # rbw-agent listed as a child = bug
cat /proc/$(pgrep -x rbw-agent)/cgroup     # must say rbw-agent.service
```

The loop: unlock (prompt 1) -> script restarts elephant -> agent killed ->
vault locked -> new elephant calls `rbw list` -> starts a new, *locked* agent
-> prompt 2 appears behind the first. No unlock could ever survive. The
`panicked ... Broken pipe` entries in `~/.local/share/rbw/agent.err` and the
`ssh_agent_lib ... Listening` line appearing in the same second as an elephant
restart are symptoms of this, not the cause.

**Fix:** `systemd/rbw-agent.service` gives the agent its own cgroup
(`Type=forking`, since `rbw-agent` ignores arguments and always daemonizes
itself). `systemd/elephant.service.d/rbw-agent.conf` adds `Wants=`/`After=`
so the agent is already running before the provider first calls it —
otherwise `rbw list` would start it into elephant's cgroup again.

Verified: `rbw-agent`'s PID is identical before and after
`systemctl --user restart elephant.service`, and only the short-lived
`rbw list` client remains in elephant's cgroup.

### 2. `elephant-bitwarden` permanently returns 0 results after an auto-lock

(Search no longer goes through this provider — it uses the generated
`bitwarden-all` menu — but the provider is still loaded by elephant and the
unconditional restart below is kept so it never sits on a stale vault.)

`elephant.service` runs persistently in the background, and its `bitwarden`
provider holds its own connection to `rbw-agent`, established at the moment
the vault was last locked. After re-unlocking (`rbw` has a `lock_timeout`),
this connection doesn't refresh itself — the static folder menu still works
(it's regenerated fresh via `rbw list`), but live search permanently reports
0 results until `elephant.service` is restarted.

**Fix:** `bin/bitwarden-generate-menus` therefore ALWAYS (not conditionally)
ends with `systemctl --user restart elephant.service`. It lives there rather
than in the launcher so that `bin/bitwarden-sync` gets the same behaviour from
one place. The restart is unconditional because the provider only reads the
vault once at startup: if it was locked back then it stays permanently empty,
and a running script can't tell that happened — so making the restart
conditional on "did we just unlock" does not close the hole.

This costs ~1-2s per open, and it is only harmless because of issue 1 above:
with `rbw-agent` in its own cgroup the restart no longer locks the vault, so
it triggers no password prompt.

### 3. `pinentry-gtk` can't unlock the vault on Sway/wlroots

Two independent causes, both fixed by `bin/pinentry-rbw` (the wrapper that
`"pinentry"` in `rbw config.json` points to):

- **Global X11 grab.** `pinentry-gtk` grabs the keyboard/pointer globally by
  default (via XWayland), which conflicts on wlroots compositors ("could not
  grab keyboard: already grabbed", "it took 4097 tries to grab the pointer")
  and the unlock ends up as "pinentry cancelled". Fixed with
  `--no-global-grab` (grabs only while the window is focused).

- **`rbw-agent` always passes `--display :1`.** Even with `--no-global-grab`,
  window mapping still failed if `rbw-agent` (inheriting `$DISPLAY` from its
  own startup) passed pinentry an explicit `--display`, forcing GTK onto the
  X11/XWayland backend instead of native Wayland — the window then never
  mapped at all (verified by direct comparison: 0 mapped windows with
  `--display`, always 1 without it). The wrapper filters this flag out and
  additionally sets `GDK_BACKEND=wayland` explicitly.

### 4. The green look (`themes/pinentry-green`)

Adwaita-dark draws the entry focus ring (`entry:focus`) with a hardcoded blue
(`box-shadow: ... #15539e`), not through a theme variable
(`@theme_selected_bg_color`) — so a generic black-and-green `window`/`dialog`
override (used elsewhere on the system) doesn't catch it. A separate GTK
theme (`GTK_THEME=pinentry-green`, set in `pinentry-rbw`) imports the base
Adwaita-dark theme and overrides only `entry:focus`/`selection`/
`.suggested-action`, without touching the selection color anywhere else on
the system.

## What's deliberately NOT in this repo

The generated `gen-bitwarden-*.toml` menu files (written to tmpfs under
`$XDG_RUNTIME_DIR/bitwarden-xdg/elephant/menus/`, never to disk; they contain
real entry/folder names from the vault) and `~/.config/rbw/config.json` with
a real email — both are runtime/personal state, not code. The screenshot
above was captured with temporary fake menu data on an otherwise empty
workspace for the same reason.
