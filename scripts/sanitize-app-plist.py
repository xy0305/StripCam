#!/usr/bin/env python3
"""Strip empty UIApplicationSceneManifest that iOS 26/27 kills on launch."""
import plistlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: sanitize-app-plist.py <Info.plist>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    pl = plistlib.loads(path.read_bytes())
    manifest = pl.get("UIApplicationSceneManifest")
    if isinstance(manifest, dict):
        configs = manifest.get("UISceneConfigurations")
        if configs == {} or configs is None:
            print("Removing empty UIApplicationSceneManifest")
            pl.pop("UIApplicationSceneManifest", None)
            path.write_bytes(plistlib.dumps(pl, fmt=plistlib.FMT_BINARY))
    print("MinimumOSVersion", pl.get("MinimumOSVersion"))
    print("CFBundleShortVersionString", pl.get("CFBundleShortVersionString"))
    print("CFBundleVersion", pl.get("CFBundleVersion"))
    print("scene", pl.get("UIApplicationSceneManifest"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
