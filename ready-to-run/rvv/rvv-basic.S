// -----------------------------------------------------------------------------
// RVV basic directed test
// -----------------------------------------------------------------------------
// 目标：覆盖当前实现的 vsetvli/vsetivli/vsetvl 与基础整数向量 ALU。
// 约定：通过时执行 nemu_trap(0)，失败时进入死循环。
// -----------------------------------------------------------------------------

    .section .text
    .option norvc
    .option norelax
    .globl _start

    .macro rvv_putc reg
    li      t5, 0x40600000
.Lrvv_putc_wait\@:
    lbu     t6, 8(t5)
    andi    t6, t6, 8
    bnez    t6, .Lrvv_putc_wait\@
    sb      \reg, 4(t5)
    .endm

_start:
    // 让 SEW=64、LMUL=1，VLEN=128 时 vl 应为 2。
    li      t0, 2
    vsetvli t1, t0, e64, m1, ta, ma
    li      t2, 2
    bne     t1, t2, fail

    // v1 = [1, 2]，v2 = [10, 20]
    la      t0, src_a
    la      t1, src_b
    vle64.v v1, (t0)
    vle64.v v2, (t1)

    // vv：v3 = v1 + v2 = [11, 22]
    vadd.vv v3, v1, v2
    la      t0, dst_add_vv
    vse64.v v3, (t0)

    ld      t1, 0(t0)
    li      t2, 11
    bne     t1, t2, fail
    ld      t1, 8(t0)
    li      t2, 22
    bne     t1, t2, fail

    // vx：v4 = v3 - 1 = [10, 21]
    li      t0, 1
    vsub.vx v4, v3, t0
    la      t1, dst_sub_vx
    vse64.v v4, (t1)

    ld      t2, 0(t1)
    li      t3, 10
    bne     t2, t3, fail
    ld      t2, 8(t1)
    li      t3, 21
    bne     t2, t3, fail
     

    // vi + RAW：v5 依赖上一条 v4，测试向量 RAW stall。
    vadd.vi v5, v4, 3
    la      t0, dst_add_vi
    vse64.v v5, (t0)

    ld      t1, 0(t0)
    li      t2, 13
    bne     t1, t2, fail
    ld      t1, 8(t0)
    li      t2, 24
    bne     t1, t2, fail

    // 逻辑与移位：v6 = (v5 xor v1) << 1。
    vxor.vv v6, v5, v1
    vsll.vi v6, v6, 1
    la      t0, dst_logic_shift
    vse64.v v6, (t0)

    ld      t1, 0(t0)
    li      t2, 24      // (13 xor 1) << 1
    bne     t1, t2, fail
    ld      t1, 8(t0)
    li      t2, 52      // (24 xor 2) << 1
    bne     t1, t2, fail

    // vsetivli：AVL=1，只更新第 0 个元素；第 1 个元素保留旧 vd。
    vsetivli t0, 1, e64, m1, ta, ma
    li      t1, 100
    vadd.vx v6, v6, t1
    li      t0, 2
    vsetvli t1, t0, e64, m1, ta, ma
    la      t2, dst_vl1
    vse64.v v6, (t2)

    ld      t3, 0(t2)
    li      t4, 124
    bne     t3, t4, fail
    ld      t3, 8(t2)
    li      t4, 52
    bne     t3, t4, fail

    // vsetvl：从 GPR 读取 AVL 和 vtype。
    li      t0, 2
    li      t1, 0xd8    // e64,m1,ta,ma 的 vtype 编码
    vsetvl  t2, t0, t1
    li      t3, 2
    bne     t2, t3, fail

pass:
    la      t0, pass_msg
1:
    lbu     t1, 0(t0)
    beqz    t1, 2f
    li      t2, 10
    bne     t1, t2, 3f
    li      t3, 13
    rvv_putc t3
3:
    rvv_putc t1
    addi    t0, t0, 1
    j       1b
2:
     
    .word   0x0005006b  // nemu_trap(0)

fail:
    j       fail

    .section .data
    .align  3
src_a:
    .dword  1
    .dword  2
src_b:
    .dword  10
    .dword  20
dst_add_vv:
    .dword  0
    .dword  0
dst_sub_vx:
    .dword  0
    .dword  0
dst_add_vi:
    .dword  0
    .dword  0
dst_logic_shift:
    .dword  0
    .dword  0
dst_vl1:
    .dword  0
    .dword  0
pass_msg:
    .asciz  "RVV Test pass\n"
