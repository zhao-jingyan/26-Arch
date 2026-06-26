# 仿真器 C++ 编译优化：略增编译/链接时间，显著缩短仿真时间
# 用法示例：
#   make sim EMU_MARCH=znver4 EMU_MTUNE=znver4          # AMD Zen 4 + AOCC
#   make sim EMU_CXX=amdclang++ EMU_MARCH=znver3        # 手动指定 AOCC
#   make vsim VSIM_MARCH=skylake VSIM_MTUNE=skylake     # Intel

EMU_OPT ?= 1
EMU_LTO ?= 1
EMU_MARCH ?= native
EMU_MTUNE ?=

# verilate vsim 别名（可与 EMU_* 分别覆盖）
VSIM_OPT ?= $(EMU_OPT)
VSIM_LTO ?= $(EMU_LTO)
VSIM_MARCH ?= $(EMU_MARCH)
VSIM_MTUNE ?= $(EMU_MTUNE)

# 厂商编译器：默认自动探测 AOCC(amdclang++) / Intel(icpx) / clang++ / g++
ifndef EMU_CXX
AOCC_CLANG := $(shell ls /opt/AMD/aocc-compiler-*/bin/amdclang++ 2>/dev/null | tail -1)
ifeq ($(AOCC_CLANG),)
EMU_CXX := $(shell \
	command -v amdclang++ 2>/dev/null || \
	command -v icpx 2>/dev/null || \
	command -v clang++ 2>/dev/null || \
	command -v g++ 2>/dev/null || \
	echo g++)
else
EMU_CXX := $(AOCC_CLANG)
endif
endif

VSIM_CXX ?= $(EMU_CXX)

ifeq ($(EMU_OPT),1)
EMU_OPT_FLAG_LIST := -O3 -march=$(EMU_MARCH)
ifneq ($(EMU_MTUNE),)
EMU_OPT_FLAG_LIST += -mtune=$(EMU_MTUNE)
endif
ifeq ($(EMU_LTO),1)
EMU_OPT_FLAG_LIST += -flto
EMU_LDFLAGS_OPT := -flto
else
EMU_LDFLAGS_OPT :=
endif
EMU_OPT_FLAGS := $(EMU_OPT_FLAG_LIST)
else
EMU_OPT_FLAG_LIST :=
EMU_OPT_FLAGS :=
EMU_LDFLAGS_OPT :=
endif

ifeq ($(VSIM_OPT),1)
VSIM_OPT_FLAG_LIST := -O3 -march=$(VSIM_MARCH)
ifneq ($(VSIM_MTUNE),)
VSIM_OPT_FLAG_LIST += -mtune=$(VSIM_MTUNE)
endif
ifeq ($(VSIM_LTO),1)
VSIM_OPT_FLAG_LIST += -flto
endif
VSIM_OPT_FLAGS := $(VSIM_OPT_FLAG_LIST)
else
VSIM_OPT_FLAG_LIST :=
VSIM_OPT_FLAGS :=
endif

# LTO 需要配套 ar/ranlib（探测失败则回退系统 ar）
ifeq ($(EMU_LTO),1)
AR := $(shell $(EMU_CXX) -print-prog-name=gcc-ar 2>/dev/null)
RANLIB := $(shell $(EMU_CXX) -print-prog-name=gcc-ranlib 2>/dev/null)
ifeq ($(shell command -v $(AR) 2>/dev/null),)
AR := $(shell $(EMU_CXX) -print-prog-name=llvm-ar 2>/dev/null)
RANLIB := $(shell $(EMU_CXX) -print-prog-name=llvm-ranlib 2>/dev/null)
endif
ifeq ($(shell command -v $(AR) 2>/dev/null),)
AR := ar
RANLIB := ranlib
endif
export AR
export RANLIB
endif

export EMU_CXX
