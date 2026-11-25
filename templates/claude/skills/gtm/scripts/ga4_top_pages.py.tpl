#!/usr/bin/env python3
"""Toont de best bekeken pagina's van een GA4-property (alleen-lezen).

Gebruik:
  ~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/ga4_top_pages.py --property 123456789 \\
      --start 2026-11-01 --end 2026-11-25 [--path-contains /blog] [--limit 10]

Gebruikt alleen de scope analytics.readonly. Schrijft niets naar schijf.
"""
import argparse
import os
import re
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtm_common import GA4_READONLY_SCOPES, build_service, explain_http_error, fail  # noqa: E402

DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}|today|yesterday|\d+daysAgo)$")
FETCH_LIMIT = 10000  # rijen per pad+titel; daarna sommeren we per pad


def check_date(value, name):
    if not DATE_RE.match(value):
        fail(f"--{name} moet YYYY-MM-DD zijn (of today, yesterday, NdaysAgo), kreeg: {value!r}")
    if value[0].isdigit() and "-" in value:
        try:
            date.fromisoformat(value)
        except ValueError:
            fail(f"--{name} is geen geldige datum: {value!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--property", required=True, help="numeriek GA4 property-ID")
    parser.add_argument("--start", required=True, help="startdatum YYYY-MM-DD")
    parser.add_argument("--end", required=True, help="einddatum YYYY-MM-DD")
    parser.add_argument("--path-contains", help="alleen pagePath's die dit bevatten, bv. /blog")
    parser.add_argument("--limit", type=int, default=10)
    args = parser.parse_args()
    if args.limit < 1:
        fail(f"--limit moet minstens 1 zijn, kreeg: {args.limit}")
    if not re.fullmatch(r"(properties/)?\d+", args.property):
        fail(f"--property moet een numeriek property-ID zijn, kreeg: {args.property!r}")
    check_date(args.start, "start")
    check_date(args.end, "end")

    data, _email = build_service("analyticsdata", "v1beta", GA4_READONLY_SCOPES)
    from googleapiclient.errors import HttpError  # pas na build_service: dan is de dependency gecontroleerd

    prop = args.property if args.property.startswith("properties/") else f"properties/{args.property}"
    body = {
        "dateRanges": [{"startDate": args.start, "endDate": args.end}],
        "dimensions": [{"name": "pagePath"}, {"name": "pageTitle"}],
        "metrics": [{"name": "screenPageViews"}],
        "orderBys": [{"metric": {"metricName": "screenPageViews"}, "desc": True}],
        "limit": FETCH_LIMIT,
    }
    if args.path_contains:
        body["dimensionFilter"] = {"filter": {
            "fieldName": "pagePath",
            "stringFilter": {"matchType": "CONTAINS", "value": args.path_contains, "caseSensitive": False},
        }}

    try:
        response = data.properties().runReport(property=prop, body=body).execute()
    except HttpError as exc:
        print(f"FOUT: {explain_http_error(exc)}", file=sys.stderr)
        return 2

    # pageTitle is een aparte dimensie: tel de weergaven per pad op en toon de
    # titel met de meeste weergaven, zodat een gewijzigde titel de top niet verschuift.
    totals = {}
    titles = {}
    for row in response.get("rows", []):
        path, title = (d["value"] for d in row["dimensionValues"])
        views = int(row["metricValues"][0]["value"])
        totals[path] = totals.get(path, 0) + views
        titles.setdefault(path, {})
        titles[path][title] = titles[path].get(title, 0) + views
    rows = sorted(totals.items(), key=lambda item: -item[1])[: args.limit]
    print(f"Property: {prop} | periode: {args.start} t/m {args.end}"
          + (f" | pad bevat: {args.path_contains}" if args.path_contains else ""))
    if not rows:
        print("Geen resultaten.")
        return 0
    print(f"{'weergaven':>10}  {'pagePath':<60}  pageTitle")
    for path, views in rows:
        candidates = {t: v for t, v in titles[path].items() if t != "(not set)"} or titles[path]
        title = max(candidates, key=candidates.get)
        print(f"{views:>10}  {path:<60}  {title}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
