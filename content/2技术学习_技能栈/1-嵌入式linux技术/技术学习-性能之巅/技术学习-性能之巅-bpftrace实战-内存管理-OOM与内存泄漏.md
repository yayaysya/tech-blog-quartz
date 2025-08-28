---
是否发表: "false"
publish: true
---



# bpftrace 实战：内存管理（OOM 与内存泄漏）排查指南

适合刚掌握基础语法的同学，本文提供可直接运行的脚本片段，覆盖 OOM 预警、回收观察、内核/用户分配热点、以及用户态泄漏定位思路。

## 1. 常见问题清单
- OOM：系统内存耗尽被内核 OOM killer 杀进程。
- 回收压力：频繁 direct reclaim / kswapd 活跃导致抖动。
- 泄漏：用户态 malloc/free 配对异常、热点调用栈持续增长。

## 2. 你将用到哪些探针
- tracepoint: `oom:oom_kill`、`vmscan:mm_vmscan_*`、`kmem:kmalloc/kmem_cache_alloc`
- kfunc（如可用 BTF）：`kfunc:__kmalloc`/`kretfunc:__kmalloc`、`kfunc:kfree`
- 用户态 uprobe：`libc:malloc`/`free`/`calloc`/`realloc`

> 不同内核版本 tracepoint 字段名略有差异，遇到错误先用 `bpftrace -l` 或查看 `/sys/kernel/debug/tracing/events/.../format`。

## 3. 新手向：排查思路与内核流程对应

内存问题通常表现为缓慢的资源泄露或突发的性能抖动。我们的排查思路同样是从宏观现象入手，逐步聚焦。

- **第一步：定性 (Qualification) - 是“抖动”还是“泄露”？**
  - **思路**：首先要区分问题的类型。性能抖动通常与内存回收（Reclaim）活动有关；而内存泄露则表现为进程RSS（Resident Set Size）持续、单调增长。`top`或`htop`可以给你一个初步印象。
  - **抖动排查**：
    - **行动**：使用`vmscan`相关的tracepoint监控内存回收活动。
    - **脚本**：见4.2节的`direct_reclaim`时长统计和4.3节的`kswapd`活跃度统计。
    - **解读**：如果`direct_reclaim`直方图出现长尾（毫秒级），说明进程在分配内存时被迫同步回收，这是性能杀手。如果`kswapd`频繁唤醒，说明系统持续处于内存压力下。10
  - **泄露排查**：
    - **行动**：如果观察到某个进程RSS持续增长，直接进入第二步。

- **第二步：定位 (Localization) - 问题在“内核”还是“用户态”？**
  - **思路**：内存分配既可能发生在内核空间（驱动、内核服务），也可能发生在用户空间（应用程序）。我们需要确定是哪一方的过错。
  - **内核侧排查**：
    - **行动**：使用`kmem`相关的tracepoint来观察内核内存分配。
    - **脚本**：见5.1节的`kmalloc`大小分布和5.2节的调用栈聚合。
    - **解读**：如果`kmalloc`的调用栈高度集中在某个驱动或内核模块，并且随时间推移，该调用栈的累计分配量`sum()`持续增长，那么很可能是内核泄露。如果只是分配总量大，但没有持续增长趋势，则可能是正常的内核开销。
  - **用户态侧排查**：
    - **行动**：如果内核侧没有明显异常，那么焦点就转向用户态。我们需要“审计”`malloc`和`free`的配对情况。
    - **脚本**：见第6节的用户态内存泄露定位脚本。
    - **解读**：这个脚本的核心是`@live`哈希表，它记录了所有已分配但尚未释放的内存块。如果`@by_stack`中某个调用栈的累计分配量`sum()`随时间持续增长，那么这个调用栈就是泄露源头。

- **第三步：根因分析 (Root Cause Analysis)**
  - **思路**：找到泄露的调用栈后，就需要结合代码逻辑进行分析。
  - **行动**：
    1.  拿到泄露的用户态调用栈。
    2.  对照源代码，检查该调用路径上的所有内存分配点，分析在哪些异常分支或逻辑中，`free`调用被遗漏了。
    3.  例如，一个函数在入口处`malloc`，但在某个错误检查分支中`return`之前忘记了`free`。

- **内核流程映射（简化）**：
  - 用户态调用`malloc` -> glibc的内存分配器 -> `brk`/`mmap`系统调用 -> 内核处理页错误 -> **伙伴系统(Buddy System)** 分配物理页。
  - 内核自身调用`kmalloc` -> **SLAB/SLUB/SLOB分配器** -> 从伙伴系统获取大块内存。
  - 内存不足 -> 触发**kswapd**后台回收或**direct reclaim**同步回收。
  - 回收仍不足 -> 触发**OOM Killer**选择并杀死一个进程。

