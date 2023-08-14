#!/bin/bash

# Unofficial Bash Strict Mode
set -euo pipefail
IFS=$'\n\t'

finish() {
  local ret=$?
  if [ ${ret} -ne 0 ] && [ ${ret} -ne 130 ]; then
    echo
    echo "ERROR: Failed to setup XFCE on Termux."
    echo "Please refer to the error message(s) above"
  fi
}

trap finish EXIT

clear

echo ""
echo "This script will install XFCE Desktop in Termux along with a Debian proot"
echo ""
read -r -p "Please enter username for proot installation: " username </dev/tty

termux-setup-storage
# termux-change-repo

export DEBIAN_FRONTEND=noninteractive

pkg update
pkg upgrade -y
pkg uninstall dbus -y
pkg install wget ncurses-utils dbus proot-distro x11-repo tur-repo pulseaudio -y

#Create default directories
mkdir -p Desktop
mkdir -p Downloads
mkdir -p Documents
mkdir -p Pictures
mkdir -p Music
mkdir -p Video

setup_proot() {
#Install Debian proot
proot-distro install debian
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 apt update
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 apt upgrade -y
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 apt install sudo wget -y

#Create user
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 groupadd storage
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 groupadd wheel
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 useradd -m -g users -G wheel,audio,video,storage -s /bin/bash "$username"

#Add user to sudoers
chmod u+rw $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/sudoers
echo "$username ALL=(ALL) NOPASSWD:ALL" | tee -a $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/sudoers > /dev/null
chmod u-w  $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/sudoers

#Set proot DISPLAY
echo "export DISPLAY=:1.0" >> $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/$username/.bashrc

#Set proot aliases
echo "
alias virgl='GALLIUM_DRIVER=virpipe '
alias ls='exa -lF'
alias cat='bat '
" >> $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/$username/.bashrc

#Set proot timezone
timezone=$(getprop persist.sys.timezone)
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 rm /etc/localtime
proot-distro login debian --shared-tmp -- env DISPLAY=:1.0 cp /usr/share/zoneinfo/$timezone /etc/localtime
}

