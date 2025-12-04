#!/usr/bin/env bash
# shellcheck disable=SC2016

set -eEuo pipefail

PACKAGE_MANAGER=""
PACKAGE_MANAGER_CMD=""
add_proxy_response=""

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        PACKAGE_MANAGER_CMD="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
        PACKAGE_MANAGER_CMD="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
        PACKAGE_MANAGER_CMD="yum"
    else
        echo "Supported package manager not found (need apt, dnf, or yum)."
        exit 1
    fi
}

is_apt() {
    [[ "${PACKAGE_MANAGER}" == "apt" ]]
}

hashicorp_repo_url() {
    local os_id=""
    local os_id_like=""
    if [[ -r /etc/os-release ]]; then
        os_id="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
        os_id_like="$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"')"
    fi
    if [[ "${os_id_like}" == *"fedora"* || "${os_id}" == "fedora" ]]; then
        printf "%s" "https://rpm.releases.hashicorp.com/fedora/hashicorp.repo"
        return
    fi
    if [[ "${os_id_like}" == *"rhel"* ]] || \
        [[ "${os_id}" =~ ^(rhel|centos|rocky|almalinux)$ ]]
    then
        printf "%s" "https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo"
        return
    fi
    printf "%s" ""
}

check_binaries() {
    local missing=0
    for binary in "$@"; do
        if ! command -v "${binary}" >/dev/null 2>&1; then
            echo "Missing required binary: ${binary}"
            missing=1
        fi
    done
    printf "%s" "${missing}"
}

package_for_binary() {
    case "${1}" in
        add-apt-repository) printf "%s" "software-properties-common" ;;
        lsb_release) printf "%s" "lsb-release" ;;
        apt-key) printf "%s" "apt" ;;
        *) printf "%s" "${1}" ;;
    esac
}

package_in_list() {
    local target="${1}"
    shift
    for item in "$@"; do
        if [[ "${item}" == "${target}" ]]; then
            return 0
        fi
    done
    return 1
}

install_missing_binaries() {
    local missing_binaries=("$@")
    local packages=()
    for binary in "${missing_binaries[@]}"; do
        local pkg
        pkg="$(package_for_binary "${binary}")"
        if ! package_in_list "${pkg}" "${packages[@]:-}"; then
            packages+=("${pkg}")
        fi
    done
    if [[ "${#packages[@]}" -eq 0 ]]; then
        return
    fi
    print "Installing required binaries: ${packages[*]}"
    pkg_install_list "${packages[@]}"
}

verify_required_binaries() {
    local missing_binaries=()
    local missing
    missing="$(check_binaries sudo curl wget git awk tee grep sed cut tr head tail xargs)"
    if [[ "${missing}" -eq 1 ]]; then
        missing_binaries+=(
            "sudo" "curl" "wget" "git" "awk" "tee"
            "grep" "sed" "cut" "tr" "head" "tail" "xargs"
        )
    fi
    if is_apt; then
        if [[ "$(check_binaries apt add-apt-repository apt-key lsb_release)" -eq 1 ]]; then
            missing_binaries+=("apt" "add-apt-repository" "apt-key" "lsb_release")
        fi
    else
        if [[ "$(check_binaries "${PACKAGE_MANAGER_CMD}" rpm)" -eq 1 ]]; then
            missing_binaries+=("${PACKAGE_MANAGER_CMD}" "rpm")
        fi
    fi
    if [[ "${#missing_binaries[@]}" -eq 0 ]]; then
        return
    fi
    printf "%s\n" "Install missing binaries now? [y/n]: "
    local response
    read -r response
    if [[ "${response}" =~ [yY] ]]; then
        install_missing_binaries "${missing_binaries[@]}"
    else
        echo "Missing required binaries. Exiting."
        exit 1
    fi
}

install_epel() {
    if is_apt; then
        echo "EPEL is only available on yum or dnf systems."
        return
    fi
    if [[ ! -r /etc/os-release ]]; then
        echo "Cannot detect release; /etc/os-release missing."
        return
    fi
    local version_id=""
    local major_version=""
    version_id="$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
    major_version="${version_id%%.*}"
    if [[ -z "${major_version}" ]]; then
        echo "Cannot determine major version from VERSION_ID=${version_id}"
        return
    fi
    local epel_url
    epel_url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major_version}.noarch.rpm"
    if ! sudo "${PACKAGE_MANAGER_CMD}" install -y "${epel_url}"; then
        echo "Failed to install EPEL from ${epel_url}"
        return
    fi
    print "Done installing EPEL for release ${major_version}"
}

