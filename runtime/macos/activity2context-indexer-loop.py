#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-root", default=os.path.expanduser("~/.activity2context"))
    parser.add_argument("--config-path", default="")
    args = parser.parse_args()

    install_root = os.path.abspath(os.path.expanduser(args.install_root))
    config_path = args.config_path or os.path.join(install_root, "config.json")
    config_path = os.path.abspath(os.path.expanduser(config_path))

    run_dir = os.path.join(install_root, "run")
    os.makedirs(run_dir, exist_ok=True)
    stop_flag = os.path.join(run_dir, "indexer.stop.flag")
    indexer_script = os.path.join(install_root, "runtime", "macos", "activity2context-entity-indexer.py")

    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config not found: {config_path}")
    if not os.path.exists(indexer_script):
        raise FileNotFoundError(f"Indexer script not found: {indexer_script}")

    print("[activity2context] indexer loop started", flush=True)
    while True:
        if os.path.exists(stop_flag):
            try:
                os.remove(stop_flag)
            except OSError:
                pass
            break

        interval = 15
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            idx = cfg.get("indexer", {})
            interval = max(5, int(idx.get("intervalSeconds", 60)))
            cmd = [
                sys.executable,
                indexer_script,
                "--input-log",
                cfg.get("behaviorLog", ""),
                "--output-file",
                cfg.get("entitiesLog", ""),
                "--min-duration-seconds",
                str(int(idx.get("minDurationSeconds", 10))),
                "--max-age-minutes",
                str(int(idx.get("maxAgeMinutes", 60))),
                "--max-total",
                str(int(idx.get("maxTotal", 10))),
                "--max-web",
                str(int(idx.get("maxWeb", 3))),
                "--max-doc",
                str(int(idx.get("maxDoc", 4))),
                "--max-app",
                str(int(idx.get("maxApp", 3))),
            ]
            subprocess.run(cmd, check=False)
        except Exception as exc:
            print(f"[activity2context] indexer loop error: {exc}", flush=True)
            interval = 15

        for _ in range(interval):
            if os.path.exists(stop_flag):
                try:
                    os.remove(stop_flag)
                except OSError:
                    pass
                print("[activity2context] indexer loop stopped", flush=True)
                return 0
            time.sleep(1)

    print("[activity2context] indexer loop stopped", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
