"""Turn `flutter test --file-reporter json:...` output into GitHub annotations.

Each failing test becomes one `::error` line with its name, file and the first
part of its error, so failures are readable from the Actions UI and API.
"""
import json
import sys


def main(path: str) -> None:
    tests, suites, errors, prints = {}, {}, {}, {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            t = ev.get("type")
            if t == "suite":
                suites[ev["suite"]["id"]] = ev["suite"].get("path", "")
            elif t == "testStart":
                tests[ev["test"]["id"]] = ev["test"]
            elif t == "print":
                prints.setdefault(ev.get("testID"), []).append(ev.get("message", ""))
            elif t == "error":
                errors.setdefault(ev["testID"], []).append(ev.get("error", ""))
            elif t == "testDone" and ev.get("result") != "success" and not ev.get("hidden"):
                errors.setdefault(ev["testID"], [])
    count = 0
    for tid, errs in errors.items():
        test = tests.get(tid, {})
        name = test.get("name", f"test {tid}")
        if name.startswith("loading "):
            name = "COMPILE/LOAD " + name
        file = suites.get(test.get("suiteID"), "")
        log = "\n".join(prints.get(tid, []))
        # Keep the most useful part of Flutter's exception dump.
        start = log.find("EXCEPTION CAUGHT")
        detail = log[start:] if start >= 0 else log
        detail = "\n".join(
            ln for ln in detail.splitlines()
            if ln.strip() and not ln.startswith("#") and "package:flutter/" not in ln
        )[:3500]
        msg = (" | ".join(e.strip() for e in errs) + "\n" + detail).strip()
        msg = msg.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
        title = name[:180].replace("%", "%25").replace(",", "%2C").replace(":", "%3A")
        print(f"::error file={file},title={title}::{msg or 'failed'}")
        count += 1
        if count >= 45:
            break


if __name__ == "__main__":
    main(sys.argv[1])
