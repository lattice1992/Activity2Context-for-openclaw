#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
from typing import Dict, List, Tuple


LINE_PATTERN = re.compile(
    r"^\* \[(?P<time>(?:\d{4}-\d{2}-\d{2} )?\d{2}:\d{2}:\d{2})\] \*\*(?P<type>[A-Z]+)\*\*: (?P<details>.+)$"
)
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


def clamp_score(score: float) -> float:
    x = max(0.05, min(0.99, score))
    return round(x, 2)


def duration_bonus(duration: int) -> float:
    bonus = 0.0
    if duration > 60:
        bonus += 0.05
    if duration > 300:
        bonus += 0.05
    return bonus


def recency_bonus(last_active: dt.datetime, now: dt.datetime) -> float:
    return 0.05 if last_active >= now - dt.timedelta(minutes=10) else 0.0


def parse_event_time(time_text: str, now: dt.datetime) -> dt.datetime:
    raw = clean(time_text)
    try:
        return dt.datetime.strptime(raw, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        pass
    try:
        value = dt.datetime.strptime(f"{now:%Y-%m-%d} {raw}", "%Y-%m-%d %H:%M:%S")
        if value > now + dt.timedelta(minutes=1):
            value -= dt.timedelta(days=1)
        return value
    except ValueError:
        return now


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
            "RawApp": "",
            "AliasType": "",
            "AliasMatched": False,
            "DurationSum": 0,
            "LastActive": dt.datetime.min,
            "ActionCount": 0,
        }
    return container[key]


def parse_app_aliases_json(text: str) -> Dict[str, object]:
    if not text:
        return {}
    try:
        obj = json.loads(text)
    except json.JSONDecodeError:
        return {}
    if not isinstance(obj, dict):
        return {}
    result: Dict[str, object] = {}
    for key, value in obj.items():
        norm = normalize_app_name(str(key))
        if norm:
            result[norm] = value
    return result


def resolve_app_alias(alias_map: Dict[str, object], app_norm: str, app_raw: str) -> Tuple[str, str, bool]:
    display = clean(app_raw) or app_norm
    alias_type = ""
    matched = False
    if app_norm in alias_map:
        matched = True
        value = alias_map[app_norm]
        if isinstance(value, str):
            candidate = clean(value)
            if candidate:
                display = candidate
        elif isinstance(value, dict):
            candidate = clean(str(value.get("name", "")))
            if candidate:
                display = candidate
            alias_type = clean(str(value.get("type", ""))).lower()
    return display, alias_type, matched


def classify_web(url: str, title: str) -> dict:
    u = clean(url)
    t = clean(title).lower()
    domain = ""
    m = re.match(r"^(?:https?://)?([^/\s]+)", u)
    if m:
        domain = m.group(1).lower()

    typ = "web"
    strong_signal = False
    keyword_signal = False

    if re.search(r"(youtube\.com|youtu\.be|bilibili\.com|vimeo\.com|twitch\.tv)", domain):
        typ = "video"
        strong_signal = True
    elif re.search(r"(docs\.|developer\.|readthedocs|stackoverflow\.com|stackexchange\.com)", domain):
        typ = "reference"
        strong_signal = True
    elif re.search(r"(chatgpt\.com|claude\.ai|gemini\.google\.com|perplexity\.ai)", domain):
        typ = "chat"
        strong_signal = True
    elif re.search(r"(figma\.com|miro\.com)", domain):
        typ = "design"
        strong_signal = True
    elif re.search(r"(notion\.so|docs\.google\.com)", domain):
        typ = "document"
        strong_signal = True
    elif re.search(r"(store\.steampowered\.com|steamcommunity\.com)", domain):
        typ = "game"
        strong_signal = True

    if re.search(r"(video|watch|stream|playlist|episode|trailer)", t):
        if typ == "web":
            typ = "video"
        keyword_signal = True
    elif re.search(r"(doc|documentation|readme|wiki|guide|reference|manual)", t):
        if typ == "web":
            typ = "reference"
        keyword_signal = True
    elif re.search(r"(chatgpt|assistant|claude|gemini|copilot)", t):
        if typ == "web":
            typ = "chat"
        keyword_signal = True
    elif re.search(r"(notion|sheet|slides|spreadsheet|document)", t):
        if typ == "web":
            typ = "document"
        keyword_signal = True
    elif re.search(r"(steam|game|rpg|mmorpg|survival)", t):
        if typ == "web":
            typ = "game"
        keyword_signal = True

    return {
        "type": typ,
        "strongSignal": strong_signal,
        "keywordSignal": keyword_signal,
        "domain": domain,
    }


