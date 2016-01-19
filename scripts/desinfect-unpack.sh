#!/bin/bash
# encoding: utf-8
# (c) Mattias Schlenker 2015 für Heise
#     MIT License http://opensource.org/licenses/MIT 
#
# Aufruf:
#	desinfect-unpack.sh pfad/zu/desinfect-alt-2015.iso
#
# Entpackt Desinfec't in zwei Ordner build_iso (DVD-Inhalt) und 
# build_squash (entpacktes Dateisystem)

me=` id -u `
if [ "$me" -gt 0 ] ; then
	echo '***> Bitte rufen Sie dieses Script mit Root-Rechten auf!'
	exit 1
fi

if [ -z "$1" ] ; then
	echo '***> Bitte Pfad zum Desinfect-Input-ISO als ersten Parameter übergeben!'
	exit 1 
fi
 
for c in xorriso unsquashfs ; do
	if which $c ; then
		echo '---> Befehl '${c}' gefunden...'
	else
		echo '***> Befehl '${c}' nicht gefunden! Bitte nachinstallieren und erneut versuchen...'
		exit 1
	fi
done 

# Zuerst ein originales Desinfect entpacken.
if [ -d build_iso ] ; then
	echo '===> Ausgabeverzeichnis (ISO) existiert, entpacke nicht!'
else
	xorriso -osirrox on -indev "$1" -extract / build_iso/ || exit 1 
	chmod -R +w build_iso
	rm -f build_iso/isolinux/boot.cat
fi

# SquahsFS entpacken
if [ -d build_squash ] ; then
        echo '===> Ausgabeverzeichnis (SquashFS) existiert, entpacke nicht!'
else
        unsquashfs -d build_squash build_iso/casper/filesystem.squashfs || exit 1
fi
