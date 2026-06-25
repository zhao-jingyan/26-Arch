# xv6-riscv 运行说明

本目录用于放置面向当前 CPU 的 xv6 生成物：

- `kernel.elf`
- `kernel.bin`
- `fs.img`

默认构建入口：

```shell
make xv6-build-image XV6_HOME=/path/to/xv6-riscv
```

当前 CPU 仿真平台默认设备地址：

- RAM 起始地址：`0x80000000`
- UART base：`0x40600000`
- UART TX：`0x40600004`
- UART STATUS：`0x40600008`
- MSIP：`0x38000000`
- MTIMECMP：`0x38004000`
- MTIME：`0x3800bff8`
- 简易 SD 地址寄存器：`0x40601000`
- 简易 SD 数据寄存器：`0x40601008`

本目录已提供 `xv6-platform.patch`，`make xv6-build-image` 会在构建前尝试应用该补丁。
