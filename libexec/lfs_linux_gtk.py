"""Native renderer for the existing desktop controller; no installer logic."""
import os
from pathlib import Path
import socket

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk

from lfs_linux_dialog import MAX_FRAME, decode_request, encode, parse_dialog

PHASES = (("runtime", "Prepare compatibility"), ("game", "Install game"),
          ("graphics", "Prepare graphics"), ("launch", "Start game"))


def label(text, style=None):
    widget = Gtk.Label(label=text, xalign=0, wrap=True)
    widget.set_hexpand(True)
    if style:
        widget.add_css_class(style)
    return widget


def text_view(text):
    view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                        wrap_mode=Gtk.WrapMode.WORD_CHAR)
    view.get_buffer().set_text(text)
    scroll = Gtk.ScrolledWindow(min_content_height=140, vexpand=True)
    scroll.set_child(view)
    return scroll, view.get_buffer()


class View(Gtk.Application):
    def __init__(self, path, icon):
        super().__init__(application_id="io.github.mitzracing.live_for_speed_linux",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.path, self.icon = path, icon
        self.sessions = {}
        self.active = None
        self.progress = None
        self.completed = set()
        self.connect("activate", self.activate)

    def activate(self, _application):
        self.hold()
        self.window = Gtk.ApplicationWindow(application=self, title="Live for Speed Linux",
                                           default_width=620, default_height=480)
        self.window.set_icon_name(self.get_application_id())
        self.window.connect("close-request", self.close_requested)
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.key_pressed)
        self.window.add_controller(keys)
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20,
                       margin_start=24, margin_end=24, margin_top=24, margin_bottom=20)
        body.add_css_class("lfs-view")
        self.window.set_child(body)
        header = Gtk.Box(spacing=16)
        if Path(self.icon).is_file():
            image = Gtk.Image.new_from_gicon(Gio.FileIcon.new(Gio.File.new_for_path(self.icon)))
        else:
            image = Gtk.Image.new_from_icon_name(self.icon)
        image.set_pixel_size(64)
        image.set_tooltip_text("Live for Speed Linux community logo")
        header.append(image)
        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                        valign=Gtk.Align.CENTER)
        names.append(label("Live for Speed Linux", "brand"))
        names.append(label("Install. Play. Race.", "dim-label"))
        header.append(names)
        body.append(header)
        self.content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, vexpand=True)
        viewport = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        viewport.set_child(self.content)
        body.append(viewport)
        # Keep Cancel outside the area that scrolls for Details or larger fonts.
        self.actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        body.append(self.actions)
        footer = Gtk.Box(spacing=12)
        footer.append(label("Community launcher · Official game downloads", "dim-label"))
        footer.append(Gtk.LinkButton.new_with_label("https://www.lfs.net/agreement", "LFS license"))
        body.append(footer)
        css = Gtk.CssProvider()
        css.load_from_data(b".lfs-view .brand {font-size: 1.8em; font-weight: bold;} "
                           b".lfs-view .primary {background: #3bc7de; color: #07131b;} "
                           b".lfs-view .step {padding: 3px 0;}")
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(self.path)
        os.chmod(self.path, 0o600)
        self.listener.listen(4)
        self.listener.setblocking(False)
        GLib.io_add_watch(self.listener.fileno(), GLib.IO_IN, self.accept)
        Path(self.path + ".ready").touch(mode=0o600)

    def accept(self, _fd, _condition):
        connection, _address = self.listener.accept()
        connection.setblocking(False)
        request = {"socket": connection, "buffer": b"", "options": None}
        self.sessions[connection] = request
        request["watch"] = GLib.io_add_watch(connection.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
                                              self.receive, request)
        return GLib.SOURCE_CONTINUE

    def receive(self, _fd, _condition, request):
        try:
            chunk = request["socket"].recv(8192)
            if not chunk:
                self.finish(request, 2)
                return GLib.SOURCE_REMOVE
            request["buffer"] += chunk
            if len(request["buffer"]) > MAX_FRAME:
                raise ValueError("view frame too large")
            while b"\n" in request["buffer"]:
                frame, request["buffer"] = request["buffer"].split(b"\n", 1)
                message = decode_request(frame)
                if request["options"] is None and "args" in message:
                    request["options"] = parse_dialog(message["args"])
                    # Recovery and progress clients can arrive in either order.
                    # A late progress request must not dismiss the confirmation.
                    if request["options"].kind == "progress":
                        if self.progress is not None:
                            raise ValueError("another progress request is active")
                        self.progress = request
                        self.build(request)
                        if self.active is None:
                            self.show(request)
                    else:
                        if self.active is not None and self.active is not self.progress:
                            raise ValueError("another dialog is active")
                        self.build(request)
                        self.show(request)
                elif request is self.progress and "line" in message:
                    self.progress_line(request, message["line"])
                else:
                    raise ValueError("unexpected view message")
                if request["socket"] not in self.sessions:
                    return GLib.SOURCE_REMOVE
        except (OSError, ValueError) as error:
            print(f"View request failed: {error}", flush=True)
            self.finish(request, 2)
            return GLib.SOURCE_REMOVE
        return GLib.SOURCE_CONTINUE

    def show(self, request):
        child = self.content.get_first_child()
        if child is not None:
            self.content.remove(child)
        self.content.append(request["box"])
        child = self.actions.get_first_child()
        if child is not None:
            self.actions.remove(child)
        self.actions.append(request["buttons"])
        self.active = request
        self.window.present()
        if request.get("default") is not None:
            self.window.set_default_widget(request["default"])
            request["default"].grab_focus()
        else:
            self.window.set_default_widget(None)
        if request["options"].kind == "file-selection":
            self.choose_file(request)

    def button(self, request, row, text, code, result="", primary=False):
        button = Gtk.Button(label=text)
        if primary:
            button.add_css_class("primary")
            request["default"] = button
        button.connect("clicked", lambda _button: self.finish(request, code, result))
        row.append(button)

    def build(self, request):
        options = request["options"]
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, vexpand=True)
        request["box"] = box
        request["default"] = None
        message = label(options.text)
        box.append(message)
        if options.kind == "text-info":
            with open(options.filename, encoding="utf-8") as report:
                text = report.read(MAX_FRAME)
            scroll, _buffer = text_view(text)
            box.append(scroll)
        if options.kind == "progress":
            self.build_progress(request, box, message)
        row = Gtk.Box(spacing=10, halign=Gtk.Align.END)
        request["buttons"] = row
        for extra in options.extra_button:
            self.button(request, row, extra, 1, extra)
        if options.kind == "question" or (options.kind == "progress" and not options.no_cancel):
            self.button(request, row, options.cancel_label, 1)
        if options.kind not in ("progress", "file-selection"):
            self.button(request, row, options.ok_label, 0, primary=True)

    def build_progress(self, request, box, message):
        spinner = Gtk.Spinner(spinning=True, halign=Gtk.Align.START)
        box.append(spinner)
        meter = label("")
        meter.set_visible(False)
        box.append(meter)
        progress = Gtk.ProgressBar(visible=False)
        box.append(progress)
        steps = {}
        checklist = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        for phase, title in PHASES:
            steps[phase] = label("○  " + title, "step")
            checklist.append(steps[phase])
        box.append(checklist)
        details = Gtk.Expander(label="Details")
        scroll, buffer = text_view("")
        details.set_child(scroll)
        box.append(details)
        request.update(message=message, spinner=spinner, bar=progress, meter=meter, steps=steps,
                       detail_buffer=buffer, history=[], phase=None)
        self.set_phase(request, None)

    def set_phase(self, request, phase):
        keys = [item[0] for item in PHASES]
        previous = request["phase"]
        if phase == "ready":
            self.completed.update(keys[:3])
        elif previous in keys and phase in keys and keys.index(phase) > keys.index(previous):
            self.completed.add(previous)
        request["phase"] = phase
        for key, title in PHASES:
            prefix = "●" if key == phase else "✓" if key in self.completed else "○"
            request["steps"][key].set_text(f"{prefix}  {title}")

    def progress_line(self, request, line):
        if line == "100":
            self.finish(request, 0)
        elif line == "@eof":
            self.finish(request, 2)
        elif line == "@hide":
            self.window.set_visible(False)
        elif line.startswith("#"):
            text = line[1:].strip()
            request["message"].set_text(text)
            if not request["history"] or request["history"][-1] != text:
                request["history"] = (request["history"] + [text])[-128:]
                request["detail_buffer"].set_text("\n".join(request["history"]))
        elif line.startswith("@phase\t"):
            self.set_phase(request, line.split("\t", 1)[1])
        elif line.startswith("@bytes\t"):
            _kind, current, total = line.split("\t")
            current, total = int(current), int(total)
            if not 0 <= current <= total or total <= 0:
                raise ValueError("invalid download progress")
            request["bar"].set_fraction(current / total)
            request["meter"].set_text(f"{current / total:.0%} of this download")
            request["meter"].set_visible(True)
            request["bar"].set_visible(True)
            request["spinner"].set_spinning(False)
            request["spinner"].set_visible(False)
        elif line == "@indeterminate":
            request["meter"].set_visible(False)
            request["bar"].set_visible(False)
            request["spinner"].set_visible(True)
            request["spinner"].set_spinning(True)

    def choose_file(self, request):
        chooser = Gtk.FileDialog(title=request["options"].title,
                                 initial_name=Path(request["options"].filename).name)
        request["chooser"] = chooser
        request["cancellable"] = Gio.Cancellable()
        chooser.save(self.window, request["cancellable"], self.file_chosen, request)

    def file_chosen(self, chooser, result, request):
        try:
            file = chooser.save_finish(result)
            path = file.get_path()
            self.finish(request, 0, path) if path else self.finish(request, 1)
        except GLib.Error:
            self.finish(request, 1)

    def finish(self, request, code, text=""):
        connection = request["socket"]
        if connection not in self.sessions:
            return
        if "cancellable" in request:
            request["cancellable"].cancel()
        try:
            connection.sendall(encode({"code": code, "text": text}))
        except (OSError, ValueError):
            pass
        GLib.source_remove(request["watch"])
        del self.sessions[connection]
        connection.close()
        if "buttons" in request:
            request["buttons"].set_sensitive(False)
        if request is self.progress:
            request["spinner"].set_spinning(False)
            self.progress = None
            if code != 0:
                request["message"].set_text("Stopping safely… Your downloaded data is kept.")
                request["box"].set_sensitive(False)
        if request is self.active:
            self.active = None
            if self.progress is not None:
                self.show(self.progress)
            else:
                request["box"].set_sensitive(False)

    def key_pressed(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.close_requested(self.window)
            return True
        return False

    def close_requested(self, _window):
        if self.active is not None:
            if self.active["options"].no_cancel:
                return True
            self.finish(self.active, 1)
        return True
