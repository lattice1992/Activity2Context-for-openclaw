#!/usr/bin/env python3
import argparse
import datetime as dt
import os
import re
from typing import Dict, List


LINE_PATTERN = re.compile(r"^\* \[(?P<time>\d{2}:\d{2}:\d{2})\] \*\*(?P<type>[A-Z]+)\*\*: (?P<details>.+)$")
BROWSER_PATTERN = re.compile(r"^(?P<mode>Stay|Focus):(?P<sec>\d+)s \| Title:(?P<title>.*?) \| URL:(?P<url>.+)$")
APP_PATTERN = re.compile(
    r"^(?P<mode>Stay|Focus):(?P<sec>\d+)s \| App:(?P<app>[^|]+) \| Title:(?P<title>[^|]*)(?: \| RecentDoc:(?P<doc>.+))?$"
)
DOC_PATTERN = re.compile(r"^Action:(?P<action>\w+) \| Name:(?P<name>.*?) \| Path:(?P<path>.+)$")


def clean(value: str) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", value.replace("\r", " ").replace("\n", " ")).strip()


def normalize_app_name(app: str) -> str:
    x = clean(app).lower()
    if x.endswith(".exe"):
        x = x[:-4]
    return x


def parse_log_time(time_text: str, now: dt.datetime) -> dt.datetime:
    value = dt.datetime.strptime(f"{now:%Y-%m-%d} {time_text}", "%Y-%m-%d %H:%M:%S")
    if value > now + dt.timedelta(minutes=1):
        value -= dt.timedelta(days=1)
    return value


def ensure_entity(container: Dict[str, dict], key: str, kind: str) -> dict:
    if key not in container:
        container[key] = {
            "Type": kind,
            "Key": key,
            "Title": "",
            "URL": "",
            "Name": "",
            "Path": "",
            "App": "",
            "DurationSum": 0,
            "LastActive": dt.datetime.min,
            "ActionCount": 0,
        }
    return container[key]


