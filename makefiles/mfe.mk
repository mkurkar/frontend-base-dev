# makefiles/mfe.mk: lab frontend-base DEV MODE (box-side).
#
# Runs the self-contained dev shell that ships with lab-frontend-base (see the
# "Development" section of its README): webpack-dev-server serves the shell, header
# and footer straight from source, with hot reload, so a frontend developer can
# iterate on the UI without a site checkout or an MFE image rebuild.
#
#   make mfe.dev          # node + deps + box site config + `npm run dev` (foreground)
#   make mfe.dev.alt      # same on an alternate port (PORT=...)
#   make mfe.deps         # just (re)install node_modules (FORCE=1 to force)
#   make mfe.config       # just (re)generate the box-aware dev-shell site config
#
# The dev shell is reachable from the laptop once the devbox proxy is up
# (`make proxy.up PROJECT=lab` in the devbox repo):
#
#   http://<box>.openedx.devbox:3080/
#
# The dev shell talks to the box's LMS (tutor dev publishes it on :8000; override with
# LAB_MFE_LMS_URL, e.g. http://<box>.openedx.devbox when the box-side Caddy on :80 is up).
# The generated site config points login/logout/API there, and the webpack dev-server proxies
# the runtime site-config API to the LMS. The LMS must whitelist the dev-shell origin for
# CORS/CSRF — the lab-tutor-plugin patch does that (dev settings).

LAB_FRONTEND_BASE_DIR ?= $(WORKSPACE_DIRECTORY)/lab-frontend-base
LAB_MFE_DEV_PORT      ?= 3080
LAB_MFE_NODE_VERSION  ?= 24
LAB_MFE_NVM_DIR       ?= $(HOME)/.nvm
LAB_MFE_DEV_HOST      ?= $(SERVICE_HOST)
LAB_MFE_DEV_CONFIG    ?= shell/site.config.dev.box.tsx
# The LMS the dev shell talks to. Tutor dev publishes the LMS on :8000 on every box, so that
# always works; override to e.g. http://<box>.openedx.devbox if the box-side Caddy (:80) is up.
LAB_MFE_LMS_URL       ?= http://$(SERVICE_HOST):8000

# nvm is not on a non-interactive shell's PATH; source it explicitly in every recipe.
NVM = export NVM_DIR="$(LAB_MFE_NVM_DIR)"; . "$$NVM_DIR/nvm.sh";

.PHONY: mfe.node mfe.deps mfe.config mfe.dev mfe.dev.alt

mfe.node: #- Ensure Node $(LAB_MFE_NODE_VERSION) (via nvm) is installed
	@$(NVM) \
	if [ ! -s "$$NVM_DIR/nvm.sh" ]; then \
	  echo ">> installing nvm"; \
	  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null; \
	fi; \
	. "$$NVM_DIR/nvm.sh"; \
	if ! nvm which "$(LAB_MFE_NODE_VERSION)" >/dev/null 2>&1; then \
	  echo ">> installing Node $(LAB_MFE_NODE_VERSION)"; \
	  nvm install "$(LAB_MFE_NODE_VERSION)" >/dev/null; \
	fi; \
	echo ">> node $$(node --version) / npm $$(npm --version)"

mfe.deps: mfe.node #- Install the frontend-base node_modules (FORCE=1 to force a reinstall)
	@test -d "$(LAB_FRONTEND_BASE_DIR)" || { \
	  echo ">> !! $(LAB_FRONTEND_BASE_DIR) not found — is lab-frontend-base in the devbox manifest?"; exit 1; }
	@$(NVM) \
	cd "$(LAB_FRONTEND_BASE_DIR)"; \
	if [ -d node_modules ] && [ -z "$(FORCE)" ]; then \
	  echo ">> node_modules present (FORCE=1 to reinstall)"; \
	else \
	  echo ">> npm install in $(LAB_FRONTEND_BASE_DIR) (first run is slow)"; \
	  npm install; \
	fi

# The webpack dev-server proxies the runtime site-config API to local.openedx.io:8000, so point
# that name at the box's own LMS (127.0.0.1:8000) for the proxy target to resolve on the box.
mfe.config: #- Generate the box-aware dev-shell site config (host $(LAB_MFE_DEV_HOST), port $(LAB_MFE_DEV_PORT))
	@test -d "$(LAB_FRONTEND_BASE_DIR)" || { \
	  echo ">> !! $(LAB_FRONTEND_BASE_DIR) not found — is lab-frontend-base in the devbox manifest?"; exit 1; }
	@cd "$(LAB_FRONTEND_BASE_DIR)"; \
	sed \
	  -e "s#http://apps.local.openedx.io:8080#http://$(LAB_MFE_DEV_HOST):$(LAB_MFE_DEV_PORT)#g" \
	  -e "s#http://apps.local.openedx.io:1995#http://apps.$(LAB_MFE_DEV_HOST):1995#g" \
	  -e "s#http://apps.local.openedx.io:1997#http://apps.$(LAB_MFE_DEV_HOST):1997#g" \
	  -e "s#http://studio.local.openedx.io:8001#http://studio.$(LAB_MFE_DEV_HOST):8001#g" \
	  -e "s#http://local.openedx.io:8000#$(LAB_MFE_LMS_URL)#g" \
	  shell/site.config.dev.tsx > "$(LAB_MFE_DEV_CONFIG)"; \
	echo ">> wrote $(LAB_MFE_DEV_CONFIG) for $(LAB_MFE_DEV_HOST):$(LAB_MFE_DEV_PORT)"
	@grep -qE "^127\.0\.0\.1[[:space:]]+local\.openedx\.io" /etc/hosts || \
	  echo "127.0.0.1 local.openedx.io" | sudo tee -a /etc/hosts >/dev/null; \
	echo ">> runtime-config proxy target: local.openedx.io -> 127.0.0.1 (LMS :8000)"

mfe.dev: mfe.deps mfe.config #- Run the frontend-base dev shell in development mode (foreground)
	@$(NVM) \
	cd "$(LAB_FRONTEND_BASE_DIR)"; \
	echo ">> dev shell: http://$(LAB_MFE_DEV_HOST):$(LAB_MFE_DEV_PORT)/"; \
	echo ">>   (laptop: make proxy.up PROJECT=lab in the devbox repo, then open the URL above)"; \
	PORT=$(LAB_MFE_DEV_PORT) SITE_CONFIG_PATH=$(LAB_MFE_DEV_CONFIG) npm run dev

mfe.dev.alt: #- Dev shell on an alternate port (PORT=<port>)
	@$(MAKE) --no-print-directory mfe.dev LAB_MFE_DEV_PORT=$(or $(PORT),3081)
