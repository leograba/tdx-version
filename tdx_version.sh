#!/bin/sh

## Script to get useful info about Toradex hardware.
# Date: may-02-2022
# Author: hiagofranco & g-claudino

#### Variables ####

HORIZONTAL_LINE_WIDTH=60
TABULATION_WIDTH=25

#### Functions ####

print_header ()
{
    if [ -n "$1" ]; then
        echo ""
        echo "$1"
        printf "%0.s-" $(seq 1 $HORIZONTAL_LINE_WIDTH)
        printf "\n"
    else
        echo 'Error: "print_header" called without a parameter!'
        exit 1
    fi
}

print_info ()
{
    if [ -z "$1" ] ; then
        echo 'Error: "print_info" is missing parameter(s)!'
        exit 1
    else
        if [ -z "$2" ]; then
            printf "%-${TABULATION_WIDTH}s %s\n" "$1:" "-"
        elif [ "$(echo "$2" | sed -re '/^$/d' | wc -l)" -gt 1 ]; then
            echo "$1:"
            echo "$2" | sed "s/^/ $(printf "%0.s " $(seq 1 $TABULATION_WIDTH))/"
        else
            printf "%-${TABULATION_WIDTH}s %s\n" "$1:" "$2"
        fi
    fi
}

print_footer ()
{
    printf "%0.s-" $(seq 1 $HORIZONTAL_LINE_WIDTH)
    printf "\n"
}

software_summary ()
{
    kernel_version=$(uname -rv)
    kernel_cmdline=$(cat /proc/cmdline)
    if [ -f /etc/os-release ]; then
        distro_name=$(grep ^NAME /etc/os-release)
        distro_version=$(grep VERSION_ID /etc/os-release)
    else
        distro_name=$(cat /etc/issue)
        distro_version=""
    fi
    hostname=$(cat /etc/hostname)

    print_header "Software summary"
    print_info "Bootloader" "$BOOTLOADER"
    print_info "Kernel version" "$kernel_version"
    print_info "Kernel command line" "$kernel_cmdline"
    print_info "Distro name" "$distro_name"
    print_info "Distro version" "$distro_version"
    print_info "Hostname" "$hostname"
    print_footer
}

hardware_info ()
{
    hw_model=$(tr -d '\0' 2> /dev/null </proc/device-tree/model)
    serial=$(tr -d '\0' 2> /dev/null </proc/device-tree/serial-number)
    som_pid4=$(tr -d '\0' 2> /dev/null </proc/device-tree/toradex,product-id)
    som_pid8=$(tr -d '\0' 2> /dev/null </proc/device-tree/toradex,board-rev)
    processor=$(uname -m)

    print_header "Hardware info"
    print_info "HW model" "$hw_model"
    print_info "Toradex version" "$som_pid4 $som_pid8"
    print_info "Serial number" "$serial"
    print_info "Processor arch" "$processor"
    print_footer
}

bootloader_info ()
{
    print_header "Bootloader info"
    if [ "$BOOTLOADER" = "U-Boot" ]; then
        uboot_version=$(tr -d '\0' 2> /dev/null </proc/device-tree/chosen/u-boot,version)
        uboot_env_vendor=$(fw_printenv vendor 2> /dev/null | sed -r "s/.*=//g")
        uboot_env_board=$(fw_printenv board 2> /dev/null | sed -r "s/.*=//g")
        uboot_env_fdt_board=$(fw_printenv fdt_board 2> /dev/null | sed -r "s/.*=//g")
        uboot_env_soc=$(fw_printenv soc 2> /dev/null | sed -r "s/.*=//g")
        uboot_env_vidargs=$(fw_printenv vidargs 2> /dev/null | sed -r "s/.*=//g")
        uboot_env_sec_boot=$(fw_printenv sec_boot 2> /dev/null | sed -r "s/.*=//g")
        uboot_env_bootdelay=$(fw_printenv bootdelay 2> /dev/null | sed -r "s/.*=//g")

        print_info "U-Boot version" "$uboot_version"
        print_info "U-Boot vendor" "$uboot_env_vendor"
        print_info "U-Boot board" "$uboot_env_board"
        print_info "U-Boot fdt_board" "$uboot_env_fdt_board"
        print_info "U-Boot soc" "$uboot_env_soc"
        print_info "U-Boot video args" "$uboot_env_vidargs"
        print_info "U-Boot secure boot" "$uboot_env_sec_boot"
        print_info "U-Boot boot delay" "$uboot_env_bootdelay"
    elif [ "$BOOTLOADER" = "GRUB" ]; then
        grub_version=$(grub-install --version | awk -F ' ' '{printf $NF}')

        print_info "GRUB version" "$grub_version"
    else
        print_info "Unknown bootloader"
    fi
    print_footer
}

