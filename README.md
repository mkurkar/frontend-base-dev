# frontend-base dev mode — lab setup

> **Canonical location: `zeit-labs/lab-configurations`** (makefiles + `docs/MFE-DEV.md` +
> `docs/FRESH-BOX.md` + the CORS stopgap plugin), together with `zeit-labs/lab-frontend-site`
> (`DEV-QUICKSTART.md`), `zeit-labs/lab-tutor-plugin` (the CORS patch) and `zeit-labs/devbox`
> (`docs/LAB-quickstart.md`). This repository is a **personal mirror**, kept for other projects
> and reference — lab work should use the team repos.

Everything needed to run **Open edX `frontend-base`** (the new OEP-65 frontend) in development
mode on a ZeitLabs devbox: two Makefile includes, one small Tutor plugin, and a walkthrough of
what each piece does.

`frontend-base` replaces `frontend-build`, `frontend-platform`, `frontend-plugin-framework` **and**
the separate header/footer MFE packages — the shell and the header/footer now live inside
`lab-frontend-base` (`shell/header/`, `shell/footer/`). That changes how frontend development
works: instead of building custom header/footer packages into every MFE image, you edit the
frontend-base checkout and see it live.

> **Status** — both loops tested end-to-end on `mkurkar-eduba-01` and `mkurkar-lab-02`
> (webpack compiles clean, hot reload works, ports reachable from the laptop, CORS/CSRF verified).
> See [Verified environments](#verified-environments).
>
> **Starting from a fresh box?** Follow **[docs/FRESH-BOX.md](docs/FRESH-BOX.md)** — the complete
> step-by-step runbook (provision → tooling → node → LMS whitelist → loop A → loop B → login).

---

## 1. The two dev loops

| | **A — dev shell** | **B — site** |
|---|---|---|
| Makefile | `makefiles/mfe.mk` | `makefiles/mfe-site.mk` |
| Command | `make mfe.dev` | `make mfe.site.dev` |
| What runs | `frontend-base`'s self-contained dev shell: shell + header + footer + showcase apps, straight from source | a real **site** (`frontend-template-site` layout) composed from the actual apps (authn, learner/instructor dashboard, notifications, …) + the frontend-base checkout as an npm workspace |
| Use for | day-to-day header/footer work | integration checks in a production-like composition |
| Port | `3080` | `3081` |
| Node modules | the fork's own `node_modules` | the site's own `node_modules` (the fork is bind-mounted without it) |
| Relative cost | fast | slower to set up, heavier to run |

Both can run **at the same time** — the site link exposes only the fork's *source* into the site,
so neither loop touches the other's dependencies.

Legacy MFEs (learning, discussions, authoring, …) are **not** part of either loop — Tutor serves
them from the MFE image at their own ports. To edit one live, see
**[docs/MFE-DEV.md § C](docs/MFE-DEV.md#c-editing-a-legacy-mfe-optional)**.

---

## 2. Where the files go

These are box-side files. On a lab box the devbox clones `lab-configurations`; drop the includes in
its `makefiles/` directory (included automatically by `makefiles/*.mk`):

```
lab-configurations/
  makefiles/
    mfe.mk         # loop A
    mfe-site.mk    # loop B
docs/MFE-DEV.md    # the developer quick start
```

The Tutor plugin goes to the box's local plugin directory:

```
~/.local/share/tutor-plugins/mfe_dev_shell_cors.py
```

Everything runs **on the box** (node, npm, webpack); the laptop only needs the devbox proxy to
open the ports in a browser.

---

## 3. One-time setup

```bash
# 0. laptop: reach the box's URLs
cd <devbox repo>
make proxy.up PROJECT=lab            # writes /etc/hosts + starts the box-side Caddy for the LMS

# 1. box: Node 24 (there is no node on a fresh box)
make box.make PROJECT=lab TARGET="mfe.node"

# 2. box: the LMS must whitelist the dev-server origins (CORS + CSRF)
#    copy tutor-plugin/mfe_dev_shell_cors.py to ~/.local/share/tutor-plugins/ and:
tutor plugins enable mfe_dev_shell_cors && tutor config save && tutor dev restart lms

# 3. box: install the fork's dependencies (loop A)
make box.make PROJECT=lab TARGET="mfe.deps"
```

The frontend-base fork is cloned by the devbox manifest as `~/workspace/lab-frontend-base`
(`lab.yaml`, `role: mfe`).

---

## 4. How loop A works — `makefiles/mfe.mk`

`frontend-base` ships a self-contained dev mode (`npm run dev`): it builds the library and starts a
webpack dev server that serves a minimal site **from the source files**, so you can iterate on the
shell/header/footer without a separate site checkout or an MFE image rebuild.

The Makefile turns that into box-aware targets:

| Target | What it does |
|---|---|
| `mfe.node` | installs Node `LAB_MFE_NODE_VERSION` (24) via nvm if missing. nvm is not on a non-interactive shell's `PATH`, so every recipe sources it explicitly. |
| `mfe.deps` | `npm install` in `LAB_FRONTEND_BASE_DIR` (skips when `node_modules` exists; `FORCE=1` reinstalls). |
| `mfe.config` | generates **`shell/site.config.dev.box.tsx`** from the repo's own `shell/site.config.dev.tsx`, rewriting every URL to point at *your box*: shell URL (`http://<box>.openedx.devbox:3080`), LMS (`LAB_MFE_LMS_URL`, default `http://<box>.openedx.devbox:8000`), Studio, and the profile/account external routes. It also adds `127.0.0.1 local.openedx.io` to `/etc/hosts`, because the webpack dev server proxies `/api/frontend_site_config/v1/` to `local.openedx.io:8000` and that name must resolve on the box. |
| `mfe.dev` | `PORT=<port> SITE_CONFIG_PATH=shell/site.config.dev.box.tsx npm run dev` — the foreground dev server. |
| `mfe.dev.alt` | the same on another port (`PORT=3082`). |

`SITE_CONFIG_PATH` and `PORT` are read by frontend-base's webpack config at startup, so the
generated config and the port need no source edits — and `git status` stays clean in the fork.

**Loop:** edit anything under `shell/` or `runtime/` → webpack hot-reloads in well under a second.

---

## 5. How loop B works — `makefiles/mfe-site.mk`

A *site* is a repository — the lab's is **`zeit-labs/lab-frontend-site`** (based on
`frontend-template-site`) — with a `site.config.tsx`, a
`packages/*` npm workspace, and the frontend-base checkout living in `packages/frontend-base`.
`npm run dev:packages` watch-builds the workspace packages (in dependency order, via Turborepo)
and starts the site's webpack dev server.

The interesting part is **how the fork is linked**: not by a plain bind mount of the whole
directory (that would make the site's `npm install` prune the fork's `node_modules`, and an
overlay to protect them masks them for the dev shell too — same dentry). Instead the Makefile
mounts **each top-level entry of the fork except `node_modules`** into
`frontend-site/packages/frontend-base`:

| Target | What it does |
|---|---|
| `mfe.site.deps` | clones/updates the site repo (`LAB_MFE_SITE_REPO`, default **`zeit-labs/lab-frontend-site`**) into `LAB_MFE_SITE_DIR` and runs `npm install` (skips when installed; `FORCE=1` reinstalls). |
| `mfe.site.link` | creates `packages/frontend-base` and bind-mounts every top-level entry of the fork into it (skipping `node_modules`), so the site gets a **live view of the source** and keeps its **own** `node_modules`; the fork's stays untouched and loop A keeps working. |
| `mfe.site.unlink` | unmounts them (stop the site dev server first). |
| `mfe.site.config` | generates `site.config.dev.box.tsx` with the box URLs. For a stock template it also patches two quirks — the hardcoded `PORT=8080` in the `dev` script, and Turbo 2's strict env mode (`globalPassThroughEnv` for `PORT`/`SITE_CONFIG_PATH`). The lab's site repo already carries both, so those edits are idempotent no-ops there. |
| `mfe.site.dev` | deps + link + config, then `npm run dev:packages` at `LAB_MFE_SITE_PORT` (3081). |

Edits in the fork are watch-built into the site (a few seconds for the library build, then the
site recompiles in under a second).

---

## 6. The LMS side — `mfe_dev_shell_cors`

Both dev servers run on origins that are neither the LMS nor the MFE host, so the LMS rejects
their API calls. The plugin appends `http://<LMS_HOST>:3080|3081` and `http://<MFE_HOST>:3080|3081`
to `CORS_ORIGIN_WHITELIST` and `CSRF_TRUSTED_ORIGINS` in **development** settings only. It needs no
parameters; it renders with whatever the box's hosts are.

---

## 7. Variables reference

All are `?=` (override on the command line or in `local.mk`).

| Variable | Default | Meaning |
|---|---|---|
| `LAB_FRONTEND_BASE_DIR` | `$(WORKSPACE_DIRECTORY)/lab-frontend-base` | the frontend-base checkout |
| `LAB_MFE_NODE_VERSION` | `24` | Node major version installed via nvm |
| `LAB_MFE_DEV_PORT` | `3080` | loop A port |
| `LAB_MFE_SITE_PORT` | `3081` | loop B port |
| `LAB_MFE_DEV_HOST` | `$(SERVICE_HOST)` | the box hostname used in generated configs |
| `LAB_MFE_LMS_URL` | `http://$(SERVICE_HOST):8000` | LMS base URL baked into the dev configs — override for boxes whose LMS is behind an HTTPS proxy |
| `LAB_FRONTEND_BASE_DIR`, `LAB_MFE_SITE_DIR` | `$(WORKSPACE_DIRECTORY)/frontend-site` | loop B checkout |
| `LAB_MFE_SITE_REPO`, `LAB_MFE_SITE_REF` | `zeit-labs/lab-frontend-site`, `main` | point at another site checkout to use it instead (e.g. the upstream template) |
| `FORCE` | — | `FORCE=1` forces `npm install` to re-run |

---

## 8. Daily developer flow

```bash
# laptop: get a shell on the box (or run targets through box.make)
make box.ssh PROJECT=lab

# box:
cd ~/workspace/lab-configurations

make mfe.dev                 # loop A, foreground, http://<box>.openedx.devbox:3080/
make mfe.site.dev            # loop B, foreground, http://<box>.openedx.devbox:3081/

# edit the shell/header/footer
vim ~/workspace/lab-frontend-base/shell/header/Header.tsx
```

Log in for authenticated states at `http://<box>.openedx.devbox:8000/login` (the dev servers are
same-site with that host, so the JWT cookie is picked up) and then open the dev server URL.

> On the lab project the developer-facing one-pager lives in the site repo:
> **`zeit-labs/lab-frontend-site` → `DEV-QUICKSTART.md`** (loops, what to edit, every page,
> the legacy-MFE loop, gotchas).

---

## 9. Troubleshooting (hard-won)

| Symptom | Cause / fix |
|---|---|
| Blank page; `status: 0` + `_securityState: "broken"` in the browser's network log | **TLS**, not CORS: the box's HTTPS cert is self-signed / for another domain. Point `LAB_MFE_LMS_URL` at the plain-http LMS (`http://<box>:8000`). |
| `401` on `/login_refresh`, `403` on `/api/user/v2/account/login_session/`, only on a box with a staging config | The LMS sets cookies with `Domain=<staging domain>` (`SESSION_COOKIE_DOMAIN`), so the browser drops them on the box hostname. Use a box whose cookie domain is its own host (plain tutor dev), or log in on the staging domain. |
| CORS preflight fails | The LMS must whitelist the dev-server origins — install `mfe_dev_shell_cors` (above) and restart the LMS. |
| `EADDRINUSE` | Another dev server is on that port: `ss -tlnp \| grep <port>`, stop it, or use `mfe.dev.alt PORT=…`. |
| `Failed to compile: … react-refresh … / html-webpack-plugin/lib/loader.js` | The fork's `node_modules` is masked (an old-style whole-directory link, or a mount left behind). Run `make mfe.site.unlink`, check `mount \| grep frontend-base`, then restart the dev shell. |
| Turbo task ignores `PORT` / `SITE_CONFIG_PATH` | `make mfe.site.config` must have run (it patches `turbo.json`'s `globalPassThroughEnv`). |
| `tsc: No such file or directory` when starting loop A | The fork has no `node_modules` — `make mfe.deps FORCE=1`. |
| `make mfe.link` seems to do nothing | Check no `$`-escaping regressions: inside recipes, shell variables need `$$` (`$$entry`), or make expands them itself. |
| The fork's files disappeared after deleting/moving the site checkout | Loop B bind-mounts the fork's entries into `frontend-site/packages/frontend-base` — an `rm -rf` through an active mount deletes the **source**. Always `make mfe.site.unlink` first; recover the fork with `git clone` (or from a bundle). |
| Mounted legacy MFE crash-loops: `sh: 1: fedx-scripts: not found` | The mount overlays the image's `/openedx/app` — install once: `tutor dev run --no-deps <app> npm install`, then `tutor dev restart <app>`. |
| Cloning a private repo on the box: `could not read Username` | The box has no git credentials. Use `box.sync` (provision token) or transfer a `git bundle` from your laptop. |

---

## 10. Verified environments

| Box | What was verified |
|---|---|
| `mkurkar-eduba-01` | loop A compiled clean (`compiled successfully in 12.6 s`, hot reload ~0.6 s); loop B cloned, linked, installed, compiled (`./packages/frontend-base/dist` in the bundle, recompile ~0.8 s); both served on 3080/3081 simultaneously; CORS preflight + `POST /login_refresh` from both origins return the right `access-control-allow-origin`. |
| `mkurkar-lab-02` | loop A compiled clean (`10.5 s`), config pointed at `http://mkurkar-lab-02.openedx.devbox:8000`, CORS plugin enabled, superuser created, dev shell served on 3080. |

---

## 11. Upstream references

- `frontend-base`: <https://github.com/openedx/frontend-base> — the "Development" section of its README describes the self-contained dev mode.
- `frontend-template-site`: <https://github.com/openedx/frontend-template-site> — the site layout and "Local development with workspaces".
- `tutor-mfe`: <https://github.com/overhangio/tutor-mfe> — the production composition; its dev services wire a `frontend-site` mount into an `mfe-dev` container (that is loop B, but served by Tutor).
- "How I do frontend-base development": <https://discuss.openedx.org/t/how-i-do-frontend-base-development/19501> — the npm-workspace + bind-mount pattern this setup follows.
