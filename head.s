# 该文件为32位保护模式代码
#
# 编译方法：
#	as -o head.o head.s
#	ld -s -x -M -Ttext 0x0 -e startup_32 -o system head.o > System.map
# 编译选项说明：
# 	'-s' 去除最后生成的可执行文件中的符号信息
# 	'-x' 删除所有局部符号
# 	'-M' 生成link Map到标准输出
#	'-Ttext' 指定text段的起始位置
#	'-e' 指定程序入口
# 	'-o' 指定输出文件的名称
#
LATCH				= 11930				# 定时器初始计数值（10ms）
SCRN_SEL			= 0x18				# 屏幕显示内存段选择符
TSS0_SEL			= 0x20				# 任务0的TSS段选择符
LDT0_SEL			= 0x28				# 任务0的LDT段选择符
TSS1_SEL			= 0x30				# 任务1的TSS段选择符
LDT1_SEL			= 0x38				# 任务1的LDT段选择符
.global startup_32
.text
startup_32:

# 15----------3|--0
#   		   |T R
#	描述符索引 |I P
#			   |  L
# -------------|---
		movl $0x10, %eax				# 0x10为GDT表索引为2的位置，权限位为0x00，也就是数据段，基地址为0x0
		mov %ax, %ds

# lss，若REG是16位的，则源操作数必须是32位的；
# 若REG是32位的，则源操作数必须是48位的。
# 将低位送REG，将高位送SS，REG不能是段寄存器
		lss init_stack, %esp			# 这里将SS也设为了0x10，参见后面的init_stack

# 上面的操作应该就是为了下面的两个call做DS和SS的准备
# 跳到现在这个新的位置之后，重新设置IDT和GDT
# 但实际上，可以沿用boot.s中的设置，这里进行设置是为了让程序更清晰，也与Linux的处理保持一致
		call setup_idt					# 设置IDT，所有中断都由默认中断处理程序处理
		call setup_gdt					# 设置GDT

		movl $0x10, %eax				# 改变GDT后，重新加载所有段寄存器
		mov %ax, %ds
		mov %ax, %es
		mov %ax, %fs
		mov %ax, %gs
		lss init_stack, %esp

# 设置8253定时器芯片
# 8253采用减1计数的方式
# 端口0~2分别对应计数器0~2，端口3是控制寄存器，端口地址在0x40 ~ 0x43

# 控制寄存器
# 7------0
# SSRRMMMB
# CCLL   C
# 1010210D
# --------
# SC 通道0 ~ 2，3不用
# RL 读写方式 0，计数器锁存；1，只读写低8位；2，只读写高8位；3，全16位
# M  计数方式 0 ~ 5，分别为“计数结束则中断”、“单脉冲发生器”、“速率波发生器”、“方波发生器”、“软件触发方式计数”、“硬件触发方式计数”
# BCD 0，计数值为二进制数；1，计数值为BCD编码的数
		movb $0x36, %al					# 通道0，全16位读写，计数方式3：“方波发生器”，二进制计数
		movl $0x43,	%edx				# 控制端口地址
		outb %al, %dx					# 端口输出

# 输出频率 = CLK频率 / 计数值 = 1.193MHz / 11930 = 1193000 / 11930 = 100Hz
# 所以，计数值如果设为11930，每隔10ms，就会收到一个时钟中断
		movl $LATCH, %eax				# $LATCH = 11930
		movl $0x40, %edx				# 计数器0的端口地址
		outb %al, %dx					# 全16位输出需分两次，先低后高
		movb %ah, %al
		outb %al, %dx

# 中断门描述符
# 31------24----19------16|----|11-------8|7------0
# |	         	          | D  |  		  |		  |
# |  过程入口点偏移值 	  |PP 0|  1110	  | ALL	  |	4
# |	  31..16 			  | L S|  TYPE	  |	0	  |
# ------------------------|----|----------|--------
# |						  |					  	  |
# |	段选择符			  | 过程入口点偏移值  	  |	0
# |						  | 15..0			 	  |
# ------------------------|------------------------
# S=0 为系统描述符，包括LDT描述符，TSS描述符，调用（TYPE=12）、中断（TYPE=14）、陷阱（TYPE=15）、任务（TYPE=5）门描述符

# 接下来设置时钟中断处理程序
		movl $0x00080000, %eax			# 段选择符0x0008，系统代码段
		movw $timer_interrupt, %ax		# 过程入口点偏移值
		movw $0x8E00, %dx				# P=1，DPL=0，S=0，TYPE=14
		movl $0x08, %ecx				# 中断向量号为8，与BIOS的设定一致