## 4. OOM 事件与回收活动
```c
// 4.1 监听 OOM kill 事件
tracepoint:oom:oom_kill {
  printf("OOM kill: victim=%s pid=%d rss=%d order=%d\n", str(args->comm), args->pid, args->totalpage, args->order);
  @[str(args->comm)] = count();
}
interval:s:10 { print(@); clear(@); }
```

```c
// 4.2 统计 direct reclaim 持续时间（可能带来长尾卡顿）
tracepoint:vmscan:mm_vmscan_direct_reclaim_begin {
  @begin[tid] = nsecs;
}
tracepoint:vmscan:mm_vmscan_direct_reclaim_end /@begin[tid]/ {
  @reclaim = lhist(nsecs - @begin[tid], 0, 50*1000*1000, 500*1000); // 0~50ms, 0.5ms 步
  delete(@begin[tid]);
}
interval:s:10 { print(@reclaim); clear(@reclaim); }
```

```c
// 4.3 观察 kswapd 活跃度
tracepoint:vmscan:mm_vmscan_kswapd_wake { @wake = count(); }
tracepoint:vmscan:mm_vmscan_kswapd_sleep { @sleep = count(); }
interval:s:30 { printf("kswapd wake=%d sleep=%d\n", @wake, @sleep); clear(@wake); clear(@sleep); }
```

## 5. 内核分配大小分布与热点调用点
```c
// 5.1 kmalloc 大小分布（需内核启用 kmem tracepoint）
tracepoint:kmem:kmalloc {
  @sz = lhist(args->bytes_alloc, 0, 256*1024, 1024);
}
interval:s:10 { print(@sz); clear(@sz); }
```

```c
// 5.2 以调用栈聚合 kmalloc（如支持）
tracepoint:kmem:kmalloc {
  @[kstack()] = sum(args->bytes_alloc);
}
interval:s:10 { print(@, 20); clear(@); }
```

> 若 kmem tracepoint 不可用，可尝试 `kfunc:__kmalloc`/`kretfunc:__kmalloc` 方案（依赖 BTF，字段以实际内核为准）。

## 6. 用户态内存泄漏定位（malloc/free 配对）
以 glibc 为例，路径因系统而异，请根据发行版修正：`/usr/lib/x86_64-linux-gnu/libc.so.6`。

```c
// 6.1 记录 malloc 请求大小（入口）
uprobe:/usr/lib/x86_64-linux-gnu/libc.so.6:malloc {
  @req[tid] = arg0; // size
}

// 6.2 获取返回的指针与大小（返回）
uretprobe:/usr/lib/x86_64-linux-gnu/libc.so.6:malloc /@req[tid]/ {
  $sz = @req[tid];
  @live[retval] = $sz;           // 活跃分配：ptr -> size
  @by_stack[ustack()] = sum($sz); // 以分配点栈聚合
  delete(@req[tid]);
}

// 6.3 捕捉 free 并回收活跃表
uprobe:/usr/lib/x86_64-linux-gnu/libc.so.6:free /@live[arg0]/ {
  delete(@live[arg0]);
}

// 6.4 周期输出：活跃分配 Top-N 与热点栈
interval:s:15 {
  print(@by_stack, 20);
}
```

## 7. 业务实战（STAR 方法）
- 感知模块泄漏：[[技术学习-性能之巅-bpftrace实战-内存管理-案例-感知泄漏_STAR.md]]
- 你也可按模板撰写“编码链长期回收抖动”“控制环短时 OOM 回收”等案例。

## 8. 练习题（含解析与参考答案）
1) 题目：统计“一次 direct reclaim 超过 5ms”的次数并输出 Top 进程。
- 思路：在 end 事件计算 `nsecs-@begin[tid]`，超阈值则按 `comm` 计数；
- 参考答案：在 4.2 基础上 `if (nsecs-@begin[tid] > 5e6) { @[comm] = count(); }` 并周期 `print(@,10); clear(@);`。

2) 题目：如何判断是“内核分配异常”还是“用户态泄漏”？
- 思路：kmalloc 分布和栈若无异常，用户态活跃表/热点栈持续累积更可疑；
- 参考答案：交叉对照 5 与 6 的统计，锁定异常侧。

3) 题目：把用户态活跃分配按进程名聚合并输出 Top-10。
- 思路：将 key 从 `ustack()` 改为 `comm`；
- 参考答案：`@by_comm[comm] = sum($sz); interval:s:15 { print(@by_comm, 10); clear(@by_comm); }`。

4) 题目：如何降低 `malloc/free` 观测对性能的影响？
- 思路：限定 PID/采样窗口/截断字符串长度；
- 参考答案：加谓词 `/pid==X/`，缩短 `interval` 窗口并 `clear()`。

5) 题目：如何对“热点栈”做函数级聚合？
- 思路：对 `usym()` 结果作为 key；
- 参考答案：`@[usym(arg0)] = count();` 或在采样栈外部聚合符号。

## 9. 快速复习图（SVG 引用）
![[技术学习-性能之巅-bpftrace实战-内存管理-复习.svg]]
