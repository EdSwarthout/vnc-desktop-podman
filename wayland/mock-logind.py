#!/usr/bin/python3
"""Minimal stand-in for systemd-logind on a private "system" bus, for mutter's native backend."""
import os, sys, dbus, dbus.service, fcntl
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SID, SEAT = 'c1', 'seat0'
SPATH = '/org/freedesktop/login1/session/' + SID
TPATH = '/org/freedesktop/login1/seat/' + SEAT
M, S, T = 'org.freedesktop.login1.Manager', 'org.freedesktop.login1.Session', 'org.freedesktop.login1.Seat'
P = 'org.freedesktop.DBus.Properties'
def log(*a): print('mock-logind:', *a, file=sys.stderr, flush=True)

class Props(dbus.service.Object):
    props = {}
    @dbus.service.method(P, in_signature='ss', out_signature='v')
    def Get(self, i, n): return self.props[i][n]
    @dbus.service.method(P, in_signature='s', out_signature='a{sv}')
    def GetAll(self, i): return self.props.get(i, {})
    @dbus.service.method(P, in_signature='ssv')
    def Set(self, i, n, v): pass
    @dbus.service.signal(P, signature='sa{sv}as')
    def PropertiesChanged(self, i, c, inv): pass

class Manager(Props):
    props = {M: {'IdleHint': dbus.Boolean(False), 'PreparingForSleep': dbus.Boolean(False),
                 'PreparingForShutdown': dbus.Boolean(False), 'Docked': dbus.Boolean(False),
                 'LidClosed': dbus.Boolean(False), 'OnExternalPower': dbus.Boolean(True),
                 'NCurrentSessions': dbus.UInt64(1)}}
    @dbus.service.method(M, in_signature='s', out_signature='o')
    def GetSession(self, s): return dbus.ObjectPath(SPATH)
    @dbus.service.method(M, in_signature='u', out_signature='o')
    def GetSessionByPID(self, p): return dbus.ObjectPath(SPATH)
    @dbus.service.method(M, in_signature='s', out_signature='o')
    def GetSeat(self, s): return dbus.ObjectPath(TPATH)
    @dbus.service.method(M, in_signature='u', out_signature='o')
    def GetUser(self, u): return dbus.ObjectPath('/org/freedesktop/login1/user/_%d' % os.getuid())
    @dbus.service.method(M, out_signature='a(susso)')
    def ListSessions(self):
        return [(SID, dbus.UInt32(os.getuid()), os.environ.get('USER', 'user'), SEAT, dbus.ObjectPath(SPATH))]
    @dbus.service.method(M, in_signature='ssss', out_signature='h')
    def Inhibit(self, what, who, why, mode):
        r, w = os.pipe(); self._keep = getattr(self, '_keep', []) + [w]
        fd = dbus.types.UnixFd(r); os.close(r); return fd
    for _n in ('CanPowerOff', 'CanReboot', 'CanSuspend', 'CanHibernate', 'CanHybridSleep', 'CanSuspendThenHibernate', 'CanRebootToFirmwareSetup'):
        exec("@dbus.service.method(M, out_signature='s')\ndef %s(self): return 'na'" % _n)
    @dbus.service.signal(M, signature='b')
    def PrepareForSleep(self, b): pass
    @dbus.service.signal(M, signature='b')
    def PrepareForShutdown(self, b): pass

class Session(Props):
    props = {S: {'Id': SID, 'Active': dbus.Boolean(True), 'State': 'active', 'Type': 'wayland',
                 'Class': 'user', 'Remote': dbus.Boolean(False), 'Name': os.environ.get('USER', 'user'),
                 'Seat': dbus.Struct((SEAT, dbus.ObjectPath(TPATH)), signature='so'),
                 'User': dbus.Struct((dbus.UInt32(os.getuid()), dbus.ObjectPath('/org/freedesktop/login1/user/self')), signature='uo'),
                 'VTNr': dbus.UInt32(0), 'TTY': '', 'Display': '', 'Service': 'mock', 'Desktop': 'GNOME',
                 'IdleHint': dbus.Boolean(False), 'LockedHint': dbus.Boolean(False)}}
    @dbus.service.method(S, in_signature='b')
    def TakeControl(self, force): log('TakeControl')
    @dbus.service.method(S)
    def ReleaseControl(self): log('ReleaseControl')
    @dbus.service.method(S, in_signature='uu', out_signature='hb')
    def TakeDevice(self, major, minor):
        name = None
        for l in open('/sys/dev/char/%d:%d/uevent' % (major, minor)):
            if l.startswith('DEVNAME='): name = '/dev/' + l.strip()[8:]
        fd = os.open(name, os.O_RDWR | os.O_CLOEXEC | os.O_NOCTTY | os.O_NONBLOCK)
        if major == 226:
            try: fcntl.ioctl(fd, 0x641e)   # DRM_IOCTL_SET_MASTER
            except OSError as e: log('SET_MASTER', name, e)
        log('TakeDevice', major, minor, name)
        r = dbus.types.UnixFd(fd); os.close(fd)
        return r, False
    @dbus.service.method(S, in_signature='uu')
    def ReleaseDevice(self, major, minor): log('ReleaseDevice', major, minor)
    @dbus.service.method(S, in_signature='uu')
    def PauseDeviceComplete(self, major, minor): pass
    for _n in ('Activate', 'Terminate', 'SetIdleHint:b', 'SetLockedHint:b', 'SetType:s', 'SetBrightness:ssu', 'SetClass:s'):
        _m, _, _s = _n.partition(':')
        _a = ''.join(', a%d' % i for i in range(len(_s)))
        exec("@dbus.service.method(S, in_signature=%r)\ndef %s(self%s): log(%r%s)" % (_s, _m, _a, _m, _a))
    @dbus.service.signal(S, signature='uus')
    def PauseDevice(self, a, b, t): pass
    @dbus.service.signal(S, signature='uuh')
    def ResumeDevice(self, a, b, f): pass
    @dbus.service.signal(S)
    def Lock(self): pass
    @dbus.service.signal(S)
    def Unlock(self): pass

class Seat(Props):
    props = {T: {'Id': SEAT, 'ActiveSession': dbus.Struct((SID, dbus.ObjectPath(SPATH)), signature='so'),
                 'CanTTY': dbus.Boolean(False), 'CanGraphical': dbus.Boolean(True)}}
    @dbus.service.method(T, in_signature='u')
    def SwitchTo(self, vt): log('SwitchTo', vt)

UI = 'org.freedesktop.login1.User'
class User(Props):
    props = {UI: {'UID': dbus.UInt32(os.getuid()), 'GID': dbus.UInt32(os.getgid()), 'Name': os.environ.get('USER', 'user'),
                  'State': 'active', 'IdleHint': dbus.Boolean(False), 'Linger': dbus.Boolean(False),
                  'Display': dbus.Struct((SID, dbus.ObjectPath(SPATH)), signature='so'),
                  'Sessions': dbus.Array([dbus.Struct((SID, dbus.ObjectPath(SPATH)), signature='so')], signature='(so)')}}

DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
name = dbus.service.BusName('org.freedesktop.login1', bus)
Manager(bus, '/org/freedesktop/login1'); User(bus, '/org/freedesktop/login1/user/_%d' % os.getuid()); User(bus, '/org/freedesktop/login1/user/self'); s = Session(bus, SPATH); Seat(bus, TPATH)
Session(bus, '/org/freedesktop/login1/session/auto'); Session(bus, '/org/freedesktop/login1/session/self')
log('ready')
GLib.MainLoop().run()