# disp(base, index, scale)格式，地址为base + index * scale + disp
# 这里，idt中的每一项都是8字节，而%ecx表示第8项，该命令将idt的第8项的有效地址（即段内偏移量）装入%esi
		lea idt(, %ecx, 8), %esi		# %esi为中断向量8的描述符首地址
		movl %eax, (%esi)				# 设置该描述符
		movl %edx, 4(%esi)
		
# 接下来，系统调用陷阱门
# 陷阱门类似于中断门，但陷阱门处理过程中不会清除IF标志位，即陷阱门处理中可以接收中断
		movw $system_interrupt, %ax		# 系统调用处理程序入口
		movw $0xef00, %dx				# P=1, DPL=3, S=0, TYPE=15
		movl $0x80, %ecx				# 系统调用的中断向量号为0x80
		lea idt(, %ecx, 8), %esi		# 取idt表中索引为0x80的位置
		movl %eax, (%esi)				# 设置描述符
		movl %edx, 4(%esi)
		
# OK，准备启动任务0，先来个人造堆栈，最后用iret（中断返回指令）来跳到任务0
# 中断时，如果中断是在高特权级上执行，则会发生任务堆栈切换，此时会先将当前任务的SS和ESP压入新栈中；
# 然后，会依次向栈中压入EFLAGS、CS、EIP、有时还有错误码，IRET会把他们弹出去赋给对应的寄存器
		pushfl							# 复位EFLAGS中的嵌套任务标志
		andl $0xffffbfff, (%esp)		# 因为我们这个任务不是被其他任务调起来的，执行结束后不需要返回父任务
		popfl							# 使用pushfl将EFLAGS压入栈中，修改，然后弹出
		movl $TSS0_SEL, %eax			# 也许因为这里的操作数是32位的
		ltr %ax							# TR寄存器永远指向当前任务的TSS段，其中存放的是16位的段选择符，ltr指令用来加载这个寄存器
		movl $LDT0_SEL, %eax			# 类似地，设置LDT表基地址
		lldt %ax
		movl $0, current				# 当前任务，任务0
		
# 中断处理时，处理器会将IF标志复位。而中断处理最后的IRET指令会利用压入栈中的EFLAGS将IF置位。
# 所以，我们需要
		sti								# 置EFLAGS中的IF标志位，准备人造堆栈
		pushl $0x17						# 任务0的局部数据段（堆栈段），在LDT的第2项，特权级3
		pushl $init_stack				# 堆栈指针（也可以直接压入ESP）
		pushfl							# EFLAGS
		pushl $0x0f						# 任务0局部空间的代码段选择符，在LDT的第1项，特权级3
		pushl $task0					# 任务0的EIP，入口地址
		iret							# 跳走~，这条执行之后就切换到任务0了
		
# 剩下的是一些子程序
# 首先是设置gdt和idt的
setup_gdt:
		lgdt lgdt_opcode				# ldgt命令接受48位的操作数
		ret

setup_idt:
		lea ignore_int, %edx
		movl $0x00080000, %eax			# 段选择符0x0008，系统代码段
		movw %dx, %ax					# ignore_int 过程入口点偏移值
		movw $0x8E00, %dx				# P=1，DPL=0，S=0，TYPE=14
		lea idt, %edi					# %edi是idt首地址
		mov $256, %ecx					# 以下重复256次
rp_idt:
		movl %eax, (%edi)				# 填写idt中的一项
		movl %edx, 4(%edi)
		addl $8, %edi					# 移动到下一项
		dec %ecx						# 计数值减1
		jne rp_idt						# 计数值不为0则重复
		lidt lidt_opcode				# 最后加载idt基址寄存器
		ret
		
# 接下来，是显示字符串的子程序。
# 取当前光标位置，并把al中的字符显示在屏幕上（80x25）
write_char:
		push %gs						# 保存要用到的寄存器，eax由调用者负责保存
		pushl %ebx
		mov $SCRN_SEL, %ebx				# 让gs指向显示内存段（0xb8000）
		mov %bx, %gs
		movl scr_loc, %ebx				# 从scr_loc变量中取当前的显示位置
		shl $1, %ebx					# 对应的显示内存位置=显示位置*2
		movb %al, %gs:(%ebx)			# 送去显示
		shr $1, %ebx					# 再恢复%ebx本来的值
		incl %ebx						# 显示位置加1
		cmpl $2000, %ebx				# 如果一屏满，则复位为0，注意AT&T的cmp指令是后面的操作数-前面的操作数，结果影响标志位
		jb 1f							# 一屏不满则向前跳到标号1，不清零
		movl $0, %ebx					# 清零
