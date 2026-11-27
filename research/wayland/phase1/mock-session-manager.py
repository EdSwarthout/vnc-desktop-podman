#!/usr/bin/python3
"""Minimal stand-in for gnome-session's org.gnome.SessionManager on the session bus, for a
GNOME Shell started without gnome-session (it needs systemd). Log Out, Power Off and Restart
open the Shell's own end-session dialog; when the user confirms, gnome-shell is sent SIGTERM,
which ends the gnomewl session (and so the container). Inhibitors are accepted and ignored."""
import os, signal, sys, dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SM, P = 'org.gnome.SessionManager', 'org.freedesktop.DBus.Properties'
DLG_NAME, DLG_PATH = 'org.gnome.Shell', '/org/gnome/SessionManager/EndSessionDialog'
DLG = 'org.gnome.SessionManager.EndSessionDialog'
def log(*a): print('mock-session-manager:', *a, file=sys.stderr, flush=True)

def end_session(why):
    log('ending session:', why)
    uid = os.getuid()
    for pid in os.listdir('/proc'):
        if not pid.isdigit(): continue
        try:
            if open('/proc/%s/comm' % pid).read().strip() == 'gnome-shell' and os.stat('/proc/' + pid).st_uid == uid:
                os.kill(int(pid), signal.SIGTERM); log('SIGTERM gnome-shell', pid)
        except OSError: pass

class Manager(dbus.service.Object):
    props = {'SessionName': 'gnome', 'Renderer': '', 'SessionIsActive': dbus.Boolean(True),
             'InhibitedActions': dbus.UInt32(0)}
    def __init__(self, bus):
        super().__init__(bus, '/org/gnome/SessionManager'); self.bus = bus; self.cookie = 0
        for s in ('ConfirmedLogout', 'ConfirmedShutdown', 'ConfirmedReboot'):
            bus.add_signal_receiver(lambda s=s: end_session(s), signal_name=s, dbus_interface=DLG, path=DLG_PATH)
        bus.add_signal_receiver(lambda: log('dialog canceled'), signal_name='Canceled', dbus_interface=DLG, path=DLG_PATH)
    def _dialog(self, kind):
        # type: 0 logout, 1 shutdown, 2 restart; confirmed through the signals above
        try:
            self.bus.get_object(DLG_NAME, DLG_PATH).Open(dbus.UInt32(kind), dbus.UInt32(0), dbus.UInt32(60),
                dbus.Array([], signature='o'), dbus_interface=DLG)
        except dbus.DBusException as e:
            log('no end-session dialog (%s); ending at once' % e.get_dbus_name()); end_session('no dialog')
    @dbus.service.method(SM, in_signature='u')
    def Logout(self, mode):
        log('Logout', mode)
        if mode == 0: self._dialog(0)
        else: end_session('Logout %d' % mode)
    @dbus.service.method(SM)
    def Shutdown(self): log('Shutdown'); self._dialog(1)
    @dbus.service.method(SM)
    def Reboot(self): log('Reboot'); self._dialog(2)
    @dbus.service.method(SM, out_signature='b')
    def CanShutdown(self): return True
    @dbus.service.method(SM, out_signature='b')
    def IsSessionRunning(self): return True
    @dbus.service.method(SM, in_signature='susu', out_signature='u')
    def Inhibit(self, app, xid, reason, flags): self.cookie += 1; return dbus.UInt32(self.cookie)
    @dbus.service.method(SM, in_signature='u')
    def Uninhibit(self, cookie): pass
    @dbus.service.method(SM, in_signature='u', out_signature='b')
    def IsInhibited(self, flags): return False
    @dbus.service.method(SM, out_signature='ao')
    def GetInhibitors(self): return dbus.Array([], signature='o')
    @dbus.service.method(SM, out_signature='ao')
    def GetClients(self): return dbus.Array([], signature='o')
    @dbus.service.method(SM, in_signature='ss', out_signature='o')
    def RegisterClient(self, app, startup): return dbus.ObjectPath('/org/gnome/SessionManager/Client1')
    @dbus.service.method(SM, in_signature='o')
    def UnregisterClient(self, client): pass
    @dbus.service.method(SM, in_signature='ss')
    def Setenv(self, k, v): pass
    @dbus.service.method(SM, in_signature='s', out_signature='s')
    def GetLocale(self, cat): return os.environ.get('LANG', 'C.UTF-8')
    @dbus.service.method(SM)
    def InitializationError(self, *a): pass
    @dbus.service.method(P, in_signature='ss', out_signature='v')
    def Get(self, i, n): return self.props[n]
    @dbus.service.method(P, in_signature='s', out_signature='a{sv}')
    def GetAll(self, i): return self.props if i == SM else {}
    @dbus.service.signal(SM, signature='o')
    def InhibitorAdded(self, o): pass
    @dbus.service.signal(SM, signature='o')
    def InhibitorRemoved(self, o): pass
    @dbus.service.signal(SM, signature='b')
    def SessionRunning(self, b): pass

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName(SM, bus)
Manager(bus)
log('ready')
GLib.MainLoop().run()