pkg_update_cache() {
    case "${PACKAGE_MANAGER}" in
        apt)
            sudo apt update
            ;;
        dnf)
            sudo dnf makecache --refresh
            ;;
        yum)
            sudo yum makecache
            ;;
    esac
}

pkg_upgrade() {
    case "${PACKAGE_MANAGER}" in
        apt)
            sudo apt upgrade -y
            ;;
        dnf)
            sudo dnf upgrade -y
            ;;
        yum)
            sudo yum update -y
            ;;
    esac
}

pkg_install_list() {
    local packages=("$@")
    local pkg
    for pkg in "${packages[@]}"; do
        case "${PACKAGE_MANAGER}" in
            apt)
                if ! sudo apt install -y "${pkg}"; then
                    echo "Skipping unavailable package: ${pkg}"
                fi
                ;;
            dnf|yum)
                if ! sudo "${PACKAGE_MANAGER_CMD}" install -y "${pkg}"; then
                    echo "Skipping unavailable package: ${pkg}"
                fi
                ;;
        esac
    done
    return 0
}

is_package_installed() {
    case "${PACKAGE_MANAGER}" in
        apt) dpkg -s "${1}" >/dev/null 2>&1 ;;
        dnf|yum) rpm -q "${1}" >/dev/null 2>&1 ;;
    esac
}

filter_missing_packages() {
    local pkg
    local filtered=()
    for pkg in "$@"; do
        if ! is_package_installed "${pkg}"; then
            filtered+=("${pkg}")
        fi
    done
    printf "%s\n" "${filtered[@]:-}"
}

pkg_remove_list() {
    local packages=("$@")
    case "${PACKAGE_MANAGER}" in
        apt)
            sudo apt purge -y "${packages[@]}"
            ;;
        dnf|yum)
            sudo "${PACKAGE_MANAGER_CMD}" remove -y "${packages[@]}"
            ;;
    esac
}

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

        if is_apt; then
            # Add to apt configuration.
            printf \
                "%s\n%s\n" \
                "Acquire::http::Proxy \"http://${proxy_ip_and_port}\";" \
                "Acquire::https::Proxy \"http://${proxy_ip_and_port}\";" |
                sudo tee /etc/apt/apt.conf.d/proxy.conf 1>/dev/null

            # Restart snapd to read new environment vars.
            systemctl restart snapd
        else
            configure_yum_dnf_proxy "${proxy_ip_and_port}"
        fi
        pkg_update_cache
    else
        echo "Must use a format of IP:PORT (e.g. 10.0.0.1:3143 or myproxy.domain:8008)"
        add_proxy_ip_and_port
    fi
}

configure_yum_dnf_proxy() {
    local proxy_ip_and_port="${1}"
    local config_path

    if [[ "${PACKAGE_MANAGER}" == "dnf" ]]; then
        config_path="/etc/dnf/dnf.conf"
    else
        config_path="/etc/yum.conf"
    fi

    sudo mkdir -p "$(dirname "${config_path}")"
    sudo touch "${config_path}"

    if sudo grep -q "^proxy=" "${config_path}"; then
        sudo sed -i "s|^proxy=.*|proxy=http://${proxy_ip_and_port}|" "${config_path}"
    else
        printf "\nproxy=http://%s\n" "${proxy_ip_and_port}" |
            sudo tee -a "${config_path}" 1>/dev/null
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
            sudo wget -v "${proxy_cert_url}" \
                --output-document="${proxy_dir}/proxy_${proxy_ip_and_port}_cert.crt"

            print "Updating certificate store"
            if is_apt; then
                sudo update-ca-certificates
            else
                sudo update-ca-trust extract
            fi
            return
        else
            printf "%s\n" \
                'Must use a format of ^(http|ftp)s?:\/\/.+\.' \
                'Example: http://myserver.domain/certp.pem'
        fi
    done
}