device_tree_info ()
{
    if [ ! "$USE_DEVICETREE" ]; then
        return
    fi

    dt_compatible=$(tr -d '\0' 2> /dev/null </proc/device-tree/compatible)
    dt_used=$(fw_printenv fdtfile 2> /dev/null | sed -r "s/.*=//g")
    if [ -d /boot/ostree ]; then
        stateroot=$(awk -F "ostree=" '{print $2}' /proc/cmdline | awk '{print $1}' | awk -F "/" '{print $5}')
        # shellcheck disable=SC2010
        dt_available=$(ls /boot/ostree/torizon-"$stateroot"/dtb/ 2> /dev/null | grep dtb)
        dto_enabled=$(cat /boot/ostree/torizon-"$stateroot"/dtb/overlays.txt 2> /dev/null)
        dto_available=$(ls /boot/ostree/torizon-"$stateroot"/dtb/overlays 2> /dev/null)
    else
        # shellcheck disable=SC2010
        dt_available=$(ls /boot/ 2> /dev/null | grep dtb)
        dto_enabled=$(cat /boot/overlays.txt 2> /dev/null)
        dto_available=$(ls /boot/overlays 2> /dev/null)
    fi

    print_header "Device tree"
    print_info "Device tree enabled" "$dt_used"
    print_info "Compatible string" "$dt_compatible"
    print_info "Device trees available" "$dt_available"
    print_footer

    print_header "Device tree overlays"
    print_info "Overlays enabled" "$dto_enabled"
    print_info "Overlays available" "$dto_available"
    print_footer
}

devices_info ()
{
    devices=$(ls -lh /dev)

    print_header "Devices"
    print_info "All devices available" "$devices"
    print_footer
}

modules_info ()
{
    lsmod=$(lsmod)

    print_header "Kernel modules"
    print_info "Kernel modules loaded" "$lsmod"
    print_footer
}

dmesg_log ()
{
    loggeduser=${SUDO_USER:-$(logname)}
    dmesg > /home/"$loggeduser"/dmesg.txt
    chown "$loggeduser":"$loggeduser" /home/"$loggeduser"/dmesg.txt
}

check_root_user ()
{
    if [ "$(id -u)" != "0" ]; then
        echo "Please, run as root."
        exit 13
    fi
}

distro_detect ()
{
    # For (arguably) any modern distro, rely on /etc/os-release
    if [ -f /etc/os-release ]; then
        export "DISTRO_$(grep ^NAME /etc/os-release)"
    else
        export DISTRO_NAME="Unknown"
    fi
}

devicetree_detect ()
{
    # fw_utils are not present on L4T
    # fw_utils presennce does not guarantee U-Boot is used
    # GRUB seem to have some sort of support for device tree
    if  find /boot/ -name "*dtb" 2> /dev/null | grep -q . || \
        find /var/rootdirs/mnt/boot/ -name "*dtb" 2> /dev/null | grep -q .; then
        export USE_DEVICETREE=1
    else
        export USE_DEVICETREE=""
    fi
}

bootloader_detect ()
{
    if [ -f /boot/grub/grub.cfg ] || [ "$(command -v grub-install)" ]; then
        export BOOTLOADER="GRUB"
    elif [ "$USE_DEVICETREE" ]; then
        export BOOTLOADER="U-Boot"
    # Don't care about other bootloaders for now, only GRUB and U-Boot
    else
        export BOOTLOADER="Unknown"
    fi
}

help_info ()
{
    echo "Usage: tdx_version.sh [OPTION]"
    echo "List information about hardware and software from Toradex modules."
    echo ""
    echo "--bootloader, -b   : Display bootloader related information (U-Boot and GRUB only)."
    echo "--devices, -d      : List all devices in /dev/."
    echo "--device-tree, -dt : Display device tree and overlays related information."
    echo "--dmesg, -dm       : Export the dmesg output in a txt file at ~."
    echo "--hardware, -w     : Display only hardware information."
    echo "--help, -h         : Display this message."
    echo "--no-devices, -nd  : Diplay hardware and software information without listing devices."
    echo "--software, -s     : Display only software information."
    echo ""
}

#### Main ####

check_root_user
distro_detect
devicetree_detect
bootloader_detect

case $1 in
    "--help" | "-h")
        help_info 
        ;;
    "--software" | "-s")
        software_summary
        ;;
    "--hardware" | "-w")
        hardware_info
        ;;
    "--bootloader" | "-b")
        bootloader_info
        ;;
    "--device-tree" | "-dt")
        device_tree_info
        ;;
    "--devices" | "-d")
        devices_info
        ;;
    "--no-devices" | "-nd")
        software_summary
        hardware_info
        ;;
    "--dmesg" | "-dm")
        dmesg_log
          ;;
    "--modules" | "-m")
        modules_info
        ;;
    "-a" | "--all" | *)
        software_summary
        hardware_info
        bootloader_info
        device_tree_info
        devices_info
        modules_info
        ;;
esac
