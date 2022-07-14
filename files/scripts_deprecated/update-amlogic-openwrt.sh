#!/bin/bash

# check cmd param
if [ "$1" == "" ];then
    echo "�÷�: $0 xxx.img"
    exit 1
fi

# ��龵���ļ��Ƿ����
IMG_NAME=$1
if [ ! -f "$IMG_NAME" ];then
    echo "$IMG_NAME ������!"
    exit 1
fi

# ���ҵ�ǰ�� /boot ������Ϣ
DEPENDS="lsblk uuidgen grep awk btrfs mkfs.fat mkfs.btrfs perl md5sum"
echo "����Ҫ�������ļ� ..."
for dep in ${DEPENDS};do
    WITCH=$(which $dep)
    if [ "$WITCH" == "" ];then
        echo "����������: $dep �����ڣ��޷�����������ֻ��ͨ��U��/TF��ˢ����"
	exit 1
    else
	echo "$dep �������ʵ·��: $WITCH"
    fi
done
echo "�����ͨ��"
echo 

BOOT_PART_MSG=$(lsblk -l -o NAME,PATH,TYPE,UUID,MOUNTPOINT | awk '$3~/^part$/ && $5 ~ /^\/boot$/ {print $0}')
if [ "${BOOT_PART_MSG}" == "" ];then
    echo "Boot ���������ڣ�����û����ȷ����, ����޷���������!"
    echo "ԭ����������޸Ĺ����ص�, ֻ�й��ص����ñ��޸�֮��ſ��Խ�������������"
    echo "����1: �� flippy ���ԭ etc-000 �� etc-001 ����֮������"
    echo "����2: cp /.snapshots/etc-000/config/fstab /etc/config/   # Ȼ������"
    exit 1
fi
BOOT_NAME=$(echo $BOOT_PART_MSG | awk '{print $1}')
BOOT_PATH=$(echo $BOOT_PART_MSG | awk '{print $2}')
BOOT_UUID=$(echo $BOOT_PART_MSG | awk '{print $4}')

echo -n "����ж�� /boot ... "
umount -f /boot
if [ $? -ne 0 ];then
    echo "���ɹ�! ������������!"
    exit 1
else
    echo "�ɹ�"
    echo -n "�������¹��� /boot ... "
    mount -t vfat -o "errors=remount-ro" ${BOOT_PATH} /boot 
    if [ $? -ne 0 ];then
	echo "ж�سɹ�, �����¹���ʧ��, ������������!"
	exit 1
    else
        echo "�ɹ�"
    fi
fi

# ��õ�ǰʹ�õ� dtb �ļ���
cp /boot/uEnv.txt /tmp/
source /boot/uEnv.txt 2>/dev/null
CUR_FDTFILE=${FDT}
if [ "${CUR_FDTFILE}" == "" ];then
    echo "����: δ�鵽��ǰʹ�õ� dtb �ļ���������Ӱ����������(Ҳ���ܲ�Ӱ��)"
fi

# ��õ�ǰ�̼��Ĳ���
CUR_SOC=""
CUR_BOARD=""
CUR_MAINLINE_UBOOT=""
CUR_MAINLINE_UBOOT_MD5SUM=""
if [ -f /etc/flippy-openwrt-release ];then
    source /etc/flippy-openwrt-release
    CUR_SOC=$SOC
    CUR_BOARD=$BOARD
    CUR_MAINLINE_UBOOT=${MAINLINE_UBOOT}
    CUR_MAINLINE_UBOOT_MD5SUM=${MAINLINE_UBOOT_MD5SUM}
fi

CUR_KV=$(uname -r)
# �ж��ں˰汾�Ƿ� >= 5.10
CK_VER=$(echo "$CUR_KV" | cut -d '.' -f1)
CK_MAJ=$(echo "$CUR_KV" | cut -d '.' -f2)

if [ $CK_VER -eq 5 ];then
    if [ $CK_MAJ -ge 10 ];then
        CUR_K510=1
    else
        CUR_K510=0
    fi
elif [ $CK_VER -gt 5 ];then
    CUR_K510=1
else
    CUR_K510=0
fi

