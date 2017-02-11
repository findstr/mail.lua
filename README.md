# lua.smtp
a smtp protocol implement based on lua

## 使用

smtp只提供了一个send函数，send函数只接收一个table类型的参数msg

msg["FROM"] 用于指定发送方邮件地址

msg["PASSWD"] 用于指定发送方邮件密码

msg["TO"] 用于指定收件人地址

msg["SUBJECT"] 用于指定邮件主题

msg["CONTENT"] 用于指定邮件内容

    smtp.send(msg) 即可发送邮件

## 运行

编译. 在linux下输入make linux来编译, 在macosx操作系统下输入make macosx来编译
运行. 在控制台下输入./smtp test 即可运行

ps. 默认邮件密码是错误的，如果需要测试请至少将msg["FROM"], msg["TO"], msg["PASSWD"]这三个值改为正确值

## 移植

默认情况下，smtp.lua运行于[silly](https://github.com/findstr/silly)平台

但是smtp模块仅借用了silly的三个模块:
1. 同步非阻塞socket
2. dns域名模块
3. 加密模块（仅借用了base64加密功能）

因此移植仅需要替换这3个模块即可。

ps. 在替换socket模块时，只需要替换为同步socket即可，可阻塞，可非阻塞

