> [!question] 如果我需要mmap一个文件, 然后再读取这个文件内容, 涉及的底层流程是怎样的?
> 

# Linux内核内存管理架构


![[读取文件核心流程图08262010.svg]]




# 流程图

```mermaid
graph TD
    A["用户进程调用 mmap()"] --> B["系统调用入口 sys_mmap()"]
    
    B --> C["内存管理子系统"]
    C --> C1["在进程VMA中分配虚拟地址区域"]
    C1 --> C2["创建 vm_area_struct 结构"]
    C2 --> C3["设置VMA权限和文件映射信息"]
    
    C3 --> D["文件系统层"]
    D --> D1["调用文件系统的 mmap 操作"]
    D1 --> D2["检查文件权限和大小"]
    D2 --> D3["建立 inode 与 VMA 的关联"]
    
    D3 --> E["页表管理"]
    E --> E1["暂不分配物理页面<br/>(延迟分配策略)"]
    E1 --> E2["页表项标记为未映射"]
    
    E2 --> F["mmap() 返回虚拟地址"]
    
    F --> G["用户进程访问mapped内存"]
    G --> H["CPU MMU 查找页表"]
    H --> I{"页面是否<br/>已映射?"}
    
    I -->|否| J["触发 Page Fault"]
    I -->|是| K["直接访问物理内存"]
    
    J --> L["Page Fault 处理器"]
    L --> L1["检查VMA有效性"]
    L1 --> L2["确定这是文件映射的缺页"]
    
    L2 --> M["页面缓存系统"]
    M --> M1{"页面是否在<br/>Page Cache中?"}
    
    M1 -->|是| N["直接使用缓存页面"]
    M1 -->|否| O["文件系统读取"]
    
    O --> O1["调用文件系统 readpage()"]
    O1 --> O2["向块设备发起I/O请求"]
    O2 --> O3["从磁盘读取数据到页面"]
    O3 --> O4["将页面加入Page Cache"]
    
    O4 --> P["内存分配"]
    N --> P
    P --> P1["分配物理页面"]
    P1 --> P2["将文件数据复制到物理页"]
    
    P2 --> Q["页表更新"]
    Q --> Q1["建立虚拟地址到物理地址映射"]
    Q1 --> Q2["设置页表项权限"]
    Q2 --> Q3["刷新TLB缓存"]
    
    Q3 --> R["返回用户空间"]
    R --> K
    
    K --> S["用户进程成功读取数据"]
    
    subgraph "内核空间"
        C
        D
        E
        L
        M
        O
        P
        Q
    end
    
    subgraph "硬件层"
        H
        O2
    end
    
    subgraph "用户空间"
        A
        G
        S
    end
    
    style A fill:#e1f5fe
    style G fill:#e1f5fe
    style S fill:#e1f5fe
    style J fill:#ffebee
    style M1 fill:#fff3e0
    style I fill:#fff3e0
```



# 核心代码调用流程
![[文件读取核心代码调用流程20250826.svg|257x1035]]


# 详细代码调用流程图

![[详细代码调用流程20250826.svg]]

