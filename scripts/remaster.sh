#!/bin/bash
# encoding: utf-8
#
# (c) Mattias Schlenker 2017, 2016 für Heise
#     MIT License http://opensource.org/licenses/MIT 
#
# Dieses Script muss mit Rootrechten ausgeführt werden! 
#
# Das aktuelle Arbeitsverzeichnis muss auf einem ext4- oder btrfs-Volume mit
# ausreichend freiem Platz liegen. Die Verwendung im RAM (Overlay-Dateisystem)
# schlägt meist fehl!
#
# Lesen Sie auch:
# http://www.heise.de/ct/ausgabe/2015-18-Eigene-Erweiterungen-und-frische-Signaturen-fuer-das-c-t-Live-System-2767399.html
#
# Aufruf:
#	remaster.sh pfad/zu/desinfect-alt-2016.iso pfad/zu/desinfect-neu-2016.iso
#
# ...aus einem laufenden Desinfec't:
#	remaster.sh /isodevices/software/desinfect-2016.iso pfad/zu/desinfect-neu-2016.iso
#
# oder, sinnvoll wenn das build_iso per NFS für PXE-Boot exportiert werden soll:
#
#	NOISO=1 NAMESERVER=8.8.8.8 remaster.sh pfad/zu/desinfect-alt-2016.iso
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
#	UPDATE_FIRST=1	- apt-get update && apt-get -y dist-upgrade durchführen
#
#	APT_GET_INSTALL	- Liste von Paketen, die vom regulären Debian-Server 
# 			  installiert werden sollen
#
# ACHTUNG! Die Installation von Debian-Paketen und die Synchronisierung von 
# Overlays erfolgt nur beim ersten Entpacken! Falls Änderungen an Overlays 
# oder Debs vorgenommen werden, die beiden Verzeichnisse "build_squash" und
# "build_iso" bitte löschen!
#
# Nach der Installation von Debs muss manuell bestätigt werden, dass alles OK 
# ist - die Verwendung in einem Cronjob o.ä. ist daher in diesem Fall erst 
# möglich, nachdem das Script einmal manuell ausgeführt wurde!

comment_lines=69

install_extras=0
me=` id -u `
if [ "$me" -gt 0 ] ; then
	echo '***> Bitte rufen Sie dieses Script mit Root-Rechten auf!'
	head -n "$comment_lines" "$0"
	exit 1
fi

if [ -z "$1" ] ; then
	echo '***> Bitte Pfad zum Desinfect-Input-ISO als ersten Parameter übergeben!'
	head -n "$comment_lines" "$0"
	exit 1 
fi
if [ -z "$2" ] ; then
        echo '***> Bitte Pfad zum Desinfect-Output-ISO als zweiten Parameter übergeben!'
	if [ "0${NOISO}" -gt 0 ] ; then
		echo '***> OK, geht ohne.'
	else
		head -n "$comment_lines" "$0"
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

# Nameserver setzen falls angefordert:
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
# Overlays für Kaspersky
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
if [ -n "$APT_GET_INSTALL" -o "$UPDATE_FIRST" -gt 0 ] ; then
	mv build_squash/etc/apt/sources.list{,.bak}
	echo 'deb http://localhost/desinfect 2017 main' >> build_squash/etc/apt/sources.list
	echo 'deb http://de.archive.ubuntu.com/ubuntu xenial main restricted universe multiverse' >> build_squash/etc/apt/sources.list
	echo 'deb http://security.ubuntu.com/ubuntu xenial-updates main restricted universe multiverse' >> build_squash/etc/apt/sources.list
	echo 'deb http://security.ubuntu.com/ubuntu xenial-security main restricted universe multiverse' >> build_squash/etc/apt/sources.list
	chroot build_squash apt-get update
	if [ "$UPDATE_FIRST" -gt 0 ] ; then
		chroot build_squash apt-get -y dist-upgrade
		chroot build_squash update-initramfs -k all -c
	fi
	if [ -n "$APT_GET_INSTALL" ] ; then
		for pkg in $APT_GET_INSTALL ; do
			chroot build_squash apt-get -y install $pkg 
		done
	fi
	mv build_squash/etc/apt/sources.list{.bak,}
fi

# Lokale Signaturen verwenden, wenn unter Desinfec't ausgeführt
if [ -x /opt/desinfect/update_all_signatures.sh ] ; then
	/opt/desinfect/update_all_signatures.sh
