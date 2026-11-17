#!/bin/bash
# stop everything the experiments started (patterns live in this file, not on a command line)
for p in xfreerdp3 gnome-remote-de gnome-shell wireplumber pipewire chrome; do pkill -x "$p"; done
pkill -f '[m]ock-logind.py'; sleep 2; pkill -f '[d]bus-daemon --config-file=/home/ed/shell'; pkill -f '[d]bus-run-session'
sleep 1; rm -rf /tmp/xdg-$(id -u)
ps -eo pid,etime,args | grep -E 'gnome-shell|pipewire|wireplumber|mock-logind|system-bus|remote-desktop|xfreerdp|chrome' | grep -v grep | cut -c1-110
echo "left: $(ps -e | wc -l) processes"
