#! /bin/sh

# as86 ld86 需要bin86软件包支持
as86 -0 -a -o boot.o boot.s
ld86 -0 -s -o boot boot.o
as -o head.o head.s
ld -s -x -M -Ttext 0x0 -e startup_32 -o system head.o > System.map

# 制作空白软盘映像（1024 * 1440 字节）
dd bs=1024 if=/dev/zero of=fd.vfd count=1440

# 关联软盘到loop设备，并写入编译生成的文件
losetup /dev/loop0 fd.vfd
dd bs=32 if=boot of=/dev/loop0 skip=1				# 跳过开头的32字节MINIX可执行文件头
dd bs=512 if=system of=/dev/loop0 skip=8 seek=1		# 跳过4K的ELF可执行文件头，seek=1指定从512字节的位置写入
sync
losetup -d /dev/loop0
