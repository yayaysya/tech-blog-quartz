# bpftrace 语法手册（实践导向）

本手册聚焦 bpftrace 语言核心语法与高频用法，便于快速上手与日常性能分析。内容综合 bpftrace 官方文档与业界通用实践。

## 1. 基本概念与运行方式
---

- **bpftrace 是什么**: 基于 eBPF 的高级追踪语言，提供一行到几十行的脚本即可观测内核/用户态行为。
- **最小运行示例**:
```bash
bpftrace -e 'BEGIN { printf("hello\\n"); }'
```

脚本由若干“探针块”构成，形如：`probe /谓词/ { 动作 }`。

## 2. 程序结构与语法
---

- **探针块结构**:
```c
probe_spec 
/predicate/ 
{
  statements;
}
```
- **谓词 predicate（可选）**: 斜杠包裹的布尔表达式，用于服务端过滤事件，减少开销。
- **动作 statements**: 在事件触发时执行的语句块。

示例：统计 `sys_enter_openat` 中按文件名计数，并每 5 秒打印一次。
```c
tracepoint:syscalls:sys_enter_openat {
  @[str(args->filename)] = count();
}

interval:s:5 {
  print(@);
  clear(@);
}
```

## 3. 探针类型（probe specs）
---

- **BEGIN / END**: 程序启动与结束的特殊探针。
```c
BEGIN { printf("start\\n"); }
END   { printf("done\\n"); }
```

- **kprobe / kretprobe**: 钩住内核函数进入/返回。
```c
kprobe:tcp_v4_connect { @cnt = count(); }
kretprobe:tcp_v4_connect { @ret[retval] = count(); }
```

- **tracepoint**: 内核静态跟踪点，具备稳定的 `args->field` 字段。
```c
tracepoint:sched:sched_switch {
  @[args->prev_comm, args->next_comm] = count();
}
```

- **uprobe / uretprobe**: 用户态函数进入/返回（需二进制与符号）。
```c
uprobe:/usr/bin/bash:readline { printf("%s\n", str(arg0)); }
```

- **usdt**: 用户态静态探针（DTrace 风格），常用于数据库、JVM 等。
```c
usdt:/usr/bin/python:gc__start { @gc = count(); }
```

- **profile / interval**: 时间驱动的采样与定时器。
```c
profile:hz:99   { @[ustack()] = count(); }  // 99Hz 采样堆栈, 按照频率触发
interval:s:10   { print(@); clear(@); }   // 达到定时时间触发
```

- **hardware / software（perf 事件）**:
```c
hardware:cache-misses { @miss = count(); }
software:cpu-clock    { @clk = count(); }
```

- **kfunc / kretfunc**: 基于 BTF 的类型化内核函数探针（较新内核更推荐）。
```c
kfunc:tcp_v4_connect {
  // 可用 args 结构体访问形参（取决于 BTF 信息）
  @pid[pid] = count();
}
```

## 4. 谓词与条件过滤
---

- **谓词过滤（首选⭐）**: 在探针后面用 `/.../`，开销最低。
```c
tracepoint:syscalls:sys_enter_openat /pid == 1234/ { @cnt = count(); }
```

- **动作内判断**: 复杂逻辑可用 `if (...) { ... } else { ... }`。
```c
kprobe:__x64_sys_write {
  if (arg2 > 4096) { @big = count(); } else { @small = count(); }
}
```

## 5. 内置变量与常用内置
---

- **进程/线程**: `pid`, `tid`, `uid`, `gid`, `comm`, `cgroup`, `cgroupid`
	- `pid` (Process ID) **用途**: 返回当前进程的 ID。一个进程可能包含一个或多个线程，但它们共享同一个 `pid`。
	- `tid` (Thread ID): **用途**: 返回当前线程的 ID
	- `comm` (Command): **用途**: 返回当前进程的命令名。这是一个字符串，通常是进程启动时使用的**可执行文件名**。

- **CPU/时间**: `cpu`, `nsecs`, `elapsed`（自程序启动起的秒数）

- **探针与函数**: `func`, `probe`, `retval`（返回探针）
	- `func` (Function Name):**用途**: 返回当前探针所附加到的内核或用户空间函数的名称。它是一个字符串，可以帮助你确认正在跟踪的是哪个函数。
		- **示例**: 如果你使用 `kprobe:vfs_read` 探针，那么在探针被触发时，`func` 变量的值就是 `vfs_read`。

