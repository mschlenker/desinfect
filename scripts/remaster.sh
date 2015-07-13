#!/bin/bash
# encoding: utf-8
# (c) Mattias Schlenker 2015 für Heise
#     MIT License http://opensource.org/licenses/MIT 
#
# Aufruf:
#	remaster.sh pfad/zu/desinfect-alt-2015.iso pfad/zu/desinfect-neu-2015.iso
#
# oder, sinnvoll wenn das build_iso per NFS für PXE-Boot exportiert werden soll:
#
#	NOISO=1 NAMESERVER=8.8.8.8 remaster.sh pfad/zu/desinfect-alt-2015.iso
#
# oder, es soll erst einmal nur entpackt werden:
#
#	NOISO=1 NOSQUASH=1 remaster.sh pfad/zu/desinfect-alt-2015.iso 
#
# Verzeichnisse - werden verwendet, wenn sie in dem Ordner anwesend sind,
# in dem dieses Script aufgerufen wird:
#
#	overlay_squash	- wird über das SquashFS synchronisiert, kann 
#			  für eigene Lizenzschlüssel, Scripte etc. verwendet 
#			  werden
#	overlay_iso	- wird über das ISO synchronisiert, kann für 
#			  erweiterte Bootkonfiguration oder zusätzliche 
#			  (Windows-) Tools genutzt werden
#	extra_debs 	- zusätzliche Debian-Pakete, die im SquashFS 
# 			  installiert werden sollen, beispielsweise TrueCrypt
#			  libbde (BitLocker) oder libvshadow
#
# Umgebungsvariablen:
#	
#	NOISO=1		- kein ISO bauen, wenn build_iso direkt für PXE-Boot
#			  bereitgestellt werden soll
#	
#	NOSQUASH=1	- kein SquashFS bauen, entpackt alles, man kann dann 
#			  Änderungen direkt im Chroot vornehmen oder Dateien 
#			  für die Overlays kopieren
#
#	NAMESERVER='8.8.8.8'
#			- Für PXE-Boot sinnvoll: fixen Nameserver definieren!
#			  Wird immer vor Aktualisierung der Signaturen gesetzt
#
#	BIOS_ONLY=1	- ISO ohne UEFI-Unterstützung bauen
#
# ACHTUNG! Die Installation von Debian-Paketen und die Synchronisierung von 
# Overlays erfolgt nur beim ersten Entpacken! Falls Änderungen an Overlays 
# oder Debs vorgenommen werden, die beiden Verzeichnisse "build_squash" und
# "build_iso" bitte löschen!
#
# Nach der Installation von Debs muss manuell bestätigt werden, dass alles OK 
# ist - die Verwendung in einem Cronjob o.ä. ist daher in diesem Fall erst 
# möglich, nachdem das Script einmal manuell ausgeführt wurde!

install_extras=0
me=` id -u `
if [ "$me" -gt 0 ] ; then
	echo '***> Bitte rufen Sie dieses Script mit Root-Rechten auf!'
	exit 1
fi

if [ -z "$1" ] ; then
	echo '***> Bitte Pfad zum Desinfect-Input-ISO als ersten Parameter übergeben!'
	exit 1 
fi
if [ -z "$2" ] ; then
        echo '***> Bitte Pfad zum Desinfect-Output-ISO als zweiten Parameter übergeben!'
	if [ "0${NOISO}" -gt 0 ] ; then
		echo '***> OK, geht ohne.'
	else
		exit 1 
	fi
fi

for c in xorriso rsync mksquashfs ; do
	if which $c ; then
		echo '---> Befehl '${c}' gefunden...'
	else
		echo '***> Befehl '${c}' nicht gefunden! Bitte nachinstallieren und erneut versuchen...'
		exit 1
	fi
done 

# Zuerst ein originales desinfect entpacken.
if [ -d build_iso ] ; then
	echo '===> Ausgabeverzeichnis (ISO) existiert, entpacke nicht!'
else
	xorriso -osirrox on -indev "$1" -extract / build_iso/ || exit 1 
	chmod -R +w build_iso
	rm -f build_iso/isolinux/boot.cat
	# Overlay syncen
        [ -d overlay_iso ] && rsync -avHP overlay_iso/ build_iso/
fi

# SquahsFS entpacken
if [ -d build_squash ] ; then
        echo '===> Ausgabeverzeichnis (SquashFS) existiert, entpacke nicht!'
else
        unsquashfs -d build_squash build_iso/casper/filesystem.squashfs || exit 1
	# Zusätzliche Software installieren
	[ -d extra_debs ] && install_extras=1 
	# Overlay syncen, enthält möglicherweise neue Lizenzschlüssel, daher zuerst
	[ -d overlay_squash ] && rsync -avHP overlay_squash/ build_squash/ 
