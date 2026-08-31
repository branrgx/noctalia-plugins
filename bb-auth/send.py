#!/usr/bin/env python3

import json
import os
import socket
import sys


RUNTIME_DIR = os.environ.get(
    "XDG_RUNTIME_DIR",
    f"/run/user/{os.getuid()}",
)

COMMAND_SOCKET = os.path.join(
    RUNTIME_DIR,
    "noctalia-bb-auth.sock",
)


def main():
    if len(sys.argv) != 2:
        return 1

    payload_path = sys.argv[1]

    try:
        with open(
            payload_path,
            "r",
            encoding="utf-8",
        ) as file:
            message = json.load(file)

    finally:
        try:
            os.unlink(payload_path)
        except FileNotFoundError:
            pass

    # Only allow the two commands that the
    # Noctalia panel needs.
    if message.get("type") not in (
        "session.respond",
        "session.cancel",
    ):
        return 1

    data = (
        json.dumps(
            message,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")

    sock = socket.socket(
        socket.AF_UNIX,
        socket.SOCK_STREAM,
    )

    try:
        sock.connect(COMMAND_SOCKET)
        sock.sendall(data)
        sock.shutdown(socket.SHUT_WR)

    finally:
        sock.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