# ���ݱ�־
BR_FLAG=1
echo -ne "����Ҫ���ݾɰ汾�����ã������仹ԭ���������ϵͳ����? y/n [y]\b\b"
read yn
case $yn in
     n*|N*) BR_FLAG=0;;
esac

# emmc�豸����  /dev/mmcblk?p?boot0��/dev/mmcblk?p?boot1��2�������豸, tf����u���򲻴��ڸ��豸
MMCBOOT0=${BOOT_PATH%%p*}boot0
if [ -b "${MMCBOOT0}" ];then
    CUR_BOOT_FROM_EMMC=1        # BOOT��EMMC 
    echo "��ǰ�� boot ������ EMMC ��"
    cp /boot/u-boot.ext  /tmp/ 2>/dev/null
    cp /boot/u-boot.emmc /tmp/ 2>/dev/null
    BOOT_LABEL="EMMC_BOOT"
else
    CUR_BOOT_FROM_EMMC=0        # BOOT ���� EMMC
    if echo "${BOOT_PATH}" | grep "mmcblk" > /dev/null;then
        echo "��ǰ�� boot ������ TF�� ��"
    else
        echo "��ǰ�� boot ������ U�� ��"
    fi
    cp /boot/u-boot.ext  /tmp/ 2>/dev/null
    cp /boot/u-boot.emmc /tmp/ 2>/dev/null
    BOOT_LABEL="BOOT"
fi

# find root partition 
ROOT_PART_MSG=$(lsblk -l -o NAME,PATH,TYPE,UUID,MOUNTPOINT | awk '$3~/^part$/ && $5 ~ /^\/$/ {print $0}')
ROOT_NAME=$(echo $ROOT_PART_MSG | awk '{print $1}')
ROOT_PATH=$(echo $ROOT_PART_MSG | awk '{print $2}')
ROOT_UUID=$(echo $ROOT_PART_MSG | awk '{print $4}')
case $ROOT_NAME in 
  mmcblk1p2) NEW_ROOT_NAME=mmcblk1p3
             NEW_ROOT_LABEL=EMMC_ROOTFS2
             ;;
  mmcblk1p3) NEW_ROOT_NAME=mmcblk1p2
             NEW_ROOT_LABEL=EMMC_ROOTFS1
             ;;
  mmcblk2p2) NEW_ROOT_NAME=mmcblk2p3
             NEW_ROOT_LABEL=EMMC_ROOTFS2
             ;;
  mmcblk2p3) NEW_ROOT_NAME=mmcblk2p2
             NEW_ROOT_LABEL=EMMC_ROOTFS1
             ;;
          *) echo "ROOTFS ����λ�ò���ȷ, ����޷���������!"
             exit 1
             ;;
esac

# find new root partition
NEW_ROOT_PART_MSG=$(lsblk -l -o NAME,PATH,TYPE,UUID,MOUNTPOINT | grep "${NEW_ROOT_NAME}" | awk '$3 ~ /^part$/ && $5 !~ /^\/$/ && $5 !~ /^\/boot$/ {print $0}')
if [ "${NEW_ROOT_PART_MSG}" == "" ];then
    echo "�µ� ROOTFS ����������, ����޷���������!"
    exit 1
fi
NEW_ROOT_NAME=$(echo $NEW_ROOT_PART_MSG | awk '{print $1}')
NEW_ROOT_PATH=$(echo $NEW_ROOT_PART_MSG | awk '{print $2}')
NEW_ROOT_UUID=$(echo $NEW_ROOT_PART_MSG | awk '{print $4}')
NEW_ROOT_MP=$(echo $NEW_ROOT_PART_MSG | awk '{print $5}')

# losetup
losetup -f -P $IMG_NAME
if [ $? -eq 0 ];then
    LOOP_DEV=$(losetup | grep "$IMG_NAME" | awk '{print $1}')
    if [ "$LOOP_DEV" == "" ];then
        echo "loop �豸δ�ҵ�!"
        exit 1
    fi
else
    echo "losetup $IMG_FILE ʧ��!"
    exit 1
fi

WAIT=3
echo -n "The loopdev is $LOOP_DEV, wait ${WAIT} seconds "
while [ $WAIT -ge 1 ];do
    echo -n "."
    sleep 1
    WAIT=$(( WAIT - 1 ))
done
echo

