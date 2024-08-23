#!/bin/bash
LOGFILE="client_installer.log"
exec 3>&1 1>"$LOGFILE" 2>&1

distro=""
version=""
name=""
fsx_dns_name=""
dryrun=""

# Logging codes
INFO='INFO'
ERROR='ERROR'
SUCCESS='SUCCESS'

# Supported ubuntu versions
declare -A ubuntu_version_codenames=(
    ["22.04"]="jammy"
    ["20.04"]="focal"
    ["18.04"]="bionic"
)

# parse script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fsx_dns_name)
        shift
        fsx_dns_name=$1
        ;;
        --dryrun)
        shift
        dryrun="true"
        ;;
        *)
        print_message $ERROR "Invalid argument: $1"
        exit 1
        ;;
    esac
    shift
done

function get_os_version() {
    if command -v lsb_release &> /dev/null; then
        distro=$(lsb_release -si | tr '[:upper:]' '[:lower:]') 
        version=$(lsb_release -sr)
        name=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        distro=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        version="$VERSION_ID"
        name="$NAME"
    elif [ -f /etc/redhat-release ]; then # EL based distributions
        . /etc/os-release 
        distro="el"
        version="$VERSION_ID"
        name="$NAME"
    else
        print_message $ERROR "Unable to determine the Linux distribution. Check the operating system being used has FSxL client support - https://docs.aws.amazon.com/fsx/latest/LustreGuide/install-lustre-client.html. Exiting."
        exit 1
    fi
}

function uninstall_lustre_debian() {
    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: sudo apt-get remove -y lustre-client-modules-*" 
        print_message $INFO "Dry run: sudo apt-get autoremove -y"
    else
        sudo apt-get remove -y lustre-client-modules-* || handle_failure_to_uninstall_lustre
        sudo apt-get autoremove -y || handle_failure_to_uninstall_lustre
    fi
}

function uninstall_lustre_rpm() {
    if [[ $distro == "amzn" && $version == "2023" ]]; then
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo yum remove -y lustre-client"
        else
            sudo yum remove -y lustre-client || handle_failure_to_uninstall_lustre
        fi
    else
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo yum remove -y kmod-lustre-client lustre-client"
        else
            sudo yum remove -y kmod-lustre-client lustre-client || handle_failure_to_uninstall_lustre
        fi
    fi

    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: sudo yum clean all"
    else
        sudo yum clean all || handle_failure_to_uninstall_lustre
    fi
}

function uninstall_lustre_zypper() {
    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: sudo zypper remove -y lustre-client-*"
        print_message $INFO "Dry run: sudo zypper clean --all"
    else
        sudo zypper remove -y lustre-client-* || handle_failure_to_uninstall_lustre
        sudo zypper clean --all || handle_failure_to_uninstall_lustre
    fi
}

function check_and_handle_lustre_installation() {
    if command -v lfs &> /dev/null; then
        print_message $INFO "Lustre is already installed, checking if it is configured correctly..."
        if ! verify_installation; then
            print_message $INFO "Lustre is already installed but not configured correctly, uninstalling Lustre & restarting the installation"
            case "$distro" in
                ubuntu)
                    uninstall_lustre_debian
                    ;;
                amzn|el|centos|rhel|rocky)
                    uninstall_lustre_rpm
                    ;;
                suse|sles)
                    uninstall_lustre_zypper
                    ;;
                *)
                    handle_failure_to_uninstall_lustre
                    ;;
            esac
        else
            print_message $SUCCESS "Lustre is installed and configured correctly, nothing to do."
            exit 0
        fi
    fi
}


function install_lustre_client() {
    case "$distro" in
        ubuntu)
            install_ubuntu_client
            ;;
        amzn)
            install_amazon_client
            ;;
        el|centos|rhel|rocky)
            install_el_client
            ;;
        suse|sles)
            install_suse_client
            ;;
        *)
            print_message $ERROR "Unsupported Linux distribution: $name, check that the OS being used has FSxL support - https://docs.aws.amazon.com/fsx/latest/LustreGuide/install-lustre-client.html"
            exit 1
            ;;
    esac
}

function handle_failure_to_uninstall_lustre() {
    print_message $ERROR "Failed to uninstall Lustre, exiting."
    exit 1
}