install_packages() {
    read -r -p "Install ${PACKAGE_MANAGER} packages? [y/n]: " response
    if [[ "${response}" =~ [yY] ]]; then
        print "Installing ${PACKAGE_MANAGER} packages"
        local packages=()
        if is_apt; then
            packages=(
                agrep
                ansible
                apt-rdepends
                autojump
                bat
                curl
                dash
                feh
                flake8
                fzf
                gcc
                git
                bash-completion
                htop
                iftop
                iproute2
                jq
                traceroute
                libmagic-dev
                lsof
                diffutils
                mediainfo
                mlocate
                moreutils
                time
                net-tools
                netcat
                nfs-common
                nfstrace
                nfswatch
                npm
                p7zip
                pdfgrep
                pngcrush
                findutils
                python3-isort
                python3-pip
                python3-psutil
                python3-pynvim
                yq
                ranger
                renameutils
                ripgrep
                rsync
                screen
                shellcheck
                sloccount
                fd-find
                ncdu
                sshpass
                strace
                tcpdump
                tmux
                tuned
                w3m
                yarn
                zip
            )
        else
            packages=(
                agrep
                ansible
                autojump
                bat
                curl
                dash
                feh
                python3-flake8
                fzf
                gcc
                git
                bash-completion
                htop
                iftop
                iproute
                jq
                traceroute
                file-devel
                lsof
                diffutils
                mediainfo
                mlocate
                moreutils
                time
                net-tools
                nmap-ncat
                nfs-utils
                nfstrace
                nfswatch
                npm
                p7zip
                pdfgrep
                pngcrush
                findutils
                python3-isort
                python3-pip
                python3-psutil
                python3-neovim
                yq
                ranger
                renameutils
                ripgrep
                rsync
                screen
                ShellCheck
                sloccount
                fd-find
                ncdu
                sshpass
                strace
                tcpdump
                tmux
                tuned
                w3m
                yarn
                zip
            )
        fi
        local missing_packages=()
        read -r -a missing_packages < <(filter_missing_packages "${packages[@]}")
        if [[ "${#missing_packages[@]}" -eq 0 ]]; then
            print "All developer tools already installed"
            return
        fi
        pkg_update_cache
        pkg_upgrade
        pkg_install_list "${missing_packages[@]}"
        print "Done installing packages"
    elif [[ "${response}" =~ [nN] ]]; then
        return
    else
        echo "Enter y or n"
        install_packages
    fi
}

install_lazygit() {
    local version
    local plain_version
    local tarball_url
    local tmp_dir
    version="$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
        grep '"tag_name"' |
        head -n 1 |
        cut -d '"' -f4)"
    if [[ -z "${version}" ]]; then
        echo "Could not determine latest lazygit version"
        return 1
    fi
    plain_version="${version#v}"
    tarball_url="https://github.com/jesseduffield/lazygit/releases/download/${version}/"\
"lazygit_${plain_version}_linux_x86_64.tar.gz"
    tmp_dir="$(mktemp -d)"
    curl -fsSL -o "${tmp_dir}/lazygit.tar.gz" "${tarball_url}"
    sudo tar xzf "${tmp_dir}/lazygit.tar.gz" --directory "${tmp_dir}"
    sudo install -m 0755 "${tmp_dir}/lazygit" /usr/local/bin/lazygit
    rm -rf "${tmp_dir}"
    print "Done installing lazygit (${version})"
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

install_hstr() {
    if command -v hstr >/dev/null 2>&1; then
        print "hstr already installed"
        return
    fi
    if is_apt; then
        sudo add-apt-repository ppa:ultradvorka/ppa
        pkg_update_cache
        pkg_install_list hstr
        print "Done installing hstr"
        return
    fi
    if sudo "${PACKAGE_MANAGER_CMD}" install -y hstr; then
        print "Done installing hstr"
    else
        printf "%s\n" "Skipping hstr install; package not available for ${PACKAGE_MANAGER}."
    fi
}

install_neovim() {
    if command -v nvim >/dev/null 2>&1; then
        print "Neovim already installed"
        return
    fi
    if is_apt; then
        sudo add-apt-repository ppa:neovim-ppa/stable
        pkg_update_cache
        pkg_install_list neovim
        print "Done installing neovim"
        return
    fi
    if sudo "${PACKAGE_MANAGER_CMD}" install -y neovim; then
        print "Done installing neovim"
    else
        printf "%s\n" "Skipping neovim install; package not available for ${PACKAGE_MANAGER}."
    fi
}

