#! /bin/sh

# as86 ld86 ��Ҫbin86�����֧��
as86 -0 -a -o boot.o boot.s
ld86 -0 -s -o boot boot.o
as -o head.o head.s
ld -s -x -M -Ttext 0x0 -e startup_32 -o system head.o > System.map

# �����հ�����ӳ��
dd bs=1024 if=/dev/zero of=fd.vfd count=1440

# �������̵�loop�豸����д��������ɵ��ļ�
losetup /dev/loop0 fd.vfd
dd bs=32 if=boot of=/dev/loop0 skip=1
dd bs=512 if=system of=/dev/loop0 skip=8 seek=1
sync
losetup -d /dev/loop0