setup_xfce() {
#Install xfce4 desktop and additional packages
pkg install git neofetch virglrenderer-android papirus-icon-theme xfce4 xfce4-goodies pavucontrol-qt exa bat wmctrl tigervnc firefox -y

#Create .bashrc
cp $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/etc/skel/.bashrc $HOME/.bashrc

#Enable Sound
echo "pulseaudio --start --exit-idle-time=-1
pacmd load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1
" > $HOME/.sound
echo "source $HOME/.sound" >> $HOME/.bashrc

#Set aliases
echo "
alias debian='proot-distro login debian --user $username --shared-tmp'
alias ls='exa -lF'
alias cat='bat '
" >> $HOME/.bashrc

#Put Firefox icon on Desktop
cp $HOME/../usr/share/applications/firefox.desktop $HOME/Desktop 
chmod +x $HOME/Desktop/firefox.desktop

cat <<'EOF' > ../usr/bin/prun
#!/bin/bash
varname=$(basename $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/*)
proot-distro login debian --user $varname --shared-tmp -- env DISPLAY=:1.0 $@

EOF
chmod +x ../usr/bin/prun

#App Installer Utility
git clone https://github.com/phoenixbyrd/App-Installer.git
mv $HOME/App-Installer $HOME/.App-Installer
chmod +x $HOME/.App-Installer/*

echo "[Desktop Entry]
Version=1.0
Type=Application
Name=App Installer
Comment=
Exec=/data/data/com.termux/files/home/.App-Installer/app-installer
Icon=package-install
Path=
Terminal=false
StartupNotify=false
" > $HOME//Desktop/App-Installer.desktop
chmod +x $HOME//Desktop/App-Installer.desktop
}

setup_termux_x11() {
# Install Termux-X11
sed -i '12s/^#//' $HOME/.termux/termux.properties

curl -sL https://nightly.link/termux/termux-x11/workflows/debug_build/master/termux-companion%20packages.zip -o termux_companion_packages.zip
unzip termux_companion_packages.zip "termux-x11-nightly*.deb"
mv termux-x11-nightly*.deb termux-x11-nightly.deb
dpkg -i termux-x11-nightly.deb
rm termux_companion_packages.zip termux-x11-nightly.deb

curl -sL https://nightly.link/termux/termux-x11/workflows/debug_build/master/termux-x11-universal-debug.zip -o termux-x11.zip
unzip termux-x11.zip
mv app-universal-debug.apk $HOME/storage/downloads/
termux-open $HOME/storage/downloads/app-universal-debug.apk
rm termux-x11.zip

#Create kill_termux_x11.desktop
echo "[Desktop Entry]
Version=1.0
Type=Application
Name=Kill Termux X11
Comment=
Exec=kill_termux_x11
Icon=system-shutdown
Path=
StartupNotify=false
" > $HOME/Desktop/.kill_termux_x11.desktop

chmod +x $HOME/Desktop/.kill_termux_x11.desktop

#Create XFCE Start and Shutdown
cat <<'EOF' > start
#!/bin/bash

termux-x11 :1.0 &
virgl_test_server_android &
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity && env 
DISPLAY=:1.0 dbus-launch --exit-with-session glxfce &

mv $HOME/Desktop/.kill_termux_x11.desktop $HOME/Desktop/kill_termux_x11.desktop

EOF

chmod +x start
mv start $HOME/../usr/bin

#glxfce Hardware Acceleration XFCE Desktop
cat <<'EOF' > glxfce
#!/bin/bash

export DISPLAY=:1.0
GALLIUM_DRIVER=virpipe xfce4-session &

Terminal=false
EOF

chmod +x glxfce
mv glxfce $HOME/../usr/bin

#Shutdown Utility
cat <<'EOF' > $HOME/../usr/bin/kill_termux_x11
#!/bin/bash

# Get the process IDs of Termux-X11 and XFCE sessions
termux_x11_pid=$(pgrep -f "/system/bin/app_process / com.termux.x11.Loader :1.0")
xfce_pid=$(pgrep -f "xfce4-session")

# Check if the process IDs exist
if [ -n "$termux_x11_pid" ] && [ -n "$xfce_pid" ]; then
  # Kill the processes
  kill -9 "$termux_x11_pid" "$xfce_pid"
  echo "Termux-X11 and XFCE sessions closed."
else
  echo "Termux-X11 or XFCE session not found."
fi

mv $HOME/Desktop/kill_termux_x11.desktop $HOME/Desktop/.kill_termux_x11.desktop  

EOF

chmod +x $HOME/../usr/bin/kill_termux_x11
}

setup_vnc() {
vncserver
vncserver -kill :1.0

echo "[Desktop Entry]
Version=1.0
Type=Application
Name=Kill vncserver
Comment=
Exec=vncstop
Icon=system-shutdown
Path=
Terminal=false
StartupNotify=false
" > $HOME/Desktop/.kill_vncserver.desktop

chmod +x $HOME/Desktop/.kill_vncserver.desktop

sed -i '7s/.*/#/' $HOME/.vnc/xstartup
sed -i '11s/.*/xfce4-session \&/' $HOME/.vnc/xstartup

cat <<'EOF' > $HOME/../usr/bin/vncstart
#!/bin/bash

rm -rf $HOME/../usr/tmp/.X1*
vncserver

mv $HOME/Desktop/.kill_vncserver.desktop $HOME/Desktop/kill_vncserver.desktop

EOF

chmod +x $HOME/../usr/bin/vncstart

cat <<'EOF' > $HOME/../usr/bin/vncstop
#!/bin/bash

vncserver -kill :1.0

mv $HOME/Desktop/kill_vncserver.desktop $HOME/Desktop/.kill_vncserver.desktop

EOF

chmod +x $HOME/../usr/bin/vncstop
}

setup_theme() {
#Download Wallpaper
wget https://raw.githubusercontent.com/phoenixbyrd/Termux_XFCE/main/peakpx.jpg
mv peakpx.jpg $HOME/../usr/share/backgrounds/xfce/

#Install WhiteSur-Dark Theme
wget https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/tags/2023-04-26.zip
unzip 2023-04-26.zip
tar -xf WhiteSur-gtk-theme-2023-04-26/release/WhiteSur-Dark-44-0.tar.xz
mv WhiteSur-Dark/ $HOME/../usr/share/themes/
rm -rf WhiteSur*
rm 2023-04-26.zip

#Install Fluent Cursor Icon Theme
wget https://github.com/vinceliuice/Fluent-icon-theme/archive/refs/tags/2023-02-01.zip
unzip 2023-02-01.zip
mv Fluent-icon-theme-2023-02-01/cursors/dist $HOME/../usr/share/icons/ 
mv Fluent-icon-theme-2023-02-01/cursors/dist-dark $HOME/../usr/share/icons/
rm -rf $HOME//Fluent*
rm 2023-02-01.zip

#Setup Fonts
wget https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip
mkdir .fonts 
unzip CascadiaCode-2111.01.zip
mv otf/static/* .fonts/ && rm -rf otf
mv ttf/* .fonts/ && rm -rf ttf/
rm -rf woff2/ && rm -rf CascadiaCode-2111.01.zip

#Setup Fancybash Termux
wget https://raw.githubusercontent.com/phoenixbyrd/Termux_XFCE/main/fancybash.sh
mv fancybash.sh .fancybash.sh
echo "source $HOME/.fancybash.sh" >> $HOME/.bashrc
sed -i "326s/\\\u/$username/" $HOME/.fancybash.sh
sed -i "327s/\\\h/termux/" $HOME/.fancybash.sh

#Setup Fancybash Proot
cp .fancybash.sh $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/$username
echo "source ~/.fancybash.sh" >> $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/$username/.bashrc
sed -i '327s/termux/proot/' $HOME/../usr/var/lib/proot-distro/installed-rootfs/debian/home/$username/.fancybash.sh
}

setup_xfce_settings() {
wget https://github.com/phoenixbyrd/Termux_XFCE/raw/main/config.tar.gz
tar -xvzf config.tar.gz
rm config.tar.gz
}

setup_proot
setup_xfce
setup_termux_x11
setup_vnc
setup_theme
setup_xfce_settings

rm setup.sh

########
##Finish ##
########

clear -x
echo ""
echo ""
echo "Setup completed successfully!"
echo ""
echo "You can now connect to your Termux XFCE4 Desktop after restarting termux."
echo ""
echo "To open the desktop use the command start"
echo ""
echo "This will start the termux-x11 server in termux and start the XFCE Desktop open the installed Termux-X11 app."
echo ""
echo "To exit, doublick the exit icon on the desktop"
echo ""
echo "To start vnc use command vncstart and to exit, doublick exit icon on desktop"
echo ""
echo "Enjoy your Termux XFCE4 Desktop experience!"
echo ""
echo ""