- **栈与符号**: `kstack()`, `ustack()`, `ksym(addr)`, `usym(addr)`
	- `kstack()` (Kernel Stack Trace): **用途:** 返回当前进程在内核态的堆栈调用信息。它会显示函数从最顶层一直到当前执行点的调用路径。这对于调试内核或驱动程序中的问题非常有用。
	- `ustack()` (User Stack Trace): **用途:** 返回当前进程在用户态的堆栈调用信息。它会显示应用程序从 main 函数开始，到当前正在执行的函数为止的调用路径。这对于调试应用程序的性能问题或代码逻辑非常有用。

- **参数**: `arg0..argN`（kprobe/uprobes），`args->field`（tracepoint/usdt/kfunc）
- **字符串/内存**: `str(ptr)` 复制用户态字符串；`buf(ptr, len)` 复制原始字节

示例：仅统计大写写入，并截取前 32 字节预览。
```c
kprobe:__x64_sys_write /arg2 > 0/ {
  @[pid, comm] = count();
  printf("first bytes: %r\n", buf(arg1, arg2 < 32 ? arg2 : 32));
}
```

- **常用参数**:
  - `-e` 直接执行一段程序；`script.bt` 运行脚本文件
  - `-o file` 输出到文件；`-f json` 指定输出格式
  - `-p PID` 指定目标进程（主要用于 USDT/uprobes 场景）
  - `-v` 更详细日志；`--unsafe` 允许不安全操作（谨慎使用）


## 6. 变量、映射与聚合
---

- **标量变量**: `@x`（全局map变量）、`$x`（临时/局部），默认初始为 0/空。
- **关联数组（map）**: `@[key]`，key 可为标量、元组或字符串；默认 0。
- **聚合器**:
  - `count()` 计数: 将它理解为一个“<mark style="background-color:#a3be8c">计数器</mark>”，每当它被执行一次，内部的计数就会加一
  - `sum(x)`, `avg(x)`, `min(x)`, `max(x)`
  - `hist(x)` 2 的幂次桶直方图
  - `lhist(x, min, max, step)` 线性直方图

- **打印与清理**:
```c
print(@, 10);   // 只打印前 10 项（按值排序）
clear(@);       // 清空 map
delete(@[key]); // 删除单个键
```


### 示例：按进程名统计 write 大小分布。


```c
kprobe:__x64_sys_write {
  @[comm] = lhist(arg2, 0, 65536, 1024);
}

interval:s:5 { print(@); clear(@); }
```

解释: 

`comm` : 是 BPFtrace 的一个内置变量，代表当前进程的命令名 
**`arg2`**：这是 `__x64_sys_write` 函数的第二个参数; `write` 函数的原型通常是 `ssize_t write(int fd, const void *buf, size_t count)`。在这里，`arg2` 对应于 `count`，也就是**写入的字节数**。所以，这个 `lhist` 函数在对每次 `write` 系统调用写入的字节数进行统计。
`print(@)`: print @就是表示打印所有的@变量的值, 也就是map中的所有值

> @和@[comm] 这个怎么理解呢? 

@可以理解为一个键值对, 没有键的时候, 就退化成一个变量

我们用一个简单的例子来对比一下：
1. **没有键的映射 (`@`)** 如果你写 `@ = count();`，这表示你正在创建一个只有一个元素的映射。它的键是空的（或者说是一个默认值），值是 `count()` 的结果。它只能用来存储一个单一的、全局的统计值。
2. **有键的映射 (`@[comm]`)** 如果你写 `@[comm] = count();`，这表示你正在创建一个更复杂的映射。它会根据每个**不同的 `comm`（进程名）**来存储一个单独的计数。
    - 当 `bash` 进程触发探针时，`@[comm]` 实际上是 `@[ "bash" ]`。
    - 当 `httpd` 进程触发探针时，`@[comm]` 实际上是 `@[ "httpd" ]`。
这样，你就可以在同一个哈希表中，为不同的进程分别进行统计，而不会混淆它们的数据。

> [!info] 所以在使用@[]的时候, 就需要考虑 key是什么?  value是什么?


