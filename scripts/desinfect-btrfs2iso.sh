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
# If you are running with an updated kernel, make sure the partition 
# containing the boot files is mounted at /media/desinfSYS or
# /media/desinfect/desinfSYS - in this case kernel and initramfs will
# be copied to the new DVD. 
#
# Environment variables:
#
# OUTPUT_DIR=/path/to/a/directory
#	Do not write the output ISO to the FAT partition of the thumb drive
# CASPER_PATH=/path/to/casper
#	Specify a different casper directory than /cdrom/casper as source
# 
# Comments in English since also contained in international license issues.

HELPLINES=40

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

if [ -n "$OUTPUT_DIR" ] ; then
	if [ -d "$OUTPUT_DIR" ] ; then
		OUTDIR="$OUTPUT_DIR"
	else
		head -n $HELPLINES $0 
		echo '***> Output directory '"$OUTPUT_DIR"' is missing!'
		echo ''
		exit 1 
	fi
elif mountpoint -q /media/desinfect/desinfDATA || mountpoint -q /media/desinfDATA ; then
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

INDIR="/cdrom/casper/filesystem.dir"
if [ -n "$CASPER_PATH" ] ; then
	if [ -d "$CASPER_PATH/filesystem.dir" ] ; then
		INDIR="$CASPER_PATH/filesystem.dir"
	else
		head -n $HELPLINES $0 
		echo '***> Input directory '"$CASPER_PATH/filesystem.dir"' is missing!'
		echo ''
		exit 1 
	fi
fi

mkdir -p "${TEMPDIR}/mount_iso"
mount -o loop "$INPUTISO" "${TEMPDIR}/mount_iso" || exit 1
rsync -avHP --exclude=filesystem.squashfs "${TEMPDIR}/mount_iso/" "${TEMPDIR}/build_iso/"
umount -f "${TEMPDIR}/mount_iso/"
rmdir "${TEMPDIR}/mount_iso/"
rm -f "${TEMPDIR}/build_iso/casper/filesystem.squashfs"
mksquashfs "$INDIR" "${TEMPDIR}/build_iso/casper/filesystem.squashfs" \
	-comp xz -wildcards -e 'boot/vmlinuz-*' 'boot/initrd.img-*'
# Copy kernels if boot partition is mounted!
if mountpoint -q /media/desinfect/desinfSYS || mountpoint -q /media/desinfSYS ; then
	SRCDIR=/media/desinfSYS
	mountpoint -q /media/desinfect/desinfSYS && SRCDIR=/media/desinfect/desinfSYS
	for f in vmlinuz initrd.img initrd.str ; do
		cp -v ${srcdir}/casper/${f} "${TEMPDIR}/build_iso/casper/"
	done
fi

xorriso -as mkisofs -graft-points -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot \
	-boot-info-table -boot-load-size 4 -isohybrid-mbr \
	/cdrom/casper/filesystem.dir/usr/lib/ISOLINUX/isohdpfx.bin \
	-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
	-isohybrid-gpt-basdat -V DESINFECT -o "$OUTPUTISO" -r -J \
	"${TEMPDIR}/build_iso" --sort-weight 0 / --sort-weight 2 /boot --sort-weight 1 /isolinux

echo '+++> Done. Please clean up '"${TEMPDIR}/build_iso"'. Have fun!'
