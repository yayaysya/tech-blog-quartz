---
title: "C++ 访问控制：私有、保护、公有"
description: "详解 C++ 中 private、protected、public 访问控制符的区别和使用场景"
tags: ["C++", "面向对象", "访问控制", "卡片"]
date: "2023-08-27"
---

# C++ 访问控制：私有、保护、公有

## 概念差异
1. 公有(public) 类的公有成员在**整个程序**中都可以被访问。
2. 私有(private) 类的私有成员只在**该类的内部**可以被访问,对外不可见。
3. 保护(protected) 类的保护成员在**派生类中可以访问**,但是在**类的外部不能访问**。

## 例子
```cpp
class Base {
public:
  void public_func() {} 
  
protected:
  void protected_func() {}
  
private:
  void private_func() {}
};

class Derived : public Base {
  void test() {
    public_func(); // OK
    protected_func(); // OK 
    private_func(); // 错误,不可访问
  }
};

int main() {  
  Base b;
  b.public_func(); // OK
  b.protected_func(); // 错误
  b.private_func(); // 错误 
}
```


## 公有继承
- 子类可以访问父类的公有和保护成员
- 继承关系对外部完全可见。外部代码可以将子类对象转换为父类对象,也**可以访问父类的公有和保护成员**。

## 保护继承
- 子类可以访问父类的公有和保护成员
- 继承关系对外部不可见。外部代码不能将子类对象转换为父类对象,也**不能访问父类的保护成员和公有成员**。

## 私有继承
- 子类只能访问父类的公有成员
- 继承关系对外部完全不可见。外部代码既不能转换对象,也**不能访问父类的任何成员**。



