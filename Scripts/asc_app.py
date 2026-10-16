"""App Store Connect chores with the same API key as the TestFlight upload (see asc_signing.py for the token).

rename <name>: sets the app's name on every editable App Information localization.
testflight: waits for the newest build to finish processing, then makes sure every internal TestFlight group has it.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ETF_BUNDLE_ID, RUNNER_TEMP (the key in $RUNNER_TEMP/etf-signing/AuthKey.p8).
"""
import os
import sys
import time
import urllib.parse

from asc_signing import ApiError, call


def app_id() -> str:
    bundle = os.environ["ETF_BUNDLE_ID"]
    apps = [a for a in call("GET", "apps?filter[bundleId]=" + urllib.parse.quote(bundle))["data"] if a["attributes"]["bundleId"] == bundle]
    if not apps:
        raise ApiError(f"App Store Connect 沒有 Bundle ID 為 {bundle} 的 App。")
    print(f"App: {apps[0]['attributes']['name']} ({apps[0]['id']})")
    return apps[0]["id"]


def rename(name: str) -> None:
    app = app_id()
    changed = 0
    for info in call("GET", f"apps/{app}/appInfos")["data"]:
        state = info["attributes"].get("state") or info["attributes"].get("appStoreState")
        for loc in call("GET", f"appInfos/{info['id']}/appInfoLocalizations")["data"]:
            old = loc["attributes"].get("name")
            if old == name:
                print(f"{loc['attributes']['locale']} ({state}): already {name}")
                continue
            try:
                call("PATCH", f"appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {"name": name}}})
                print(f"{loc['attributes']['locale']} ({state}): {old} -> {name}")
                changed += 1
            except ApiError as error:
                print(f"::warning::{loc['attributes']['locale']} ({state}) not changed: {error}")
    print(f"Renamed {changed} localization(s).")


def testflight() -> None:
    app = app_id()
    deadline = time.time() + 45 * 60
    while True:
        builds = call("GET", f"builds?filter[app]={app}&sort=-uploadedDate&limit=1")["data"]
        if not builds:
            raise ApiError("還沒有任何組建。")
        build = builds[0]
        state = build["attributes"]["processingState"]
        print(f"Build {build['attributes']['version']}: {state}")
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            raise ApiError(f"組建 {build['attributes']['version']} 處理失敗（{state}），請查看 App Store Connect 的電子郵件。")
        if time.time() > deadline:
            raise ApiError("等了 45 分鐘組建仍在處理中，請稍後在 TestFlight 查看。")
        time.sleep(60)
    for group in call("GET", f"betaGroups?filter[app]={app}&limit=50")["data"]:
        attrs = group["attributes"]
        if not attrs.get("isInternalGroup"):
            continue
        if attrs.get("hasAccessToAllBuilds"):
            print(f"Internal group {attrs['name']}: gets every build automatically.")
            continue
        call("POST", f"betaGroups/{group['id']}/relationships/builds", {"data": [{"type": "builds", "id": build["id"]}]})
        print(f"Internal group {attrs['name']}: build {build['attributes']['version']} added.")
    print(f"Build {build['attributes']['version']} is ready in TestFlight.")


if __name__ == "__main__":
    try:
        if sys.argv[1] == "rename":
            rename(sys.argv[2])
        elif sys.argv[1] == "testflight":
            testflight()
        else:
            raise SystemExit("usage: asc_app.py rename <name> | testflight")
    except ApiError as error:
        print(f"::error::{error}")
        sys.exit(1)
