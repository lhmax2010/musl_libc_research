# Codex 授权 Prompt:板端 RPM 安装 Smack 插件阻塞分级处置

根因定性(写入事故归档):Tizen 板端 rpm 的 security 插件在安装事务中
写 Smack 规则与 /etc/device-sec-policy 失败,属安装钩子环境限制,
与包内容无关。demo 二进制经 sdb root 直接执行,不依赖 Smack manifest
注册,跳过该插件不影响测量有效性。

## 分级处置(按序尝试,前一级明确失败才降级;每级完整记录命令与输出)

方案 A(首选,保留 rpm 数据库语义):
  rpm -Uvh --noplugins <rpm>
  该选项仅跳过插件钩子(含 security),文件布局/scriptlet/数据库记录不变。
  若板端 rpm 不识别 --noplugins(记录报错原文),尝试等价宏:
  rpm -Uvh --define '__transaction_msm %{nil}' <rpm>
  两者输出均归档;成功即进入验证。

方案 B(A 全部失败后;放弃 rpm 数据库,保文件语义):
  rpm2cpio <rpm> | (cd / && cpio -idmv './opt/usr/musl-demo/*')
  明确记录:RPM 未入库,卸载需手工 rm -rf /opt/usr/musl-demo;
  该偏离写入报告 Caveats。

禁止:remount 系统分区、修改 /etc/device-sec-policy、改动 Smack 全局规则、
删改板上任何既有安全配置。

## 安装后验证(A/B 通用,全部落 deploy 日志)

1. sha256sum /opt/usr/musl-demo/bin/* 与 host 侧 artifacts.sha256 逐一比对;
2. ls -Z /opt/usr/musl-demo/bin /opt/usr/musl-demo/lib(Smack 标签存档);
3. smoke:三变体无参调用;musl-dyn 经包内 ld-musl-arm.so.1 运行成功为关键项;
4. 若任一执行被 Smack 拦截:归档 dmesg | grep -i smack 与 journalctl 相关行,
   停车报告,不得 chsmack 改标签。

## 后续

验证通过后,前序 prompt 全部条款继续有效:
SDB_TARGET=<BOARD_IP> scripts/run_board.sh → gen_report.py。
事故归档 results/logs/incident-board-rpm-smack.md 补充最终采用的方案级别;
report.md 的 Caveats 增加一行:安装方式偏离(A:插件跳过 / B:cpio 展开)
及其对测量无影响的论证。
新的未预授权失败照旧停车。