# umount loop devices (openwrt will auto mount some partition)
MOUNTED_DEVS=$(lsblk -l -o NAME,PATH,MOUNTPOINT | grep "$LOOP_DEV" | awk '$3 !~ /^$/ {print $2}')
for dev in $MOUNTED_DEVS;do
    while : ;do
        echo -n "ж�� $dev ... "
        umount -f $dev
        sleep 1
        mnt=$(lsblk -l -o NAME,PATH,MOUNTPOINT | grep "$dev" | awk '$3 !~ /^$/ {print $2}')
        if [ "$mnt" == "" ];then
            echo "�ɹ�"
            break
        else 
            echo "���� ..."
        fi
    done
done

# mount src part
WORK_DIR=$PWD
P1=${WORK_DIR}/boot
P2=${WORK_DIR}/root
mkdir -p $P1 $P2
echo -n "���� ${LOOP_DEV}p1 -> ${P1} ... "
mount -t vfat -o ro ${LOOP_DEV}p1 ${P1}
if [ $? -ne 0 ];then
    echo "����ʧ��!"
    losetup -D
    exit 1
else 
    echo "�ɹ�"
fi        

echo -n "���� ${LOOP_DEV}p2 -> ${P2} ... "
mount -t btrfs -o ro,compress=zstd ${LOOP_DEV}p2 ${P2}
if [ $? -ne 0 ];then
    echo "����ʧ��!"
    umount -f ${P1}
    losetup -D
    exit 1
else
    echo "�ɹ�"
fi        

# ����¾ɰ汾
NEW_SOC=""
NEW_BOARD=""
if [ -f ${P2}/etc/flippy-openwrt-release ];then
    source ${P2}/etc/flippy-openwrt-release
    NEW_SOC=${SOC}
    NEW_BOARD=${BOARD}
fi

NEW_MAINLINE_UBOOT_MD5SUM=""
if [ "${CUR_MAINLINE_UBOOT}" != "" ];then
    if [ -f "${P2}${CUR_MAINLINE_UBOOT}" ];then
        NEW_MAINLINE_UBOOT_MD5SUM=$(md5sum ${P2}${CUR_MAINLINE_UBOOT} | awk '{print $1}')
    fi
fi

NEW_KV=$(ls ${P2}/lib/modules/)
# �ж��ں˰汾�Ƿ� >= 5.10
NK_VER=$(echo "$NEW_KV" | cut -d '.' -f1)
NK_MAJ=$(echo "$NEW_KV" | cut -d '.' -f2)

if [ $NK_VER -eq 5 ];then
    if [ $NK_MAJ -ge 10 ];then
        NEW_K510=1
    else
        NEW_K510=0
    fi
elif [ $NK_VER -gt 5 ];then
    NEW_K510=1
else
    NEW_K510=0
fi

# �ж�Ҫˢ�İ汾
echo $NEW_KV | grep -E '\w+-[0-9]{1,3}\+[o]{0,1}$' > /dev/null
if [ $? -ne 0 ];then
    echo "Ŀ��̼����ں˰汾��׺��ʽ�޷�ʶ��"
    umount -f ${P1}
    umount -f ${P2}
    losetup -D
    exit 1
fi

