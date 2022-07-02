#!/bin/sh

while getopts ":a:r:b:p:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit 1 ;;
	r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit 1 ;;
	b) repobranch=${OPTARG} ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/DusanLesan/dotfiles.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/DusanLesan/larbs/master/progs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"
[ -z "$repobranch" ] && repobranch="master"
nvimmanagerrepo="https://github.com/wbthomason/packer.nvim"
nvimmanagerdir=".local/share/nvim/site/pack/packer/start/packer.nvim"

### FUNCTIONS ###
installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}

error() { clear; printf "ERROR:\\n%s\\n" "$1" >&2; exit 1;}

getuserandpass() {
	name=$(whiptail --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
}

echo "$* #LARBS" >> /etc/sudoers ;}

manualinstall() {
	whiptail --infobox "Installing \"$1\", an AUR helper..." 7 50
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{ cd "$repodir/$1" || return 1 ; sudo -u "$name" git pull --force origin master ;}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" -D "$repodir/$1" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
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

displaymanager() {
	aurinstall ly
	systemctl enable ly.service
}

### THE ACTUAL SCRIPT ###

# Check if user is root on Arch distro. Install whiptail.
pacman --noconfirm --needed -Sy libnewt || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Get and verify username and password.
getuserandpass || error "User exited."

# Allow user to select programs he wants
getpackagelist

for x in curl ca-certificates base-devel git ntp zsh ; do
	whiptail --title "LARBS Installation" \
		--infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
	installpkg "$x"
done

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

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# Start/restart PulseAudio.
killall pulseaudio; sudo -u pulseaudio --start
