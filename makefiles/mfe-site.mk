# makefiles/mfe-site.mk: lab frontend-base SITE DEV MODE (approach B, box-side).
#
# Approach A (makefiles/mfe.mk) runs frontend-base's self-contained dev shell: fast, but it
# only exercises the shell + header + footer. Approach B composes a real SITE — the same way
# Tutor/tutor-mfe builds one — from the site layout and the npm workspace under packages/, so
# the header/footer run next to the actual apps (authn, learner dashboard, instructor
# dashboard, notifications, ...). The default site is the lab's own repo
# (zeit-labs/lab-frontend-site); point LAB_MFE_SITE_REPO at another site checkout to use that
# instead (e.g. the upstream openedx/frontend-template-site).
#
#   make mfe.site.deps    # clone/update the site repo + npm install its workspace deps
#   make mfe.site.link    # bind-mount lab-frontend-base as the site's packages/frontend-base
#   make mfe.site.unlink  # tear the mounts down
#   make mfe.site.config  # generate the box-aware site config (host, port, LMS URLs)
#   make mfe.site.dev     # all of the above + run `npm run dev:packages` (foreground)
#
# Reachable from the laptop once the devbox proxy is up:
#
#   http://<box>.openedx.devbox:3081/
#
# The checkout under packages/frontend-base is a bind mount of each top-level entry of
# LAB_FRONTEND_BASE_DIR (node_modules excluded), so edits land in the frontend-base fork
# directly, turbo watch-builds them, and the fork's own node_modules is left alone — the two dev
# loops (make mfe.dev / make mfe.site.dev) can run at the same time.

LAB_MFE_SITE_DIR      ?= $(WORKSPACE_DIRECTORY)/frontend-site
LAB_MFE_SITE_REPO     ?= https://github.com/zeit-labs/lab-frontend-site.git
LAB_MFE_SITE_REF      ?= main
LAB_MFE_SITE_PORT     ?= 3081
LAB_MFE_SITE_CONFIG   ?= site.config.dev.box.tsx

.PHONY: mfe.site.deps mfe.site.link mfe.site.unlink mfe.site.config mfe.site.dev

mfe.site.deps: mfe.node #- Clone/update the site repo and npm install its workspace deps
	@if [ ! -d "$(LAB_MFE_SITE_DIR)/.git" ]; then \
	  echo ">> cloning $(LAB_MFE_SITE_REPO) ($(LAB_MFE_SITE_REF)) -> $(LAB_MFE_SITE_DIR)"; \
	  git clone --branch "$(LAB_MFE_SITE_REF)" "$(LAB_MFE_SITE_REPO)" "$(LAB_MFE_SITE_DIR)"; \
	else \
	  echo ">> $(LAB_MFE_SITE_DIR) exists: git pull --ff-only"; \
	  git -C "$(LAB_MFE_SITE_DIR)" pull --ff-only || echo ">> (pull skipped)"; \
	fi
	@$(NVM) \
	cd "$(LAB_MFE_SITE_DIR)"; \
	if [ -d node_modules ] && [ -z "$(FORCE)" ]; then \
	  echo ">> node_modules present (FORCE=1 to reinstall)"; \
	else \
	  echo ">> npm install in $(LAB_MFE_SITE_DIR) (first run is slow)"; \
	  npm install; \
	fi