NEW_FLIPPY_VER=${NEW_KV##*-}
NEW_FLIPPY_NUM=${NEW_FLIPPY_VER%+*}
if [ $NEW_FLIPPY_NUM -le 53 ];then
    echo "���ű���֧�ֽ����� 53+ �� 53+o ���µİ汾���뻻�� update-amlogic-openwrt-old.sh"
    umount -f ${P1}
    umount -f ${P2}
    losetup -D
    exit 1
fi

if [ "${CUR_SOC}" != "" ];then
    if [ "${CUR_SOC}" != "${NEW_SOC}" ];then
        echo "���õľ����ļ��뵱ǰ������ SOC ��ƥ��, ���飡"
        umount -f ${P1}
        umount -f ${P2}
        losetup -D
        exit 1
    else
        if [ "${CUR_BOARD}" != "" ];then
            if [ "${CUR_BOARD}" != "${NEW_BOARD}" ];then
                echo "���õľ����ļ��뵱ǰ������ BOARD ��ƥ��, ���飡"
                umount -f ${P1}
                umount -f ${P2}
                losetup -D
                exit 1
            fi
        fi
    fi
fi

echo 
echo "����°�̼����Ƿ���ڱ�Ҫ�������ļ� ..."
for dep in ${DEPENDS};do
    echo -n "��� $dep ... "
    if find "${P2}" -name "${dep}" > /dev/null;then
	echo "���ҵ� $dep �ļ�."
    else
        echo "δ�ҵ� $dep �ļ�, ��˵���þ�������ĳЩ��������������������!"
        umount -f ${P1}
        umount -f ${P2}
        losetup -D
	exit 1
    fi
done
echo "���������ͨ��"
echo

BOOT_CHANGED=0
if [ $CUR_BOOT_FROM_EMMC -eq 0 ];then
       while :;do # do level 1
           read -p "Ŀ��̼����Դ� EMMC ����������Ҫ�л� boot �� EMMC �� y/n " yn1
           case $yn1 in 
               n|N)  break;;
               y|Y)  NEW_BOOT_MSG=$(lsblk -l -o PATH,NAME,TYPE,FSTYPE,MOUNTPOINT | grep "vfat" | grep -v "loop" | grep -v "${BOOT_PATH}" | head -n 1)
                     if [ "${NEW_BOOT_MSG}" == "" ];then
                         echo "�ܱ�Ǹ��δ���� emmc ����õ� fat32 ����, �ټ���"
                         umount -f $P1
                         umount -f $P2
                         losetup -D
                         exit 1
                     fi
                     NEW_BOOT_PATH=$(echo $NEW_BOOT_MSG | awk '{print $1}')
                     NEW_BOOT_NAME=$(echo $NEW_BOOT_MSG | awk '{print $2}')
                     NEW_BOOT_MOUNTPOINT=$(echo $NEW_BOOT_MSG | awk '{print $5}')
                     read -p "�µ� boot �豸�� $NEW_BOOT_PATH , ȷ���� y/n " pause

                     NEW_BOOT_OK=0
                     case $pause in 
                         n|N) echo "�޷��ҵ����ʵ�boot�豸�� �ټ�!"
                              umount -f $P1
                              umount -f $P2
                              losetup -D
                              exit 1
                              ;;
                         y|Y) BOOT_LABEL="EMMC_BOOT" 
                              while :;do # do level 2
                              read -p "��Ҫ���¸�ʽ�� ${NEW_BOOT_PATH} �豸,��������ݽ��ᶪʧ�� ȷ����? y/n " yn2
                              case $yn2 in 
                                  n|N) echo "�ټ�"
                                       umount -f $P1
                                       umount -f $P2
                                       losetup -D
                                       exit 1
                                       ;;
                                  y|Y) if [ "${NEW_BOOT_MOUNTPOINT}" != "" ];then
                                           umount -f ${NEW_BOOT_MOUNTPOINT}
                                           if [ $? -ne 0 ];then
                                                echo "�޷�ж�� ${NEW_BOOT_MOUNTPOINT}, �ټ�"
                                                umount -f $P1
                                                umount -f $P2
                                                losetup -D
                                                exit 1
                                           fi
                                       fi
                                       echo "��ʽ�� ${NEW_BOOT_PATH} ..."
                                       mkfs.fat -F 32 -n "${BOOT_LABEL}" ${NEW_BOOT_PATH}

                                       echo "���� ${NEW_BOOT_PATH} ->  /mnt/${NEW_BOOT_NAME} ..."
                                       mount ${NEW_BOOT_PATH}  /mnt/${NEW_BOOT_NAME} 
                                       if [ $? -ne 0 ];then
                                           echo "���� ${NEW_BOOT_PATH} ->  /mnt/${NEW_BOOT_NAME} ʧ��!"
                                           umount -f $P1
                                           umount -f $P2
                                           loseup -D
                                           exit 1
                                       fi

                                       echo "���� /boot ->  /mnt/${NEW_BOOT_NAME} ..."
                                       cp -a  /boot/*  /mnt/${NEW_BOOT_NAME}/

                                       echo "�л� boot ..."
                                       umount -f /boot && \
                                       umount -f /mnt/${NEW_BOOT_NAME}/ && \
                                       mount ${NEW_BOOT_PATH}  /boot
                                       if [ $? -ne 0 ];then
                                           echo "�л�ʧ��!"
                                           umount -f $P1
                                           umount -f $P2
                                           loseup -D
                                           exit 1
                                       else
                                           echo "/boot ���л��� ${NEW_BOOT_PATH}"
				           NEW_BOOT_OK=1
                                       fi
                                       break  # ������2��
                                       ;;
                              esac
                         done # do level 2
                         ;;
                     esac # case $pause
		     if [ $NEW_BOOT_OK -eq 1 ];then
                         BOOT_CHANGED=-1
                         break # ������һ��
                     fi
		     ;;
           esac # case $yn1
       done # do level 1
fi # ��ǰ����emmc������

#format NEW_ROOT
echo "ж�� ${NEW_ROOT_MP}"
umount -f "${NEW_ROOT_MP}"
if [ $? -ne 0 ];then
    echo "ж��ʧ��, ������������һ��!"
    umount -f ${P1}
    umount -f ${P2}
    losetup -D
    exit 1
fi

echo "��ʽ�� ${NEW_ROOT_PATH}"
NEW_ROOT_UUID=$(uuidgen)
mkfs.btrfs -f -U ${NEW_ROOT_UUID} -L ${NEW_ROOT_LABEL} -m single ${NEW_ROOT_PATH}
if [ $? -ne 0 ];then
    echo "��ʽ�� ${NEW_ROOT_PATH} ʧ��!"
    umount -f ${P1}
    umount -f ${P2}
    losetup -D
    exit 1
fi

echo "���� ${NEW_ROOT_PATH} -> ${NEW_ROOT_MP}"
mount -t btrfs -o compress=zstd ${NEW_ROOT_PATH} ${NEW_ROOT_MP}
if [ $? -ne 0 ];then
    echo "���� ${NEW_ROOT_PATH} -> ${NEW_ROOT_MP} ʧ��!"
    umount -f ${P1}
    umount -f ${P2}
    losetup -D
    exit 1
fi

# begin copy rootfs
cd ${NEW_ROOT_MP}
echo "��ʼ�������ݣ� �� ${P2} �� ${NEW_ROOT_MP} ..."
ENTRYS=$(ls)
for entry in $ENTRYS;do
    if [ "$entry" == "lost+found" ];then
        continue
    fi
    echo -n "�Ƴ��ɵ� $entry ... "
    rm -rf $entry 
    if [ $? -eq 0 ];then
        echo "�ɹ�"
    else
        echo "ʧ��"
        exit 1
    fi
done
echo

echo "���� etc �Ӿ� ..."
btrfs subvolume create etc
echo -n "�����ļ��� ... "
mkdir -p .snapshots .reserved bin boot dev lib opt mnt overlay proc rom root run sbin sys tmp usr www
ln -sf lib/ lib64
ln -sf tmp/ var
echo "���"
echo

COPY_SRC="root etc bin sbin lib opt usr www"
echo "�������� ... "
for src in $COPY_SRC;do
    echo -n "���� $src ... "
    (cd ${P2} && tar cf - $src) | tar xf - 2>/dev/null
    sync
    echo "���"
done

SHFS="/mnt/mmcblk2p4"
echo "�޸������ļ� ... "
rm -f "./etc/rc.local.orig" "./usr/bin/mk_newpart.sh" "./etc/part_size"
rm -f ./etc/bench.log
cat > ./etc/fstab <<EOF
UUID=${NEW_ROOT_UUID} / btrfs compress=zstd 0 1
LABEL=${BOOT_LABEL} /boot vfat defaults 0 2
#tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF

cat > ./etc/config/fstab <<EOF
config global
        option anon_swap '0'
        option anon_mount '1'
        option auto_swap '0'
        option auto_mount '1'
        option delay_root '5'
        option check_fs '0'

config mount
        option target '/overlay'
        option uuid '${NEW_ROOT_UUID}'
        option enabled '1'
        option enabled_fsck '1'
        option fstype 'btrfs'
        option options 'compress=zstd'

config mount
        option target '/boot'
        option label '${BOOT_LABEL}'
        option enabled '1'
        option enabled_fsck '0'
        option fstype 'vfat'
                
EOF

echo "������ʼ etc ���� -> .snapshots/etc-000"
btrfs subvolume snapshot -r etc .snapshots/etc-000

[ -d ${SHFS}/docker ] || mkdir -p ${SHFS}/docker
rm -rf opt/docker && ln -sf ${SHFS}/docker/ opt/docker

if [ -f /mnt/${NEW_ROOT_NAME}/etc/config/AdGuardHome ];then
    [ -d ${SHFS}/AdGuardHome/data ] || mkdir -p ${SHFS}/AdGuardHome/data
    if [ ! -L /usr/bin/AdGuardHome ];then
        [ -d /usr/bin/AdGuardHome ] && \
        cp -a /usr/bin/AdGuardHome/* ${SHFS}/AdGuardHome/
    fi
    ln -sf ${SHFS}/AdGuardHome /mnt/${NEW_ROOT_NAME}/usr/bin/AdGuardHome
fi

rm -f /mnt/${NEW_ROOT_NAME}/root/install-to-emmc.sh
sync
echo "�������"
echo

BACKUP_LIST=$(${P2}/usr/sbin/flippy -p)
if [ $BR_FLAG -eq 1 ];then
    echo -n "��ʼ��ԭ�Ӿ�ϵͳ���ݵ������ļ� ... "
    (
      cd /
      eval tar czf ${NEW_ROOT_MP}/.reserved/openwrt_config.tar.gz "${BACKUP_LIST}" 2>/dev/null
    )
    tar xzf ${NEW_ROOT_MP}/.reserved/openwrt_config.tar.gz 2>/dev/null
    [ -f ./etc/config/dockerman ] && sed -e "s/option wan_mode 'false'/option wan_mode 'true'/" -i ./etc/config/dockerman 2>/dev/null
    [ -f ./etc/config/dockerd ] && sed -e "s/option wan_mode '0'/option wan_mode '1'/" -i ./etc/config/dockerd 2>/dev/null
    [ -f ./etc/config/verysync ] && sed -e 's/config setting/config verysync/' -i ./etc/config/verysync

    # ��ԭ fstab
    cp -f .snapshots/etc-000/fstab ./etc/fstab
    cp -f .snapshots/etc-000/config/fstab ./etc/config/fstab
    sync
    echo "���"
    echo
fi

sed -e 's/ttyAMA0/ttyAML0/' -i ./etc/inittab
sed -e 's/ttyS0/tty0/' -i ./etc/inittab
sss=$(date +%s)
ddd=$((sss/86400))
sed -e "s/:0:0:99999:7:::/:${ddd}:0:99999:7:::/" -i ./etc/shadow
# �޸�amuleÿ���������ظ������Ŀ������
sed -e "/amule:x:/d" -i ./etc/shadow
# �޸�dropbearÿ���������ظ����sshd��Ŀ������
sed -e "/sshd:x:/d" -i ./etc/shadow
if [ `grep "sshd:x:22:22" ./etc/passwd | wc -l` -eq 0 ];then
    echo "sshd:x:22:22:sshd:/var/run/sshd:/bin/false" >> ./etc/passwd
    echo "sshd:x:22:sshd" >> ./etc/group
    echo "sshd:x:${ddd}:0:99999:7:::" >> ./etc/shadow
fi

if [ $BR_FLAG -eq 1 ];then
    if [ -x ./bin/bash ] && [ -f ./etc/profile.d/30-sysinfo.sh ];then
        sed -e 's/\/bin\/ash/\/bin\/bash/' -i ./etc/passwd
    fi
    sync
    echo "���"
    echo
fi
sed -e "s/option hw_flow '1'/option hw_flow '0'/" -i ./etc/config/turboacc
eval tar czf .reserved/openwrt_config.tar.gz "${BACKUP_LIST}" 2>/dev/null

rm -f ./etc/part_size ./usr/bin/mk_newpart.sh
if [ -x ./usr/sbin/balethirq.pl ];then
    if grep "balethirq.pl" "./etc/rc.local";then
        echo "balance irq is enabled"
    else
        echo "enable balance irq"
        sed -e "/exit/i\/usr/sbin/balethirq.pl" -i ./etc/rc.local
    fi
fi

mv ./etc/rc.local ./etc/rc.local.orig

cat > ./etc/rc.local <<EOF
if [ ! -f /etc/rc.d/*dockerd ];then
        /etc/init.d/dockerd enable
        /etc/init.d/dockerd start
fi
mv /etc/rc.local.orig /etc/rc.local
exec /etc/rc.local
exit
EOF

chmod 755 ./etc/rc.local*

# �ж��Ƿ����°������uboot����д��
if [ "${CUR_MAINLINE_UBOOT}" != "" ];then
    UPDATE_UBOOT=0
    if [ -f ".${CUR_MAINLINE_UBOOT}" ] && [ "${CUR_MAINLINE_UBOOT_MD5SUM}" != "${NEW_MAINLINE_UBOOT_MD5SUM}" ];then
	cat <<EOF
----------------------------------------------------------------------
�������°������ bootloader (Mainline u-boot), ����ˢ�� EMMC
----------------------------------------------------------------------
EOF
        while :;do
            read -p "�Ƿ�Ҫ���� bootloader?  y/n " yn
	    case $yn in 
		    y|Y) UPDATE_UBOOT=1
			 break
			 ;;
		    n|N) UPDATE_UBOOT=0
			 break
			 ;;
	    esac
	done
    fi
    
    if [ $UPDATE_UBOOT -eq 1 ];then
        echo "************************************************************************"
        echo "д���µ� bootloader ..."
        EMMC_PATH=${NEW_ROOT_PATH%%p*}
        echo "dd if=.${CUR_MAINLINE_UBOOT} of=${EMMC_PATH} conv=fsync bs=1 count=444"
        dd if=".${CUR_MAINLINE_UBOOT}" of=${EMMC_PATH} conv=fsync bs=1 count=444

        echo "dd if=.${CUR_MAINLINE_UBOOT} of=${EMMC_PATH} conv=fsync bs=512 skip=1 seek=1"
        dd if=".${MAINLINE_UBOOT}" of=${EMMC_PATH} conv=fsync bs=512 skip=1 seek=1

	echo "MAINLINE_UBOOT=${CUR_MAINLINE_UBOOT}" >> ./etc/flippy-openwrt-release
	echo "MAINLINE_UBOOT_MD5SUM=${NEW_MAINLINE_UBOOT_MD5SUM}" >> ./etc/flippy-openwrt-release

        sync
        echo "���"
        echo "************************************************************************"
        echo 
    else
	echo "MAINLINE_UBOOT=${CUR_MAINLINE_UBOOT}" >> ./etc/flippy-openwrt-release
	echo "MAINLINE_UBOOT_MD5SUM=${CUR_MAINLINE_UBOOT_MD5SUM}" >> ./etc/flippy-openwrt-release

        sync
    fi
fi
echo "���� etc ���� -> .snapshots/etc-001"
btrfs subvolume snapshot -r etc .snapshots/etc-001

# 2021.04.01���
# ǿ������fstab,��ֹ�û������޸Ĺ��ص�
# �����˿��չ���֮�󣬲�����Ҫ����fstab
#chattr +ia ./etc/config/fstab

cd ${WORK_DIR}
 
echo -n "ж�� /boot ... "
umount -f /boot
if [ $? -ne 0 ];then
    echo "ж�� /boot ʧ��, ��������ֹ��, ����ľɰ�ϵͳδ��Ӱ�죬�Կɼ���ʹ�á�"
    umount ${P1}
    umount ${P2}
    losetup -D
    exit 1
fi

echo "���¸�ʽ�� ${BOOT_PATH} ..."
if mkfs.fat -n ${BOOT_LABEL} -F 32 ${BOOT_PATH} 2>/dev/null;then
    echo -n "���� /boot ..."
    mount -t vfat -o "errors=remount-ro" ${BOOT_PATH} /boot 
    if [ $? -eq 0 ];then
        echo "�ɹ�"
    else
        echo "����ʧ��! ϵͳ���ƻ�, ׼����ˢ��!"
	exit 1
    fi
else
    echo "��ʽ��ʧ����! ϵͳ���ƻ�, ׼����ˢ��!"
    exit 1
fi

echo "��ʼ�������ݣ� �� ${P1} �� /boot ..."
cd /boot
#cp -a ${P1}/* . && sync
(cd ${P1} && tar cf - . ) | tar xf - 2>/dev/null

if [ "$BOOT_LABEL" == "BOOT" ];then
    [ -f u-boot.ext ] || cp u-boot.emmc u-boot.ext
elif [ "$BOOT_LABEL" == "EMMC_BOOT" ];then
    [ ! -f u-boot.emmc ] && [ -f u-boot.ext ] && cp u-boot.ext u-boot.emmc
    rm -f aml_autoscript* s905_autoscript*
    mv -f boot-emmc.ini boot.ini
    mv -f boot-emmc.cmd boot.cmd
    mv -f boot-emmc.scr boot.scr
fi

sync
echo "���"
echo

echo -n "���� boot ���� ... "
if [ -f /tmp/uEnv.txt ];then
    lines=$(wc -l < /tmp/uEnv.txt)
    lines=$(( lines - 1 ))
    head -n $lines /tmp/uEnv.txt > uEnv.txt
    cat >> uEnv.txt <<EOF
APPEND=root=UUID=${NEW_ROOT_UUID} rootfstype=btrfs rootflags=compress=zstd console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF
elif [ "${CUR_FDTFILE}" != "" ];then
    cat > uEnv.txt <<EOF
LINUX=/zImage
INITRD=/uInitrd

FDT=${CUR_FDTFILE}

APPEND=root=UUID=${NEW_ROOT_UUID} rootfstype=btrfs rootflags=compress=zstd console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF
else
    FDT_OK=0
    while [ $FDT_OK -eq 0 ];do
        echo "-----------------------------------------------------------------------------"
	(cd ${P2}/dtb/amlogic && ls *.dtb)
        echo "-----------------------------------------------------------------------------"
        read -p "���ֶ����� dtb �ļ���: " CUR_FDTFILE
	if [ -f "${P2}/dtb/amlogic/${CUR_FDTFILE}" ];then
            FDT_OK=1
        else
            echo "�� dtb �ļ������ڣ�����������!"
        fi
    done
    cat > uEnv.txt <<EOF
LINUX=/zImage
INITRD=/uInitrd

FDT=${CUR_FDTFILE}

APPEND=root=UUID=${NEW_ROOT_UUID} rootfstype=btrfs rootflags=compress=zstd console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF
fi

sync
echo "���"
echo

# �����쳣�������ˢ��+��ʱ��������boot����֮����ʱ zImage �� uInitrd�� md5sum ��ԭ�ļ���һ��, ����������LOGO�����, Ӧ����Ӳ��BUG���µ�
echo "��� boot �ļ������� ..."
PIVOTAL_FILES="vmlinuz-${NEW_KV} uInitrd-${NEW_KV} zImage uInitrd"
while :;do
    SUM_BAD=0
    for f in ${PIVOTAL_FILES};do
	  SRC_SUM=$(md5sum ${P1}/${f} | awk '{print $1}')
	  DST_SUM=$(md5sum ./${f} | awk '{print $1}')
          if [ "$SRC_SUM" != "$DST_SUM" ];then
	       echo -n "${f} �� md5sum ����ȷ�� �������޸� ..."
	       rm -f ${f} 
	       cp ${P1}/${f} ${f}
	       sync
	       echo "���"
	       SRC_SUM=$(md5sum ${P1}/${f} | awk '{print $1}')
	       DST_SUM=$(md5sum ./${f} | awk '{print $1}')
               if [ "$SRC_SUM" != "$DST_SUM" ];then
                   SUM_BAD=$((SUM_BAD + 1))
	       fi
	  fi
    done	       
    if [ ${SUM_BAD} -eq 0 ];then
        break
    else
	echo "�����ļ�δ�޸�, �����޸� ... "
    fi
done
echo "���"

cd $WORK_DIR
umount -f ${P1} ${P2}
losetup -D
rmdir ${P1} ${P2}
sync

echo
echo "----------------------------------------------------------------------"
if [ $BOOT_CHANGED -lt 0 ];then
    echo "���������, ������ poweroff ����رյ�Դ, Ȼ���Ƴ�ԭ�е� TF�� �� U�̣� ������ϵͳ!"
else
    echo "���������, ������ reboot ��������ϵͳ!"
fi
echo "----------------------------------------------------------------------"

