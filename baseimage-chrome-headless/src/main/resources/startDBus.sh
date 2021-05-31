#!/bin/bash

if [[ -f '/var/run/dbus/pid' ]]
then
   rm /var/run/dbus/pid
fi

exec dbus-daemon --config-file=/usr/share/dbus-1/system.conf