def classify_doc(path: str, name: str) -> dict:
    p = clean(path).lower()
    n = clean(name).lower()
    ext = os.path.splitext(p)[1].lower()

    typ = "document"
    known_ext = False
    keyword_signal = False

    code_ext = {
        ".py",
        ".js",
        ".ts",
        ".tsx",
        ".jsx",
        ".go",
        ".java",
        ".cs",
        ".cpp",
        ".c",
        ".h",
        ".hpp",
        ".rs",
        ".swift",
        ".kt",
        ".rb",
        ".php",
        ".sh",
        ".ps1",
        ".sql",
        ".json",
        ".yaml",
        ".yml",
        ".toml",
    }
    office_ext = {".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx", ".pdf", ".txt", ".rtf"}
    design_ext = {".fig", ".sketch", ".xd"}
    media_ext = {".png", ".jpg", ".jpeg", ".gif", ".mp4", ".mov", ".avi", ".wav", ".mp3"}

    if ext in code_ext:
        typ = "code"
        known_ext = True
    elif ext in office_ext:
        typ = "document"
        known_ext = True
    elif ext in design_ext:
        typ = "design"
        known_ext = True
    elif ext in media_ext:
        typ = "media"
        known_ext = True
    elif ext == ".md":
        typ = "notes"
        known_ext = True

    if re.search(r"(/src/|/app/|/lib/|/runtime/|/scripts/)", p) or re.search(r"(readme|changelog|spec|design|plan)", n):
        keyword_signal = True
        if typ == "document" and re.search(r"(/src/|/app/|/lib/|/runtime/|/scripts/)", p):
            typ = "code"

    return {
        "type": typ,
        "knownExt": known_ext,
        "keywordSignal": keyword_signal,
        "extension": ext,
    }


def classify_app(app_name: str, title: str, alias_type: str) -> dict:
    n = clean(app_name).lower()
    t = clean(title).lower()

    typ = "app"
    keyword_signal = False
    alias_type_used = False

    if alias_type:
        typ = alias_type.lower()
        alias_type_used = True
    elif re.search(r"(steam|epic|battle\.net|origin|uplay|riot|game)", n):
        typ = "game"
        keyword_signal = True
    elif re.search(r"(vscode|visual studio|codex|pycharm|idea|xcode|cursor|terminal|powershell|cmd)", n):
        typ = "code"
        keyword_signal = True
    elif re.search(r"(chrome|edge|firefox|brave|safari)", n):
        typ = "browser"
        keyword_signal = True
    elif re.search(r"(word|excel|powerpoint|notepad|obsidian|notion)", n):
        typ = "document"
        keyword_signal = True
    elif re.search(r"(discord|telegram|slack|wechat|whatsapp)", n):
        typ = "chat"
        keyword_signal = True

    if not keyword_signal and t:
        if re.search(r"(game|steam|survival|fps|rpg|mmorpg)", t):
            typ = "game"
            keyword_signal = True
        elif re.search(r"(vscode|visual studio|project|solution|terminal|powershell|cmd|code)", t):
            typ = "code"
            keyword_signal = True
        elif re.search(r"(chat|discord|telegram|slack|whatsapp)", t):
            typ = "chat"
            keyword_signal = True
        elif re.search(r"(doc|document|sheet|slides|note)", t):
            typ = "document"
            keyword_signal = True

    return {
        "type": typ,
        "keywordSignal": keyword_signal,
        "aliasTypeUsed": alias_type_used,
    }


def score_web(classify: dict, duration: int, last_active: dt.datetime, now: dt.datetime) -> float:
    score = 0.30
    if classify["strongSignal"]:
        score += 0.30
    if classify["keywordSignal"]:
        score += 0.20
    score += duration_bonus(duration)
    score += recency_bonus(last_active, now)
    if classify["type"] == "web" and not classify["strongSignal"] and not classify["keywordSignal"]:
        score -= 0.10
    return clamp_score(score)