1:		movl %ebx, scr_loc				# 更新scr_loc变量
		popl %ebx						# 弹栈
		pop %gs
		ret

# 然后是中断处理程序
# ignore_int是默认的中断处理程序
.align 4								# 强制此处位于4字节内存边界，为了与旧时的中断向量表兼容？（因为中断向量x4得到中断程序入口）
ignore_int:
		push %ds
		pushl %eax
		movl $0x10, %eax				# 让ds指向内核数据段，因为中断程序属于内核
		mov %ax, %ds
		movl $67, %eax					# 显示‘C’
		call write_char
		popl %eax
		pop %ds
		iret							# 注意这里是中断返回
		
# 定时中断处理程序
.align 4
timer_interrupt:
		push %ds
		pushl %eax
		movl $0x10, %eax				# 让ds指向内核数据段，因为中断程序属于内核
		mov %ax, %ds

# 必须在中断处理程序结束之前发送EOI命令，告知8259A中断处理结束
# 否则8259A会认为中断处理一直在进行，下次同级别以及低级别的中断将无法得到响应
# 但，软中断由于是直接调用了中断处理程序，不经过8259A的处理，所以不用发送EOI
# 发送EOI之后，也不是肯定就会被打断，得看当前的中断处理程序是否允许嵌套，即IF标志位是否置位
# 默认是不允许的，除非在中断处理程序中用sti指令打开
# 所以，我怀疑默认中断处理程序写得有点问题，因为没有发送EOI；系统调用中断处理没问题，因为是软中断
# 没问题了，0x8是第一个硬件中断，IRQ0，0x8之前的都是IBM系统保留的异常服务程序
# 但实际上IBM的设置方法是违背Intel的要求的（Intel对0x00 ~ 0x1f是保留的），所以Linux中重新对8259A进行了编程
		movb $0x20, %al					# 立刻允许其他硬件中断，即向8259A发送EOI命令
		outb %al, $0x20
		movl $1, %eax
		cmpl %eax, current				# 如果当前是任务1，则去执行任务0
		je 1f
		movl %eax, current				# 否则执行任务1

# 可以用jmp或call指令来跳转到或调用一个任务，Linux采用的是jmp方式
		ljmp $TSS1_SEL, $0				# 偏移在这里是没有用的，但要写上，真正的EIP值是由处理器从TSS段中加载的
		jmp 2f
1:		movl $0, current				# 更新current，ljmp到任务几就更新为几
		ljmp $TSS0_SEL, $0
2:		popl %eax
		pop %ds
		iret
		
# 系统调用中断int 0x80，显示字符
.align 4
system_interrupt:
		push %ds
		pushl %edx
		pushl %ecx
		pushl %ebx
		pushl %eax
		movl $0x10, %edx				# DS指向内核数据段
		mov %dx, %ds
		call write_char					# 调用显示字符字程序，显示AL中的字符
		popl %eax
		popl %ebx
		popl %ecx
		popl %edx
		pop %ds
		iret
		
/******************************************************************************/
current:.long 0							# 当前任务号（0或1）
scr_loc:.long 0							# 当前屏幕显示位置（从左上到右下）

.align 4
lidt_opcode:							# lidt的48位操作数
		.word 256 * 8 - 1				# 表限长的值+基地址应该得到表中最后一个有效的地址，因此限长值应该减一
		.long idt						# 基地址

lgdt_opcode:							# lgdt的48位操作数
		.word (end_gdt - gdt) - 1		# 表限长
		.long gdt						# 基地址
		
.align 8								# IDT、GDT、LDT等表的基地址应该8字节对齐，以达到最佳处理器性能
idt:	.fill 256, 8, 0					# 一个空的idt表，固定256项，每项8字节，初始化为0

# GDT描述符
# 31------24----19------16|----|11-------8|7------0
# |	         D A          | D  |  0EWA	  |		  |
# |	BASE    G/0V  LIMIT   |PP S|  TYPE	  | BASE  |	4
# |	31..24   B L  19..16  | L  |  1CRA	  |	23..16|
# ------------------------|----|----------|--------
# |						  |					  	  |
# |	BASE				  | LIMIT			  	  |	0
# |	15..0				  | 15..0			 	  |
# ------------------------|------------------------
gdt:	.quad	0x0000000000000000		# 空描述符

# 内核代码段描述符，选择符0x08
		.word	0x07ff					# 段长度（注意需要加1） 2K * 4K = 8M
		.word	0x0000					# 段基址低位（15..0）
		.word	0x9a00					# 1001 1010 0000 0000 存在，DPL=0，S=1（非系统），TYPE=0xa（代码段，非一致，可读，未访问），段基址（23..16）=0
		.word	0x00c0					# 0000 0000 1100 0000 G=1（颗粒度4K），D=1（32位段）

