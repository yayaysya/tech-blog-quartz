# 如何在嵌入式设备上部署 perf

### 核心流程概览

整个过程可以分为四个主要阶段：

1. **准备工作 (Prerequisites)**: 准备好交叉编译环境和源代码。
2. **配置并编译内核 (Kernel)**: 在内核中开启`perf`所需的所有支持选项。
3. **编译`perf`工具 (Tool)**: 交叉编译`perf`用户空间程序。
4. **部署与验证 (Deploy & Verify)**: 将编译好的内核、`perf`程序和其依赖库部署到嵌入式设备上并进行测试。
    

---

### 阶段一：准备工作

在开始之前，您需要准备好以下环境：

1. **一台Linux主机**: 例如，安装了Ubuntu 20.04或更高版本的PC。我们将在这台主机上进行所有的交叉编译工作。
    
2. **交叉编译工具链 (Cross-Compile Toolchain)**:
    
    - 这是最重要的工具，它允许您在x86的PC上生成能在ARM64设备上运行的代码。
    - 推荐从ARM官网或Linaro下载预编译好的工具链。例如，`aarch64-linux-gnu`。
    - **关键**: 确保这个工具链的`sysroot`（系统根）中包含了`perf`依赖的开发库，如`libelf`, `libdw`, `zlib`等。一个功能完备的工具链通常会自带这些。
        
3. **目标内核的源代码**: 下载与您嵌入式设备匹配的Linux内核源代码。
    

---

### 阶段二：配置并编译内核

这一步是在“服务器端”（内核）开启`perf`服务。

1. **进入源码目录并清理**:
    ```Bash
    cd /path/to/your/linux-source
    make mrproper
    ```
    
2. 加载基础配置:
    使用您的嵌入式开发板的默认配置文件（defconfig）来创建一个.config文件。
    ``` Bash
    # ARCH指定目标架构, CROSS_COMPILE指定工具链前缀
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- your_board_defconfig
    ```
    
3. 打开配置菜单并开启perf相关选项:
    
    这是最关键的一步。运行make menuconfig来开启必要的选项。
    ```Bash
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
    ```
    
    在菜单中，找到并开启（设置为`[*]`）以下选项：
    
    - **`perf`基础支持 (必须)**:
        
        - `General setup --->`
            
            - `[*] Kernel Performance Events And Counters` (`CONFIG_PERF_EVENTS`)
                
    - **可靠的调用栈 (强烈推荐)**:
        
        - `Kernel hacking --->`
            
            - `Compile-time checks and compiler options --->`
                
                - `[*] Compile the kernel with frame pointers` (`CONFIG_FRAME_POINTER`)
                    
    - **符号解析 (强烈推荐)**:
        
        - `Kernel hacking --->`
            
            - `Compile-time checks and compiler options --->`
                
                - `[*] Compile the kernel with debug info` (`CONFIG_DEBUG_INFO`)
                    
    - **ftrace 和 kprobes 支持 (推荐，增强功能)**:
        
        - `Kernel hacking --->`
            
            - `Tracers --->`
                
                - `[*] Kernel Function Tracer` (`CONFIG_FUNCTION_TRACER`)
                    
                - `[*] Enable kprobes to be attached to functions` (`CONFIG_KPROBES`)
                    
                - `[*] Enable uprobes to be attached to userspace functions` (`CONFIG_UPROBES`)
                    
    
    完成后，保存配置并退出。
    
4. 编译内核:
    
    使用多线程编译内核镜像和设备树文件。
    
    Bash
    
    ```
    # -j$(nproc) 使用所有可用的CPU核心来加速编译
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
    ```
    
    编译成功后，您需要的内核产物通常是：
    
    - 内核镜像: `arch/arm64/boot/Image.gz`
        
    - 设备树文件: `arch/arm64/boot/dts/your-vendor/your-board.dtb`
        
    - 带符号的内核: `vmlinux` (用于后续符号解析)
        

---

### 阶段三：编译 `perf` 工具

现在我们来编译“客户端”`perf`。

1. 进入perf工具目录:
    
    perf的源码就在内核源码树中。
    
    Bash
    
    ```
    cd /path/to/your/linux-source/tools/perf
    ```
    
2. 交叉编译perf:
    
    直接在这里运行make，并务必带上与编译内核时相同的ARCH和CROSS_COMPILE参数。perf的构建系统会自动检测您的交叉编译工具链中的库（如libelf, libdw）并启用相应功能。
    
    Bash
    
    ```
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
    ```
    
    如果编译成功，当前目录下会生成一个`perf`可执行文件。
    

---

### 阶段四：部署与验证

最后一步，将我们的劳动成果部署到嵌入式设备上。

1. **部署新内核**:
    
    - 将新编译的内核镜像 (`Image.gz`) 和设备树文件 (`.dtb`) 拷贝到您的设备的`/boot`分区或通过TFTP等方式由U-Boot加载。**具体方法高度依赖于您的嵌入式设备和引导加载程序 (bootloader)。**
        
2. **部署`perf`和其依赖库**:
    
    - **拷贝`perf`程序**: 将PC上编译好的`perf`可执行文件拷贝到嵌入式设备的文件系统的`/usr/bin/`目录下。
        
        Bash
        
        ```
        # 在PC上
        scp tools/perf/perf root@<device_ip>:/usr/bin/
        ```
        
    - 查找并拷贝依赖库 (关键步骤):
        
        perf依赖一些共享库。我们需要找出是哪些，并从交叉编译工具链中把它们拷贝到设备上。
        
        在PC上，使用交叉编译工具链的ldd来查看依赖：
        
        Bash
        
        ```
        aarch64-linux-gnu-ldd ./perf
        ```
        
        您会看到类似输出：
        
        ```
        libdw.so.1 => /path/to/toolchain/sysroot/lib/libdw.so.1 (0x...)
        libelf.so.1 => /path/to/toolchain/sysroot/lib/libelf.so.1 (0x...)
        libz.so.1 => /path/to/toolchain/sysroot/lib/libz.so.1 (0x...)
        libc.so.6 => /path/to/toolchain/sysroot/lib/libc.so.6 (0x...)
        ...
        ```
        
        将列表中的、您设备上缺失或版本不兼容的库文件，从工具链的`sysroot`目录中拷贝到您设备的`/usr/lib/`目录下。
        
3. **在设备上验证**:
    
    - **重启设备**，让它加载新的内核。
        
    - 登录到设备的终端，检查内核版本，确认新内核已启动。
        
        Bash
        
        ```
        uname -a
        # 确认输出中的编译日期是你刚刚编译的时间
        ```
        
    - 检查`perf`是否可以运行。
        
        Bash
        
        ```
        perf --version
        # 应该显示与你的内核版本匹配的版本号
        ```
        
    - 运行一个简单的`perf`命令。
        
        Bash
        
        ```
        # 给perf执行权限
        chmod +x /usr/bin/perf
        
        # 运行
        perf stat ls
        ```
        
        如果能看到`ls`命令的性能统计数据，说明基本部署成功！
        
    - 运行一个需要调用栈和符号的复杂命令来做最终验证。
        
        Bash
        
        ```
        perf record -g -- sleep 1
        perf report
        ```
        
        如果您在`perf report`的输出中能看到清晰的函数调用栈（而不是一堆十六进制地址），那么恭喜您，整个流程完美成功！