fi

if [ -d /var/kl/bases_rd ] ; then
	# Kaspersky aktualisieren
	echo '---> Aktualisiere Kaspersky...'
	if mountpoint -q /var/kl/bases_rd ; then
		rsync -avHP --delete /var/kl/bases_rd/ build_squash/var/kl/bases_rd/
	else
		echo 'PATH=/usr/lib/kl:$PATH' > build_squash/tmp/kavupdate
		echo 'LD_LIBRARY_PATH=/usr/lib/kl:$LD_LIBRARY_PATH' >> build_squash/tmp/kavupdate
		echo 'KL_PLUGINS_PATH=/usr/lib/kl' >> build_squash/tmp/kavupdate
		echo 'export PATH LD_LIBRARY_PATH KL_PLUGINS_PATH' >> build_squash/tmp/kavupdate
		echo '/usr/lib/kl/kav update' >> build_squash/tmp/kavupdate
		chroot build_squash /bin/bash /tmp/kavupdate
	fi
fi
# Avira aktualisieren
echo '---> Aktualisiere Avira...'
if [ -d /AntiVir -a -d /AntiVirUpdate ] ; then
	rsync -avHP --delete /AntiVir/ build_squash/AntiVir/ 
else
	chroot build_squash /AntiVirUpdate/avupdate
fi
# ClamAV aktualisieren
echo '---> Aktualisiere ClamAV...'
if [ -d /var/lib/clamav ] ; then
	rsync -avHP /var/lib/clamav/ build_squash/var/lib/clamav/ 
	chown -R 200:200 build_squash/var/lib/clamav/ 
else
	chroot build_squash freshclam
fi
# ESET aktualisieren
echo '---> Aktualisiere ESET...' 
if [ -d /var/opt/eset ] ; then 
	rsync -avHP --delete /var/opt/eset/ build_squash/var/opt/eset/
else
	chroot build_squash /etc/init.d/esets start
	chroot build_squash /opt/eset/esets/sbin/esets_daemon --update
	echo "Bitte warten Sie ein paar Minuten, prüfen Sie dann, ob unter"
	echo "/var/opt/eset/esets/lib aktualisierte Signaturen liegen und"
	echo "drücken Sie dann [ENTER]."
	read nix 
	chroot build_squash /etc/init.d/esets stop
fi

# Sophos aktualisieren
echo '---> Aktualisiere Sophos...'
if [ -d /opt/sophos-av ] ; then
	rsync -avHP /opt/sophos-av/ build_squash/opt/sophos-av/
fi	
chroot build_squash /opt/sophos-av/bin/savupdate -v3 

# F-Secure aktualisieren 
echo '---> Aktualisiere F-Secure'
if [ -d /opt/f-secure/fssp ] ; then
	rsync -avHP /opt/f-secure/ build_squash/opt/f-secure/ 
fi
( sleep 30 ; chroot build_squash /etc/init.d/fsaua start ) &
chroot build_squash /opt/f-secure/fssp/bin/dbupdate_lite 

# Obsolete Datei entfernen
rm -f build_squash/var/lib/clamav/daily.cld

for d in build_squash/tmp build_squash/root build_squash/proc build_squash/dev \
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

# Existiert ein neueres initramfs?
ls build_squash/boot/initrd.img-* 
if [ "$?" -lt 1 ] ; then
	# Rebuild initramfs again:
	chroot build_squash update-initramfs -k all -c
	cp -v `ls build_squash/boot/initrd.img-* | tail -n1 ` build_iso/casper/initrd.lz
	cp -v `ls build_squash/boot/vmlinuz-* | tail -n1 ` build_iso/casper/vmlinuz
	rsync -avHP build_squash/usr/share/desinfect-remaster/initramfs-stretch/ build_initramfs/
	mkdir -p orig_initramfs 
	( cd orig_initramfs ; gunzip -c ../build_iso/casper/initrd.lz | cpio -i )
	rsync -avHP orig_initramfs/lib/firmware/ build_initramfs/lib/firmware/
	moddir=` ls build_squash/lib/modules | tail -n1 ` 
	rsync -avHP orig_initramfs/lib/modules/${moddir}/ build_initramfs/lib/modules/${moddir}/
	( cd build_initramfs ; find . | cpio -H newc -o | gzip -c > ../build_iso/casper/initrd.str ) 
	rm -rf orig_initramfs 
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
