#!/usr/bin/env python3
"""Check the published FFmpeg plugin digests against the bytes in the app APK."""

import argparse
import hashlib
import json
from zipfile import ZipFile


def verify(apk):
    abi = "arm64-v8a"
    for plugin in ("source-normalizer-ffmpeg", "remux-ffmpeg"):
        plugin_id = f"io.github.umbrella22.vesper.{plugin}"
        fragment = json.loads(apk.read(f"assets/vesper/plugins/{abi}/{plugin_id}.json"))
        matches = [a for a in fragment["artifacts"] if a["plugin_id"] == plugin_id]
        if len(matches) != 1 or matches[0]["integrity"]["kind"] != "sha256":
            raise ValueError(f"Invalid SHA-256 registry entry for {plugin_id}")
        artifact = matches[0]
        path = f"lib/{abi}/lib{artifact['locator']['name']}.so"
        digest = hashlib.sha256(apk.read(path)).hexdigest()
        if digest != artifact["integrity"]["digest"]:
            raise ValueError(f"{path} differs from the published digest for {plugin_id}")
        print(f"{path} SHA-256 {digest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    args = parser.parse_args()
    with ZipFile(args.apk) as apk:
        try:
            verify(apk)
        except (KeyError, ValueError) as error:
            parser.exit(1, f"{error}\n")