function print_message() {
    code="$1"
    msg="$2"
    echo "$(date +%F) $(date +%H:%M:%S) - $code - $msg" >&3
    echo "$(date +%F) $(date +%H:%M:%S) - $code - $msg"
}

function check_amazon_kernel_compatibility() {
    minimum_kernel_version="$1"
    current_kernel_version=$(uname -r)
    if [ "$(printf '%s\n' "$minimum_kernel_version" "$current_kernel_version" | sort -V | head -n1)" = "$minimum_kernel_version" ]; then
        return 0
    else
        return 1
    fi
}

function print_kernel_compatibility_error() {
    current_kernel_version=$(uname -r)
    print_message $ERROR "Kernel version $current_kernel_version does not meet the minimum requirement. For more information on kernel compatibility, visit https://docs.aws.amazon.com/fsx/latest/LustreGuide/lustre-client-matrix.html"
    exit 1
}

function check_installation() {
    if [ $? -ne 0 ]; then
        print_message $ERROR "Installation failed, exiting."
        exit 1
    else
        print_message $INFO "Lustre client installed, verifying installation..."
    fi
}

function install_amazon_client() {
    print_message $INFO "Installing Lustre client for $name ..."
    if [ "$version" == "2023" ]; then
        minimum_kernel_version="6.1.79-99.167.amzn2023"

        if check_amazon_kernel_compatibility "$minimum_kernel_version"; then
            if [ "$dryrun" != "true" ]; then
                sudo dnf install -y lustre-client
                check_installation
            else
                print_message $INFO "Dry run: sudo dnf install -y lustre-client"
            fi
        else
            print_kernel_compatibility_error
        fi
    elif [ "$version" == "2" ]; then
        minimum_kernel_version_5_10="5.10.144-127.601.amzn2"
        minimum_kernel_version_5_4="5.4.214-120.368.amzn2"
        minimum_kernel_version_4_14="4.14.294-220.533.amzn2"
        current_kernel_version=$(uname -r)

        if check_amazon_kernel_compatibility "$minimum_kernel_version_5_10"; then
            if [ "$dryrun" != "true" ]; then
                sudo amazon-linux-extras install -y lustre
                check_installation
            else
                print_message $INFO "Dry run: sudo amazon-linux-extras install -y lustre"
            fi   
        elif check_amazon_kernel_compatibility "$minimum_kernel_version_5_4"; then
            if [ "$dryrun" != "true" ]; then
                sudo amazon-linux-extras install -y lustre
                check_installation
            else
                print_message $INFO "Dry run:  sudo amazon-linux-extras install -y lustre"
            fi
        elif check_amazon_kernel_compatibility "$minimum_kernel_version_4_14"; then
            if [ "$dryrun" != "true" ]; then
                sudo amazon-linux-extras install -y lustre
                check_installation
            else
                print_message $INFO "Dry run: sudo amazon-linux-extras install -y lustre"
            fi
        else
            print_kernel_compatibility_error
        fi
    elif [[ $(rpm --eval '%{dist}') == ".amzn1" ]]; then
        minimum_kernel_version="4.14.104-78.84.amzn1.x86_64"
        if check_amazon_kernel_compatibility "$minimum_kernel_version"; then
            if [ "$dryrun" != "true" ]; then
                sudo yum install -y lustre-client
                check_installation
            else
                print_message $INFO "Dry run: yum install -y lustre-client"
            fi
        else
            print_kernel_compatibility_error
        fi
    else
        print_message $ERROR "Unsupported Amazon Linux version"
        exit 1
    fi
}


