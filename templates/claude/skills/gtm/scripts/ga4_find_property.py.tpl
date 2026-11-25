#!/usr/bin/env python3
"""Zoekt het GA4 property-ID bij een measurement-ID (alleen-lezen).

Gebruik:
  ~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/ga4_find_property.py [--measurement-id G-XXXXXXX]

Zonder argument: toont alle zichtbare accounts en properties.
Gebruikt alleen de scope analytics.readonly en toont nooit de private key.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtm_common import GA4_READONLY_SCOPES, build_service, explain_http_error, list_all  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--measurement-id", help="measurement-ID, bv. G-6K97PVKZFQ")
    args = parser.parse_args()

    admin, email = build_service("analyticsadmin", "v1beta", GA4_READONLY_SCOPES)
    from googleapiclient.errors import HttpError  # pas na build_service: dan is de dependency gecontroleerd

    print(f"Service account: {email}")
    try:
        summaries = list_all(admin.accountSummaries().list, "accountSummaries", pageSize=200)
    except HttpError as exc:
        print(f"FOUT: {explain_http_error(exc)}", file=sys.stderr)
        return 2

    if not summaries:
        print("Geen GA4-accounts zichtbaar: het service account is (nog) niet toegevoegd aan een GA4-account/property.")
        return 3

    wanted = (args.measurement_id or "").strip().upper()
    if not wanted:
        for acc in summaries:
            print(f"\nAccount: {acc.get('displayName')} ({acc.get('account')})")
            for prop in acc.get("propertySummaries", []):
                print(f"  - {prop.get('displayName')} | {prop.get('property')}")
        return 0

    for acc in summaries:
        for prop in acc.get("propertySummaries", []):
            try:
                streams = list_all(admin.properties().dataStreams().list, "dataStreams",
                                   parent=prop["property"], pageSize=200)
            except HttpError as exc:
                print(f"  FOUT bij streams van {prop['property']}: {explain_http_error(exc)}", file=sys.stderr)
                continue
            for stream in streams:
                web = stream.get("webStreamData", {})
                if (web.get("measurementId") or "").upper() == wanted:
                    print(f"\nGevonden: {wanted}")
                    print(f"Property-ID: {prop['property'].split('/')[-1]}")
                    print(f"Propertynaam: {prop.get('displayName')}")
                    print(f"Account: {acc.get('displayName')} ({acc.get('account')})")
                    print(f"Stream: {stream.get('displayName')} | {web.get('defaultUri', '-')}")
                    return 0
    print(f"Geen property gevonden voor measurement-ID {wanted} binnen de zichtbare accounts.")
    return 4


if __name__ == "__main__":
    sys.exit(main())
