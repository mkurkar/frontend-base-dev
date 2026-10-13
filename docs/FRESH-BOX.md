# Fresh box: step by step

From an empty devbox to the frontend-base dev servers in the browser. Every command is copy-pastable.

Replace `lab` / `NN` with your project + instance (`mkurkar-lab-02` = `PROJECT=lab INSTANCE=02`).

---

## 0. Prerequisites (once per laptop)

- ZeitLabs **Tailscale** account, connected.
- The **devbox toolchain**: `cd <devbox repo> && devbox shell` (gives you `gh`, `jq`, `mutagen`, `caddy`). Needed in every terminal that runs `make box.*`.
- `gh auth login` done.
- The frontend-base fork is public; the site repo (`zeit-labs/lab-frontend-site`) is private to
  the org — the box clones it with the provision token, and a local clone needs org access.

---

## 1. Provision the box (laptop)

```bash
cd <devbox repo>
make box.create PROJECT=lab INSTANCE=NN      # fires the GitHub Action -> droplet -> cloud-init -> tutor dev
make box.watch                                # follow the Action
make box.status PROJECT=lab INSTANCE=NN       # wait for: status=done + heartbeat: HTTP 200  (~25-35 min)
```

That gives you `~/workspace/` on the box with the project repos already cloned
(`lab-configurations`, `lab-tutor-plugin`, `lab-brand-openedx`, `lab-frontend-base`) and the LMS
running under `tutor dev`.

---

## 2. Make the box's URLs usable in the browser (laptop)

Either run the proxy (adds a box-side Caddy for the port-less LMS on :80):

```bash
make proxy.up PROJECT=lab INSTANCE=NN
```

or just add a hosts line yourself (enough for this setup — the dev configs use the explicit
`:8000` LMS URL). Point it at the **Tailscale IP**:

```bash
tailscale status | grep lab-NN                 # take the 100.x.y.z address
sudo sh -c 'echo "<100.x.y.z> mkurkar-lab-NN.openedx.devbox apps.mkurkar-lab-NN.openedx.devbox studio.mkurkar-lab-NN.openedx.devbox" >> /etc/hosts'
```

> Why `.openedx.devbox` and not the tailnet name: the LMS scopes its session/JWT cookies to
> `Domain=<box>.openedx.devbox` and marks them `SameSite=Lax`. Browse via the `.devbox` hostname
> and the dev servers are same-site with the LMS, so login works. The tailnet name is fine for
> anonymous poking, but not for authenticated sessions.

---

## 3. Put the dev tooling on the box (box)

```bash
make box.ssh PROJECT=lab INSTANCE=NN

# get the makefiles + plugin (public repo)
git clone https://github.com/mkurkar/frontend-base-dev.git ~/frontend-base-dev
cp ~/frontend-base-dev/makefiles/*.mk ~/workspace/lab-configurations/makefiles/
mkdir -p ~/.local/share/tutor-plugins
cp ~/frontend-base-dev/tutor-plugin/mfe_dev_shell_cors.py ~/.local/share/tutor-plugins/
```

If you'd rather not clone: `scp` the four files over, or paste them — they are the only artifacts.

---

## 4. Node + LMS whitelist (box)

```bash
cd ~/workspace/lab-configurations

# Node 24 via nvm (a fresh box has no node)
make mfe.node

# let the dev servers call the LMS (CORS + CSRF, dev settings only)
export PATH=$HOME/.local/bin:$PATH
tutor plugins enable mfe_dev_shell_cors
tutor config save
tutor dev restart lms
```

---

## 5. Loop A — the dev shell (box)

```bash
make mfe.deps        # npm install in ~/workspace/lab-frontend-base (first run: a few minutes)
make mfe.dev         # foreground; Ctrl-C stops it
```

Open `http://<box>.openedx.devbox:3080/` — shell + header + footer from source, hot reload.
Edit anything under `~/workspace/lab-frontend-base/shell/` and the browser updates in <1 s.

---

## 6. Loop B — the site (box)

```bash
make mfe.site.deps   # clones zeit-labs/lab-frontend-site -> ~/workspace/frontend-site + npm install
                     #   (first run: pulls all the real apps — ~10 min)
make mfe.site.link   # exposes the fork's source as packages/frontend-base (no deps shared)
make mfe.site.config # box-aware site config + template quirks (PORT, turbo env passthrough)
make mfe.site.dev    # foreground; site dev server on :3081
```

