#!/bin/bash
# Installation script for Kiosk

# Whiptail prompt to enable Ctrl+X logout bind
if (whiptail --yesno 'Do you want to enable Ctrl+X logout bind?' --title 'Ctrl+X Option' 10 60) then
    enable_ctrl_x=true
else
    enable_ctrl_x=false
fi

# Update rc.xml based on user choice
if [ "$enable_ctrl_x" = true ]; then
    echo "Enabling Ctrl+X logout bind..
"  # Additional logic to modify C-X keybind
else
    echo "Ctrl+X logout bind is disabled."
fi

# Openbox Keyblocks setup
KIOSK_KEYBLOCKS_BEGIN
<keyboard>
    <keybind key='A-Tab'>
        <action name='nextWorkspace'/>
    </keybind>
    <keybind key='A-Shift-Tab'>
        <action name='previousWorkspace'/>
    </keybind>
    <keybind key='A-Esc'>
        <action name='cancel'/>
    </keybind>
    <keybind key='A-Space'>
        <action name='showMenu'/>
    </keybind>
    <keybind key='C-Esc'>
        <action name='exit'/>
    </keybind>
    <keybind key='A-F4'>
        <action name='close'/>
    </keybind>
    <keybind key='A-F1'/>
    <keybind key='A-F2'/>
    <keybind key='A-F3'/>
    <keybind key='A-F5'/>
    <keybind key='A-F6'/>
    <keybind key='A-F7'/>
    <keybind key='A-F8'/>
    <keybind key='A-F9'/>
    <keybind key='A-F10'/>
    <keybind key='A-F11'/>
    <keybind key='A-F12'/>
</keyboard>
KIOSK_KEYBLOCKS_END

# Leave original behaviour intact
# Additional installation components can go here.