fi

# Nameserver setzen fals angefordert:
if [ -n "$NAMESERVER" ] ; then
	for f in etc/resolv.conf \
		etc/resolvconf/resolv.conf.d/original \
		etc/resolvconf/resolv.conf.d/tail ; do
		echo "nameserver $NAMESERVER" > build_squash/$f  
	done
fi

# Verzeichnisse mounten:
mount -t tmpfs tmpfs build_squash/tmp
mount -t tmpfs tmpfs build_squash/root
mount --bind /dev build_squash/dev
mount --bind /proc build_squash/proc
# Overlays für Kaspersky und BitDefender
mount --bind build_squash/opt/BitDefender-scanner/var/lib/scan{.orig,} 
mount --bind build_squash/var/kl/bases_rd{.orig,}

if [ "$install_extras" -gt 0 ] ; then
	mkdir build_squash/tmp/extra_debs 
	mount --bind extra_debs build_squash/tmp/extra_debs 
	echo 'dpkg -i /tmp/extra_debs/*.deb' > build_squash/tmp/install_debs
	chroot build_squash /bin/bash /tmp/install_debs 
	echo '???> Alles gut? Weiter mit [ENTER], Strg+C zum Abbrechen'
	read nix 
	umount build_squash/tmp/extra_debs
fi 

# Kaspersky aktualisieren
echo '---> Aktualisiere Kaspersky...'
echo 'PATH=/usr/lib/kl:$PATH' > build_squash/tmp/kavupdate
echo 'LD_LIBRARY_PATH=/usr/lib/kl:$LD_LIBRARY_PATH' >> build_squash/tmp/kavupdate
echo 'KL_PLUGINS_PATH=/usr/lib/kl' >> build_squash/tmp/kavupdate
echo 'export PATH LD_LIBRARY_PATH KL_PLUGINS_PATH' >> build_squash/tmp/kavupdate
echo '/usr/lib/kl/kav update' >> build_squash/tmp/kavupdate
chroot build_squash /bin/bash /tmp/kavupdate
# Bitdefender aktualisieren
echo '---> Aktualisiere BitDefender...'
chroot build_squash bdscan --update
# Avira aktualisieren
echo '---> Aktualisiere Avira...'
chroot build_squash /AntiVirUpdate/avupdate
# ClamAV aktualisieren
echo '---> Aktualisiere ClamAV...'
chroot build_squash freshclam
# Obsolete Datei entfernen
rm -f build_squash/var/lib/clamav/daily.cld

for d in build_squash/tmp build_squash/root build_squash/proc build_squash/dev \
	build_squash/opt/BitDefender-scanner/var/lib/scan \
	build_squash/var/kl/bases_rd ; do
	umount $d
	retval=$?
	if [ "$retval" -gt 0 ] ; then
		echo '***> Aushängen von '${d}' fehlgeschlagen!'
		exit 1
	fi
done

# Zeit, das squashfs neu aufzubauen...
if [ "0${NOSQUASH}" -gt 0 ] ; then
	echo '---> Baue auf ausdrücklichen Wunsch kein neues SquashFS.'
else 
	rm -f build_iso/casper/filesystem.squashfs || exit 1
	echo '---> Baue SquashFS...'
	mksquashfs build_squash build_iso/casper/filesystem.squashfs || exit 1 
fi

# Kein ISO?
if [ "0${NOISO}" -gt 0 ] ; then
	echo '---> Baue auf ausdrücklichen Wunsch kein neues ISO.'
	echo '---> Fertig.'
	exit 0
fi

# Zeit, das ISO aufzubauen...
echo '---> Baue ISO...'
if [ "$BIOS_ONLY" -gt 0 ] ; then
	xorriso -as mkisofs -graft-points -c isolinux/boot.cat \
	-b isolinux/isolinux.bin \
        -no-emul-boot -boot-info-table -boot-load-size 4 -isohybrid-mbr \
        build_squash/usr/lib/syslinux/isohdpfx.bin \
        -V DESINFECT \
        -o "$2" \
        -r -J build_iso \
	--sort-weight 0 / --sort-weight 2 /boot --sort-weight 1 /isolinux
else
	xorriso -as mkisofs -graft-points -c isolinux/boot.cat \
	-b isolinux/isolinux.bin \
        -no-emul-boot -boot-info-table -boot-load-size 4 -isohybrid-mbr \
        build_squash/usr/lib/syslinux/isohdpfx.bin \
        -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
        -isohybrid-gpt-basdat -V DESINFECT \
        -o "$2" \
        -r -J build_iso \
	--sort-weight 0 / --sort-weight 2 /boot --sort-weight 1 /isolinux
fi
