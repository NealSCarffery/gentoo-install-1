#! /bin/bash

if [ "$1" == "" ]; then
    echo "Generate inc.config.sh from an existing Gentoo system being run on."
    echo "Usage: `basename $0` out_filename"
    exit 1
fi

if [ ! -f /etc/portage/make.conf ]; then
    echo "FATAL: Can't find /etc/portage/make.conf, not a Gentoo system?" >&2
    exit 1
fi

outfile="$1"

copy_from_make_conf_required() {
    if ! grep "^$1" < /etc/portage/make.conf >> "$2" ; then
        echo "FATAL: Can't find $1 in $2" >&2
        return 1
    fi
}

copy_from_make_conf_optional() {
    if ! grep "^$1" < /etc/portage/make.conf >> "$2" ; then
        echo "$1=\"\"" >> "$2"
    fi
}

echo "# Autogenerated by config_gen.sh from `uname -n` at `date`" > "$outfile"

echo >> "$outfile"
echo "# You might want to edit TARGET_HOSTNAME and ROOT_PASSWORD values below." >> "$outfile"
echo "TARGET_HOSTNAME=\"`uname -n`\"" >> "$outfile"
echo "ROOT_PASSWORD=\"somepass\"" >> "$outfile"
echo >> "$outfile"

echo "GENTOO_MIRROR=\"ftp://distfiles.gentoo.org\"" >> "$outfile"
copy_from_make_conf_required CFLAGS "$outfile" || exit 1
copy_from_make_conf_required USE "$outfile" || exit 1
copy_from_make_conf_optional INPUT_DEVICES "$outfile"
copy_from_make_conf_optional VIDEO_CARDS "$outfile"
copy_from_make_conf_optional LINGUAS "$outfile"
copy_from_make_conf_optional LIBREOFFICE_EXTENSIONS "$outfile"
copy_from_make_conf_optional NGINX_MODULES_HTTP "$outfile"
copy_from_make_conf_optional NGINX_MODULES_MAIL "$outfile"
copy_from_make_conf_optional QEMU_SOFTMMU_TARGETS "$outfile"
copy_from_make_conf_optional QEMU_USER_TARGETS "$outfile"

echo "SYSTEM_PROFILE=\"`eselect profile show | tail -n+2 | head -n -1 | sed -e 's/^ *//' -e 's/ *$//'`\"" >> "$outfile"

echo "TIMEZONE=\"`cat /etc/timezone`\"" >> "$outfile"

echo "LOCALES=\"" >> "$outfile"
grep -v '^#' /etc/locale.gen | grep -v '^$' | sed 's/^/\t/' >> "$outfile"
echo "\"" >> $outfile
echo "DEFAULT_LOCALE=\"$LANG\"" >> "$outfile"

kernel_dir="`eselect kernel show | tail -n+2 | head -n -1 | sed -e 's/^ *//' -e 's/ *$//'`"
echo "KERNEL_EBUILD=\"`qfile -C "$kernel_dir" | cut -d ' ' -f 1`\"" >> "$outfile"
KERNEL_EXTRA_FIRMWARE=""
if [ -f "$kernel_dir/.config" ]; then
    USE_KERNEL_CONFIG="$kernel_dir/.config"
    echo "USE_KERNEL_CONFIG=\"$USE_KERNEL_CONFIG\"" >> "$outfile"
    # Check for potential extra kernel firmware (binary blobs) ebuilds required.
    eval "`cat "$USE_KERNEL_CONFIG" | grep CONFIG_EXTRA_FIRMWARE`"
    if [ "$CONFIG_EXTRA_FIRMWARE" != "" ] && [ "$CONFIG_EXTRA_FIRMWARE_DIR" != "" ]; then
        KERNEL_EXTRA_FIRMWARE="`qfile -C "$CONFIG_EXTRA_FIRMWARE_DIR/$CONFIG_EXTRA_FIRMWARE" | cut -d ' ' -f 1`"
    fi
else
    echo "USE_KERNEL_CONFIG=\"\"" >> "$outfile"
fi
echo "KERNEL_EXTRA_FIRMWARE=\"$KERNEL_EXTRA_FIRMWARE\"" >> "$outfile"

# Overlays are not yet handled, so we add only packages from default repository.
# FixMe: does not handle properly same package name installed in multiple slots yet.
#  In such cases it takes only the first one and only if it is from default repository.

# GRUB, kernels and netifrc are filtered out, because they are emerged separately.
system_tools_filter="
    net-misc/netifrc
    sys-boot/grub
    `basename -a /usr/portage/sys-kernel/*-sources | sed 's/^/sys-kernel\//'`
    $KERNEL_EXTRA_FIRMWARE
"

echo "SYSTEM_TOOLS=\"" >> "$outfile"

package_use_file=""
if [ -d /etc/portage/package.use ]; then
    package_use_file="/etc/portage/package.use/*"
elif [ -f /etc/portage/package.use ]; then
    package_use_file="/etc/portage/package.use"
fi

cat /var/lib/portage/world | while read pkg_name; do
    pkg_name_without_slot="`echo "$pkg_name" | sed 's/:.*$//'`"
    if ! [[ "$system_tools_filter" =~ "$pkg_name_without_slot" ]]; then
#        pkg_name_with_version="`basename -a /var/db/pkg/$pkg_name_without_slot* | head -n 1`"
        if [ "`cat /var/db/pkg/$pkg_name_without_slot*/repository | head -n 1`" == "gentoo" ]; then
            echo -ne "\t$pkg_name" >> "$outfile"
            if [ "$package_use_file" != "" ]; then
                pkg_use="`cat $package_use_file | grep "$pkg_name_without_slot" | grep -v '^#' | sed 's/\s\+/\t/g' | cut -f 2- | tr '\n' ' ' | xargs -n1 | sort -u | tr '\n' ',' | sed 's/,$//'`"
                if [ "$pkg_use" != "" ]; then
                    echo -n "[$pkg_use]" >> "$outfile"
                fi
            fi
            echo >> "$outfile"
        fi
    fi
done

echo "\"" >> "$outfile"

if grep -qs "grub:2" < /var/lib/portage/world; then
    echo "BOOTLOADER=\"grub2\"" >> "$outfile"
else
    echo "BOOTLOADER=\"grub-legacy\"" >> "$outfile"
fi

echo "Generated configuration written to $outfile."
echo "You might want to edit TARGET_HOSTNAME and ROOT_PASSWORD values there."
echo "Then rename it to inc.config.sh and run gentoo_install.sh."

