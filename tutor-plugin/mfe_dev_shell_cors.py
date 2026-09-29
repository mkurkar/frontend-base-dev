"""
mfe_dev_shell_cors - let the frontend-base dev servers call the LMS.

The dev setup runs two webpack dev servers on the box:

  * the self-contained dev shell  (make mfe.dev)      -> http://<box>:3080
  * the composed site             (make mfe.site.dev) -> http://<box>:3081

Neither origin is the LMS or the MFE host, so the LMS rejects their XHR calls (CORS preflight
fails; CSRF rejects POSTs with "CSRF verification failed"). This plugin appends the dev-server
origins to CORS_ORIGIN_WHITELIST and CSRF_TRUSTED_ORIGINS.

Origins are derived from the box itself:
  * LMS_HOST / MFE_HOST       (the .openedx.devbox names - required for cookie-based auth)
  * the Tailscale DNS name    (e.g. <box>.tailXXXX.ts.net - handy before the hosts entry exists)
  * the Tailscale IP

Development settings only, so production/stage are untouched.

Install (on the box):
    mkdir -p ~/.local/share/tutor-plugins
    cp mfe_dev_shell_cors.py ~/.local/share/tutor-plugins/
    tutor plugins enable mfe_dev_shell_cors
    tutor config save
    tutor dev restart lms
"""
import json
import subprocess

from tutor import hooks

DEV_PORTS = (3080, 3081)


def _tailscale_hosts() -> list[str]:
    """DNS name + IP of this box on the tailnet (empty when tailscale is unavailable)."""
    try:
        out = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True, text=True, timeout=5, check=False,
        ).stdout
        self_node = json.loads(out).get("Self", {})
        hosts = [self_node.get("DNSName", "").rstrip(".")]
        hosts += self_node.get("TailscaleIPs", []) or []
        return [h for h in hosts if h]
    except Exception:  # tailscale absent, not logged in, JSON changed... never break tutor
        return []


_extra_hosts = ", ".join(f'"{h}"' for h in _tailscale_hosts())

hooks.Filters.ENV_PATCHES.add_item(
    (
        "openedx-lms-development-settings",
        """
# frontend-base dev servers (make mfe.dev :3080, make mfe.site.dev :3081): allow their origins.
for _host in ["{{ LMS_HOST }}", "{{ MFE_HOST }}"] + [%(extra_hosts)s]:
    for _port in %(ports)s:
        _devshell_origin = f"http://{_host}:{_port}"
        if _devshell_origin not in CORS_ORIGIN_WHITELIST:
            CORS_ORIGIN_WHITELIST.append(_devshell_origin)
        if _devshell_origin not in CSRF_TRUSTED_ORIGINS:
            CSRF_TRUSTED_ORIGINS.append(_devshell_origin)
"""
        % {"extra_hosts": _extra_hosts, "ports": DEV_PORTS},
    )
)
