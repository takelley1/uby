#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

print() {
    printf \
        "%s\n%s\n%s\n\n" \
        "--------------------------------------------------------------------" \
        "$*" \
        "--------------------------------------------------------------------"
}

add_proxy() {
    read -r -p 'Connect to proxy server? [y/n]: ' add_proxy_response
    if [[ "${add_proxy_response}" =~ [yY] ]]; then
        add_proxy_ip_and_port
        download_proxy_cert
    elif [[ "${add_proxy_response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        add_proxy
    fi
}

add_proxy_ip_and_port() {
    read -r -p 'Enter proxy IP/address and port in the format of IP:PORT : ' proxy_ip_and_port
    if [[ "${proxy_ip_and_port}" =~ [A-Za-z0-9.]+:[0-9]+ ]]; then

        # Add proxy IP and port to environment variables.
        # `tee` must be used here instead of redirecting stdout so we can elevate with sudo.
        printf \
            "%s\n%s\n%s\n%s\n" \
            "http_proxy=http://${proxy_ip_and_port}"
            'https_proxy=${http_proxy}'
            'HTTP_PROXY=${http_proxy}'
            'HTTPS_PROXY=${http_proxy}' | \
        sudo tee /etc/profile.d/proxy.sh 1>/dev/null

        sudo cp -- /etc/profile.d/proxy.sh /etc/environment.d/00proxy.conf

        # Add to apt configuration.
        printf \
            "%s\n%s\n" \
            "Acquire::http::Proxy \"http://${proxy_ip_and_port}\";" \
            "Acquire::https::Proxy \"http://${proxy_ip_and_port}\";" | \
        sudo tee /etc/apt/apt.conf.d/proxy.conf 1>/dev/null

        # Restart snapd to read new environment vars.
        systemctl restart snapd
        apt update
    else
        echo "Must use a format of IP:PORT (e.g. 10.0.0.1:3143 or myproxy.domain:8008)"
        add_proxy_ip_and_port
    fi
}

download_proxy_cert() {
    read -r -p 'Download proxy server certificate? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then
        true
    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        download_proxy_cert
    fi

    while :; do
        read -r -p 'Enter URL from which to download proxy certificate: ' proxy_cert_url
        if [[ "${proxy_cert_url}" =~ ^(http|ftp)s?:\/\/.+\. ]]; then
            proxy_dir="/usr/local/share/ca-certificates/proxy_${proxy_ip_and_port}"

            # User-added certs must be kept in their own directory.
            [[ ! -d "${proxy_dir}" ]] && sudo mkdir "${proxy_dir}"

            print "Attempting to download certificate"
            sudo wget -v "${proxy_cert_url}" --output-document="${proxy_dir}/proxy_${proxy_ip_and_port}_cert.crt"

            print "Updating certificate store"
            sudo update-ca-certificates
            return
        else
            echo 'Must use a format of ^(http|ftp)s?:\/\/.+\. (e.g. http://myserver.domain/certp.pem)'
        fi
    done
}

install_packages() {
    read -r -p 'Install apt packages? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then
        print "Installing apt packages"
        sudo apt update
        sudo apt upgrade -y
        sudo apt install -y \
            agrep \
            ansible \
            curl \
            dash \
            feh \
            flake8 \
            fzf \
            gimp \
            git \
            htop \
            iftop \
            imagemagick \
            jq \
            rxvt-unicode \
            lsof \
            lxappearance \
            mediainfo \
            mlocate \
            moreutils \
            mpv \
            net-tools \
            netcat \
            nfs-common \
            nfstrace \
            nfswatch \
            npm \
            p7zip \
            pdfgrep \
            pngcrush \
            python3-isort \
            python3-pip \
            python3-psutil \
            python3-pynvim \
            ranger \
            renameutils \
            ripgrep \
            rofi \
            rsync \
            scrot \
            shellcheck \
            sloccount \
            screen \
            sshpass \
            strace \
            sxiv \
            tcpdump \
            thunar \
            tmux \
            tuned \
            w3m \
            xclip \
            yarn \
            zip
        print "Done installing packages"
    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        install_packages
    fi
}

install_lazygit() {
    [[ ! -d /opt/lazygit ]] && sudo mkdir /opt/lazygit
    curl -s -k https://api.github.com/repos/jesseduffield/lazygit/releases/latest | \
        awk '/https:.*Linux_x86_64\.tar\.gz/ {gsub(/"/, ""); print $2}' | \
        sudo wget --no-check-certificate --input-file=- --output-document=/opt/lazygit/lazygit.tar.gz
    sudo tar xzf /opt/lazygit/lazygit.tar.gz --directory=/opt/lazygit
    sudo cp /opt/lazygit/lazygit /usr/bin/lazygit
    print "Done installing lazygit"
}

update_lazygit_check() {
    if hash lazygit &>/dev/null; then
        read -r -p 'lazygit already installed. Update to latest version? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            install_lazygit
        elif [[ "${response}" =~ [nN] ]]; then
            return
        else
            echo "Enter y or n"
            update_lazygit_check
        fi
    fi
}

install_external_packages() {
    while :; do
        read -r -p 'Install lazygit? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            update_lazygit_check
            install_lazygit
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done

    while :; do
        read -r -p 'Install hstr? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            # From https://github.com/dvorka/hstr/blob/master/INSTALLATION.md#ubuntu
            sudo add-apt-repository ppa:ultradvorka/ppa
            sudo apt update
            sudo apt install -y hstr
            print "Done installing hstr"
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done

    while :; do
        read -r -p 'Install hashicorp repo? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            # From https://www.hashicorp.com/blog/announcing-the-hashicorp-linux-repository
            curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
            sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
            sudo apt update
            print "Done installing hashicorp repo"
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done
    # TODO: docker repo
}

install_pip_packages() {
    read -r -p 'Install pip packages? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then
        print "Installing pip packages"
        sudo pip3 install \
            bashate \
            ueberzug \
            jedi \
            reorder-python-imports \
            molecule
        print "Done installing pip packages"
    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        install_pip_packages
    fi
}

install_snap_packages() {
    read -r -p 'Install snap packages? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then
        print "Installing snap packages"
        sudo snap install \
            shfmt
        print "Done installing snap packages"
    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        install_snap_packages
    fi
}

install_vim_plug() {
    read -r -p 'Install vim-plug? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then

        if [[ -r "${HOME}/.local/share/nvim/site/autoload/plug.vim" ]]; then
            print "Vim-plug already present"
            return
        fi

        print "Installing vim-plug"
        # From https://github.com/junegunn/vim-plug
        sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
        print "Done installing vim-plug"

    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        install_vim_plug
    fi
}

install_dotfiles() {
    read -r -p 'Install dotfiles? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then

        if [[ -d ${HOME}/.cfg ]]; then
            print "Dotfiles repo already present"
            return
        fi

        print "Installing dotfiles"
        cd ~ || exit 1
        git clone --bare git@github.com:takelley1/dotfiles.git "${HOME}/.cfg"

        # Move original files to a backup directory so git can checkout the dotfiles.
        print "Backing up original files"
        mkdir ~/.cfg.bak
        mv -v ~/.config/user-dirs.* .profile .bashrc -t ~/.cfg.bak/

        # Checkout the new files.
        alias dot='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
        dot checkout master
        print "Done installing dotfiles"

    elif
        [[ "${response}" =~ [nN] ]]
    then
        return
    else
        echo "Enter y or n"
        install_dotfiles
    fi
}

install_i3() {
    read -r -p 'Install and enable i3? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then
        sudo apt install -y \
            i3-wm \
            i3-lock \
            i3-blocks \
            dunst
        print "Done installing i3"
    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        install_i3
    fi
}

remove_packages() {
    # Ubuntu installs lots of unnecessary packages by default.
    read -r -p 'Remove unnecessary packages? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then
        print "Removing packages"
        sudo apt purge \
            alsa-topology-conf \
            alsa-ucm-conf \
            apport \
            apport-gtk \
            apport-symptoms \
            apt-config-icons-hidpi \
            aspell \
            aspell-en \
            avahi-autoipd \
            bluez-cups \
            bluez-obexd \
            bolt \
            brltty \
            chromium-codecs-ffmpeg-extra \
            eog \
            gamemode \
            gedit \
            gedit-common \
            gnome-bluetooth \
            gnome-calculator \
            gnome-getting-started-docs \
            gnome-initial-setup \
            gnome-logs \
            gnome-online-accounts \
            gnome-screenshot \
            gnome-system-monitor \
            gnome-user-docs \
            hplip \
            kerneloops \
            network-manager-pptp \
            network-manager-pptp-gnome \
            orca \
            ppp \
            pptp-linux \
            pulseaudio-module-bluetooth \
            seahorse \
            sound-icons \
            speech-dispatcher \
            speech-dispatcher-espeak-ng \
            switcheroo-control \
            ubuntu-docs \
            whoopsie \
            youtube-dl \
            rygel \
            openvpn \
            nano
        sudo apt autoremove -y
        print "Done removing packages"
    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        remove_packages
    fi
}

disable_services() {
    while :; do
        read -r -p 'Disable cups service? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            if [[ -e /lib/systemd/system/cups.service ]]; then
                sudo systemctl disable cups.service --now
            else
                print "cups.service not present"
            fi
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done
    while :; do
        read -r -p 'Disable WPA supplicant service? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            if [[ -e /lib/systemd/system/wpa_supplicant.service ]]; then
                sudo systemctl disable wpa_supplicant.service --now
            else
                print "wpa_supplicant.service not present"
            fi
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done
    while :; do
        read -r -p 'Disable update notifier? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            if [[ -e /etc/xdg/autostart/update-notifier.desktop ]]; then
                echo "Hidden=true" | sudo tee -a /etc/xdg/autostart/update-notifier.desktop 1>/dev/null
                killall update-notifier
            else
                print "update-notifier.desktop file not present"
            fi
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done
    while :; do
        read -r -p 'Disable pulse audio? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            if [[ -e /etc/xdg/autostart/pulseaudio.desktop ]]; then
                echo "Hidden=true" | sudo tee -a /etc/xdg/autostart/pulseaudio.desktop 1>/dev/null
                killall pulseaudio
            else
                print "pulseaudio.desktop file not present"
            fi
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done
}

enable_passwordless_sudo() {
    read -r -p 'Enable passwordless sudo for current user? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then

        if sudo grep -Eqr "${USER}.*NOPASSWD" /etc/sudoers /etc/sudoers.d; then
            print "Passwordless sudo already enabled"
            return
        fi
        printf "%s\n" "${USER}=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/passwordless_sudo_${USER}"
        print "Done configuring passwordless sudo"

    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        enable_passwordless_sudo
    fi
}

generate_ssh_key() {
    read -r -p 'Generate SSH key? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then

        if [[ -r ${HOME}/.ssh/id_ed25519.pub ]]; then
            print "SSH key already present"
        else
            print "Generating SSH key"
            ssh-keygen -t ed25519 -o -a 100
        fi
        print "Displaying SSH key and adding to clipboard"
        cat ~/.ssh/id_ed25519.pub
        xclip -selection clipboard <~/.ssh/id_ed25519.pub
        printf "%s\n" ""

    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        generate_ssh_key
    fi
}

clone_github_repo() {
    read -r -p 'Clone GitHub repo? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then

        while :; do
            read -r -p 'Enter repo clone URL: ' clone_url
            if [[ "${clone_url}" =~ ^(git|https?).+ ]]; then
                cd ~ || exit 1
                git clone --recurse-submodules "${clone_url}"
                break
            else
                echo "URL should start with git or http"
            fi
        done
        clone_github_repo

    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        clone_github_repo
    fi
}

post_install_message() {
    printf "\n"
    print "Done!"
    echo "TODO:"
    echo "- Launch nvim and run PlugInstall"
    if [[ "${add_proxy_response}" =~ [yY] ]]; then
        echo "- Add proxy cert and configuration to Firefox"
    fi
}

add_proxy

install_packages
install_external_packages
install_pip_packages
install_snap_packages
install_vim_plug
install_dotfiles
install_i3

remove_packages
disable_services

enable_passwordless_sudo
generate_ssh_key
clone_github_repo

post_install_message

exit 0
