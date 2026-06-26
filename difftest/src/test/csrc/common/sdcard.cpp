/***************************************************************************************
* Copyright (c) 2020-2021 Institute of Computing Technology, Chinese Academy of Sciences
* Copyright (c) 2020-2021 Peng Cheng Laboratory
*
* XiangShan is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "common.h"
#include "sdcard.h"
#include <unistd.h>
#include <fcntl.h>

FILE *fp = NULL;
static char sdcard_image_path[1024];

extern "C" {

// 从宿主 stdin 非阻塞读取一字节：返回 0..255，无输入返回 -1
int mmio_uart_rx() {
  static int initialized = 0;
  if (!initialized) {
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    if (flags != -1) {
      fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    }
    initialized = 1;
  }
  unsigned char ch = 0;
  ssize_t n = read(STDIN_FILENO, &ch, 1);
  if (n == 1) {
    return (int)ch;
  }
  return -1;
}

void sd_setaddr(uint32_t addr) {
  fseek(fp, addr, SEEK_SET);
  //printf("set addr to 0x%08x\n", addr);
  //assert(0);
}

void sd_read(uint32_t *data) {
  fread(data, 4, 1, fp);
  //printf("read data = 0x%08x\n", *data);
  //assert(0);
}

void init_sd(const char *image_path) {
  const char *path = image_path;
  if (path == NULL || path[0] == '\0') {
#ifdef SDCARD_IMAGE
    path = SDCARD_IMAGE;
#else
    path = NULL;
#endif
  }
  if (path == NULL) {
    eprintf(ANSI_COLOR_MAGENTA "[warning] sdcard img not configured\n");
    return;
  }

  snprintf(sdcard_image_path, sizeof(sdcard_image_path), "%s", path);
  fp = fopen(sdcard_image_path, "r+b");
  if (!fp) {
    fp = fopen(sdcard_image_path, "rb");
  }
  if (!fp) {
    eprintf(ANSI_COLOR_MAGENTA "[warning] sdcard img not found: %s\n", sdcard_image_path);
  }
}

void sd_read64(uint64_t addr, uint64_t *data) {
  if (!fp) {
    *data = 0;
    return;
  }
  fseek(fp, (long)addr, SEEK_SET);
  fread(data, 8, 1, fp);
}

void sd_write64(uint64_t addr, uint64_t data, uint8_t strobe) {
  if (!fp) {
    return;
  }
  uint64_t old_data = 0;
  fseek(fp, (long)addr, SEEK_SET);
  fread(&old_data, 8, 1, fp);
  uint8_t *old_bytes = reinterpret_cast<uint8_t *>(&old_data);
  uint8_t *new_bytes = reinterpret_cast<uint8_t *>(&data);
  for (int i = 0; i < 8; i++) {
    if (strobe & (1u << i)) {
      old_bytes[i] = new_bytes[i];
    }
  }
  fseek(fp, (long)addr, SEEK_SET);
  fwrite(&old_data, 8, 1, fp);
  fflush(fp);
}

}
