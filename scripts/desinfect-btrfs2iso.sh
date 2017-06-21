#!/bin/bash
# encoding: utf-8
# (c) Mattias Schlenker 2017 für Heise
#     MIT License http://opensource.org/licenses/MIT 
#
# Re-Packs Desinfec't running from BTRFS to an ISO
# 
# Must be called from within Desinfec't with super user privileges.
#
# Call:
#	desinfect-btrfs2iso.sh /path/to/desinfect-2017.iso /temporary/dir 
# 
# The ISO file (first argument) must be the inner ISO image - just mount the
# DVD and specify /media/desinfect/DESINFECT/software/desinfect-2017.iso
#
# The temporary directory might be in memory (when running with 6GB+ of RAM) -
# check whether /tmp has about 3GB free (depends on your modifications),
# otherwise create and use a directory on the BTRFS filesystem - using no
# compression speeds up the build (delete afterwards):
#
# mount -o remount,rw /cdrom
# mkdir -p /cdrom/tmp/remaster
#
# The output file is written to the desinfDATA partition as 
# desinfect-2017-from-btrfs.iso
#
# Comments in English since also contained in international license issues.

HELPLINES=28

me=` id -u `
if [ "$me" -gt 0 ] ; then
	head -n $HELPLINES $0 
	echo '***> Please call with super user privileges!'
	echo ''
	exit 1
fi

if [ -z "$1" ] ; then
	head -n $HELPLINES $0 
	echo '***> Please specify path to input ISO image!'
	echo ''
	exit 1 
fi

INPUTISO="$1"

if [ -z "$2" ] ; then
	head -n $HELPLINES $0 
	echo '***> Please specify temporary directory for the build!'
	echo ''
	exit 1 
fi

TEMPDIR="$2"
OUTDIR=""

if mountpoint -q /media/desinfect/desinfDATA || mountpoint -q /media/desinfDATA ; then
	echo 'OK, found mountpoint desinfDATA'
	if mountpoint -q /media/desinfect/desinfDATA ; then
		OUTDIR=/media/desinfect/desinfDATA
	fi
	if mountpoint -q /media/desinfDATA ; then
		OUTDIR=/media/desinfDATA
	fi
else
	head -n $HELPLINES $0 
	echo '***> Please mount the desinfDATA partition'
	echo ''
	exit 1 
fi

if [ -d "/cdrom/casper/filesystem.dir" ] ; then
	echo 'OK, found Desinfect running from BTRFS'
else
	head -n $HELPLINES $0 
	echo '***> Run from within a Desinfect instance that is installed on BTRFS'
	echo ''
	exit 1 
fi

if [ -f "$INPUTISO" ] ; then
	echo 'OK, found input ISO'
else
	head -n $HELPLINES $0 
	echo '***> Missing ISO image'
	echo ''
	exit 1 
fi

ISONAME=` basename "$INPUTISO" `
OUTPUTISO="${OUTDIR}/${ISONAME%.iso}-from-btrfs.iso"

if [ -f "$OUTPUTISO" ] ; then
	head -n $HELPLINES $0 
	echo '***> Output ISO exists, cowardly refusing to overwrite. Please remove first.'
	echo ''
	exit 1 
fi

xorriso -osirrox on -indev "$INPUTISO" -extract / "${TEMPDIR}/build_iso"
rm -f "${TEMPDIR}/build_iso/casper/filesystem.squashfs"
mksquashfs /cdrom/casper/filesystem.dir "${TEMPDIR}/build_iso/casper/filesystem.squashfs" \
	-comp xz -wildcards -e 'boot/vmlinuz-*' 'boot/initrd.img-*'
# Copy kernels if boot partition is mounted!
xorriso -as mkisofs -graft-points -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot \
	-boot-info-table -boot-load-size 4 -isohybrid-mbr \
	/cdrom/casper/filesystem.dir/usr/lib/ISOLINUX/isohdpfx.bin \
	-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
	-isohybrid-gpt-basdat -V DESINFECT -o "$OUTPUTISO" -r -J \
	"${TEMPDIR}/build_iso" --sort-weight 0 / --sort-weight 2 /boot --sort-weight 1 /isolinux

echo '+++> Done. Please clean up '"${TEMPDIR}/build_iso"'. Have fun!'