def write_empty(output_file: str, max_age_minutes: int) -> None:
    parent = os.path.dirname(output_file) or "."
    os.makedirs(parent, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("[ACTIVITY2CONTEXT ENTITIES]\n")
        f.write(f"- (no active entities in the last {max_age_minutes} minutes)\n")
    print(f"Entity index generated: {output_file}")
    print("Selected: web=0 doc=0 app=0 total=0")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-log", default=os.path.expanduser("~/.activity2context/data/activity2context_behavior.md"))
    parser.add_argument("--output-file", default=os.path.expanduser("~/.activity2context/data/activity2context_entities.md"))
    parser.add_argument("--min-duration-seconds", type=int, default=10)
    parser.add_argument("--max-age-minutes", type=int, default=60)
    parser.add_argument("--max-total", type=int, default=10)
    parser.add_argument("--max-web", type=int, default=3)
    parser.add_argument("--max-doc", type=int, default=4)
    parser.add_argument("--max-app", type=int, default=3)
    args = parser.parse_args()

    input_log = os.path.abspath(os.path.expanduser(args.input_log))
    output_file = os.path.abspath(os.path.expanduser(args.output_file))

    if not os.path.exists(input_log):
        write_empty(output_file, args.max_age_minutes)
        return 0

    now = dt.datetime.now()
    cutoff = now - dt.timedelta(minutes=args.max_age_minutes)
    app_blacklist = {"explorer", "taskmgr", "desktop", "finder", "dock"}

    web_map: Dict[str, dict] = {}
    doc_map: Dict[str, dict] = {}
    app_map: Dict[str, dict] = {}

    with open(input_log, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    for raw in lines:
        line = raw.rstrip("\n")
        m = LINE_PATTERN.match(line)
        if not m:
            continue

        event_time = parse_log_time(m.group("time"), now)
        event_type = m.group("type")
        details = m.group("details")

        if event_type == "BROWSER":
            b = BROWSER_PATTERN.match(details)
            if not b:
                continue
            sec = int(b.group("sec"))
            title = clean(b.group("title"))
            url = clean(b.group("url"))
            if not url or url == "URL Unknown":
                continue

            key = url.lower()
            entity = ensure_entity(web_map, key, "Web")
            entity["URL"] = url
            if title:
                entity["Title"] = title
            entity["DurationSum"] += sec
            if event_time > entity["LastActive"]:
                entity["LastActive"] = event_time
            continue

        if event_type == "APP":
            a = APP_PATTERN.match(details)
            if not a:
                continue
            sec = int(a.group("sec"))
            app_raw = clean(a.group("app"))
            app_norm = normalize_app_name(app_raw)
            if not app_norm or app_norm in app_blacklist:
                continue

            title = clean(a.group("title"))
            app_entity = ensure_entity(app_map, app_norm, "App")
            app_entity["App"] = app_raw
            if title:
                app_entity["Title"] = title
            app_entity["DurationSum"] += sec
            if event_time > app_entity["LastActive"]:
                app_entity["LastActive"] = event_time

            recent_doc = clean(a.group("doc") or "")
            if recent_doc:
                doc_key = recent_doc.lower()
                doc_entity = ensure_entity(doc_map, doc_key, "Doc")
                doc_entity["Path"] = recent_doc
                doc_entity["Name"] = os.path.basename(recent_doc)
                doc_entity["DurationSum"] += sec
                if event_time > doc_entity["LastActive"]:
                    doc_entity["LastActive"] = event_time
            continue

        if event_type == "DOCUMENT":
            d = DOC_PATTERN.match(details)
            if not d:
                continue
            action = clean(d.group("action"))
            name = clean(d.group("name"))
            path = clean(d.group("path"))
            if not path:
                continue

            doc_key = path.lower()
            doc_entity = ensure_entity(doc_map, doc_key, "Doc")
            doc_entity["Path"] = path
            if name:
                doc_entity["Name"] = os.path.basename(name)
            elif not doc_entity["Name"]:
                doc_entity["Name"] = os.path.basename(path)
            if action.lower() == "changed":
                doc_entity["ActionCount"] += 1
            if event_time > doc_entity["LastActive"]:
                doc_entity["LastActive"] = event_time

    web_entities = sorted(
        [e for e in web_map.values() if e["LastActive"] >= cutoff and e["DurationSum"] >= args.min_duration_seconds],
        key=lambda x: x["LastActive"],
        reverse=True,
    )
    doc_entities = sorted(
        [
            e
            for e in doc_map.values()
            if e["LastActive"] >= cutoff and e["Path"] and e["DurationSum"] >= args.min_duration_seconds
        ],
        key=lambda x: x["LastActive"],
        reverse=True,
    )
    app_entities = sorted(
        [e for e in app_map.values() if e["LastActive"] >= cutoff and e["DurationSum"] >= args.min_duration_seconds],
        key=lambda x: x["LastActive"],
        reverse=True,
    )

    selected_web = web_entities[: args.max_web]
    selected_doc = doc_entities[: args.max_doc]
    selected_app = app_entities[: args.max_app]
    selected: List[dict] = selected_web + selected_doc + selected_app

    if len(selected) < args.max_total:
        chosen = {f"{e['Type']}|{e['Key']}" for e in selected}
        leftovers = sorted(
            [e for e in (web_entities + doc_entities + app_entities) if f"{e['Type']}|{e['Key']}" not in chosen],
            key=lambda x: x["LastActive"],
            reverse=True,
        )
        need = args.max_total - len(selected)
        selected.extend(leftovers[:need])

    selected = sorted(selected, key=lambda x: x["LastActive"], reverse=True)[: args.max_total]

    lines_out = ["[ACTIVITY2CONTEXT ENTITIES]"]
    web_idx = 0
    doc_idx = 0
    app_idx = 0

    for entity in selected:
        if entity["Type"] == "Web":
            web_idx += 1
            lines_out.append(
                f"- ID: Web_{web_idx} | Title: {clean(entity['Title'])} | Time: {entity['DurationSum']}s | URL: {clean(entity['URL'])}"
            )
            continue
        if entity["Type"] == "Doc":
            doc_idx += 1
            name = entity["Name"] or os.path.basename(entity["Path"])
            lines_out.append(
                f"- ID: Doc_{doc_idx} | Name: {clean(name)} | Edits: {entity['ActionCount']} | Path: {clean(entity['Path'])}"
            )
            continue
        if entity["Type"] == "App":
            app_idx += 1
            active = entity["LastActive"].strftime("%Y-%m-%d %H:%M:%S")
            lines_out.append(
                f"- ID: App_{app_idx} | Name: {clean(entity['App'])} | Time: {entity['DurationSum']}s | Active: {active}"
            )

    if len(lines_out) == 1:
        lines_out.append(f"- (no active entities in the last {args.max_age_minutes} minutes)")

    parent = os.path.dirname(output_file) or "."
    os.makedirs(parent, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("\n".join(lines_out) + "\n")

    print(f"Entity index generated: {output_file}")
    print(f"Selected: web={web_idx} doc={doc_idx} app={app_idx} total={len(selected)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
