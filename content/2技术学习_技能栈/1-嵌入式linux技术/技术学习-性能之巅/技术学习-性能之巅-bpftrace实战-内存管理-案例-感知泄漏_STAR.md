# 内存 STAR 案例：感知模块内存泄漏导致重启

### 情景 (Situation)

*   **系统架构**：一个智驾系统的核心感知进程 `perception_service`，负责处理来自多个摄像头的图像数据。其工作流包含图像解码、特征提取、模型推理等多个步骤，处理流程高度并发。
*   **问题现象**：该进程在启动后内存占用（RSS）会从初始的500MB缓慢但稳定地增长。在路测环境下，大约运行30到60分钟后，RSS会增长到系统内存上限（例如2GB），最终被内核的OOM Killer杀死，导致感知功能中断并自动重启。`dmesg`日志中可以明确看到`oom_kill`事件，受害者正是`perception_service`。
*   **初步观察数据**：
    ```shell
    # 每分钟记录一次RSS
    $ ps -p $(pidof perception_service) -o rss
    512000  # 启动时
    ...
    834000  # 15分钟后
    ...
    1950000 # 50分钟后 -> OOM
    ```
    这个数据清晰地表明了存在内存泄露，而不是突发性的内存暴涨。

### 任务 (Task)

在线上只读环境中，使用bpftrace无侵入地定位`perception_service`中导致内存泄露的具体代码路径，并为开发团队提供精准的修复建议。

### 行动 (Action)

遵循“定性 -> 定位 -> 根因分析”的排查思路。

**第一步：定性 - 确认问题为内存泄露**

*   **思路**：RSS的稳定增长已经明确了问题是内存泄露，而不是内存回收引发的性能抖动。因此，我们直接跳到第二步。

**第二步：定位 - 内核 vs. 用户态**

*   **思路**：需要确定是内核模块（如驱动）在为该进程服务时泄露了内存，还是应用程序自身存在`malloc`/`free`不匹配的问题。
*   **脚本1：排查内核泄露**
    ```bash
    bpftrace -e 'tracepoint:kmem:kmalloc /pid == 1234/ { @[kstack()] = sum(args->bytes_alloc); } interval:s:10 { print(@, 5); }'
    # 注意：这里的print后没有clear(@)，因为我们要观察累计分配量是否持续增长
    ```
*   **结果与分析1**：
    运行几分钟后，发现输出的Top 5内核调用栈的累计分配量`sum()`基本保持稳定，没有出现无限增长的趋势。这基本排除了内核泄露的可能性。

*   **脚本2：审计用户态`malloc`/`free`**
    *   **思路**：这是最关键的一步。我们要像一个审计员一样，记录下每一次`malloc`的内存地址和大小，在`free`的时候将其核销。持续增长的、未被核销的分配，就是泄露的源头。
    *   **脚本**：
        ```bash
        # 找到perception_service使用的libc路径
        bpftrace -p $(pidof perception_service) -e '
        uretprobe:libc:malloc { @live[retval] = @size[tid]; delete(@size[tid]); }
        uprobe:libc:malloc { @size[tid] = arg0; }
        uprobe:libc:free { delete(@live[arg0]); }
        interval:s:20 {
            printf("--- Total outstanding bytes: %d ---\n", sum(@live));
            print(@live, 5);
        }'
        ```
        *   **注意**: 为了更精确地定位源头，我们将`@live`表聚合到调用栈上：
        ```bash
        bpftrace -p $(pidof perception_service) -e '
        uretprobe:libc:malloc { @by_stack[ustack()] = sum(@size[tid]); delete(@size[tid]); }
        uprobe:libc:malloc { @size[tid] = arg0; }
        // 注意：free的审计很复杂，简单版本暂时省略，通过观察分配热点栈的持续增长来定位
        interval:s:20 { print(@by_stack, 5); }'
        ```
*   **结果与分析2**：
    运行第二个脚本（带调用栈的）后，很快就发现了问题。
    ```
    # 第一次输出
    @by_stack[
        libjpeg_decode_frame+150
        process_image+80
        main_loop+200
    ]: 10485760 # 10MB

    # 5分钟后的输出
    @by_stack[
        libjpeg_decode_frame+150
        process_image+80
        main_loop+200
    ]: 157286400 # 150MB
    ```
    结果非常明显：一个来自第三方JPEG解码库`libjpeg_decode_frame`的调用栈，其累计分配的内存量在持续、快速地增长。

### 结果 (Result)

*   **结论**：内存泄露的根因位于`perception_service`调用的`libjpeg`库中。当处理一种特定分辨率的、带有特殊标记的图像时，该库内部的一个错误处理分支会直接`return`错误码，但没有释放此前已经分配的图像缓冲区。
*   **解决方案**：
    1.  **修复**：联系`libjpeg`库的维护者或在应用层面进行封装，在调用`libjpeg_decode_frame`后，如果返回错误码，则手动调用对应的`libjpeg_free_buffer`函数。
    2.  **短期缓解**：在CI/CD中加入内存泄露检测工具（如ASan），防止类似问题再次进入生产环境。同时，为`perception_service`设置更严格的cgroup内存上限，并配置监控告警，在RSS达到阈值时能提前预警而非等待OOM。
*   **最终效果**：代码修复并上线后，`perception_service`的RSS稳定在550MB左右，持续运行数周再未发生OOM。

> 与主文档联读：[[技术学习-性能之巅-bpftrace实战-内存管理-OOM与内存泄漏.md]]
