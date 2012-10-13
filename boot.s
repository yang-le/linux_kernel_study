! 该文件编译后生成操作系统的引导扇区
!
! 编译方法：
!	AS86.EXE -0 -a -o boot.o boot.s
!	LD86.EXE -0 -s -o boot boot.o
! 编译选项说明：
! 	'-0' 生成8086的16位目标程序
! 	'-a' 生成与GNU as和ld部分兼容的代码
! 	'-s' 去除最后生成的可执行文件中的符号信息
! 	'-o' 指定输出文件的名称
!
! AS86.EXE和LD86.EXE是Bruce Evans编写的Intel 8086、80386汇编编译程序和链接程序
!
BOOTSEG = 0x07c0						! 引导扇区被加载到0x7c00
SYSSEG 	= 0x1000						! 内核先加载到0x10000处，然后移动到0x0处
SYSLEN 	= 16							! 内核最大长度（扇区）
entry start
start:
		jmpi 	go, #BOOTSEG			! 跳转到BOOTSEG处是为了寻址方便，会把CS设置为0x7c0（初始为0）
go:
		mov 	ax, cs					! 用cs设置ds，ss寄存器
		mov 	ds, ax
		mov		ss, ax
		mov		sp, #0x400				! 堆栈指针需要大于程序末端，并有一定的空间

! 加载内核代码到SYSSEG处
load_system:

! INT 13h AH=02h: Read Sectors From Drive
! Parameters:
! AH=02h AL=Sectors To Read Count
! CX=Track(CL.7 CL.6 CH)/Sector(CL.5 ~ CL.0)
	! CX =       ---CH--- ---CL---
	! Track	   : 76543210 98
	! Sector   :            543210
! DH=Head DL=Drive
! ES:BX=Buffer Address Pointer
! Results:
! CF:Set On Error, Clear If No Error
! AH:Return Code AL:Actual Sectors Read Count
		mov		dx, #0x0000				! Head = 0, Drive = 0
		mov		cx, #0x0002				! Track = 0, Sector = 2	
		mov 	ax, #SYSSEG				
		mov		es, ax					! ES:BX = SYSSEG:0
		xor		bx, bx					
		mov		ax, #0x200 + SYSLEN		! AH = 02h, Sectors To Read = SYSLEN
		int		0x13					
		jnc		ok_load					
die:	
		jmp		die

! 现在不再使用BIOS中断了，可以将内核代码移动到内存的0x0位置，这样GDT表的设置就可以变得比较简单
ok_load:
		cli								! 关闭中断
		mov		ax, #SYSSEG				! 移动源位置DS:SI = 0x1000:0
		mov		ds, ax
		xor		ax, ax					! 移动目标位置ES:DI = 0:0
		mov		es, ax
		mov		cx, #0x1000				! 移动次数4K，每次一个字（word），内核长度不超过8K
		sub		si, si
		sub		di, di
		rep		
		movw							! 执行重复移动
		
! 进入保护模式第一步：设置IDT和GDT的基地址
		mov		ax, #BOOTSEG
		mov		ds, ax					! 首先让ds重新指向BOOTSEG，方便寻址
		lidt	idt_48
		lgdt	gdt_48

! 进入保护模式第二步：设置CR0（机器状态字MSW）保护模式标志位

! -|30--------19|---|15--------6|-----0
! P|  Reserved  |A W|  Reserved |NETEMP
! G|			|M P|			|ETSMPE
! -|------------|---|-----------|------
		mov		ax, #0x0001
		lmsw	ax

! 进入保护模式第三步：执行长跳转（目的：刷新处理器执行管道中已经获取的不同模式下的任何指令）
! 其他段寄存器的值在跳转之后也将失去意义
! 这句跳转之后，我们将从内存0x0的位置（内核代码刚被移动到的位置）开始保护模式下的程序执行

! 15----------3|--0
!   		   |T R
!	描述符索引 |I P
!			   |  L
! -------------|---
		jmpi	0, 0x0008					! 0x0008为GDT表索引为1的位置，权限位为0x00
		
! 以下为GDT

! 31------24----19------16|----|11-------8|7------0
! |	         D A          | D  |  0EWA	  |		  |
! |	BASE    G/0V  LIMIT   |PP S|  TYPE	  | BASE  |	4
! |	31..24   B L  19..16  | L  |  1CRA	  |	23..16|
! ------------------------|----|----------|--------
! |						  |					  	  |
! |	BASE				  | LIMIT			  	  |	0
! |	15..0				  | 15..0			 	  |
! ------------------------|------------------------

gdt:	
		.word	0, 0, 0, 0				! 第一个为空描述符

		.word	0x07FF					! 段限长 2K * 4K = 8M
		.word	0x0000					! 段基址低位（15..0）
		.word	0x9A00					! 1001 1010 0000 0000 存在，DPL=0，S=1，TYPE=0xA（代码段，非一致，可读，未访问），段基址（23..16）=0
		.word	0x00C0					! 0000 0000 1100 0000 G=1（颗粒度4K），D=1（32位段）
		
		.word	0x07FF					! 段限长 2K * 4K = 8M
		.word	0x0000					! 段基址低位（15..0）
		.word	0x9200					! 1001 0010 0000 0000 存在，DPL=0，S=1，TYPE=0x2（数据段，向上扩展，可读写，未访问），段基址（23..16）=0
		.word	0x00C0					! 0000 0000 1100 0000 G=1（颗粒度4K），D=1（32位段）
		
! 以下为LIDT和LGDT指令的48bit操作数

! 47-------------------16|15------------0
!   Linear Base Address  |  Table Length
! -----------------------|---------------

idt_48:	
		.word	0						! 16位表长度（0  ~ 15）
		.word	0, 0					! 32位基地址（16 ~ 47）
gdt_48:	
		.word	0x7ff					! 16位表长度 = 2048 字节 = 256 表项
		.word	0x7c00 + gdt, 0			! 32位基地址

.org 510
		.word	0xAA55					! 引导扇区标志，必须位于引导扇区的最后两个字节
