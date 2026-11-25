#!/usr/bin/env python3
"""Read-only export van workspaces, tags, triggers en variabelen van een GTM-container.

Gebruik:
  ~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/gtm_export.py --container accounts/123/containers/456 [--out exports/]

Zonder --out gaat de JSON naar stdout. Er worden geen wijzigingen gedaan.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtm_common import explain_http_error, list_all, load_service  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True, help="pad, bv. accounts/123/containers/456")
    parser.add_argument("--out", help="map voor de export (bv. exports/); standaard stdout")
    args = parser.parse_args()

    service, _ = load_service()
    from googleapiclient.errors import HttpError  # pas na load_service: dan is de dependency gecontroleerd

    ws_api = service.accounts().containers().workspaces()
    result = {"container": args.container, "workspaces": []}
    try:
        workspaces = list_all(ws_api.list, "workspace", parent=args.container)
        for ws in workspaces:
            p = ws["path"]
            result["workspaces"].append({
                "name": ws.get("name"),
                "path": p,
                "tags": list_all(ws_api.tags().list, "tag", parent=p),
                "triggers": list_all(ws_api.triggers().list, "trigger", parent=p),
                "variables": list_all(ws_api.variables().list, "variable", parent=p),
            })
    except HttpError as exc:
        print(f"FOUT: {explain_http_error(exc)}", file=sys.stderr)
        return 2

    data = json.dumps(result, indent=2, ensure_ascii=False)
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        name = args.container.strip("/").replace("/", "_") + ".json"
        dest = os.path.join(args.out, name)
        with open(dest, "w", encoding="utf-8") as fh:
            fh.write(data)
        print(f"Export geschreven naar {dest}")
    else:
        print(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
