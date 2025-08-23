# 模块一：CMake 入门与核心概念 - 笔记

## CMake 是什么？

* **角色**: CMake 是一个 **跨平台构建系统生成器** (Generator)。它不是编译器，也不是构建工具本身 (like Make)。
* **工作方式**: 读取 `CMakeLists.txt` 文件（你写的项目"设计蓝图"），根据当前的平台和工具链，生成**本地化的构建文件** (如 Makefiles, Ninja files, Visual Studio projects)。
* **类比**: CMake 是"超级菜谱设计师"，它不炒菜，但能根据你的需求和厨房环境，设计出最合适的"本地菜谱"。

## 为什么需要 CMake？

* **跨平台 (Cross-Platform)**: **最核心价值！** 同一份 `CMakeLists.txt`，理论上可以在 Windows, Linux, macOS 上生成对应的构建配置。
* **自动查找依赖 (Dependency Management)**: 更方便地查找和使用系统或第三方库。
* **IDE 友好**: 很多现代 IDE (VSCode, CLion, Visual Studio) 对 CMake 支持良好。
* **更高级的抽象**: 相对于 Makefile，更易于管理复杂项目结构和构建逻辑（熟悉之后）。

## CMake 核心工作流程

1.  **配置 (Configure)**:
    * **命令**: 在**构建目录**中运行 `cmake <path-to-source-directory>` (常用: `cmake ..`)。
    * **动作**: CMake 读取 `CMakeLists.txt`，检查系统/编译器，生成缓存 (`CMakeCache.txt`) 和中间文件。
2.  **生成 (Generate)**:
    * **动作**: 配置成功后，CMake 在**构建目录**中生成**本地构建系统文件** (如 `Makefile`)。
3.  **构建 (Build)**:
    * **命令**: 在**构建目录**中运行本地构建工具 (如 `make`, `ninja`, 或使用 IDE 的构建按钮)。
    * **动作**: 本地构建工具根据 CMake 生成的文件，执行编译和链接，生成最终目标（可执行文件、库）。

## 源码外构建

* **概念**: 将所有由 CMake 生成的文件和编译产物都放在一个**独立于源代码**的目录（通常命名为 `build`）。
* **好处**:
    * **源码目录干净**: 不会被编译过程污染。
    * **轻松清理**: 删除 `build` 目录即可清理所有编译结果。
    * **支持多重构建**: 可为不同配置 (Debug/Release) 创建不同的 `build` 目录。
* **实践**:

```c title:test
    # 假设在项目源码根目录 my_project/
    mkdir build      # 创建构建目录
    cd build         # 进入构建目录
    cmake ..         # 指向上一级源码目录，执行 配置+生成
    make             # 在构建目录执行 构建
```

## `CMakeLists.txt` 文件

* CMake 的**核心配置文件**，是你的项目"设计蓝图"。
* 放在项目的**根目录**以及需要独立构建逻辑的**子目录**中。
* 包含一系列 CMake 指令，告诉 CMake 如何构建项目。

## CMake 基础语法

* **指令 (Commands)**: `command_name(argument1 argument2 ...)`。推荐用**小写**。
* **注释 (Comments)**: 以 `#` 开始，直到行尾。
* **参数 (Arguments)**: 空格分隔；含空格的参数用 `"` 包裹。
* **变量 (Variables)**: `set(VAR_NAME value)` 定义, `${VAR_NAME}` 引用。(后续详解)
* **打印消息 (Messaging)**: `message("Some text")` 用于输出信息到控制台。

## 三个最基础核心指令

1.  **`cmake_minimum_required(VERSION x.y)`**
    * **作用**: 指定运行此脚本所需的 CMake 最低版本。
    * **位置**: 通常是 `CMakeLists.txt` 的**第一行**。确保兼容性。
2.  **`project(ProjectName [LANGUAGES CXX C ...])`**
    * **作用**: 定义项目名称。会设置 `PROJECT_NAME` 等变量。
    * **`LANGUAGES CXX`**: 表明项目主要使用 C++。
3.  **`add_executable(TargetName source1.cpp [source2.cpp ...])`**
    * **作用**: 定义一个**可执行文件目标**。
    * `TargetName`: 你想要生成的可执行文件的名字。
    * `source1.cpp ...`: 用于编译该目标的源文件列表。