install_kubectl_apt() {
    local version="v1.34"
    local keyring="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    local list="/etc/apt/sources.list.d/kubernetes.list"
    local repo
    sudo mkdir -p -m 755 /etc/apt/keyrings
    pkg_install_list apt-transport-https ca-certificates curl gnupg
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${version}/deb/Release.key" |
        sudo gpg --dearmor -o "${keyring}"
    sudo chmod 644 "${keyring}"
    repo="deb [signed-by=${keyring}] https://pkgs.k8s.io/core:/stable:/${version}/deb/ /"
    echo "${repo}" | sudo tee "${list}" 1>/dev/null
    sudo chmod 644 "${list}"
    pkg_update_cache
    pkg_install_list kubectl
    print "Done installing kubectl"
}

install_kubectl_rpm() {
    local version="v1.34"
    local repo_file="/etc/yum.repos.d/kubernetes.repo"
    sudo tee "${repo_file}" 1>/dev/null <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${version}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${version}/rpm/repodata/repomd.xml.key
EOF
    pkg_update_cache
    sudo "${PACKAGE_MANAGER_CMD}" install -y kubectl --disableexcludes=kubernetes
    print "Done installing kubectl"
}

install_kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
        print "kubectl already installed"
        return
    fi
    if is_apt; then
        install_kubectl_apt
        return
    fi
    install_kubectl_rpm
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        print "Docker already installed"
        return
    fi
    if is_apt; then
        pkg_install_list apt-transport-https ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
            sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" |
            sudo tee /etc/apt/sources.list.d/docker.list 1>/dev/null
        pkg_update_cache
        pkg_install_list \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin
        print "Done installing Docker"
        return
    fi
    pkg_install_list dnf-plugins-core
    sudo "${PACKAGE_MANAGER_CMD}" config-manager \
        --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    pkg_install_list \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    print "Done installing Docker"
}

install_helm() {
    if command -v helm >/dev/null 2>&1; then
        print "Helm already installed"
        return
    fi
    local helm_script="/tmp/get_helm.sh"
    curl -fsSL -o "${helm_script}" \
        https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 "${helm_script}"
    if ! "${helm_script}"; then
        echo "Helm installation failed"
    else
        print "Done installing Helm"
    fi
}

configure_hashicorp_repo_apt() {
    curl -kfsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
    sudo apt-add-repository \
        "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    printf \
        "%s\n%s\n" \
        'Acquire::https::apt.releases.hashicorp.com::Verify-Peer "false";' \
        'Acquire::https::apt.releases.hashicorp.com::Verify-Host "false";' |
        sudo tee /etc/apt/apt.conf.d/99hashicorp.conf 1>/dev/null
    pkg_update_cache
    print "Done installing hashicorp repo"
}

configure_hashicorp_repo_rpm() {
    local repo_url
    repo_url="$(hashicorp_repo_url)"
    if [[ -z "${repo_url}" ]]; then
        printf "%s\n" "Skipping hashicorp repo setup; unsupported platform."
        return
    fi
    if [[ "${PACKAGE_MANAGER}" == "dnf" ]]; then
        sudo dnf install -y dnf-plugins-core
        sudo dnf config-manager --add-repo "${repo_url}"
    else
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo "${repo_url}"
    fi
    sudo rpm --import https://rpm.releases.hashicorp.com/gpg
    pkg_update_cache
    print "Done installing hashicorp repo"
}

