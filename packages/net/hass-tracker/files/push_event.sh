#!/bin/sh

source /lib/functions.sh
config_load hass-tracker

source /usr/lib/hass-tracker/functions.sh
push_event $@