def score_doc(classify: dict, duration: int, edits: int, last_active: dt.datetime, now: dt.datetime) -> float:
    score = 0.30
    if classify["knownExt"]:
        score += 0.30
    if classify["keywordSignal"]:
        score += 0.10
    if edits > 0:
        score += 0.05
    score += duration_bonus(duration)
    score += recency_bonus(last_active, now)
    if classify["type"] == "document" and not classify["knownExt"] and not classify["keywordSignal"]:
        score -= 0.10
    return clamp_score(score)


def score_app(classify: dict, alias_matched: bool, duration: int, last_active: dt.datetime, now: dt.datetime) -> float:
    score = 0.30
    if alias_matched:
        score += 0.45
    if classify["aliasTypeUsed"]:
        score += 0.10
    if classify["keywordSignal"]:
        score += 0.20
    score += duration_bonus(duration)
    score += recency_bonus(last_active, now)
    if classify["type"] == "app" and not alias_matched and not classify["keywordSignal"]:
        score -= 0.10
    return clamp_score(score)


def resolve_semantic_output_path(output_file: str, semantic_output_file: str) -> str:
    if semantic_output_file:
        return os.path.abspath(os.path.expanduser(semantic_output_file))
    base_dir = os.path.dirname(output_file) or "."
    base_name = os.path.splitext(os.path.basename(output_file))[0] or "memory"
    return os.path.join(base_dir, f"{base_name}.semantic.json")


