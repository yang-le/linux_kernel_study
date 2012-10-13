! ���ļ���������ɲ���ϵͳ����������
!
! ���뷽����
!	AS86.EXE -0 -a -o boot.o boot.s
!	LD86.EXE -0 -s -o boot boot.o
! ����ѡ��˵����
! 	'-0' ����8086��16λĿ�����
! 	'-a' ������GNU as��ld���ּ��ݵĴ���
! 	'-s' ȥ��������ɵĿ�ִ���ļ��еķ�����Ϣ
! 	'-o' ָ������ļ�������
!
! AS86.EXE��LD86.EXE��Bruce Evans��д��Intel 8086��80386�������������ӳ���
!
BOOTSEG = 0x07c0						! �������������ص�0x7c00
SYSSEG 	= 0x1000						! �ں��ȼ��ص�0x10000����Ȼ���ƶ���0x0��
SYSLEN 	= 16							! �ں���󳤶ȣ�������
entry start
start:
		jmpi 	go, #BOOTSEG			! ��ת��BOOTSEG����Ϊ��Ѱַ���㣬���CS����Ϊ0x7c0����ʼΪ0��
go:
		mov 	ax, cs					! ��cs����ds��ss�Ĵ���
		mov 	ds, ax
		mov		ss, ax
		mov		sp, #0x400				! ��ջָ����Ҫ���ڳ���ĩ�ˣ�����һ���Ŀռ�

! �����ں˴��뵽SYSSEG��
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

! ���ڲ���ʹ��BIOS�ж��ˣ����Խ��ں˴����ƶ����ڴ��0x0λ�ã�����GDT������þͿ��Ա�ñȽϼ�
ok_load:
		cli								! �ر��ж�
		mov		ax, #SYSSEG				! �ƶ�Դλ��DS:SI = 0x1000:0
		mov		ds, ax
		xor		ax, ax					! �ƶ�Ŀ��λ��ES:DI = 0:0
		mov		es, ax
		mov		cx, #0x1000				! �ƶ�����4K��ÿ��һ���֣�word�����ں˳��Ȳ�����8K
		sub		si, si
		sub		di, di
		rep		
		movw							! ִ���ظ��ƶ�
		
! ���뱣��ģʽ��һ��������IDT��GDT�Ļ���ַ
		mov		ax, #BOOTSEG
		mov		ds, ax					! ������ds����ָ��BOOTSEG������Ѱַ
		lidt	idt_48
		lgdt	gdt_48

! ���뱣��ģʽ�ڶ���������CR0������״̬��MSW������ģʽ��־λ

! -|30--------19|---|15--------6|-----0
! P|  Reserved  |A W|  Reserved |NETEMP
! G|			|M P|			|ETSMPE
! -|------------|---|-----------|------
		mov		ax, #0x0001
		lmsw	ax

! ���뱣��ģʽ��������ִ�г���ת��Ŀ�ģ�ˢ�´�����ִ�йܵ����Ѿ���ȡ�Ĳ�ͬģʽ�µ��κ�ָ�
! �����μĴ�����ֵ����ת֮��Ҳ��ʧȥ����
! �����ת֮�����ǽ����ڴ�0x0��λ�ã��ں˴���ձ��ƶ�����λ�ã���ʼ����ģʽ�µĳ���ִ��

! 15----------3|--0
!   		   |T R
!	���������� |I P
!			   |  L
! -------------|---
		jmpi	0, 0x0008					! 0x0008ΪGDT������Ϊ1��λ�ã�Ȩ��λΪ0x00
		
! ����ΪGDT

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
		.word	0, 0, 0, 0				! ��һ��Ϊ��������

		.word	0x07FF					! ���޳� 2K * 4K = 8M
		.word	0x0000					! �λ�ַ��λ��15..0��
		.word	0x9A00					! 1001 1010 0000 0000 ���ڣ�DPL=0��S=1��TYPE=0xA������Σ���һ�£��ɶ���δ���ʣ����λ�ַ��23..16��=0
		.word	0x00C0					! 0000 0000 1100 0000 G=1��������4K����D=1��32λ�Σ�
		
		.word	0x07FF					! ���޳� 2K * 4K = 8M
		.word	0x0000					! �λ�ַ��λ��15..0��
		.word	0x9200					! 1001 0010 0000 0000 ���ڣ�DPL=0��S=1��TYPE=0x2�����ݶΣ�������չ���ɶ�д��δ���ʣ����λ�ַ��23..16��=0
		.word	0x00C0					! 0000 0000 1100 0000 G=1��������4K����D=1��32λ�Σ�
		
! ����ΪLIDT��LGDTָ���48bit������

! 47-------------------16|15------------0
!   Linear Base Address  |  Table Length
! -----------------------|---------------

idt_48:	
		.word	0						! 16λ���ȣ�0  ~ 15��
		.word	0, 0					! 32λ����ַ��16 ~ 47��
gdt_48:	
		.word	0x7ff					! 16λ���� = 2048 �ֽ� = 256 ����
		.word	0x7c00 + gdt, 0			! 32λ����ַ

.org 510
		.word	0xAA55					! ����������־������λ��������������������ֽ�
