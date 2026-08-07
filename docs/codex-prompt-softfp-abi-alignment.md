# Codex 授权 Prompt:demo 对齐平台 softfp ABI 后重跑

根因定性(写入事故归档):上游设计假设错误——设计方按 hard-float 假设
写入了 armhf loader 路径与 VFP registers 门禁,而 Tizen armv7l 平台 ABI
为 softfp(%optflags 含 -mfloat-abi=softfp);musl 判定 __ARM_PCS_VFP=false
产出 ld-musl-arm.so.1 是正确行为。责任在设计方,不在实现。
处置:demo 对齐平台 softfp;禁止改用 -mfloat-abi=hard(将破坏 glibc-dyn
与板端 softfp glibc 的链接一致性,并使结论脱离平台语境)。

## 授权修改(单独 commit;本轮显式授权修改门禁本体的指定两处,其余门禁零改动)

1. loader 命名全面切换:
   PRIVATE_LOADER=/opt/usr/musl-demo/lib/ld-musl-arm.so.1
   spec 的 symlink 与 %files 同步;-Wl,--dynamic-linker 同步;
   grep -rn 'armhf' 全仓库,scripts/ 与 packaging/ 中的代码引用全部改为 arm
   (docs/ 与历史归档不改,保留原始记录);自查输出贴入日志。

2. 门禁修改一:musl-dyn interpreter 期望值改为
   /opt/usr/musl-demo/lib/ld-musl-arm.so.1(判定逻辑不变,仅期望值)。

3. 门禁修改二:check_arm_hard_float 整体替换为 check_arm_abi_consistency:
   a. 三变体均为 ELF32 + ARM(保留);
   b. 提取三变体 readelf -AW 的 Tag_ABI_VFP_args 行(可能缺失,缺失记 ABSENT),
   三者必须完全一致;
   c. softfp 断言:任一变体出现 "VFP registers" 即 fail;
   d. 提取 chroot /bin/sh 同一 Tag,与三变体比对,一致性结果与四方原文
   写入 compiler-decision.txt(键:platform_float_abi=softfp、
   variant_vfp_args、binsh_vfp_args、abi_consistency=PASS/FAIL);
   /bin/sh 比对不一致时 fail(demo 与平台 ABI 脱节即无效)。

4. compiler-decision.txt 追加 musl_ldso_name=ld-musl-arm.so.1。
   事故归档 results/logs/incident-softfp-abi-alignment.md:
   现象/根因(设计假设 hard-float vs 平台 softfp)/处置/教训
   (ABI 断言应取自平台实测而非设计方记忆)。

5. commit message 引用 expected/actual loader 两行原文。

## 重跑

scripts/build_gbs.sh
期望:三变体构建 → 全部 ELF 门禁(含新 ABI 一致性门禁)→
BUILD_GATE_PASS → RPM。
成功后前序 prompt 全部条款继续有效(deploy → run_board → report)。
板端 smoke 时留意:musl-dyn 必须经包内 ld-musl-arm.so.1 运行成功。
新的未预授权失败照旧停车。
