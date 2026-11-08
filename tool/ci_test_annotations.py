"""Turn `flutter test --file-reporter json:...` output into GitHub annotations.

Each failing test becomes one `::error` line with its name, file and the first
part of its error, so failures are readable from the Actions UI and API.
"""
import json
import sys


def main(path: str) -> None:
    tests, suites, errors = {}, {}, {}
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
        msg = " | ".join(e.strip().replace("\n", " ") for e in errs)[:900]
        msg = msg.replace("%", "%25").replace("\r", "").replace("::", ": :")
        print(f"::error file={file},title={name[:180]}::{msg or 'failed'}")
        count += 1
        if count >= 45:
            break


if __name__ == "__main__":
    main(sys.argv[1])
