#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

# If XML files don't have comments before the XML header, use this flag
# Can still be used with broken XML files by using blob_fixup
export TARGET_DISABLE_XML_FIXING=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_DEVICE_COMMON=
ONLY_TARGET=
SECTION=
KANG=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common)
            ONLY_COMMON=true
            ;;
        --only-device-common )
            ONLY_DEVICE_COMMON=true
            ;;
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        --only-target)
            ONLY_TARGET=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        system_ext/etc/init/dpmd.rc)
            [ "$2" = "" ] && return 0
            grep -q "/system/product/bin/" "${2}" && sed -i "s|/system/product/bin/|/system/system_ext/bin/|g" "${2}"
            ;;
        system_ext/etc/permissions/com.qti.dpmframework.xml | system_ext/etc/permissions/dpmapi.xml)
            [ "$2" = "" ] && return 0
            grep -q "/system/product/framework/" "${2}" && sed -i "s|/system/product/framework/|/system/system_ext/framework/|g" "${2}"
            ;;
        system_ext/etc/permissions/qcrilhook.xml)
            [ "$2" = "" ] && return 0
            grep -q "/product/framework/qcrilhook.jar" "${2}" && sed -i 's|/product/framework/qcrilhook.jar|/system_ext/framework/qcrilhook.jar|g' "${2}"
            ;;
        system_ext/lib64/libdpmframework.so)
            [ "$2" = "" ] && return 0
            for LIBSHIM_DPMFRAMEWORK in $(grep -L "libcutils_shim.so" "${2}"); do
                grep -q "libcutils_shim.so" "$LIBSHIM_DPMFRAMEWORK" || "${PATCHELF}" --add-needed "libcutils_shim.so" "$LIBSHIM_DPMFRAMEWORK"
            done
            ;;
        vendor/bin/mlipayd@1.1)
            [ "$2" = "" ] && return 0
            grep -q "vendor.xiaomi.hardware.mtdservice@1.0.so" "${2}" && "${PATCHELF}" --remove-needed "vendor.xiaomi.hardware.mtdservice@1.0.so" "${2}"
            ;;
        vendor/lib64/libmlipay.so | vendor/lib64/libmlipay@1.1.so)
            [ "$2" = "" ] && return 0
            grep -q "vendor.xiaomi.hardware.mtdservice@1.0.so" "${2}" && "${PATCHELF}" --remove-needed "vendor.xiaomi.hardware.mtdservice@1.0.so" "${2}"
            grep -q "/system/etc/firmware" "${2}" && sed -i "s|/system/etc/firmware|/vendor/firmware\x0\x0\x0\x0|g" "${2}"
            ;;
        vendor/bin/pm-service)
            [ "$2" = "" ] && return 0
            grep -q "libutils-v33.so" "${2}" || "${PATCHELF}" --add-needed "libutils-v33.so" "${2}"
            ;;
        vendor/lib64/vendor.xiaomi.hardware.mlipay@1.0.so | vendor/lib64/vendor.xiaomi.hardware.mlipay@1.1.so)
            [ "$2" = "" ] && return 0
            grep -q "libhidlbase-v32.so" "${2}" || "${PATCHELF}" --replace-needed "libhidlbase.so" "libhidlbase-v32.so" "${2}"
            ;;
        vendor/lib/vendor.qti.hardware.fingerprint@1.0.so | vendor/lib64/vendor.qti.hardware.fingerprint@1.0.so)
            [ "$2" = "" ] && return 0
            grep -q "libhidlbase-v32.so" "${2}" || "${PATCHELF}" --replace-needed "libhidlbase.so" "libhidlbase-v32.so" "${2}"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

if [ -z "${ONLY_TARGET}" ] && [ -z "${ONLY_DEVICE_COMMON}" ]; then
    # Initialize the helper for common device
    setup_vendor "${DEVICE_COMMON}" "${VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" ${KANG} --section "${SECTION}"
    extract "${MY_DIR}/proprietary-files-fm.txt" "${SRC}" "${KANG}" --section "${SECTION}"
    extract "${MY_DIR}/proprietary-files-ir.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -z "${ONLY_TARGET}" ] && [ -s "${MY_DIR}/../${DEVICE_SPECIFIED_COMMON}/proprietary-files.txt" ];then
    # Reinitialize the helper for device specified common
    source "${MY_DIR}/../${DEVICE_SPECIFIED_COMMON}/extract-files.sh"
    setup_vendor "${DEVICE_SPECIFIED_COMMON}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    extract "${MY_DIR}/../${DEVICE_SPECIFIED_COMMON}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -z "${ONLY_DEVICE_COMMON}" ] && [ -s "${MY_DIR}/../${DEVICE}/proprietary-files.txt" ]; then
    # Reinitialize the helper for device
    source "${MY_DIR}/../${DEVICE}/extract-files.sh"
    setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    extract "${MY_DIR}/../${DEVICE}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

"${MY_DIR}/setup-makefiles.sh"