function install_ubuntu_client() {
    print_message $INFO "Installing Lustre client for $name ..."
    # Install appropriate key & add the repo.
    if [[ -n "${ubuntu_version_codenames[$version]}" ]]; then
        repo_codename="${ubuntu_version_codenames[$version]}"
    else
        print_message $ERROR "Unsupported Ubuntu version"
        return 1
    fi

    repo_url="https://fsx-lustre-client-repo.s3.amazonaws.com/ubuntu"
    key_repo_url="https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-ubuntu-public-key.asc"
    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: wget -O - $key_repo_url | gpg --dearmor | sudo tee /usr/share/keyrings/fsx-ubuntu-public-key.gpg"
        print_message $INFO "Dry run: sudo bash -c \"echo \"deb [signed-by=/usr/share/keyrings/fsx-ubuntu-public-key.gpg] $repo_url $repo_codename main\" > /etc/apt/sources.list.d/fsxlustreclientrepo.list && apt-get update\""
    else
        wget -O - $key_repo_url | gpg --dearmor | sudo tee /usr/share/keyrings/fsx-ubuntu-public-key.gpg >/dev/null
        sudo bash -c "echo \"deb [signed-by=/usr/share/keyrings/fsx-ubuntu-public-key.gpg] $repo_url $repo_codename main\" > /etc/apt/sources.list.d/fsxlustreclientrepo.list && apt-get update"
    fi

    # check for kernel version compatibility
    kernel_version=$(uname -r)
    lustre_package_available=$(sudo apt-cache search ^lustre | grep -c "$kernel_version")

    if [ "$lustre_package_available" -gt 0 ]; then
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo apt install -y \"lustre-client-modules-$kernel_version\""
        else
            sudo apt install -y "lustre-client-modules-$kernel_version"
            check_installation
        fi
    else
        print_message $ERROR "Kernel version $kernel_version is not supported for Lustre client, exiting."
    fi
}

function install_el_client() {
    case "$version" in
        9.0|9.3|9.4)
            install_el9_client
            ;;
        8|8.2|8.3|8.4|8.5|8.6|8.7|8.8|8.9|8.10)
            if [[ "$distro" == "rocky" && ("$version" == "8.2" || "$version" == "8.3") ]]; then
                print_message $ERROR "Rocky Linux 8.2 and 8.3 are not supported for Lustre client, exiting."
                exit 1
            fi
            install_el8_client
            ;;
        7|7.7|7.8|7.9)
            arch=$(uname -m)
            if [[ "$arch" == "aarch64" && "$version" == "7.7" ]]; then
                print_message $ERROR "ARM architecture is not supported for (RHEL, Centos) based system version 7.7"
                exit 1
            else
                install_el7_client
            fi
            ;;
        *)
            print_message $ERROR "Unsupported $name version: $version"
            exit 1
            ;;
    esac
}

