#!/bin/bash

REPO="https://github.com/StealthChanger/klipper-toolchanger.git"
CONFIG_PATH="${HOME}/printer_data"
KLIPPER_PATH="${HOME}/klipper"
INSTALL_PATH="${HOME}/klipper-toolchanger"

set -eu
export LC_ALL=C

function preflight_checks {
    if [ "$EUID" -eq 0 ]; then
        echo "[PRE-CHECK] This script must not be run as root!"
        exit -1
    fi

    if [ "$(sudo systemctl list-units --full -all -t service --no-legend | grep -F 'klipper.service')" ]; then
        echo "[PRE-CHECK] Klipper service found!"
    else
        echo "[ERROR] Klipper service not found, please install Klipper first!"
        exit -1
    fi
    echo
}

function check_download {
    local installdirname installbasename
    installdirname="$(dirname ${INSTALL_PATH})"
    installbasename="$(basename ${INSTALL_PATH})"

    doclone=0
    if [ ! -d "${INSTALL_PATH}" ]; then
        doclone=1
    else
        if [ "$(cd "${INSTALL_PATH}" && git remote get-url origin)" != "${REPO}" ]; then
            echo "[DOWNLOAD] Incorrect repository found in ${INSTALL_PATH}, remove and rerun install!"
            exit -1
        fi
    fi

    if [ $doclone -gt 0 ]; then
        echo -n "[DOWNLOAD] Cloning repository..."
        if git -C $installdirname clone ${REPO} $installbasename; then
            chmod +x ${INSTALL_PATH}/install.sh
            echo " complete!"
        else
            echo " failed!"
            exit -1
        fi
    else
        echo "[DOWNLOAD] repository already found locally."
    fi
    echo
}

function remove_links {
    echo -n "[UNINSTALL] Remove old links..."
    for path in "${KLIPPER_PATH}"/klippy/extras/ "${CONFIG_PATH}"/config/; do
        for file in $(find "${path}" -type l); do
            if readlink -f "${file}" | grep -q "${INSTALL_PATH}"; then
                if ! rm ${file}; then
                    echo " failed!"
                    exit -1
                fi
            fi
        done
    done
    echo " complete!"
    echo
}

function link_extension {
    echo -n "[INSTALL] Linking extension to Klipper..."
    for file in "${INSTALL_PATH}"/klipper/extras/*.py; do
        if ! ln -sfn ${file} "${KLIPPER_PATH}"/klippy/extras/; then
            echo " failed!"
            exit -1
        fi
    done
    echo " complete!"
    echo
}

function link_macros {
    echo -n "[INSTALL] Linking macros to Klipper..."
    for file in "${INSTALL_PATH}"/macros/*.cfg; do
        if ! ln -sfn ${file} "${CONFIG_PATH}"/config/; then
            echo " failed!"
            exit -1
        fi
    done
    echo " complete!"
    echo
}

function copy_examples {
    echo -n "[INSTALL] Copying in examples to Klipper..."
    for file in "${INSTALL_PATH}"/examples/*.cfg; do
        if ! cp -n ${file} "${CONFIG_PATH}"/config/; then
            echo " failed!"
            exit -1
        fi
    done
    echo " complete!"
    echo
}

function check_includes {
    echo -n "[CHECK-INSTALL] Checking for missing includes..."
    found=0
    for file in "${INSTALL_PATH}"/macros/*.cfg; do
        filename=$(basename ${file});
        if ! grep -q "include ${filename}" "${CONFIG_PATH}"/config/printer.cfg; then
            if [ $found -lt 1 ]; then
                echo " found!"
                found=1
            fi
            echo " - Missing [include ${filename}] in printer.cfg"
        fi
    done
    if [ $found -lt 1 ]; then
        echo " complete!"
    fi
    echo
}

function add_updater {
    echo -n "[INSTALL] Adding update manager to moonraker.conf..."

    update_section=$(grep -c '\[update_manager led_effect\]' ${MOONRAKER_CONFIG_DIR}/moonraker.conf || true)
    if [ "${update_section}" -eq 0 ]; then
        echo -e "\n" >> ${MOONRAKER_CONFIG_DIR}/moonraker.conf
        while read -r line; do
            echo -e "${line}" >> ${MOONRAKER_CONFIG_DIR}/moonraker.conf
        done < "$PWD/file_templates/moonraker_update.txt"
        echo -e "\n" >> ${MOONRAKER_CONFIG_DIR}/moonraker.conf
        echo "[OK]"
        restart_moonraker
        else
        echo -e "[update_manager led_effect] already exists in moonraker.conf [SKIPPED]"
    fi
}

function restart_klipper {
    echo -n "[POST-INSTALL] Restarting Klipper..."
    if ! sudo systemctl restart klipper; then
        echo " failed!"
        exit -1
    fi
    echo " complete!"
    echo
}

printf "\n======================================\n"
echo "- Klipper toolchanger install script -"
printf "======================================\n\n"

doinstall=1;
if [ $# -gt 0 ]; then
    if [ "$1" == "uninstall" ]; then
        doinstall=0;
    fi
fi

# Run steps
if [ $doinstall -gt 0 ]; then
    preflight_checks
    check_download
fi

remove_links

if [ $doinstall -gt 0 ]; then
    link_extension
    link_macros
    copy_examples
    check_includes
    add_update
    restart_klipper

    printf "======================================\n"
    echo "- If you are upgrading maybe sure to -"
    echo "- you check for changes in the user  -"
    echo "- config files                       -"
    printf "======================================\n\n"
fi