configure_hashicorp_repo() {
    if is_apt; then
        configure_hashicorp_repo_apt
        return
    fi
    configure_hashicorp_repo_rpm
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
        if command -v lf >/dev/null 2>&1; then
            print "lf already installed"
            break
        fi
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
        if command -v hstr >/dev/null 2>&1; then
            print "hstr already installed"
            break
        fi
        read -r -p 'Install hstr? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            install_hstr
            break
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done

    while :; do
        if command -v nvim >/dev/null 2>&1; then
            print "Neovim already installed"
            break
        fi
        read -r -p 'Install neovim? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            install_neovim
            break
        elif [[ "${response}" =~ [nN] ]]; then
            break
        else
            echo "Enter y or n"
        fi
    done

    while :; do
        if command -v tflint >/dev/null 2>&1; then
            print "tflint already installed"
            break
        fi
        read -r -p 'Install tflint? [y/n]: ' response
        if [[ "${response}" =~ [yY] ]]; then
            # From https://github.com/terraform-linters/tflint#installation
            curl -s \
                https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh |
                bash
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
            configure_hashicorp_repo
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
        if is_apt; then
            pkg_install_list \
                libx11-dev \
                libxext-dev
        else
            pkg_install_list \
                libX11-devel \
                libXext-devel
        fi

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
        if command -v snap >/dev/null 2>&1; then
            sudo snap install \
                shfmt
            print "Done installing snap packages"
        else
            echo "snap command not found; skipping snap package installs."
        fi
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
        local plug_data_dir
        local plug_path
        local plug_url
        plug_data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}"
        plug_path="${plug_data_dir}/nvim/site/autoload/plug.vim"
        plug_url="https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
        curl -kfLo "${plug_path}" --create-dirs "${plug_url}"
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
        if [[ -r "${HOME}/.cfg/.bashrc" ]]; then
            cp "${HOME}/.cfg/.bashrc" "${HOME}/.bashrc"
            print "Copied .bashrc from dotfiles to ${HOME}/.bashrc"
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
        if is_apt; then
            pkg_install_list \
                i3-wm \
                i3-lock \
                i3-blocks \
                dunst
        else
            pkg_install_list \
                i3 \
                i3lock \
                i3blocks \
                dunst
        fi
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
        if is_apt; then
            pkg_remove_list \
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
        else
            echo "Package removal list is Ubuntu-specific; skipping on ${PACKAGE_MANAGER}."
        fi
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
                echo "Hidden=true" |
                    sudo tee -a /etc/xdg/autostart/update-notifier.desktop 1>/dev/null
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
        printf "%s\n" "${USER}=(ALL) NOPASSWD: ALL" |
            sudo tee "/etc/sudoers.d/passwordless_sudo_${USER}"
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
        clone_repo "https://github.com/takelley1/scripts.git" "scripts"
        clone_repo "https://github.com/takelley1/notes.git" "notes"
        clone_repo "https://github.com/takelley1/linux-notes.git" "linux-notes"

        [[ ! -d ~/repos ]] && mkdir ~/repos
        [[ ! -d ~/roles ]] && mkdir ~/roles

        cd ~/roles || exit 1
        clone_repo "https://github.com/takelley1/ansible-role-postgresql.git" "postgresql"
        clone_repo "https://github.com/takelley1/ansible-role-nexus.git" "nexus"
        clone_repo "https://github.com/takelley1/ansible-role-jira-software.git" "jira_software"
        clone_repo "https://github.com/takelley1/ansible-role-httpd.git" "httpd"
        clone_repo "https://github.com/takelley1/ansible-role-haproxy.git" "haproxy"
        clone_repo "https://github.com/takelley1/ansible-role-gitlab-runner.git" "gitlab_runner"
        clone_repo "https://github.com/takelley1/ansible-role-gitlab.git" "gitlab"
        clone_repo "https://github.com/takelley1/ansible-role-docker.git" "docker"
        clone_repo "https://github.com/takelley1/ansible-role-confluence.git" "confluence"
        clone_repo "https://github.com/takelley1/ansible-role-bitbucket.git" "bitbucket"
        clone_repo "https://github.com/takelley1/ansible-role-zabbix-proxy.git" "zabbix_proxy"
        clone_repo "https://github.com/takelley1/ansible-role-users.git" "users"
        clone_repo "https://github.com/takelley1/ansible-role-trusted-certs.git" "trusted_certs"
        clone_repo "https://github.com/takelley1/ansible-role-tenablesc.git" "tenablesc"
        clone_repo "https://github.com/takelley1/ansible-role-sysctl.git" "sysctl"
        clone_repo "https://github.com/takelley1/ansible-role-stig-rhel-7.git" "stig_rhel_7"
        clone_repo "https://github.com/takelley1/ansible-role-samba-server.git" "samba_server"
        clone_repo "https://github.com/takelley1/ansible-role-rsyslog.git" "rsyslog"
        clone_repo "https://github.com/takelley1/ansible-role-repos.git" "repos"
        clone_repo "https://github.com/takelley1/ansible-role-repo-mirror.git" "repo_mirror"
        clone_repo "https://github.com/takelley1/ansible-role-postfix.git" "postfix"
        clone_repo "https://github.com/takelley1/ansible-role-packages.git" "packages"
        clone_repo "https://github.com/takelley1/ansible-role-openssh.git" "openssh"
        clone_repo "https://github.com/takelley1/ansible-role-mcafee-agent.git" "mcafee_agent"
        clone_repo "https://github.com/takelley1/ansible-role-logrotate.git" "logrotate"
        clone_repo "https://github.com/takelley1/ansible-role-firewalld.git" "firewalld"
        clone_repo "https://github.com/takelley1/ansible-role-cron.git" "cron"
        clone_repo "https://github.com/takelley1/ansible-role-chrony.git" "chrony"
        clone_repo "https://github.com/takelley1/ansible-role-unix-common.git" "unix_common"
        clone_repo "https://github.com/takelley1/ansible-role-e2guardian.git" "e2guardian"
        clone_repo "https://github.com/takelley1/ansible-role-zabbix-server.git" "zabbix_server"
        clone_repo "https://github.com/takelley1/ansible-role-zabbix-agent.git" "zabbix_agent"
        clone_repo "https://github.com/takelley1/ansible-role-workstation.git" "workstation"
        clone_repo "https://github.com/takelley1/ansible-role-podman-services.git" "podman_services"
        clone_repo "https://github.com/takelley1/ansible-role-dotfiles.git" "dotfiles"
        clone_repo "https://github.com/takelley1/ansible-role-bootstrap.git" "bootstrap"

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
    if [[ "${add_proxy_response:-}" =~ [yY] ]]; then
        echo "- Add proxy cert and configuration to Firefox"
    fi
}

