#!/usr/bin/env python3

import json
import os
import selectors
import socket
import sys
import threading
import time


RUNTIME_DIR = os.environ.get(
    "XDG_RUNTIME_DIR",
    f"/run/user/{os.getuid()}",
)

BB_AUTH_SOCKET = os.path.join(
    RUNTIME_DIR,
    "bb-auth.sock",
)

COMMAND_SOCKET = os.path.join(
    RUNTIME_DIR,
    "noctalia-bb-auth.sock",
)

PROVIDER_NAME = "noctalia-v5"
PROVIDER_PRIORITY = 100
HEARTBEAT_INTERVAL = 2.0

send_lock = threading.Lock()


def log(message):
    print(
        json.dumps(
            {
                "_bridge": True,
                "type": "bridge.log",
                "message": str(message),
            },
            separators=(",", ":"),
        ),
        flush=True,
    )


def emit(message):
    print(
        json.dumps(
            message,
            separators=(",", ":"),
        ),
        flush=True,
    )


def send_json(sock, message):
    payload = (
        json.dumps(
            message,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")

    with send_lock:
        sock.sendall(payload)


def create_command_socket():
    try:
        os.unlink(COMMAND_SOCKET)
    except FileNotFoundError:
        pass

    server = socket.socket(
        socket.AF_UNIX,
        socket.SOCK_STREAM,
    )

    server.bind(COMMAND_SOCKET)

    # Only this user may communicate with the bridge.
    os.chmod(COMMAND_SOCKET, 0o600)

    server.listen(8)
    server.setblocking(False)

    return server


def read_command(connection):
    data = bytearray()

    while True:
        chunk = connection.recv(4096)

        if not chunk:
            break

        data.extend(chunk)

        if len(data) > 65536:
            raise ValueError("command exceeds 64 KiB")

    if not data:
        return None

    return json.loads(
        data.decode("utf-8")
    )


def connect_bb_auth():
    sock = socket.socket(
        socket.AF_UNIX,
        socket.SOCK_STREAM,
    )

    sock.connect(BB_AUTH_SOCKET)
    sock.setblocking(False)

    return sock


def register_provider(sock):
    send_json(
        sock,
        {
            "type": "ui.register",
            "name": PROVIDER_NAME,
            "kind": "custom",
            "priority": PROVIDER_PRIORITY,
        },
    )

    send_json(
        sock,
        {
            "type": "subscribe",
        },
    )


def cleanup():
    try:
        os.unlink(COMMAND_SOCKET)
    except FileNotFoundError:
        pass


def run():
    command_server = create_command_socket()

    selector = selectors.DefaultSelector()

    selector.register(
        command_server,
        selectors.EVENT_READ,
        "command-server",
    )

    bb_sock = None
    bb_buffer = bytearray()

    last_heartbeat = 0.0
    reconnect_at = 0.0
    reconnect_delay = 0.5

    while True:
        now = time.monotonic()

        if bb_sock is None and now >= reconnect_at:
            try:
                bb_sock = connect_bb_auth()

                selector.register(
                    bb_sock,
                    selectors.EVENT_READ,
                    "bb-auth",
                )

                register_provider(bb_sock)

                last_heartbeat = now
                reconnect_delay = 0.5

                log("connected")

            except OSError as exc:
                bb_sock = None

                reconnect_at = (
                    now + reconnect_delay
                )

                reconnect_delay = min(
                    reconnect_delay * 2,
                    5.0,
                )

                log(
                    f"connection failed: {exc}"
                )

        if (
            bb_sock is not None
            and now - last_heartbeat
            >= HEARTBEAT_INTERVAL
        ):
            try:
                send_json(
                    bb_sock,
                    {
                        "type": "ui.heartbeat",
                    },
                )

                last_heartbeat = now

            except OSError:
                try:
                    selector.unregister(
                        bb_sock
                    )
                except Exception:
                    pass

                try:
                    bb_sock.close()
                except Exception:
                    pass

                bb_sock = None
                reconnect_at = now + 0.5
                continue

        events = selector.select(
            timeout=0.25
        )

        for key, _ in events:
            if key.data == "command-server":
                connection, _ = (
                    command_server.accept()
                )

                try:
                    command = read_command(
                        connection
                    )

                    if (
                        command is not None
                        and bb_sock is not None
                    ):
                        send_json(
                            bb_sock,
                            command,
                        )

                except Exception as exc:
                    log(
                        f"command error: {exc}"
                    )

                finally:
                    connection.close()

            elif key.data == "bb-auth":
                try:
                    chunk = bb_sock.recv(
                        4096
                    )

                    if not chunk:
                        raise ConnectionError(
                            "bb-auth disconnected"
                        )

                    bb_buffer.extend(chunk)

                    while b"\n" in bb_buffer:
                        line, _, remainder = (
                            bb_buffer.partition(
                                b"\n"
                            )
                        )

                        bb_buffer = bytearray(
                            remainder
                        )

                        if not line:
                            continue

                        try:
                            message = json.loads(
                                line.decode(
                                    "utf-8"
                                )
                            )
                        except json.JSONDecodeError:
                            continue

                        message_type = (
                            message.get(
                                "type",
                                "",
                            )
                        )

                        # Only forward information useful
                        # to the Noctalia service.
                        if message_type in (
                            "ui.registered",
                            "ui.active",
                            "session.created",
                            "session.updated",
                            "session.closed",
                            "error",
                        ):
                            emit(message)

                except (
                    OSError,
                    ConnectionError,
                ):
                    try:
                        selector.unregister(
                            bb_sock
                        )
                    except Exception:
                        pass

                    try:
                        bb_sock.close()
                    except Exception:
                        pass

                    bb_sock = None
                    bb_buffer.clear()

                    reconnect_at = (
                        time.monotonic()
                        + 0.5
                    )

                    log("disconnected")


def main():
    try:
        run()
    except KeyboardInterrupt:
        pass
    finally:
        cleanup()


if __name__ == "__main__":
    main()
