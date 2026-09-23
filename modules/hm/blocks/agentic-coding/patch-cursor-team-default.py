"""Keep local model selections when Cursor fetches a team's server default.

Reviewed against Cursor 3.19.13. Patch both the IDE and Agent window bundles.
Guard both GetDefaultModel and the asynchronous team-admin model nudges.
Model access checks and ordinary, user-controlled nudges are unaffected.
"""

import base64
import hashlib
import json
from pathlib import Path
import re
import sys


GUARD = "if(this._cursorAuthenticationService.getTeamId())return!1;"
METHOD = re.compile(
    r"async setDefaultModel\([A-Za-z0-9_$,=\[\]]+\)\{"
    r"(?=const [A-Za-z0-9_$]+=await this\.getValidatedDefaultModel\()"
)
IDENTIFIER = r"[A-Za-z_$][A-Za-z0-9_$]*"
NUDGE_GATE = re.compile(
    rf"function (?P<gate>{IDENTIFIER})\((?P<arg>{IDENTIFIER})\)\{{"
    rf"return (?P=arg)\.modelNudgesEnabled\|\|(?P<team>{IDENTIFIER})"
    r"\((?P=arg)\.experimentName\)\}"
)
APP_OPEN = re.compile(
    rf"async applyApplicationOpenModelSwitch\((?P<arg>{IDENTIFIER}),"
    rf"{IDENTIFIER},{IDENTIFIER}\)\{{"
)
TEAM_NUDGES = (
    "team_admin_model_reset_nudges",
    "team_admin_smart_auto_nudge",
    "team_admin_latest_cursor_model_impose",
)


def patch_nudges(source, name):
    gates = list(NUDGE_GATE.finditer(source))
    if len(gates) != 1 or len(APP_OPEN.findall(source)) != 1:
        raise SystemExit(f"{name}: Cursor model-nudge handlers changed; review patch")
    gate = gates[0]
    team = gate["team"]
    # Verify the helper still identifies exactly the three team-model policies.
    predicate = re.search(
        rf"function {re.escape(team)}\(({IDENTIFIER})\)\{{return "
        rf"\1!==void 0&&({IDENTIFIER})\.has\(\1\)\}}", source
    )
    if predicate is None:
        raise SystemExit(f"{name}: Cursor team-nudge predicate changed; review patch")
    variables = []
    for nudge in TEAM_NUDGES:
        matches = re.findall(rf'(?<![A-Za-z0-9_$])({IDENTIFIER})="{nudge}"', source)
        if len(matches) != 1:
            raise SystemExit(f"{name}: Cursor team-nudge policies changed; review patch")
        variables.extend(matches)
    declaration = f'{predicate[2]}=new Set([{",".join(variables)}])'
    if source.count(declaration) != 1:
        raise SystemExit(f"{name}: Cursor team-nudge policy set changed; review patch")
    # Shared by new-chat, mid-conversation, and restored-conversation switches.
    arg = gate["arg"]
    replacement = (
        f'function {gate["gate"]}({arg}){{return '
        f'!{team}({arg}.experimentName)&&{arg}.modelNudgesEnabled}}'
    )
    source = NUDGE_GATE.sub(lambda _: replacement, source)
    # Startup switches have their own entry point, outside the shared gate.
    return APP_OPEN.sub(
        lambda match: match[0] + f'if({team}({match["arg"]}.experimentName))return;',
        source,
    )


def main(app):
    product_path = app / "product.json"
    product = json.loads(product_path.read_text())
    changes = {}
    for name in ("workbench.desktop.main.js", "workbench.glass.main.js"):
        relative = f"vs/workbench/{name}"
        path = app / "out" / relative
        source = path.read_text()
        if GUARD in source or len(METHOD.findall(source)) != 1:
            raise SystemExit(f"{name}: Cursor default-model handler changed; review patch")
        # Refuse to patch if the expected caller has moved or multiplied.
        if source.count("this.setDefaultModel(") != 1 or source.count(".getDefaultModel(new ") != 1:
            raise SystemExit(f"{name}: Cursor default-model call sites changed; review patch")
        patched = METHOD.sub(lambda match: match[0] + GUARD, source)
        patched = patch_nudges(patched, name).encode()
        changes[path] = patched
        if relative in product.get("checksums", {}):
            product["checksums"][relative] = base64.b64encode(
                hashlib.sha256(patched).digest()
            ).decode().rstrip("=")

    # Validate both bundles before modifying either. Keep integrity metadata
    # consistent with our build rather than disabling Cursor's integrity check.
    for path, contents in changes.items():
        path.write_bytes(contents)
        print(f"Patched team default model: {path.name}")
    product_path.write_text(json.dumps(product, indent=2) + "\n")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