menu_options() {
    printf "%s\n" \
        "Add proxy settings" \
        "Install developer tools (git, fzf, ripgrep, jq, tmux, etc.)" \
        "Install external tools (lazygit/lf/hstr/neovim)" \
        "Install EPEL repo (dnf/yum)" \
        "Install kubectl (Kubernetes CLI)" \
        "Install Docker engine + plugins" \
        "Install Helm (K8s package manager)" \
        "Install Python pip packages" \
        "Install snap packages" \
        "Install vim-plug for Neovim" \
        "Install dotfiles repo" \
        "Install i3 window manager" \
        "Remove unnecessary packages" \
        "Disable background services" \
        "Enable passwordless sudo" \
        "Generate SSH key" \
        "Clone a GitHub repo" \
        "Clone personal repos" \
        "Quit"
}

render_menu() {
    local current_index="${1}"
    local options
    local index=0
    clear
    print "Select an action (arrow keys to move, Enter to run, q to quit)"
    options="$(menu_options)"
    while IFS= read -r option; do
        if [[ "${index}" -eq "${current_index}" ]]; then
            printf "> %s\n" "${option}"
        else
            printf "  %s\n" "${option}"
        fi
        index=$((index + 1))
    done <<<"${options}"
}

read_keypress() {
    local key=""
    read -rsn1 key
    if [[ "${key}" == $'\e' ]]; then
        local rest=""
        read -rsn2 -t 0.001 rest || true
        key+="${rest}"
    fi
    printf "%s" "${key}"
}

handle_menu_choice() {
    case "${1}" in
        0) add_proxy ;;
        1) install_packages ;;
        2) install_external_packages ;;
        3) install_epel ;;
        4) install_kubectl ;;
        5) install_docker ;;
        6) install_helm ;;
        7) install_pip_packages ;;
        8) install_snap_packages ;;
        9) install_vim_plug ;;
        10) install_dotfiles ;;
        11) install_i3 ;;
        12) remove_packages ;;
        13) disable_services ;;
        14) enable_passwordless_sudo ;;
        15) generate_ssh_key ;;
        16) clone_github_repo ;;
        17) clone_my_repos ;;
        18) exit 0 ;;
    esac
}

run_selected_option() {
    local selection="${1}"
    local status=0
    set +e
    handle_menu_choice "${selection}"
    status=$?
    set -e
    if [[ "${status}" -ne 0 ]]; then
        printf "\nStep failed (exit %s). Returning to the menu.\n" "${status}"
    fi
    printf "\nPress Enter to return to the menu"
    read -r
}

menu_loop() {
    local options_count
    local current_index
    local key
    options_count="$(menu_options | wc -l | xargs)"
    current_index=0
    while :; do
        render_menu "${current_index}"
        key="$(read_keypress)"
        case "${key}" in
            $'\e[A') current_index=$(( (current_index - 1 + options_count) % options_count )) ;;
            $'\e[B') current_index=$(( (current_index + 1) % options_count )) ;;
            ""|$'\n') run_selected_option "${current_index}" ;;
            q|Q) exit 0 ;;
        esac
    done
}

detect_package_manager
verify_required_binaries
menu_loop
