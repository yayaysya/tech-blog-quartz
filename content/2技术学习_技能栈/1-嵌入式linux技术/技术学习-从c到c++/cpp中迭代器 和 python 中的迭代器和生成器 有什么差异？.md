---
# 元数据区 (YAML Frontmatter)
uid: 20250501170336 
tags: [card] 
source: "[来源链接、书名章节、或想法来源]"
created: 2025-05-01
---

# 和 python 中的迭代器和生成器 有什么差异？ 

**核心观点：**

> **核心作用**： 如何统一地遍历不同类型的集合

> [!info] 相同点：
都是**访问数据集合（容器）内元素的一种机制**，它允许你按顺序逐个访问集合中的项，而**无需关心集合内部是如何存储这些项的**。


> [!info] 不同点:方式不同
> C++： 更偏向于**模仿指针操作**和使用特定值标记结束
> python： 用法更加简单： for in 格式就行（基于特定的方法 (`__next__`) 和异常 (`StopIteration`) 来驱动和结束迭代）


**例子：**
```python
# PYTHON的例子

my_list = [10, 20, 30]

# 1. 常见方法
print("Using for loop:")
for item in my_list: # my_list 是可迭代对象 (Iterable)
    print(item)

# 2. 手动调用接口方式---只用于了解内部原理
print("\nUsing manual iteration:")
my_iterator = iter(my_list) # 获取列表的迭代器 (Iterator)

while True:
    try:
        item = next(my_iterator) # 获取下一个元素，并让迭代器前进
        print(item)
    except StopIteration: # 当 next() 引发 StopIteration 时，表示迭代结束
        break
```




**与其他卡片的连接：**
*   [[python中如何定义一个迭代器对象？]]


**我的思考/疑问 (可选):**
*   [个人想法、不确定之处]