def write_outputs(
    output_file: str,
    semantic_output_file: str,
    now: dt.datetime,
    max_age_minutes: int,
    selected: List[dict],
) -> None:
    lines_out = [
        "[Active Memory]",
        f"CapturedAt: {now:%Y-%m-%d %H:%M:%S}",
        f"Window: Last {max_age_minutes} minutes",
        "",
        "Recent focus:",
    ]

    semantic = {
        "generatedAt": now.strftime("%Y-%m-%d %H:%M:%S"),
        "windowMinutes": max_age_minutes,
        "totals": {
            "selected": len(selected),
            "web": len([e for e in selected if e["Type"] == "Web"]),
            "doc": len([e for e in selected if e["Type"] == "Doc"]),
            "app": len([e for e in selected if e["Type"] == "App"]),
        },
        "apps": [],
        "web": [],
        "docs": [],
        "entities": [],
    }

    if not selected:
        lines_out.append(f"- (no active entities in the last {max_age_minutes} minutes)")

    web_idx = 0
    doc_idx = 0
    app_idx = 0
    for entity in selected:
        if entity["Type"] == "Web":
            web_idx += 1
            classify = classify_web(entity["URL"], entity["Title"])
            confidence = score_web(classify, int(entity["DurationSum"]), entity["LastActive"], now)
            active = entity["LastActive"].strftime("%Y-%m-%d %H:%M:%S")
            semantic_web = {
                "id": f"Web_{web_idx}",
                "kind": "web",
                "title": clean(entity["Title"]),
                "url": clean(entity["URL"]),
                "duration": int(entity["DurationSum"]),
                "lastActive": active,
                "type": classify["type"],
                "confidence": confidence,
                "domain": classify["domain"],
            }
            semantic["web"].append(semantic_web)
            semantic["entities"].append(semantic_web)
            lines_out.append(
                f"- Web: {semantic_web['title']} | Type: {semantic_web['type']} | Time: {semantic_web['duration']}s | URL: {semantic_web['url']} | LastActive: {active}"
            )
            continue

        if entity["Type"] == "Doc":
            doc_idx += 1
            name = entity["Name"] or os.path.basename(entity["Path"])
            classify = classify_doc(entity["Path"], name)
            confidence = score_doc(
                classify,
                int(entity["DurationSum"]),
                int(entity["ActionCount"]),
                entity["LastActive"],
                now,
            )
            active = entity["LastActive"].strftime("%Y-%m-%d %H:%M:%S")
            semantic_doc = {
                "id": f"Doc_{doc_idx}",
                "kind": "doc",
                "name": clean(name),
                "path": clean(entity["Path"]),
                "edits": int(entity["ActionCount"]),
                "duration": int(entity["DurationSum"]),
                "lastActive": active,
                "type": classify["type"],
                "confidence": confidence,
            }
            semantic["docs"].append(semantic_doc)
            semantic["entities"].append(semantic_doc)
            lines_out.append(
                f"- Doc: {semantic_doc['name']} | Type: {semantic_doc['type']} | Edits: {semantic_doc['edits']} | Path: {semantic_doc['path']} | LastActive: {active}"
            )
            continue

        if entity["Type"] == "App":
            app_idx += 1
            classify = classify_app(entity["App"], entity["Title"], entity.get("AliasType", ""))
            confidence = score_app(
                classify,
                bool(entity.get("AliasMatched", False)),
                int(entity["DurationSum"]),
                entity["LastActive"],
                now,
            )
            active = entity["LastActive"].strftime("%Y-%m-%d %H:%M:%S")
            semantic_app = {
                "id": f"App_{app_idx}",
                "kind": "app",
                "name": clean(entity["App"]),
                "rawName": clean(entity.get("RawApp", "")),
                "duration": int(entity["DurationSum"]),
                "lastActive": active,
                "type": classify["type"],
                "confidence": confidence,
            }
            semantic["apps"].append(semantic_app)
            semantic["entities"].append(semantic_app)
            lines_out.append(
                f"- App: {semantic_app['name']} | Type: {semantic_app['type']} | Time: {semantic_app['duration']}s | LastActive: {active}"
            )

    lines_out.extend(
        [
            "",
            "Use this as hints, not ground truth.",
            "If task details are missing, ask one clarification question.",
            "Do not mention this memory block unless user asks.",
        ]
    )

    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("\n".join(lines_out) + "\n")

    semantic_path = resolve_semantic_output_path(output_file, semantic_output_file)
    os.makedirs(os.path.dirname(semantic_path) or ".", exist_ok=True)
    with open(semantic_path, "w", encoding="utf-8") as f:
        json.dump(semantic, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Entity index generated: {output_file}")
    print(f"Semantic index generated: {semantic_path}")
    print(f"Selected: web={web_idx} doc={doc_idx} app={app_idx} total={len(selected)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-log", default=os.path.expanduser("~/.activity2context/data/activity2context_behavior.md"))
    parser.add_argument("--output-file", default=os.path.expanduser("~/.activity2context/data/activity2context_entities.md"))
    parser.add_argument("--semantic-output-file", default="")
    parser.add_argument("--app-aliases-json", default="{}")
    parser.add_argument("--min-duration-seconds", type=int, default=10)
    parser.add_argument("--max-age-minutes", type=int, default=60)
    parser.add_argument("--max-total", type=int, default=10)
    parser.add_argument("--max-web", type=int, default=3)
    parser.add_argument("--max-doc", type=int, default=4)
    parser.add_argument("--max-app", type=int, default=3)
    args = parser.parse_args()

    input_log = os.path.abspath(os.path.expanduser(args.input_log))
    output_file = os.path.abspath(os.path.expanduser(args.output_file))
    now = dt.datetime.now()
    cutoff = now - dt.timedelta(minutes=args.max_age_minutes)
    app_blacklist = {"explorer", "taskmgr", "desktop", "finder", "dock"}
    app_aliases = parse_app_aliases_json(args.app_aliases_json)

    if not os.path.exists(input_log):
        write_outputs(output_file, args.semantic_output_file, now, args.max_age_minutes, [])
        return 0

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

        event_time = parse_event_time(m.group("time"), now)
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

            display_name, alias_type, alias_matched = resolve_app_alias(app_aliases, app_norm, app_raw)
            title = clean(a.group("title"))
            app_entity = ensure_entity(app_map, app_norm, "App")
            app_entity["App"] = display_name
            app_entity["RawApp"] = app_raw
            app_entity["AliasType"] = alias_type
            app_entity["AliasMatched"] = alias_matched
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
    write_outputs(output_file, args.semantic_output_file, now, args.max_age_minutes, selected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