function install_el9_client() {
    print_message $INFO "Installing Lustre client for $name ..."
    # Install appropriate key & add the repo.
    if [ "$dryrun" != "true" ]; then
        curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc
        sudo rpm --import /tmp/fsx-rpm-public-key.asc
        sudo curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/9/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo
    else
        print_message $INFO "Dry run: curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc"
        print_message $INFO "Dry run: sudo rpm --import /tmp/fsx-rpm-public-key.asc"
        print_message $INFO "Dry run: curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/9/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo"
    fi

    # Setup the repo correctly
    kernel_version=$(uname -r)
    if [[ "$kernel_version" =~ ^5\.14\.0-427\..* ]]; then
        print_message $INFO "Kernel version $kernel_version meets the minimum requirement. Proceeding with installation."
    elif [[ "$kernel_version" =~ ^5\.14\.0-362\.18\.1 ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#9#9.3#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run:  sudo sed -i 's#9#9.3#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^5\.14\.0-70\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#9#9.0#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run:  sudo sed -i 's#9#9.0#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    else
        print_kernel_compatibility_error
    fi

    if [ "$dryrun" != "true" ]; then
        sudo yum install -y kmod-lustre-client lustre-client
        check_installation
    else
        print_message $INFO "Dry run: sudo yum install -y kmod-lustre-client lustre-client"
    fi
}

function install_el8_client() {
    print_message $INFO "Installing Lustre client for $name ..."
    if [ "$dryrun" != "true" ]; then
        curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc
        sudo rpm --import /tmp/fsx-rpm-public-key.asc
        sudo curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/8/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo
    else
        print_message $INFO "Dry run: curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc"
        print_message $INFO "Dry run: sudo rpm --import /tmp/fsx-rpm-public-key.asc"
        print_message $INFO "Dry run: sudo curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/8/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo"
    fi

    # Setup the repo correctly
    kernel_version=$(uname -r)
    if   [[ "$kernel_version" =~ ^4\.18\.0-553\..* ]]; then
        print_message $INFO "Kernel version $kernel_version meets the minimum requirement. Proceeding with installation."
    elif [[ "$kernel_version" =~ ^4\.18\.0-513\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.9#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.9#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^4\.18\.0-477\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.8#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.8#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^4\.18\.0-425\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.7#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.7#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^4\.18\.0-372\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.6#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.6#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^4\.18\.0-348\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.5#' /etc/yum.repos.d/aws-fsx.repo
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.5#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^4\.18\.0-305\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.4#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.4#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^4\.18\.0-240\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.3#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.3#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    elif [[ "$kernel_version" =~ ^4\.18\.0-193\..* ]]; then
        if [ "$dryrun" != "true" ]; then
            sudo sed -i 's#8#8.2#' /etc/yum.repos.d/aws-fsx.repo
            sudo yum clean all
        else
            print_message $INFO "Dry run: sudo sed -i 's#8#8.2#' /etc/yum.repos.d/aws-fsx.repo"
        fi
    else
        print_kernel_compatibility_error
    fi

    if [ "$dryrun" != "true" ]; then
        sudo yum install -y kmod-lustre-client lustre-client
        check_installation
    else
        print_message $INFO "Dry run: sudo yum install -y kmod-lustre-client lustre-client"
    fi
}

function install_el7_key_and_repo() {
    if [ "$dryrun" != "true" ]; then
        curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc
        if [[ "$arch" == "x86_64" ]]; then
            sudo rpm --import /tmp/fsx-rpm-public-key.asc
            sudo curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo
        else
            curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.cn/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc
            sudo rpm --import /tmp/fsx-rpm-public-key.asc
            sudo curl https://fsx-lustre-client-repo.s3.amazonaws.com/centos/7/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo
        fi
    else
        print_message $INFO "Dry run: curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc"
        print_message $INFO "Dry run: sudo rpm --import /tmp/fsx-rpm-public-key.asc"
        if [[ "$arch" == "x86_64" ]]; then
            print_message $INFO "Dry run: sudo curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo"
        else
            print_message $INFO "Dry run: curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.cn/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc"
            print_message $INFO "Dry run: sudo curl https://fsx-lustre-client-repo.s3.amazonaws.com/centos/7/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repos"
        fi
    fi
}

function setup_el7_repo() {
    if [[ "$arch" == "x86_64" ]]; then
        if   [[ "$kernel_version" =~ ^3\.10\.0-1160\..* ]]; then
            print_message $INFO "Kernel version $kernel_version meets the minimum requirement. Proceeding with installation."
        elif [[ "$kernel_version" =~ ^3\.10\.0-1127\..* ]]; then
            if [ "$dryrun" != "true" ]; then
                sudo sed -i 's#7#7.8#' /etc/yum.repos.d/aws-fsx.repo
                sudo yum clean all
            else
                print_message $INFO "Dry run: sudo sed -i 's#7#7.8#' /etc/yum.repos.d/aws-fsx.repo"
            fi
        elif [[ "$kernel_version" =~ ^3\.10\.0-1062\..* ]]; then
            if [ "$dryrun" != "true" ]; then
                sudo sed -i 's#7#7.7#' /etc/yum.repos.d/aws-fsx.repo
                sudo yum clean all
            else
                print_message $INFO "Dry run: sudo sed -i 's#7#7.7#' /etc/yum.repos.d/aws-fsx.repo"
            fi
        else
            print_kernel_compatibility_error
        fi
    else
        if   [[ "$kernel_version" =~ ^4\.18\.0-193\..* ]]; then
            print_message $INFO "Kernel version $kernel_version meets the minimum requirement. Proceeding with installation."
        elif [[ "$kernel_version" =~ ^4\.18\.0-147\..* ]]; then
            if [ "$dryrun" != "true" ]; then
                sudo sed -i 's#7#7.8#' /etc/yum.repos.d/aws-fsx.repo
                sudo yum clean all
            else
                print_message $INFO "Dry run: sudo sed -i 's#7#7.8#' /etc/yum.repos.d/aws-fsx.repo"
            fi
        else
            print_kernel_compatibility_error
        fi
    fi
}

function install_el7_client() {
    print_message $INFO "Installing Lustre client for $name ..."
    kernel_version=$(uname -r)
    arch=$(uname -m)

    install_el7_key_and_repo
    setup_el7_repo

    if [ "$dryrun" != "true" ]; then
        sudo yum install -y kmod-lustre-client lustre-client
        check_installation
    else
        print_message $INFO "Dry run: sudo yum install -y kmod-lustre-client lustre-client"
    fi
}

function install_suse_client_common() {
    print_message $INFO "Adding FSx repo..."
    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: sudo wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-sles-public-key.asc"
        print_message $INFO "Dry run: sudo rpm --import fsx-sles-public-key.asc"
        print_message $INFO "Dry run: sudo wget https://fsx-lustre-client-repo.s3.amazonaws.com/suse/sles-12/SLES-12/fsx-lustre-client.repo"
        print_message $INFO "Dry run: sudo sed -i 's/allow_unsupported_modules 0/allow_unsupported_modules 1/' /etc/modprobe.d/10-unsupported-modules.conf"
    else
        sudo wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-sles-public-key.asc
        sudo rpm --import fsx-sles-public-key.asc
        sudo wget https://fsx-lustre-client-repo.s3.amazonaws.com/suse/sles-12/SLES-12/fsx-lustre-client.repo
        sudo sed -i 's/allow_unsupported_modules 0/allow_unsupported_modules 1/' /etc/modprobe.d/10-unsupported-modules.conf
    fi
}

function install_suse_client_12_3() {
    print_message $INFO "Installing Lustre client for SLES 12 SP3..."
    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo"
        print_message $INFO "Dry run: sudo sed -i 's#SLES-12#SP3#' /etc/zypp/repos.d/aws-fsx.repo"
        print_message $INFO "Dry run: sudo zypper --non-interactive refresh"
        print_message $INFO "Dry run: sudo zypper --non-interactive --gpg-auto-import-keys install lustre-client"
    else
        sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo
        sudo sed -i 's#SLES-12#SP3#' /etc/zypp/repos.d/aws-fsx.repo
        sudo zypper --non-interactive refresh
        sudo zypper --non-interactive --gpg-auto-import-keys install lustre-client
        check_installation
    fi
}

function install_suse_client_12_4() {
    print_message $INFO "Installing Lustre client for SLES 12 SP4..."
    if grep -q "SP3" /etc/zypp/repos.d/aws-fsx.repo; then
        # Migrated from SP3 to SP4
        print_message $INFO "Updating Lustre client for SLES 12 SP4 (migrated from SP3)"
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo"
            print_message $INFO "Dry run: sudo sed -i 's#SP3#SP4#' /etc/zypp/repos.d/aws-fsx.repo"
            print_message $INFO "Dry run: sudo zypper --non-interactive ref"
            print_message $INFO "Dry run: sudo zypper --non-interactive --gpg-auto-import-keys up --force-resolution lustre-client-kmp-default"
        else
            sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo
            sudo sed -i 's#SP3#SP4#' /etc/zypp/repos.d/aws-fsx.repo
            sudo zypper --non-interactive ref
            sudo zypper --non-interactive --gpg-auto-import-keys up --force-resolution lustre-client-kmp-default
            check_installation
        fi
    else
        # Installed SP4 directly
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo"
            print_message $INFO "Dry run: sudo sed -i 's#SLES-12#SP4#' /etc/zypp/repos.d/aws-fsx.repo"
            print_message $INFO "Dry run: sudo zypper --non-interactive refresh"
            print_message $INFO "Dry run: sudo zypper --non-interactive --gpg-auto-import-keys install lustre-client"
        else
            sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo
            sudo sed -i 's#SLES-12#SP4#' /etc/zypp/repos.d/aws-fsx.repo
            sudo zypper --non-interactive refresh
            sudo zypper --non-interactive --gpg-auto-import-keys install lustre-client
            check_installation
        fi
    fi
}

function install_suse_client_12_5() {
    print_message $INFO "Installing Lustre client for SLES 12 SP5..."
    if grep -q "SP4" /etc/zypp/repos.d/aws-fsx.repo; then
        # Migrated from SP4 to SP5
        print_message $INFO "Updating Lustre client for SLES 12 SP5 (migrated from SP4)"
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo sed -i 's#SP4#SLES-12#' /etc/zypp/repos.d/aws-fsx.repo"
            print_message $INFO "Dry run: sudo zypper --non-interactive ref"
            print_message $INFO "Dry run: sudo zypper --non-interactive --gpg-auto-import-keys up --force-resolution lustre-client-kmp-default"
        else
            sudo sed -i 's#SP4#SLES-12#' /etc/zypp/repos.d/aws-fsx.repo
            sudo zypper --non-interactive ref
            sudo zypper --non-interactive --gpg-auto-import-keys up --force-resolution lustre-client-kmp-default
            check_installation
        fi
    else
        # Installed SP5 directly
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo"
            print_message $INFO "Dry run: sudo zypper --non-interactive refresh"
            print_message $INFO "Dry run: sudo zypper --non-interactive --gpg-auto-import-keys install lustre-client"
        else
            sudo zypper ar --gpgcheck-strict fsx-lustre-client.repo
            sudo zypper --non-interactive refresh
            sudo zypper --non-interactive --gpg-auto-import-keys install lustre-client
            check_installation
        fi
    fi
}

function install_suse_client() {
    install_suse_client_common

    case "$version" in
        12.3)
            install_suse_client_12_3
            ;;
        12.4)
            install_suse_client_12_4
            ;;
        12.5)
            install_suse_client_12_5
            ;;
        *)
            print_message $ERROR "Unsupported SUSE version: $version"
            exit 1
            ;;
    esac
}


