# rbw_custom_design

Vlastní Bitwarden menu nad [`rbw`](https://github.com/doy/rbw) (neoficiální Bitwarden
CLI) pro Sway/wlroots, postavené na [`walker`](https://github.com/abenz1267/walker) +
[`elephant`](https://github.com/abenz1267/elephant) (`elephant-bitwarden` provider),
s černo-zeleným "retro" vzhledem.

Klávesová zkratka otevře plovoucí okno se seznamem složek a živým fulltextovým
hledáním přes celý vault; z položky lze zkopírovat heslo/username/TOTP,
upravit ji nebo smazat. `rbw` zůstává jediným zdrojem pravdy (vault, sync,
zamykání) — tenhle repo je jen UI vrstva nad ním.

## Architektura

```
$mod+b (Sway)
  -> bin/bitwarden-launcher
       -> bin/bitwarden-generate-menus   (rbw list --raw -> TOML menu soubory pro elephant)
       -> systemctl --user restart elephant.service   (viz "Known issues" níže)
       -> walker -s bitwarden
            - prázdné pole   = statické menu (foldery, generované výše)
            - psaní do pole  = živé hledání přes elephant-bitwarden provider
```

Akce nad položkou (kopírovat heslo/username/TOTP, upravit, smazat) volají
`bin/bitwarden-menu-copy <id> <akce>`, které dělá přímé `rbw get`/`rbw code`/
`rbw remove` volání a heslo posílá do schránky přes `wl-copy` (s automatickým
smazáním schránky po 45s u hesel).

`bin/rbw-rofi-menu` je starší alternativní frontend (rofi script-mode místo
walkeru) — funkční, ale aktuálně na nic nenavázaný (žádný keybinding ho
nevolá). Ponecháno pro referenci/kompletnost.

## Závislosti

- `rbw` (Bitwarden CLI) + `pinentry-gtk`
- `walker` + `elephant` (`elephant.service` jako `systemctl --user` služba)
  + AUR balíček `elephant-bitwarden` (poskytuje `bitwarden` provider)
- `jq`, `wl-clipboard`, `iconv` (`glibc`)
- Sway/wlroots (floating pravidlo v `sway/rbw-bitwarden.conf` je Sway-specifické)

## Instalace

1. `bin/*` zkopírovat do `~/.local/bin/` (zachovat spustitelnost, `.bitwarden-lib.sh`
   a `.bitwarden-editor-fill` musí zůstat se skrytou tečkou — sourcují se podle
   přesného jména).
2. `themes/pinentry-green/gtk-3.0/gtk.css` zkopírovat do
   `~/.themes/pinentry-green/gtk-3.0/gtk.css`.
3. `sway/rbw-bitwarden.conf` přidat do `~/.config/sway/config` (include nebo
   ručně zkopírovat obsah).
4. `rbw/config.example.json` použít jako vzor pro `~/.config/rbw/config.json`
   (doplnit vlastní e-mail; `"pinentry": "pinentry-rbw"` je klíčové — viz níže).
5. `rbw config set email <tvůj e-mail>`, `rbw login`, `systemctl --user enable --now elephant.service`.

## Known issues a proč jsou skripty takové, jaké jsou

Tři samostatné, na sobě nezávislé bugy, které se navenek projevovaly stejně
("po odemčení rbw přestane fungovat vyhledávání/přihlášení"):

### 1. `elephant-bitwarden` po auto-locku vrací natrvalo 0 výsledků

`elephant.service` běží trvale na pozadí a jeho `bitwarden` provider si drží
vlastní spojení k `rbw-agent` navázané v okamžiku posledního zamčení vaultu.
Po opětovném odemčení (`rbw` má `lock_timeout`) se toto spojení samo neobnoví —
statické menu foldery fungují (generují se čerstvě přes `rbw list`), ale živé
hledání trvale hlásí 0 výsledků, dokud se `elephant.service` neresetuje.

**Fix:** `bin/bitwarden-launcher` proto před `exec walker -s bitwarden` VŽDY
(ne jen podmíněně) volá `systemctl --user restart elephant.service` — cena je
~1-2s navíc při každém otevření, ale bezpodmínečnost je nutná, protože
"bylo to zamčené" nejde spolehlivě detekovat (uživatel může `rbw unlock`
spustit i mimo tenhle skript).

### 2. `pinentry-gtk` na Sway/wlroots neumí unlocknout vault

Dvě nezávislé příčiny, obě řeší `bin/pinentry-rbw` (wrapper, na který
ukazuje `"pinentry"` v `rbw config.json`):

- **Globální X11 grab.** `pinentry-gtk` defaultně dělá globální grab
  klávesnice/myši (přes XWayland), který na wlroots compositorech koliduje
  ("could not grab keyboard: already grabbed", "it took 4097 tries to grab
  the pointer") a unlock skončí jako "pinentry cancelled". Řeší
  `--no-global-grab` (grabuje jen dokud je okno fokusnuté).

- **`rbw-agent` vždy posílá `--display :1`.** I s `--no-global-grab` selhávalo
  mapování okna, pokud `rbw-agent` (zděděné `$DISPLAY` z vlastního startu)
  poslalo pinentry explicitní `--display`, které vynutí GTK na X11/XWayland
  backend místo nativního Wayland — okno se pak vůbec nenamapovalo (ověřeno
  přímým porovnáním: se `--display` 0 namapovaných oken, bez něj vždy 1).
  Wrapper tenhle flag odfiltruje a navíc explicitně nastaví
  `GDK_BACKEND=wayland`.

### 3. Zelený vzhled (`themes/pinentry-green`)

Adwaita-dark kreslí focus ring vstupního pole (`entry:focus`) natvrdo
zakódovanou modrou (`box-shadow: ... #15539e`), ne přes motivovou proměnnou
(`@theme_selected_bg_color`) — obecné černo-zelené `window`/`dialog` pravidlo
(použité i jinde v systému) ho proto netrefí. Samostatné GTK téma
(`GTK_THEME=pinentry-green`, nastavené ve `pinentry-rbw`) importuje base
Adwaita-dark a přepisuje jen `entry:focus`/`selection`/`.suggested-action`,
aniž by měnilo výběrovou barvu ve zbytku systému.

## Co záměrně NENÍ v repu

Vygenerované soubory `~/.config/elephant/menus/gen-bitwarden-*.toml`
(obsahují reálné názvy položek/složek z vaultu) a `~/.config/rbw/config.json`
se skutečným e-mailem — obojí je runtime/osobní stav, ne kód.
