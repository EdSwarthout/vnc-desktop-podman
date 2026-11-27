#!/usr/bin/python3
"""Minimal stand-in for systemd-logind on a private "system" bus, for mutter's headless backend."""
import fcntl
import os
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SID, SEAT = "c1", "seat0"
SPATH = "/org/freedesktop/login1/session/" + SID
TPATH = "/org/freedesktop/login1/seat/" + SEAT
M = "org.freedesktop.login1.Manager"
S = "org.freedesktop.login1.Session"
T = "org.freedesktop.login1.Seat"
P = "org.freedesktop.DBus.Properties"


def log(*args):
    print("mock-logind:", *args, file=sys.stderr, flush=True)


class Props(dbus.service.Object):
    props = {}

    @dbus.service.method(P, in_signature="ss", out_signature="v")
    def Get(self, iface, name):
        return self.props[iface][name]

    @dbus.service.method(P, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.props.get(iface, {})

    @dbus.service.method(P, in_signature="ssv")
    def Set(self, iface, name, val):
        pass

    @dbus.service.signal(P, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass


class Manager(Props):
    props = {
        M: {
            "IdleHint": dbus.Boolean(False),
            "PreparingForSleep": dbus.Boolean(False),
            "PreparingForShutdown": dbus.Boolean(False),
            "Docked": dbus.Boolean(False),
            "LidClosed": dbus.Boolean(False),
            "OnExternalPower": dbus.Boolean(True),
            "NCurrentSessions": dbus.UInt64(1),
        }
    }

    @dbus.service.method(M, in_signature="s", out_signature="o")
    def GetSession(self, sid):
        return dbus.ObjectPath(SPATH)

    @dbus.service.method(M, in_signature="u", out_signature="o")
    def GetSessionByPID(self, pid):
        return dbus.ObjectPath(SPATH)

    @dbus.service.method(M, in_signature="s", out_signature="o")
    def GetSeat(self, seat):
        return dbus.ObjectPath(TPATH)

    @dbus.service.method(M, in_signature="u", out_signature="o")
    def GetUser(self, uid):
        return dbus.ObjectPath("/org/freedesktop/login1/user/_%d" % os.getuid())

    @dbus.service.method(M, out_signature="a(susso)")
    def ListSessions(self):
        return [
            (
                SID,
                dbus.UInt32(os.getuid()),
                os.environ.get("USER", "user"),
                SEAT,
                dbus.ObjectPath(SPATH),
            )
        ]

    @dbus.service.method(M, in_signature="ssss", out_signature="h")
    def Inhibit(self, what, who, why, mode):
        r, w = os.pipe()
        self._keep = getattr(self, "_keep", []) + [w]
        fd = dbus.types.UnixFd(r)
        os.close(r)
        return fd

    @dbus.service.method(M, out_signature="s")
    def CanPowerOff(self):
        return "na"

    @dbus.service.method(M, out_signature="s")
    def CanReboot(self):
        return "na"

    @dbus.service.method(M, out_signature="s")
    def CanSuspend(self):
        return "na"

    @dbus.service.method(M, out_signature="s")
    def CanHibernate(self):
        return "na"

    @dbus.service.method(M, out_signature="s")
    def CanHybridSleep(self):
        return "na"

    @dbus.service.method(M, out_signature="s")
    def CanSuspendThenHibernate(self):
        return "na"

    @dbus.service.method(M, out_signature="s")
    def CanRebootToFirmwareSetup(self):
        return "na"

    @dbus.service.signal(M, signature="b")
    def PrepareForSleep(self, active):
        pass

    @dbus.service.signal(M, signature="b")
    def PrepareForShutdown(self, active):
        pass


class Session(Props):
    props = {
        S: {
            "Id": SID,
            "Active": dbus.Boolean(True),
            "State": "active",
            "Type": "wayland",
            "Class": "user",
            "Remote": dbus.Boolean(False),
            "Name": os.environ.get("USER", "user"),
            "Seat": dbus.Struct((SEAT, dbus.ObjectPath(TPATH)), signature="so"),
            "User": dbus.Struct(
                (dbus.UInt32(os.getuid()), dbus.ObjectPath("/org/freedesktop/login1/user/self")),
                signature="uo",
            ),
            "VTNr": dbus.UInt32(0),
            "TTY": "",
            "Display": "",
            "Service": "mock",
            "Desktop": "GNOME",
            "IdleHint": dbus.Boolean(False),
            "LockedHint": dbus.Boolean(False),
        }
    }

    @dbus.service.method(S, in_signature="b")
    def TakeControl(self, force):
        log("TakeControl")

    @dbus.service.method(S)
    def ReleaseControl(self):
        log("ReleaseControl")

    @dbus.service.method(S, in_signature="uu", out_signature="hb")
    def TakeDevice(self, major, minor):
        name = None
        with open("/sys/dev/char/%d:%d/uevent" % (major, minor)) as f:
            for line in f:
                if line.startswith("DEVNAME="):
                    name = "/dev/" + line.strip()[8:]
        fd = os.open(name, os.O_RDWR | os.O_CLOEXEC | os.O_NOCTTY | os.O_NONBLOCK)
        if major == 226:
            try:
                fcntl.ioctl(fd, 0x641E)  # DRM_IOCTL_SET_MASTER
            except OSError as e:
                log("SET_MASTER", name, e)
        log("TakeDevice", major, minor, name)
        ret = dbus.types.UnixFd(fd)
        os.close(fd)
        return ret, False

    @dbus.service.method(S, in_signature="uu")
    def ReleaseDevice(self, major, minor):
        log("ReleaseDevice", major, minor)

    @dbus.service.method(S, in_signature="uu")
    def PauseDeviceComplete(self, major, minor):
        pass

    @dbus.service.method(S)
    def Activate(self):
        log("Activate")

    @dbus.service.method(S)
    def Terminate(self):
        log("Terminate")

    @dbus.service.method(S, in_signature="b")
    def SetIdleHint(self, hint):
        log("SetIdleHint", hint)

    @dbus.service.method(S, in_signature="b")
    def SetLockedHint(self, hint):
        log("SetLockedHint", hint)

    @dbus.service.method(S, in_signature="s")
    def SetType(self, stype):
        log("SetType", stype)

    @dbus.service.method(S, in_signature="ssu")
    def SetBrightness(self, subsys, name, val):
        log("SetBrightness", subsys, name, val)

    @dbus.service.method(S, in_signature="s")
    def SetClass(self, cls):
        log("SetClass", cls)

    @dbus.service.signal(S, signature="uus")
    def PauseDevice(self, major, minor, ptype):
        pass

    @dbus.service.signal(S, signature="uuh")
    def ResumeDevice(self, major, minor, fd):
        pass

    @dbus.service.signal(S)
    def Lock(self):
        pass

    @dbus.service.signal(S)
    def Unlock(self):
        pass


class Seat(Props):
    props = {
        T: {
            "Id": SEAT,
            "ActiveSession": dbus.Struct((SID, dbus.ObjectPath(SPATH)), signature="so"),
            "CanTTY": dbus.Boolean(False),
            "CanGraphical": dbus.Boolean(True),
        }
    }

    @dbus.service.method(T, in_signature="u")
    def SwitchTo(self, vt):
        log("SwitchTo", vt)


UI = "org.freedesktop.login1.User"


class User(Props):
    props = {
        UI: {
            "UID": dbus.UInt32(os.getuid()),
            "GID": dbus.UInt32(os.getgid()),
            "Name": os.environ.get("USER", "user"),
            "State": "active",
            "IdleHint": dbus.Boolean(False),
            "Linger": dbus.Boolean(False),
            "Display": dbus.Struct((SID, dbus.ObjectPath(SPATH)), signature="so"),
            "Sessions": dbus.Array(
                [dbus.Struct((SID, dbus.ObjectPath(SPATH)), signature="so")],
                signature="(so)",
            ),
        }
    }


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    _bus_name = dbus.service.BusName("org.freedesktop.login1", bus)
    Manager(bus, "/org/freedesktop/login1")
    User(bus, "/org/freedesktop/login1/user/_%d" % os.getuid())
    User(bus, "/org/freedesktop/login1/user/self")
    Session(bus, SPATH)
    Session(bus, "/org/freedesktop/login1/session/auto")
    Session(bus, "/org/freedesktop/login1/session/self")
    Seat(bus, TPATH)
    log("ready")
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