Open `http://<box>.openedx.devbox:3081/`. Both loops can run at the same time.

> The default site is the lab's own `zeit-labs/lab-frontend-site`; `LAB_MFE_SITE_REPO=…`
> points loop B at another site checkout (e.g. the upstream template).

---

## 7. A user to log in with (box)

Create it **with its profile** — a bare `User.objects.create_user` leaves `user.profile` missing
and the LMS then returns **500** on login (`User.profile.RelatedObjectDoesNotExist`):

```bash
tutor dev exec lms python manage.py lms shell -c \
'from django.contrib.auth import get_user_model
from common.djangoapps.student.models import UserProfile
U = get_user_model()
u, _ = U.objects.get_or_create(username="mkurkar", defaults={"email": "mkurkar@example.com"})
u.email = "mkurkar@example.com"; u.is_staff = True; u.is_superuser = True; u.is_active = True
u.set_password("labpass123"); u.save()
UserProfile.objects.get_or_create(user=u, defaults={"name": "mkurkar"})
print("user ready:", u.username)'
```

---

## 8. Log in and look (laptop)

1. `http://<box>.openedx.devbox:8000/login` → the LMS redirects to the **authn MFE**
   (`http://apps.<box>.openedx.devbox:1999/authn/login` — that is why `apps.<box>` is in the
   hosts line).
2. Log in with the user from step 7.
3. Open the dev servers — the authenticated header/avatar should render:
   * loop A: `http://<box>.openedx.devbox:3080/`
   * loop B: `http://<box>.openedx.devbox:3081/`

---

## 9. Sanity checks (box)

```bash
# dev servers listening?
ss -tlnp | grep -E ':3080|:3081'

# LMS whitelisted your origins?
curl -s -o /dev/null -D - -X OPTIONS http://localhost:8000/login_refresh \
  -H "Origin: http://<box>.openedx.devbox:3080" -H "Access-Control-Request-Method: POST" \
  | grep -i access-control-allow-origin

# fork's deps intact (loop A) and the site link active (loop B)
ls ~/workspace/lab-frontend-base/node_modules/.bin/tsc
mount | grep -c frontend-base
```

---

## 10. Troubleshooting quick table

| Symptom | Fix |
|---|---|
| `status: 0` / `_securityState: "broken"` in the browser | TLS: you are pointing at an HTTPS URL with a self-signed/foreign cert. Use `http://<box>.openedx.devbox:8000` as the LMS URL (`LAB_MFE_LMS_URL`). |
| `CSRF verification failed` / 403 on `login_session` | Your page's origin is not whitelisted (e.g. a tailnet URL). Re-run step 4 (the plugin picks up the tailnet name automatically), then `tutor config save && tutor dev restart lms`, and hard-refresh. |
| `403` persists with the right origin | Stale `csrftoken` cookie: clear cookies for the box's hosts and reload. |
| `500` on login | The user has no profile — see step 7. |
| 401 on `login_refresh`, anonymous | Normal when logged out; or you are browsing the tailnet name instead of `.devbox` (cookies are cross-site then). |
| `EADDRINUSE` | Something already serves that port: `ss -tlnp \| grep <port>`. |
| Loop A fails with `Failed to compile … react-refresh / html-webpack-plugin` | The fork's `node_modules` is masked by a leftover whole-directory mount: `make mfe.site.unlink`, check `mount \| grep frontend-base`, restart loop A. |
| Loop A: `tsc: No such file or directory` | `make mfe.deps FORCE=1`. |
| The fork's files vanished after deleting/moving the site checkout | Loop B bind-mounts the fork's entries into `frontend-site/packages/frontend-base`; `rm -rf` through an active mount deletes the source. `make mfe.site.unlink` first; recover the fork with `git clone`. |
| Mounted legacy MFE crash-loops: `sh: 1: fedx-scripts: not found` | The mount overlays the image's `/openedx/app`: `tutor dev run --no-deps <app> npm install`, then `tutor dev restart <app>`. |
| Private repos can't be cloned from the box (`could not read Username`) | The box has no git credentials — use `box.sync` (it clones with the provision token), or transfer a `git bundle` from your laptop. |
