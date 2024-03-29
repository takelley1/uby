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
            "http_proxy=http://${proxy_ip_and_port}" \
            'https_proxy=${http_proxy}' \
            'HTTP_PROXY=${http_proxy}' \
            'HTTPS_PROXY=${http_proxy}' |
            sudo tee /etc/profile.d/proxy.sh 1>/dev/null

        sudo cp -- /etc/profile.d/proxy.sh /etc/environment.d/00proxy.conf

        # Add to apt configuration.
        printf \
            "%s\n%s\n" \
            "Acquire::http::Proxy \"http://${proxy_ip_and_port}\";" \
            "Acquire::https::Proxy \"http://${proxy_ip_and_port}\";" |
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
            apt-rdepends \
            autojump \
            bat \
            curl \
            dash \
            feh \
            flake8 \
            fzf \
            gcc \
            gimp \
            git \
            htop \
            iftop \
            imagemagick \
            jq \
            libmagic-dev \
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
            rxvt-unicode \
            screen \
            scrot \
            shellcheck \
            sloccount \
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
    curl -s -k https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
        awk '/https:.*Linux_x86_64\.tar\.gz/ {gsub(/"/, ""); print $2}' |
        sudo wget --no-check-certificate --input-file=- --output-document=/opt/lazygit/lazygit.tar.gz
    sudo tar xzf /opt/lazygit/lazygit.tar.gz --directory=/opt/lazygit
    sudo cp /opt/lazygit/lazygit /usr/bin/lazygit
    print "Done installing lazygit"
}

install_lazygit_check() {
    if hash lazygit &>/dev/null; then
        read -r -p 'lazygit already installed. Update to latest version? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            install_lazygit
        elif [[ "${response}" =~ [nN] ]]; then
            return
        else
            echo "Enter y or n"
            install_lazygit_check
        fi
    else
        install_lazygit
    fi
}

