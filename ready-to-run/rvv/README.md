# RVV basic test

这个目录放手写的 RVV directed test，风格对齐 `ready-to-run/lab+`：源码提交到仓库，生成的 `.bin` 用 Makefile 直接喂给 emu。

注意：`rvv-basic.S` 会用 `vle64.v/vse64.v` 准备和检查数据，因此需要先实现最小向量访存后再运行。当前它主要作为 RVV 下一阶段的 directed test 模板。

生成命令：

```sh
riscv64-unknown-elf-gcc -march=rv64gv -mabi=lp64d -nostdlib -nostartfiles -Wl,--no-relax -Ttext=0x80000000 -o ready-to-run/rvv/rvv-basic.elf ready-to-run/rvv/rvv-basic.S
riscv64-unknown-elf-objcopy -O binary ready-to-run/rvv/rvv-basic.elf ready-to-run/rvv/rvv-basic.bin
```

运行命令：

```sh
make test-rvv-basic
```

`test-rvv-basic` 使用 `--no-diff`，因为当前仓库里的 NEMU 参考模型不支持 RVV。测试通过时会打印 `RVV Test pass`，并向 `RAMHelper2` 的 magic 地址 `0x23333000` 写入 `0x233`，仿真输出里应出现 8 个 `Pass!`；随后执行 `nemu_trap(0)`，由 `-C` 周期上限结束仿真。

当前测试覆盖：

- `vsetvli`
- `vsetivli`
- `vsetvl`
- `vle64.v`
- `vse64.v`
- `vadd.vv`
- `vsub.vx`
- `vadd.vi`
- `vxor.vv`
- `vsll.vi`
- 向量 RAW stall
- `vl=1` 时未激活元素保留旧 `vd`
