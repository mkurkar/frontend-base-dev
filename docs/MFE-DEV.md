# MFE development with frontend-base (lab box)

Frontend work now happens in [`lab-frontend-base`](https://github.com/zeit-labs/lab-frontend-base) —
the Open edX **frontend-base** fork that contains the shell **and** the header/footer
(`shell/header/`, `shell/footer/`). There are two development loops:

| | **A — dev shell** (start here) | **B — site + workspaces** |
|---|---|---|
| Command | `make mfe.dev` | `make mfe.site.dev` |
| What runs | frontend-base's self-contained dev shell: shell + header + footer from source, plus a few showcase apps | a real **site** — the lab's `lab-frontend-site` — with the actual apps (authn, learner/instructor dashboards, notifications, …) |
| Use it for | day-to-day header/footer work — fast, isolated | integration checks — "does it look right inside the real platform" |
| Port | 3080 | 3081 |
| Setup | node + `npm install` (automatic) | + site repo + npm workspace install (slower) |

Both run **on the box** and are reachable from your laptop once the devbox proxy is up:

```bash
# on the laptop, in the devbox repo
make proxy.up PROJECT=lab
```

## 0. One-time box setup

```bash
# from the laptop
make box.make PROJECT=lab TARGET="mfe.node"      # Node 24 via nvm (no node on a fresh box)
make box.make PROJECT=lab TARGET="mfe.deps"      # npm install in ~/workspace/lab-frontend-base
```

(`make box.make` drops you into `~/workspace/lab-configurations` on the box with a TTY; you can
also SSH in with `make box.ssh PROJECT=lab` and run the same `make` targets there.)

The fork is cloned by the devbox as `~/workspace/lab-frontend-base` (devbox manifest
`lab.yaml`, `role: mfe`).

## A. Dev shell loop — `make mfe.dev`

```bash
make box.make PROJECT=lab TARGET="mfe.dev"       # foreground; Ctrl-C stops it
```

- **Open:** http://‹box›.openedx.devbox:3080/
- The Makefile generates `shell/site.config.dev.box.tsx` from the repo's own
  `shell/site.config.dev.tsx`, with URLs pointed at your box (the LMS at
  `LAB_MFE_LMS_URL`, default `http://‹box›.openedx.devbox:8000`).
- **Edit** anything under `shell/` or `runtime/` — webpack hot-reloads (sub-second).

Useful knobs:

```bash
make mfe.dev.alt PORT=3082                       # another port
make mfe.deps FORCE=1                             # reinstall node_modules
make mfe.config LAB_MFE_LMS_URL=https://…         # re-generate only the config
```

## B. Site loop — `make mfe.site.dev`

```bash
make box.make PROJECT=lab TARGET="mfe.site.dev"   # foreground; Ctrl-C stops it
```

What the Makefile does:

1. clones the site repo (`LAB_MFE_SITE_REPO`, default the lab's
   **`zeit-labs/lab-frontend-site`**) into `~/workspace/frontend-site`;
2. **bind-mounts** the fork's source (`~/workspace/lab-frontend-base`, every top-level entry
   except `node_modules`) as the site's `packages/frontend-base`, so the site keeps its **own**
   `node_modules` and the fork's stays untouched;
3. generates a box-aware `site.config.dev.box.tsx` (host/port/LMS URLs);
4. runs `npm run dev:packages` → turbo watch-builds `packages/*` (the fork) and starts the
   site dev server.

- **Open:** http://‹box›.openedx.devbox:3081/
- Edits under `~/workspace/lab-frontend-base/shell|runtime` are watch-built into the site
  (a few seconds; the site itself recompiles in <1 s).

Teardown / knobs:

```bash
make mfe.site.unlink                              # remove the bind mounts
make mfe.site.deps FORCE=1                        # reinstall the site's node_modules
make mfe.site.config LAB_MFE_LMS_URL=…            # regenerate the site config
```

> The two loops can run side by side: the link exposes the fork's **source** to the site while
> the site keeps its own `node_modules`, so the dev shell's dependencies are never touched.
> `make mfe.site.unlink` removes the mounts when you are done (stop the site dev server first).

> Two template quirks are fixed by `make mfe.site.config`: the template's `dev` script
> hardcodes `PORT=8080` (we let `PORT` come from the environment), and turbo 2's strict env
> mode filters `PORT`/`SITE_CONFIG_PATH` unless they are listed in `turbo.json`'s
> `globalPassThroughEnv`. Both edits are idempotent.

## Where the code lives

```
lab-frontend-base/
  shell/
    header/     ← the site header (logo, nav links, menus, course bar)
    footer/     ← the footer (link columns, language, copyright)
    menus/      ← shared menu components
    Logo.tsx    ← the default logo component
  runtime/      ← the library under the shell (config, slots, auth, routing)
  test-site/    ← the framework's own test site (not used by the lab)
```

Header/footer behaviour is composed from **slots** (`org.openedx.frontend.slot.header.*`,
`…footer.*`). The upstream `shell/header/app.tsx` and `shell/footer/app.tsx` show every
default widget; customizations (logo swap, nav links, footer columns) are added as slot
operations — either directly in the fork or from a site's `site.config.tsx` via a custom app.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Blank page, console `CORS` on `…/login_refresh` | the LMS must whitelist the dev-server origin — the `mfe_dev_shell_cors` tutor plugin does this (dev settings); re-check the dev-shell port matches the whitelisted origins |
| Login loops | visit the app through the **box hostname** (`http://‹box›.openedx.devbox:3080/`), not the raw IP — cookies are same-site then |
| Runtime-config fetch errors in the log | harmless if the page renders; the dev server proxies `/api/frontend_site_config/v1/` to `local.openedx.io:8000`, which the Makefile points at the box's own LMS via `/etc/hosts` |
| `EADDRINUSE` on start | another dev server is running: `ss -tlnp | grep ‹port›` and stop it, or use `mfe.dev.alt PORT=…` |
| Turbo task doesn't see `PORT` | `mfe.site.config` must have run (it patches `turbo.json`) |