## 7. 栈与火焰图基础
---

- **采样堆栈**:
```c
profile:hz:97 {
  @[ustack()] = count();
}

interval:s:10 {
  print(@);
  clear(@);
}
```
- **符号解析**: 用户态需要调试符号或 `perfmap`/`jitdump` 支持；可结合 `-p` 锁定目标进程。

## 8. 时间与输出
---

- **时间**:
```c
BEGIN { time("%F %T\n"); }           // 2025-08-26 12:00:00
tracepoint:sched:sched_switch { @t = nsecs; }
```
- **格式化输出**:
```c
printf("pid=%d comm=%s\n", pid, comm);
time("%H:%M:%S "); printf("event!\n");
```

## 9. 控制流与限制
---

- 支持 `if/else`，`return`，三元表达式。不可写非展开循环（eBPF 验证器限制）。
- 固定次数循环可用 `unroll(N)`（在部分版本中提供）。
- 避免大规模字符串复制与未过滤的大范围探针，优先在谓词层过滤。

## 10. 常用模式与实战片段
---

- **Top 系统调用（按进程）**
```c
tracepoint:raw_syscalls:sys_enter {
  @[comm, args->id] = count();
}
interval:s:5 { print(@, 20); clear(@); }
```
解释: @[comm, args->id] 是个二维的键值,  这里sys_enter表示系统调用, 

- **openat 文件名热度**
```c
tracepoint:syscalls:sys_enter_openat {
  @[str(args->filename)] = count();
}
interval:s:5 { print(@, 30); clear(@); }
```
打开的文件名称次说

- **磁盘请求大小分布**
```c
tracepoint:block:block_rq_issue /args->bytes > 0/ {
  @sz = lhist(args->bytes, 0, 1024*1024, 4096);
}
interval:s:10 { print(@sz); clear(@sz); }
```

- **TCP 连接失败码统计**
```c
kretprobe:tcp_v4_connect /retval < 0/ {
  @err[-retval] = count();  // 统计正数错误码
}
interval:s:10 { print(@err); clear(@err); }
```

- **On-CPU 热栈（用户态）**
```c
profile:hz:99 /pid == 1234/ { @[ustack()] = count(); }
interval:s:15 { print(@); clear(@); }
```

## 11. 性能与安全注意
---

- 先过滤后统计：优先使用谓词 `/.../`，其次 `if`。
- Map 数量与键规模要受控，结合 `interval + clear` 周期打印与清理。
- 字符串和缓冲区复制代价高，长度要控；必要时只截取前缀。
- 采样频率（`profile:hz:X`）需结合目标负载评估开销。
- 某些探针需要 root 或特定 `CAP_BPF/CAP_SYS_ADMIN` 权限。

## 12. 小抄（Cheatsheet）
---

- 触发器：`BEGIN`/`END`、`kprobe`/`kretprobe`、`kfunc`/`kretfunc`、`tracepoint`、`uprobe`/`uretprobe`、`usdt`、`profile`、`interval`、`hardware`/`software`
- 过滤：`/predicate/`、`if (...) { ... }`
- 变量：`pid` `tid` `uid` `gid` `comm` `cpu` `elapsed` `retval`
- 参数：`arg0..argN`、`args->field`
- 字符串/内存：`str(ptr)`、`buf(ptr, len)`
- 栈：`kstack()`、`ustack()`；符号：`ksym()`、`usym()`
- 聚合：`count()` `sum()` `avg()` `min()` `max()` `hist()` `lhist()`
- Map 操作：`@[...] = ...`，`print(@, N)`，`clear(@)`，`delete(@[k])`

## 13. 参考
---

- bpftrace 官方文档与示例（`man bpftrace`、`bpftrace --help`）
- Brendan Gregg 系列文章与工具示例（profile/hist/火焰图）
- 内核 tracepoint/USDT 文档与各组件的 USDT 清单

## 14. 练习题与参考答案
---

1) 统计写系统调用次数，并每 5 秒打印 Top 10。
```c title:系统调用次数
tracepoint:raw_syscalls:sys_enter /args->id == 1/ { // 1 == write
  @[comm] = count();
}
interval:s:5 { print(@, 10); clear(@); }
```

