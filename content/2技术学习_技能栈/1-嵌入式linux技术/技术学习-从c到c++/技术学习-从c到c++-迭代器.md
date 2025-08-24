---
source: "[文章链接]"
tags:
  - 技术/领域
  - 笔记/状态
创建时间: 1日 五月 2025
publish: true
---

# 迭代器

## 是什么？

就是**任何可以用 `for...in...` 循环来遍历的东西**

## 怎么用

* **指向 (Pointing):** 迭代器内部会指向容器中的某个元素
* **访问 (Accessing):** 使用 `*迭代器` （对迭代器进行解引用操作，和指针一样用 `*`）可以获取它当前指向的元素的值。
* **移动:** 使用 `++迭代器` （对迭代器进行自增操作，和指针一样用 `++`）可以让迭代器移动到容器中的**下一个**元素。
* **标记位置:**
	- 每个容器都有一个 `begin()` 成员函数，它返回一个指向容器**第一个元素**的迭代器（类似于 C 数组名 `arr`）。
	- 每个容器都有一个 `end()` 成员函数，它返回一个指向容器**最后一个元素之后位置**的特殊迭代器
		- （类似于 C 里的 `arr + n`）。**注意：`end()` 指向的位置本身没有元素，不能解引用 `*` 它！** 它只作为一个结束标记。

## 例子

```cpp title:例子
#include <vector>
#include <iostream>

int main() 
{
    std::vector<int> vec = {10, 20, 30, 40, 50};

    // 获取指向开头和末尾之后位置的迭代器
    std::vector<int>::iterator it = vec.begin(); // 'it' 指向第一个元素 (10)
    std::vector<int>::iterator end_it = vec.end(); // 'end_it' 指向最后一个元素 (50) 之后的位置

    std::cout << "使用迭代器遍历 vector:\n";
    while (it != end_it) 
    { // 当迭代器还没到末尾之后的位置
        std::cout << "值: " << *it << std::endl; // 使用 *it 获取当前指向的值
        ++it; // 迭代器向前移动，指向下一个元素
    }

    // 更常见的写法 (使用 for 循环)
    std::cout << "\n使用 for 循环和迭代器:\n";
    for (std::vector<int>::iterator current_it = vec.begin(); current_it != vec.end(); ++current_it) 
    {
        std::cout << "值: " << *current_it << std::endl;
    }

    // C++11 之后还有更简洁的基于范围的 for 循环，它内部其实就是用了迭代器， 有点类似py
    std::cout << "\n使用基于范围的 for 循环:\n";
    for (int value : vec) 
    {
        std::cout << "值: " << value << std::endl;
    }

    return 0;
}
```
## 我的思考 / 应用

*   [这部分内容对我的启发是什么？]
*   [可以如何应用到我的工作/学习中？]
*   [[cpp中迭代器 和 python 中的迭代器和生成器 有什么差异？]]

## 疑问 / 待探索

*   [记录不理解的地方或需要进一步研究的点]
*   [后续需要查找的资料？]

---
### 复习检查点 (可选)
- [ ] 第一次复习 (例如：1天后)
- [ ] 第二次复习 (例如：3天后)
- [ ] 第三次复习 (例如：一周后)
