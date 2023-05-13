#!/bin/sh

dotfilesrepo="https://github.com/DusanLesan/dotfiles.git"
progsfile="https://raw.githubusercontent.com/DusanLesan/larbs/master/progs.csv"
aurhelper="yay"
repobranch="master"
nvimmanagerrepo="https://github.com/wbthomason/packer.nvim"
nvimmanagerdir=".local/share/nvim/site/pack/packer/start/packer.nvim"

### FUNCTIONS ###
basesetup() {
	passwd
	TZuser=$(cat tzfinal.tmp)
	ln -sf /usr/share/zoneinfo/$TZuser /etc/localtime
	hwclock --systohc
	echo "LANG=en_US.UTF-8" >> /etc/locale.conf
	echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
	echo "en_US ISO-8859-1" >> /etc/locale.gen
	locale-gen

	systemctl enable systemd-networkd.socket
}

installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}

error() { printf "ERROR:\\n%s\\n" "$1" >&2; exit 1;}

getuserandpass() {
	name=$(whiptail --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(whiptail --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

usercheck() {
	! { id -u "$name" >/dev/null 2>&1; } ||
		whiptail --title "WARNING" --yes-button "CONTINUE" \
			--no-button "No wait..." \
			--yesno "The user \`$name\` already exists on this system. LARBS can install for a user already existing, but it will OVERWRITE any conflicting settings/dotfiles on the user account.\\n\\nLARBS will NOT overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that LARBS will change $name's password to the one you just gave." 14 70
}

preinstallmsg() {
	whiptail --title "Let's get this party started!" --yes-button "Let's go!" \
		--no-button "No, nevermind!" \
		--yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit 1; }
}

adduserandpass() {
	whiptail --infobox "Adding user \"$name\"..." 7 50
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 \
		|| usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

refreshkeys() {
	whiptail --infobox "Refreshing Arch Keyring..." 7 40
	pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
}

manualinstall() {
	whiptail --infobox "Installing \"$1\", an AUR helper..." 7 50
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{ cd "$repodir/$1" || return 1 ; sudo -u "$name" git pull --force origin master ;}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	whiptail --title "LARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 9 70
	installpkg "$1"
}

gitmakeinstall() {
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	whiptail --title "LARBS Installation" \
		--infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 8 70
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{ cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master ;}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

aurinstall() {
	whiptail --title "LARBS Installation" \
		--infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 9 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	whiptail --title "LARBS Installation" \
		--infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 9 70
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

getpackagelist() {
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | tail -n +2 > /tmp/progs.csv
	options=$(awk -F',' '{print $2, "off"}' < /tmp/progs.csv)
	cmd=(whiptail --checklist --noitem --separate-output --ok-button "Install" --nocancel --title "Select packages to install:" "choose" 40 76 30)
	 selectedprograms=( $("${cmd[@]}" ${options} 3>&1 1>&2 2>&3) )
}

installationloop() {
	total=$(wc -w <<< $selectedprograms)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		[[ " ${selectedprograms[*]} " =~ " ${program} " ]] || continue
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv
}

putgitrepo() {
	whiptail --infobox "Downloading and installing config files..." 7 60
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 \
		--single-branch --no-tags -q --recursive -b "$branch" \
		--recurse-submodules "$1" "$dir"
	sudo -u "$name" cp -rfT "$dir" "$2"
}

compilec() {
	for sourcefile in $1/*; do
		appname="${sourcefile##*/}"
		appname="${appname//.c}"
		gcc "$sourcefile" -o "/usr/local/bin/$appname"
	done
}

systembeepoff() {
	whiptail --infobox "Getting rid of error beep sound..." 10 50
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;
}

bootloader() {
	case $(whiptail --title "Boot loader" --cancel-button "Skip" --menu "Select boot loader:" 7 70 0 "BIOS" "GRUB" "UEFI" "systemd-boot" 3>&1 1>&2 2>&3 3>&1) in
		"BIOS")
			while read -r path size; do
				args+=("$path")
				args+=(" $size")
			done < <(lsblk -dnrpo "name,size")
			cmd=(whiptail --menu "Select drive:" 22 76 16)
			choice=$("${cmd[@]}" "${args[@]}" 2>&1 >/dev/tty)
			[ -n "$choice" ] && pacman --noconfirm --needed -S grub && grub-install --target=i386-pc $choice && grub-mkconfig -o /boot/grub/grub.cfg ;;

		"UEFI")
			bootctl install
			mkdir -p ~/boot/loader/entries/
			root=$(lsblk -rpo "mountpoints,uuid" | grep -oP "^/ \K.*")
			printf "%s\n%s\n%s\n%s" \
				"title     Arch Lnux" \
				"linux     /vmlinuz-linux" \
				"initrd    /initramfs-linux.img" \
				"options   root=PARTUUID=$root rw" > ~/boot/loader/entries/arch.conf ;;
	esac
}

displaymanager() {
	aurinstall ly
	systemctl enable ly.service
}

### THE ACTUAL SCRIPT ###

basesetup

# Check if user is root on Arch distro. Install whiptail.
pacman --noconfirm --needed -Sy libnewt || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Allow user to select programs he wants
getpackagelist

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl ca-certificates base-devel git ntp zsh ; do
	whiptail --title "LARBS Installation" \
		--infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
	installpkg "$x"
done

whiptail --title "LARBS Installation" \
	--infobox "Synchronizing system time to ensure successful and secure installation of software..." 8 70
ntpdate 0.us.pool.ntp.org >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
trap 'rm -f /etc/sudoers.d/larbs-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/larbs-temp

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep -q "^Color" /etc/pacman.conf || sed -i "s/^#Color$/Color/" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sed -ir "s/#VerbosePkgLists/VerbosePkgLists\nILoveCandy/" /etc/pacman.conf
grep -q "^ParallelDownloads" /etc/pacman.conf || sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $(nproc)/" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall $aurhelper || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -f "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"
# make git ignore deleted LICENSE & README.md files
git update-index --assume-unchanged "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Set up nvim plugin manager
putgitrepo "$nvimmanagerrepo" "/home/$name/$nvimmanagerdir"
sudo -u "$name" nvim --headless -u "/home/$name/.config/nvim/lua/plugins/init.lua" -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

# Compile programs from source directories
compilec /home/$name/.local/bin/statusbar/src

# Most important command! Get rid of the beep!
systembeepoff

# Install display manager
displaymanager

# Install GRUB or systemd-boot
bootloader

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# Tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
	Identifier "libinput touchpad catchall"
	MatchIsTouchpad "on"
	MatchDevicePath "/dev/input/event*"
	Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

# Fix fluidsynth/pulseaudio issue.
grep -q "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" /etc/conf.d/fluidsynth ||
	echo "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" >> /etc/conf.d/fluidsynth

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm,/usr/local/bin/backlight,/bin/hostapd,/bin/openvpn,/usr/local/bin/kill-openvpn"

clear