2) 只统计 PID=1234 的写调用总字节数。
```c
kprobe:__x64_sys_write /pid == 1234/ {
  @bytes = sum(arg2);
}
interval:s:5 { print(@bytes); clear(@bytes); }
```

3) 统计 `openat` 文件名热度，并过滤只关注以 `.log` 结尾的文件。
```c
tracepoint:syscalls:sys_enter_openat /str(args->filename) ~ \.log$/ {
  @[str(args->filename)] = count();
}
interval:s:10 { print(@, 20); clear(@); }
```

4) 绘制 `read` 读大小的线性直方图（0~64KB，步长 1KB）。
```c
kprobe:__x64_sys_read /arg2 > 0/ {
  @rh = lhist(arg2, 0, 65536, 1024);
}
interval:s:10 { print(@rh); clear(@rh); }
```

5) 采样用户态堆栈（99Hz）并限定到 PID=1234。
```c
profile:hz:99 /pid == 1234/ {
  @[ustack()] = count();
}
interval:s:15 { print(@); clear(@); }
```

6) 统计 `sched_switch` 的上下文切换对（prev->next）。
```c
tracepoint:sched:sched_switch {
  @[args->prev_comm, args->next_comm] = count();
}
interval:s:5 { print(@, 20); clear(@); }
```

7) 对目标进程的 `malloc` 进行 uprobe 计数（根据 libc 路径调整）。
```c
uprobe:/usr/lib/x86_64-linux-gnu/libc.so.6:malloc /pid == 1234/ {
  @m = count();
}
interval:s:10 { print(@m); clear(@m); }
```

8) 统计 `tcp_v4_connect` 失败的错误码分布。
```c
kretprobe:tcp_v4_connect /retval < 0/ {
  @err[-retval] = count();
}
interval:s:10 { print(@err); clear(@err); }
```

9) Top N 系统调用 ID。
```c
tracepoint:raw_syscalls:sys_enter { @[args->id] = count(); }
interval:s:5 { print(@, 10); clear(@); }
```

10) 统计写入前 32 字节预览（仅示例，注意成本与隐私）。
```c
kprobe:__x64_sys_write /arg2 > 0/ {
  printf("%s: %r\n", comm, buf(arg1, arg2 < 32 ? arg2 : 32));
}
```

## 15. 常见错误与调试清单
---

- 权限不足：确保 root 或具备 `CAP_BPF`/`CAP_SYS_ADMIN`，同时内核启用 BTF/kprobe/tracepoint 等必要选项。
- 符号解析失败：
  - 用户态需带符号或启用 `perfmap`/`jitdump`。
  - 建议用 `-p <PID>` 锁定进程，避免跨进程栈混淆。
- kprobe 不命中：
  - 函数名与内核版本/配置相关；优先试 `kfunc`（需 BTF）。
  - 用 `bpftrace -l 'kfunc:tcp*'` 或 `-l 'kprobe:tcp*'` 枚举确认。
- tracepoint 字段错误：用 `bpftrace -l 'tracepoint:subsys:*'` 寻址，再查看对应 `format` 文件确认字段名与类型。
- USDT 不触发：
  - 目标二进制需内置 USDT；运行时需 `-p` 指定具体进程。
  - 用 `bpftrace -l 'usdt:/path:provider:event'` 验证。
- map 过大/内存压力：
  - 控制 key 基数；采用 `interval + print + clear`。
  - 直方图区间合理规划，避免桶太密或太稀。
- 采样过于激进：
  - `profile:hz:X` 从 49/97Hz 起步，按负载调优。
  - 加谓词限定目标进程/条件。
- 字符串/缓冲复制成本：限制 `buf` 长度，如 `min(len, 64)`。
- 版本差异：不同内核/bpftrace 版本语法/功能差异，请先 `--info`/`--help`/`man bpftrace` 对照。

调试小抄：
```bash
# 列出可用探针
bpftrace -l 'tracepoint:*:*' | cat
bpftrace -l 'kfunc:tcp*' | cat

# 查看某 tracepoint 的字段定义
cat /sys/kernel/debug/tracing/events/sched/sched_switch/format | cat

# 试运行与详细日志
bpftrace -v -e 'BEGIN { printf("ok\\n"); }' | cat
```

—— 完 ——


