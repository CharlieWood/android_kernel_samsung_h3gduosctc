#!/bin/bash
# idleKernel for Samsung Galaxy Note 3 build script by jcadduono
# This build script is for Marshmallow Touchwiz ports only

################### BEFORE STARTING ################
#
# download a working toolchain and extract it somewhere and configure this file
# to point to the toolchain's root directory.
# I highly recommend Christopher83's Linaro GCC 4.9.x Cortex-A15 toolchain.
# Download it here: http://forum.xda-developers.com/showthread.php?t=2098133
#
# once you've set up the config section how you like it, you can simply run
# ./build.sh
# while inside the /idleKernel-note3/ directory.
#
###################### CONFIG ######################

# whick ramdisk do you want to use
RAMDISK_TYPE=$2

RAMDISK_NAME=myramdisk/$RAMDISK_TYPE"ramdisk"

RAMDISK_ZIP=$RAMDISK_TYPE".zip"

# root directory of idleKernel git repo (default is this script's location)
RDIR=$(pwd)

[ -z $VARIANT ] && \
# device variant/carrier, possible options:
#	att = N900A  (AT&T)
#	can = N900W8 (Canadian, same as T-Mobile)
#	eur = N9005  (Snapdragon International / hltexx / Europe)
#	spr = N900P  (Sprint)
#	tmo = N900T  (T-Mobile, same as Canadian)
#	usc = N900R4 (US Cellular)
#	vzw = N900V  (Verizon)
# korean variants:
#	ktt = N900K  (KT Corporation)
#	lgt = N900L  (LG Telecom)
#	skt = N900S  (South Korea Telecom)
# japanese variants:
#	dcm = N900D / SC-01F  (NTT Docomo)
#	kdi = N900J / SCL22   (au by KDDI)
# Chinese variants:
#	ctc = N9009  (China Telecom)
# ONLY EUR WORKS FOR NOW

VARIANT=$1

SECFUNC_PRINT_HELP()
{
	echo -e '\E[33m'
	echo "The Usage Of The Script"
	echo "$0 \$1 \$2"
	echo "  \$1 : device variant/carrier, possible options"
	echo "      ctc"
	echo "  \$2 : ramdisk options"
	echo "      lss"
	echo "      stock"
	echo -e '\E[0m'
}

if [ "$VARIANT" == "" ] || [ "$RAMDISK_TYPE" == "" ]; then
	SECFUNC_PRINT_HELP;
	exit -1;
fi

[ -z $VER ] && \
# version number
VER=$(cat $RDIR/VERSION)

# kernel version string appended to 3.4.x-idleKernel-hlte-
# (shown in Settings -> About device)
KERNEL_VERSION=$VARIANT-$VER

[ -z $PERMISSIVE ] && \
# should we boot with SELinux mode set to permissive? (1 = permissive, 0 = enforcing)
PERMISSIVE=1

# output directory of flashable kernel
OUT_DIR=$RDIR/myramdisk

# output filename of flashable kernel
OUT_NAME=n9009-chn-$RAMDISK_TYPE-$KERNEL_VERSION

# should we make a TWRP flashable zip? (1 = yes, 0 = no)
MAKE_ZIP=1

# should we make an Odin flashable tar.md5? (1 = yes, 0 = no)
MAKE_TAR=0

# directory containing cross-compile arm-cortex_a15 toolchain

TOOLCHAIN=/opt/toolchains/arm-eabi-4.7

# amount of cpu threads to use in kernel make process
THREADS=4

############## SCARY NO-TOUCHY STUFF ###############

export ARCH=arm
export CROSS_COMPILE=$TOOLCHAIN/bin/arm-eabi-
export LOCALVERSION=-$KERNEL_VERSION

if ! [ -f $RDIR"/arch/arm/configs/variant_hlte_"$VARIANT ] ; then
	echo "Device variant/carrier $VARIANT not found in arm configs!"
	exit -1
fi

if ! [ -d $RDIR"/$RAMDISK_NAME/variant/$VARIANT/" ] ; then
	echo "Device variant/carrier $VARIANT not found in $RAMDISK_NAME/variant!"
	exit -1
fi

[ $PERMISSIVE -eq 1 ] && SELINUX="never_enforce" || SELINUX="always_enforce"

KDIR=$RDIR/build/arch/arm/boot

CLEAN_BUILD()
{
	echo "Cleaning build..."
	cd $RDIR
	rm -rf build
	echo "Removing old boot.img..."
	rm -f /$RAMDISK_NAME/$RAMDISK_ZIP/boot.img
	echo "Removing old zip/tar.md5 files..."
	rm -f $OUT_DIR/$OUT_NAME.zip
	rm -f $OUT_DIR/$OUT_NAME.tar.md5
}

BUILD_KERNEL()
{
	echo "Creating kernel config..."
	cd $RDIR
	mkdir -p build
	make -C $RDIR O=build msm8974_sec_defconfig \
		VARIANT_DEFCONFIG=variant_hlte_$VARIANT \
		SELINUX_DEFCONFIG=selinux_$SELINUX
	echo "Starting build..."
	make -C $RDIR O=build -j"$THREADS"
}

BUILD_RAMDISK()
{
	VARIANT=$VARIANT $RDIR/setup_ramdisk.sh $VARIANT $RAMDISK_NAME
	cd $RDIR/build/ramdisk
	echo "Building ramdisk.img..."
	find | fakeroot cpio -o -H newc | gzip -9 > $KDIR/ramdisk.cpio.gz
	cd $RDIR
}

BUILD_BOOT_IMG()
{
	echo "Generating boot.img..."
	$RDIR/scripts/mkqcdtbootimg/mkqcdtbootimg --kernel $KDIR/zImage \
		--ramdisk $KDIR/ramdisk.cpio.gz \
		--dt_dir $KDIR \
		--cmdline "quiet console=null androidboot.hardware=qcom user_debug=23 msm_rtb.filter=0x37 ehci-hcd.park=3" \
		--base 0x00000000 \
		--pagesize 2048 \
		--ramdisk_offset 0x02000000 \
		--tags_offset 0x01E00000 \
		--output $RDIR/$RAMDISK_NAME/$RAMDISK_ZIP/boot.img 
		echo -n "SEANDROIDENFORCE" >> $RDIR/$RAMDISK_NAME/$RAMDISK_ZIP/boot.img 
}

CREATE_ZIP()
{
	echo "Compressing to TWRP flashable zip file..."
	cd $RDIR/$RAMDISK_NAME/$RAMDISK_ZIP
	7z a -mx9 $OUT_DIR/$OUT_NAME.zip *
	zipinfo -t $OUT_DIR/$OUT_NAME.zip
	cd $RDIR
}

CREATE_TAR()
{
	echo "Compressing to Odin flashable tar.md5 file..."
	cd $RDIR/$RAMDISK_NAME/$RAMDISK_ZIP
	tar -H ustar -c boot.img > $OUT_DIR/$OUT_NAME.tar
	cd $OUT_DIR
	md5sum -t $OUT_NAME.tar >> $OUT_NAME.tar
	mv $OUT_NAME.tar $OUT_NAME.tar.md5
	cd $RDIR
}

DO_BUILD()
{
	echo "Starting build for $OUT_NAME, SELINUX = $SELINUX..."
	CLEAN_BUILD && BUILD_KERNEL && BUILD_RAMDISK && BUILD_BOOT_IMG || {
		echo "Error!"
		exit -1
	}
	if [ $MAKE_ZIP -eq 1 ]; then CREATE_ZIP; fi
	if [ $MAKE_TAR -eq 1 ]; then CREATE_TAR; fi
}

DO_BUILD