# 内核数据段描述符，选择符0x10		
		.quad	0x00c09200000007ff		# TYPE=0x2（数据段，向上扩展，可读写，未访问）

# 显示内存段描述符，选择符0x18		
		.quad	0x00c0920b80000002		# TYPE=0x2，基地址=0xb8000，段限长 3 * 4K = 12K
		
# TSS0段描述符，选择符0x20
		.word	0x0068					# 段长度 0x69 = 105 字节（段长度可以稍大一些）
		.word	tss0					# 段基址低位（15..0）
		.word	0xe900					# 1110 1001 0000 0000 存在，DPL=3，S=0（系统），TYPE=0x9（32位TSS，可用），段基址（23..16）=0
		.word	0x0						# G=0
		
# LDT0段描述符，选择符0x28
		.word	0x40, ldt0, 0xe200, 0x0	# 段限长 0x41 = 65 字节（通常大于24字节即可），TYPE=0x2（LDT）

# TSS1段描述符，选择符0x30
		.word	0x68, tss1, 0xe900, 0x0
		
# LDT1段描述符，选择符0x38
		.word	0x40, ldt1, 0xe200, 0x0
end_gdt:

		.fill	128, 4, 0				# 设置堆栈，128 x 4 = 512字节，初始化为0
init_stack:								# 栈指针ESP在高地址处
		.long	init_stack				# LSS的参数，低位送ESP
		.word	0x10					# 高位送SS，栈段同内核数据段

# 任务0的LDT和TSS
.align 8
ldt0:
		.quad	0x0000000000000000		# 第一个，空描述符

# 局部代码段描述符，选择符0x0f
		.word	0x03ff					# 段限长 1K * 4K = 4M
		.word	0x0000					# 段基址低位（15..0）
		.word	0xfa00					# 1111 1010 0000 0000 存在，DPL=3，S=1（非系统），TYPE=0xa（代码段）
		.word	0x00c0					# 0000 0000 1100 0000 G=1（颗粒度4K），D=1（32位段）

# 局部数据段描述符，选择符0x17
		.quad	0x00c0f200000003ff		# TYPE=0x2（数据段）
		
tss0:									# 任务状态段为固定结构，共104字节，如下
		.long 0							/* back link */
		.long krn_stk0, 0x10			/* esp0, ss0 */
		.long 0, 0, 0, 0, 0				/* esp1, ss1, esp2, ss2, cr3 */
		.long 0, 0, 0, 0, 0				/* eip, eflags, eax, ecx, edx */
		.long 0, 0, 0, 0, 0				/* ebx, esp, ebp, esi, edi */
		.long 0, 0, 0, 0, 0, 0			/* es, cs, ss, ds, fs, gs */
		.long LDT0_SEL, 0x8000000		/* ldt, trace bitmap */
		
		.fill 128, 4, 0					# 任务0的内核栈空间
krn_stk0:

# 任务1的LDT和TSS
.align 8
ldt1:
		.quad 0x0000000000000000		# 空描述符
		.quad 0x00c0fa00000003ff		# 局部代码段
		.quad 0x00c0f200000003ff		# 局部数据段
		
tss1:
		.long 0							/* back link */
		.long krn_stk1, 0x10			/* esp0, ss0 */
		.long 0, 0, 0, 0, 0				/* esp1, ss1, esp2, ss2, cr3 */
		.long task1, 0x200				/* eip, eflags */	
		.long 0, 0, 0, 0				/* eax, ecx, edx, edx */
		.long usr_stk1, 0, 0, 0			/* esp, ebp, esi, edi */
		.long 0x17, 0x0f, 0x17			/* es, cs, ss */
		.long 0x17, 0x17, 0x17			/* ds, fs, gs */
		.long LDT0_SEL, 0x8000000		/* ldt, trace bitmap */
		
		.fill 128, 4, 0					# 任务1的内核栈空间
krn_stk1:

# 最后，是任务0和任务1的程序
task0:
		movl $0x17, %eax				# 设置局部数据段
		movw %ax, %ds
		movb $65, %al					# 显示字符‘A’
		int $0x80
		movl $0xfff, %ecx				# 延时一段时间
1:
		loop 1b
		jmp task0						# 重复执行

task1:
		movb $66, %al					# 显示字符‘B’
		int $0x80
		movl $0xfff, %ecx				# 延时一段时间
1:
		loop 1b
		jmp task1						# 重复执行
		
		.fill 128, 4, 0					# 任务1的用户栈空间
usr_stk1:
