"""Private view transport. No core commands or game-state access live here."""
import argparse
import json
import os
import selectors
import socket
import sys

MAX_FRAME = 65536


class DialogParser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def parse_dialog(arguments):
    parser = DialogParser(add_help=False)
    kinds = parser.add_mutually_exclusive_group(required=True)
    for kind in ("question", "info", "warning", "progress", "text-info", "file-selection"):
        kinds.add_argument("--" + kind, dest="kind", action="store_const", const=kind)
    for name, default in (("title", "Live for Speed Linux"), ("text", ""), ("filename", ""),
                          ("icon", ""), ("ok-label", "OK"), ("cancel-label", "Cancel")):
        parser.add_argument("--" + name, default=default)
    parser.add_argument("--extra-button", action="append", default=[])
    for name in ("width", "height"):
        parser.add_argument("--" + name, type=int)
    for name in ("no-cancel", "no-markup", "pulsate", "auto-close", "save", "confirm-overwrite"):
        parser.add_argument("--" + name, action="store_true")
    return parser.parse_args(arguments)


def encode(value):
    data = json.dumps(value, ensure_ascii=True).encode("ascii") + b"\n"
    if len(data) > MAX_FRAME:
        raise ValueError("view frame too large")
    return data


def decode_request(data):
    if len(data) > MAX_FRAME:
        raise ValueError("view frame too large")
    value = json.loads(data)
    if not isinstance(value, dict):
        raise ValueError("invalid view request")
    if set(value) == {"args"} and isinstance(value["args"], list):
        if all(isinstance(arg, str) for arg in value["args"]):
            return value
    if set(value) == {"line"} and isinstance(value["line"], str):
        return value
    raise ValueError("invalid view request")


def client(path, arguments):
    options = parse_dialog(arguments)
    with socket.socket(socket.AF_UNIX) as connection, selectors.DefaultSelector() as selector:
        connection.settimeout(5)
        connection.connect(path)
        connection.sendall(encode({"args": arguments}))
        connection.settimeout(None)
        selector.register(connection, selectors.EVENT_READ)
        if options.kind == "progress":
            selector.register(sys.stdin, selectors.EVENT_READ)
        response = b""
        pending = b""
        while True:
            for key, _ in selector.select():
                if key.fileobj is connection:
                    chunk = connection.recv(8192)
                    if not chunk:
                        raise ValueError("view closed without a response")
                    response += chunk
                    if len(response) > MAX_FRAME:
                        raise ValueError("view response too large")
                    if b"\n" in response:
                        reply = json.loads(response.split(b"\n", 1)[0])
                        if not isinstance(reply, dict) or type(reply.get("code")) is not int or reply["code"] not in (0, 1, 2):
                            raise ValueError("invalid view response")
                        if not isinstance(reply.get("text"), str):
                            raise ValueError("invalid view response text")
                        if reply["text"]:
                            print(reply["text"])
                        return reply["code"]
                else:
                    chunk = os.read(sys.stdin.fileno(), 8192)
                    if not chunk:
                        selector.unregister(sys.stdin)
                        # EOF is not success. The controller sends an explicit completion line.
                        connection.sendall(encode({"line": "@eof"}))
                    else:
                        pending += chunk
                        if len(pending) > MAX_FRAME:
                            raise ValueError("progress line too large")
                        while b"\n" in pending:
                            line, pending = pending.split(b"\n", 1)
                            connection.sendall(encode({"line": line.decode("utf-8", errors="replace")}))
                            if line == b"100":
                                selector.unregister(sys.stdin)
                                pending = b""
                                break


def main(arguments):
    try:
        if arguments[:1] == ["--client"] and len(arguments) >= 3:
            return client(arguments[1], arguments[2:])
        if arguments == ["--probe"]:
            from lfs_linux_gtk import Gtk
            return 0 if Gtk.init_check() and Gtk.get_minor_version() >= 10 else 1
        if arguments[:1] == ["--serve"] and len(arguments) == 3:
            from lfs_linux_gtk import View
            return View(arguments[1], arguments[2]).run([])
        raise ValueError("expected --probe, --serve SOCKET ICON, or --client SOCKET DIALOG")
    except (OSError, ValueError, ImportError) as error:
        print(f"Graphical view unavailable: {error}", file=sys.stderr)
        return 2
