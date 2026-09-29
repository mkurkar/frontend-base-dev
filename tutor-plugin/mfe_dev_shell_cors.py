"""
mfe_dev_shell_cors - let the frontend-base dev servers call the LMS.

The lab frontend-base dev setup runs two webpack dev servers on the box:

  * the self-contained dev shell  (make mfe.dev)      -> http://<box>:3080
  * the composed site             (make mfe.site.dev) -> http://<box>:3081

Neither origin is the LMS or the MFE host, so the LMS rejects their XHR calls (CORS preflight
fails; CSRF checks reject POSTs). This plugin appends both origins for every plausible box
hostname to CORS_ORIGIN_WHITELIST and CSRF_TRUSTED_ORIGINS.

It patches development settings only, so production/stage are untouched.

Install (on the box):
    cp mfe_dev_shell_cors.py ~/.local/share/tutor-plugins/
    tutor plugins enable mfe_dev_shell_cors
    tutor config save
    tutor dev restart lms
"""
from tutor import hooks

hooks.Filters.ENV_PATCHES.add_item(
    (
        "openedx-lms-development-settings",
        """
# frontend-base dev servers (make mfe.dev :3080, make mfe.site.dev :3081): allow their origins.
for _host in ["{{ LMS_HOST }}", "{{ MFE_HOST }}"]:
    for _port in (3080, 3081):
        _devshell_origin = f"http://{_host}:{_port}"
        if _devshell_origin not in CORS_ORIGIN_WHITELIST:
            CORS_ORIGIN_WHITELIST.append(_devshell_origin)
        if _devshell_origin not in CSRF_TRUSTED_ORIGINS:
            CSRF_TRUSTED_ORIGINS.append(_devshell_origin)
""",
    )
)