# Mount each top-level entry of the fork individually (skipping node_modules) so the site gets
# a live view of the source while keeping its OWN node_modules. The fork's node_modules is never
# masked, so the dev shell (make mfe.dev) keeps working while the site is linked.
mfe.site.link: #- Expose the frontend-base checkout as the site's packages/frontend-base
	@test -d "$(LAB_FRONTEND_BASE_DIR)" || { \
	  echo ">> !! $(LAB_FRONTEND_BASE_DIR) not found — is lab-frontend-base checked out?"; exit 1; }
	@test -d "$(LAB_MFE_SITE_DIR)" || { echo ">> !! run 'make mfe.site.deps' first"; exit 1; }
	@mkdir -p "$(LAB_MFE_SITE_DIR)/packages/frontend-base"
	@cd "$(LAB_FRONTEND_BASE_DIR)"; \
	for entry in * .[!.]*; do \
	  [ "$$entry" = "node_modules" ] && continue; \
	  [ -e "$$entry" ] || continue; \
	  target="$(LAB_MFE_SITE_DIR)/packages/frontend-base/$$entry"; \
	  if [ -d "$$entry" ]; then mkdir -p "$$target"; else mkdir -p "$$(dirname "$$target")"; [ -e "$$target" ] || : > "$$target"; fi; \
	  if mountpoint -q "$$target"; then continue; fi; \
	  sudo mount --bind "$$(pwd)/$$entry" "$$target" || echo ">> !! could not mount $$entry"; \
	done; \
	echo ">> $(LAB_FRONTEND_BASE_DIR) is live as packages/frontend-base (site owns its node_modules)"

mfe.site.unlink: #- Undo the bind mounts created by mfe.site.link
	@cd "$(LAB_MFE_SITE_DIR)/packages/frontend-base" 2>/dev/null && { \
	  for entry in * .[!.]*; do \
	    [ -e "$$entry" ] || continue; \
	    if mountpoint -q "$$entry"; then \
	      sudo umount "$$entry" || echo ">> !! busy: $$entry (stop the site dev server first)"; \
	    fi; \
	  done; \
	} || true
	@echo ">> unlinked"

mfe.site.config: #- Generate the box-aware site config (host $(LAB_MFE_DEV_HOST), port $(LAB_MFE_SITE_PORT))
	@test -d "$(LAB_MFE_SITE_DIR)" || { echo ">> !! run 'make mfe.site.deps' first"; exit 1; }
	@cd "$(LAB_MFE_SITE_DIR)"; \
	sed -i 's|"dev": "PORT=8080 openedx dev"|"dev": "openedx dev"|' package.json; \
	sed \
	  -e "s#http://apps.local.openedx.io:8080#http://$(LAB_MFE_DEV_HOST):$(LAB_MFE_SITE_PORT)#g" \
	  -e "s#http://apps.local.openedx.io:1995#http://apps.$(LAB_MFE_DEV_HOST):1995#g" \
	  -e "s#http://apps.local.openedx.io:1997#http://apps.$(LAB_MFE_DEV_HOST):1997#g" \
	  -e "s#http://studio.local.openedx.io:8001#http://studio.$(LAB_MFE_DEV_HOST):8001#g" \
	  -e "s#http://local.openedx.io:8000#$(LAB_MFE_LMS_URL)#g" \
	  site.config.dev.tsx > "$(LAB_MFE_SITE_CONFIG)"; \
	echo ">> wrote $(LAB_MFE_SITE_CONFIG) for $(LAB_MFE_DEV_HOST):$(LAB_MFE_SITE_PORT)"
	@cd "$(LAB_MFE_SITE_DIR)"; \
	python3 -c "import json; p='turbo.json'; d=json.load(open(p)); e=d.setdefault('globalPassThroughEnv', []); [e.append(v) for v in ('PORT', 'SITE_CONFIG_PATH') if v not in e]; json.dump(d, open(p, 'w'), indent=2); print('>> turbo.json globalPassThroughEnv:', e)"

mfe.site.dev: mfe.site.deps mfe.site.link mfe.site.config #- Run the site dev server (foreground)
	@$(NVM) \
	cd "$(LAB_MFE_SITE_DIR)"; \
	echo ">> site dev: http://$(LAB_MFE_DEV_HOST):$(LAB_MFE_SITE_PORT)/"; \
	echo ">>   (edits in $(LAB_FRONTEND_BASE_DIR) are watch-built into the site)"; \
	PORT=$(LAB_MFE_SITE_PORT) SITE_CONFIG_PATH=$(LAB_MFE_SITE_CONFIG) npm run dev:packages