install_external_packages() {
    while :; do
        read -r -p 'Install lazygit? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            install_lazygit_check
            break
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done

    while :; do
        read -r -p 'Install lf? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            [[ ! -d /opt/lf ]] && sudo mkdir /opt/lf
            curl -s -k https://api.github.com/repos/gokcehan/lf/releases/latest |
                awk '/https:.*linux-amd64\.tar\.gz/ {gsub(/"/, ""); print $2}' |
                sudo wget --no-check-certificate --input-file=- --output-document=/opt/lf/lf.tar.gz
            sudo tar xzf /opt/lf/lf.tar.gz --directory=/opt/lf
            sudo cp /opt/lf/lf /usr/bin/lf

            # Also install the ctpv previewer.
            git clone --depth 1 https://github.com/NikitaIvanovV/ctpv /opt/ctpv
            cd ctpv
            sudo make install
            cd -

            print "Done installing lf"
            break
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
            break
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done

    while :; do
        read -r -p 'Install neovim ppa? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            sudo add-apt-repository ppa:neovim-ppa/stable
            sudo apt update
            print "Done installing neovim ppa"
            break
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done

    while :; do
        read -r -p 'Install tflint? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            # From https://github.com/terraform-linters/tflint#installation
            curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
            print "Done installing tflint"
            break
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
            curl -kfsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
            sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

            # Disable cert validation.
            printf \
                "%s\n%s\n" \
                'Acquire::https::apt.releases.hashicorp.com::Verify-Peer "false";' \
                'Acquire::https::apt.releases.hashicorp.com::Verify-Host "false";' |
                sudo tee /etc/apt/apt.conf.d/99hashicorp.conf 1>/dev/null

            sudo apt update
            print "Done installing hashicorp repo"
            break
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

        # Required for ueberzug
        sudo apt install -y \
            libx11-dev \
            libxext-dev

        sudo pip3 \
            --trusted-host pypi.org \
            --trusted-host pypi.python.org \
            --trusted-host files.pythonhosted.org \
            install \
            bashate \
            flake8 \
            jedi \
            molecule \
            pydocstyle \
            pylint \
            reorder-python-imports \
            ueberzug \
            yamllint
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
        sh -c 'curl -kfLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
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
        git config --global http.sslVerify "false"
        cd ~ || exit 1
        git clone --bare https://github.com/takelley1/dotfiles.git "${HOME}/.cfg"

        # Attempt to checkout files. If not possible, move the files that would've been
        #   overwritten to a backup directory.
        if ! git --git-dir="${HOME}/.cfg/" --work-tree="${HOME}" checkout master; then
            [[ ! -d ~/.cfg.bak ]] && mkdir ~/.cfg.bak
            # Must allow the git command to fail here.
            set +e
            git --git-dir="${HOME}/.cfg/" --work-tree="${HOME}" checkout master 2>/dev/stdout |
                tail -n +2 |
                head -n -2 |
                xargs mv -t ~/.cfg.bak/
            set -e
            git --git-dir="${HOME}/.cfg/" --work-tree="${HOME}" checkout master
        fi
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
            openvpn \
            orca \
            ppp \
            pptp-linux \
            pulseaudio-module-bluetooth \
            rygel \
            seahorse \
            sound-icons \
            speech-dispatcher \
            speech-dispatcher-espeak-ng \
            switcheroo-control \
            ubuntu-docs \
            whoopsie \
            youtube-dl
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
            break
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
            break
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
            break
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
            break
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
        # Allow this to fail if no X display is detected.
        set +e
        xclip -selection clipboard <~/.ssh/id_ed25519.pub
        set -e
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

clone_repo() {
    # $1 is the cloning URL of the repo
    # $2 is the name of the directory the repo will be cloned into (relative path).
    if [[ ! -d "${2}" ]]; then
        git clone --recurse-submodules "${1}" "${2}"
    fi
}

clone_my_repos() {
    read -r -p 'Clone my repos? [y/n]: ' response
    if [[ "${response}" =~ [yY] ]]; then

        cd ~ || exit 1
        export GIT_SSL_NO_VERIFY=true
        clone_repo "git@github.com:takelley1/scripts.git" "scripts"
        clone_repo "git@github.com:takelley1/notes.git" "notes"
        clone_repo "git@github.com:takelley1/linux-notes.git" "linux-notes"

        [[ ! -d ~/repos ]] && mkdir ~/repos
        [[ ! -d ~/roles ]] && mkdir ~/roles

        cd ~/roles || exit 1
        clone_repo "git@github.com:takelley1/ansible-role-postgresql.git" "postgresql"
        clone_repo "git@github.com:takelley1/ansible-role-nexus.git" "nexus"
        clone_repo "git@github.com:takelley1/ansible-role-jira-software.git" "jira_software"
        clone_repo "git@github.com:takelley1/ansible-role-httpd.git" "httpd"
        clone_repo "git@github.com:takelley1/ansible-role-haproxy.git" "haproxy"
        clone_repo "git@github.com:takelley1/ansible-role-gitlab-runner.git" "gitlab_runner"
        clone_repo "git@github.com:takelley1/ansible-role-gitlab.git" "gitlab"
        clone_repo "git@github.com:takelley1/ansible-role-docker.git" "docker"
        clone_repo "git@github.com:takelley1/ansible-role-confluence.git" "confluence"
        clone_repo "git@github.com:takelley1/ansible-role-bitbucket.git" "bitbucket"
        clone_repo "git@github.com:takelley1/ansible-role-zabbix-proxy.git" "zabbix_proxy"
        clone_repo "git@github.com:takelley1/ansible-role-users.git" "users"
        clone_repo "git@github.com:takelley1/ansible-role-trusted-certs.git" "trusted_certs"
        clone_repo "git@github.com:takelley1/ansible-role-tenablesc.git" "tenablesc"
        clone_repo "git@github.com:takelley1/ansible-role-sysctl.git" "sysctl"
        clone_repo "git@github.com:takelley1/ansible-role-stig-rhel-7.git" "stig_rhel_7"
        clone_repo "git@github.com:takelley1/ansible-role-samba-server.git" "samba_server"
        clone_repo "git@github.com:takelley1/ansible-role-rsyslog.git" "rsyslog"
        clone_repo "git@github.com:takelley1/ansible-role-repos.git" "repos"
        clone_repo "git@github.com:takelley1/ansible-role-repo-mirror.git" "repo_mirror"
        clone_repo "git@github.com:takelley1/ansible-role-postfix.git" "postfix"
        clone_repo "git@github.com:takelley1/ansible-role-packages.git" "packages"
        clone_repo "git@github.com:takelley1/ansible-role-openssh.git" "openssh"
        clone_repo "git@github.com:takelley1/ansible-role-mcafee-agent.git" "mcafee_agent"
        clone_repo "git@github.com:takelley1/ansible-role-logrotate.git" "logrotate"
        clone_repo "git@github.com:takelley1/ansible-role-firewalld.git" "firewalld"
        clone_repo "git@github.com:takelley1/ansible-role-cron.git" "cron"
        clone_repo "git@github.com:takelley1/ansible-role-chrony.git" "chrony"
        clone_repo "git@github.com:takelley1/ansible-role-unix-common.git" "unix_common"
        clone_repo "git@github.com:takelley1/ansible-role-e2guardian.git" "e2guardian"
        clone_repo "git@github.com:takelley1/ansible-role-zabbix-server.git" "zabbix_server"
        clone_repo "git@github.com:takelley1/ansible-role-zabbix-agent.git" "zabbix_agent"
        clone_repo "git@github.com:takelley1/ansible-role-workstation.git" "workstation"
        clone_repo "git@github.com:takelley1/ansible-role-podman-services.git" "podman_services"
        clone_repo "git@github.com:takelley1/ansible-role-dotfiles.git" "dotfiles"
        clone_repo "git@github.com:takelley1/ansible-role-bootstrap.git" "bootstrap"

    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        clone_my_repos
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
clone_my_repos

post_install_message

exit 0
