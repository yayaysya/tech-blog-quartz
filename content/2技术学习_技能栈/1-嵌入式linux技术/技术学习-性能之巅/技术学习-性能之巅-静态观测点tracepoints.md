---
tags:
  - tracepoints
---


> [!question] tracepoints 是什么? 

是内核开发者  在 内核代码中, 插入的一些探测点.   


## tracepoints具体代码在哪里?

在内核代码中, 通常会看到 trace_...()这样的函数, 就是跟静态观测点有关. 

### 例子

**定义的地方**
```c

#ifdef CONFIG_HAVE_SYSCALL_TRACEPOINTS

TRACE_EVENT_FN(sys_enter,

	TP_PROTO(struct pt_regs *regs, long id),

	TP_ARGS(regs, id),

	TP_STRUCT__entry(
		__field(	long,		id		)
		__array(	unsigned long,	args,	6	)
	),

	TP_fast_assign(
		__entry->id	= id;
		syscall_get_arguments(current, regs, __entry->args);
	),

	TP_printk("NR %ld (%lx, %lx, %lx, %lx, %lx, %lx)",
		  __entry->id,
		  __entry->args[0], __entry->args[1], __entry->args[2],
		  __entry->args[3], __entry->args[4], __entry->args[5]),

	syscall_regfunc, syscall_unregfunc
);

TRACE_EVENT_FLAGS(sys_enter, TRACE_EVENT_FL_CAP_ANY)

TRACE_EVENT_FN(sys_exit,

	TP_PROTO(struct pt_regs *regs, long ret),

	TP_ARGS(regs, ret),

	TP_STRUCT__entry(
		__field(	long,	id	)
		__field(	long,	ret	)
	),

	TP_fast_assign(
		__entry->id	= syscall_get_nr(current, regs);
		__entry->ret	= ret;
	),

	TP_printk("NR %ld = %ld",
		  __entry->id, __entry->ret),

	syscall_regfunc, syscall_unregfunc
);

TRACE_EVENT_FLAGS(sys_exit, TRACE_EVENT_FL_CAP_ANY)

#endif /* CONFIG_HAVE_SYSCALL_TRACEPOINTS */
```

**调用的地方**

```c title:syscall_trace_enter hl:60
/*
 * Returns the syscall nr to run (which should match regs->orig_ax) or -1
 * to skip the syscall.
 */
static long syscall_trace_enter(struct pt_regs *regs)
{
	u32 arch = in_ia32_syscall() ? AUDIT_ARCH_I386 : AUDIT_ARCH_X86_64;

	struct thread_info *ti = current_thread_info();
	unsigned long ret = 0;
	u32 work;

	if (IS_ENABLED(CONFIG_DEBUG_ENTRY))
		BUG_ON(regs != task_pt_regs(current));

	work = READ_ONCE(ti->flags);

	if (work & (_TIF_SYSCALL_TRACE | _TIF_SYSCALL_EMU)) {
		ret = tracehook_report_syscall_entry(regs);
		if (ret || (work & _TIF_SYSCALL_EMU))
			return -1L;
	}

#ifdef CONFIG_SECCOMP
	/*
	 * Do seccomp after ptrace, to catch any tracer changes.
	 */
	if (work & _TIF_SECCOMP) {
		struct seccomp_data sd;

		sd.arch = arch;
		sd.nr = regs->orig_ax;
		sd.instruction_pointer = regs->ip;
#ifdef CONFIG_X86_64
		if (arch == AUDIT_ARCH_X86_64) {
			sd.args[0] = regs->di;
			sd.args[1] = regs->si;
			sd.args[2] = regs->dx;
			sd.args[3] = regs->r10;
			sd.args[4] = regs->r8;
			sd.args[5] = regs->r9;
		} else
#endif
		{
			sd.args[0] = regs->bx;
			sd.args[1] = regs->cx;
			sd.args[2] = regs->dx;
			sd.args[3] = regs->si;
			sd.args[4] = regs->di;
			sd.args[5] = regs->bp;
		}

		ret = __secure_computing(&sd);
		if (ret == -1)
			return ret;
	}
#endif

	if (unlikely(test_thread_flag(TIF_SYSCALL_TRACEPOINT)))
		trace_sys_enter(regs, regs->orig_ax);

	do_audit_syscall_entry(regs, arch);

	return ret ?: regs->orig_ax;
}

```

具体的实现不需要关注, 只要知道内核是通过这种方式定义的就行. 


# 如何查询tracepoints支持哪些? 

## 支持哪些命令?
`cat /sys/kernel/debug/tracing/events` 这个里面可以查询到

**例子**: 调度相关的
![[技术学习-性能之巅-静态观测点tracepoints-1756261908396.png]]

## 具体怎么使用说明? 

`cat /sys/kernel/debug/tracing/events/sched/sched_switch/format`

```shell
root@song-com:/sys/kernel/debug/tracing/events/sched/sched_switch# ls
enable  filter  format  hist  id  trigger
root@song-com:/sys/kernel/debug/tracing/events/sched/sched_switch# cat format 
name: sched_switch
ID: 323
format:
        field:unsigned short common_type;       offset:0;       size:2; signed:0;
        field:unsigned char common_flags;       offset:2;       size:1; signed:0;
        field:unsigned char common_preempt_count;       offset:3;       size:1; signed:0;
        field:int common_pid;   offset:4;       size:4; signed:1;

        field:char prev_comm[16];       offset:8;       size:16;        signed:1;
        field:pid_t prev_pid;   offset:24;      size:4; signed:1;
        field:int prev_prio;    offset:28;      size:4; signed:1;
        field:long prev_state;  offset:32;      size:8; signed:1;
        field:char next_comm[16];       offset:40;      size:16;        signed:1;
        field:pid_t next_pid;   offset:56;      size:4; signed:1;
        field:int next_prio;    offset:60;      size:4; signed:1;

print fmt: "prev_comm=%s prev_pid=%d prev_prio=%d prev_state=%s%s ==> next_comm=%s next_pid=%d next_prio=%d", REC->prev_comm, REC->prev_pid, REC->prev_prio, (REC->prev_state & ((((0x0000 | 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040) + 1) << 1) - 1)) ? __print_flags(REC->prev_state & ((((0x0000 | 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040) + 1) << 1) - 1), "|", { 0x0001, "S" }, { 0x0002, "D" }, { 0x0004, "T" }, { 0x0008, "t" }, { 0x0010, "X" }, { 0x0020, "Z" }, { 0x0040, "P" }, { 0x0080, "I" }) : "R", REC->prev_state & (((0x0000 | 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040) + 1) << 1) ? "+" : "", REC->next_comm, REC->next_pid, REC->next_prio
```


可以看到 
- 被切换线程情况: prev_comm prev_pid 
- 切入线程情况: next_pid next_comm