function verify_installation() {
    # Check if Lustre utilities are installed
    if ! command -v lfs &> /dev/null; then
        if [[ $dryrun != "true" ]]; then
            print_message $ERROR "Lustre client not installed."
        fi
        return 1
    fi

    # Check if Lustre kernel module is loaded
    if lsmod | grep -q lustre; then
        print_message $INFO "Lustre kernel module is loaded."
    else
        print_message $INFO "Lustre kernel module is not loaded. Attempting to load..."
        if [[ "$dryrun" == "true" ]]; then
            print_message $INFO "Dry run: sudo modprobe lustre"
        else
            if sudo modprobe lustre; then
                print_message $SUCCESS "Lustre kernel module loaded successfully."
            else
                print_message $ERROR "Failed to load Lustre kernel module. Please visit https://docs.aws.amazon.com/fsx/latest/LustreGuide/install-lustre-client.html for more information."
                return 1
            fi
        fi
    fi

    # Check if Lustre kernel module information is available
    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: sudo modinfo lustre"
    else
        if sudo modinfo lustre &> /dev/null; then
           sudo modinfo lustre
        else
            print_message $INFO "Lustre kernel module information is not available."
            return 1
        fi
    fi

    print_message $SUCCESS "Lustre client $(lfs --version) installed successfully."
    return 0
}

function is_fsx_reachable() {
    print_message $INFO "Checking if FSx is reachable..."
    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: lctl ping \"$fsx_dns_name\""
    else
        if lctl ping "$fsx_dns_name"; then
            print_message $SUCCESS "FSx is reachable"
            exit 0
        else
            print_message $INFO "FSx is not reachable via hostname. Attempting to resolve IP address."
            fsx_ip=$(host "$fsx_dns_name" | awk '/has address/ { print $4; exit }')
            if [[ -n "$fsx_ip" ]]; then
                if lctl ping "$fsx_ip"; then
                    print_message $SUCCESS "FSx is reachable via IP address: $fsx_ip"
                    exit 0
                else
                    print_message $INFO "FSx is not reachable via IP address. Attempting to load lnet modules before retrying."
                    load_lnet_modules
                fi
            else
                print_message $ERROR "Failed to resolve IP address for $fsx_dns_name"
                exit 1
            fi
        fi
    fi

    if [[ "$dryrun" == "true" ]]; then
        print_message $INFO "Dry run: lctl ping \"$fsx_dns_name\""
    else
        if lctl ping "$fsx_dns_name"; then
            print_message $SUCCESS "FSx is reachable"
            exit 0
        else
            print_message $ERROR "Lustre client cannot establish a connection with FSx file system - troubleshoot potential networking issues with https://docs.aws.amazon.com/fsx/latest/LustreGuide/mount-troubleshooting.html"
            exit 1
        fi
    fi
}


function load_lnet_modules() {
  modprobe -v lnet
}

function main() {
    get_os_version
    print_message $INFO "Detected OS: $name $version"
    print_message $INFO "Detected kernel version: $(uname -r)"
    print_message $INFO "Check log $LOGFILE for more execution details."
    # Check if lustre is already installed
    check_and_handle_lustre_installation
    # Install the lustre client
    install_lustre_client
    # Verify the installation
    if verify_installation; then
        if [ -n "$fsx_dns_name" ]; then
            is_fsx_reachable
        fi
        exit 0
    else
        exit 1
    fi
}

main
