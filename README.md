# Parallels Tools 12.x 内核模块 Linux 7.x 移植补丁

> English summary: a patch that makes the **Parallels Tools 12.2.1 (2017)** guest kernel
> modules (`prl_eth` / `prl_tg` / `prl_fs` / `prl_fs_freeze`) **build and work on modern
> Linux kernels** (tested on Kali Rolling, kernel `7.1.5+kali-amd64`, gcc 15). See
> [What it fixes](#它修复了什么) below — roughly a decade of removed/renamed kernel APIs.

老版本 Parallels Desktop（如 12.2.1）自带的 Parallels Tools 在新版 Linux 内核上无法安装：
内核模块源码（2017 年的 `prl_mod.tar.gz`）使用的大量 API 在近十年的内核演进中被删除或改名，
编译阶段即失败。本仓库提供一份补丁，将这些模块移植到现代内核，并已在真机（虚拟机）上
完成功能验证。

**本仓库只包含补丁和使用说明，不包含任何 Parallels 原始代码**——原始文件版权归
Parallels International GmbH 所有，请从你自己的 Parallels 安装介质中获取（见下文）。

## 测试环境

| 项目 | 版本 |
|------|------|
| Parallels Desktop | 12.2.1-41615 (macOS 宿主) |
| 客户机系统 | Kali Linux Rolling (x86_64) |
| 内核 | 7.1.5+kali-amd64 |
| gcc / make | 15.3.0 / 4.4.1 |
| Parallels Tools | 12.2.1-41615（ISO 中的 `kmods/prl_mod.tar.gz`，66661 字节） |

已验证功能：网络（`prl_eth`，virtio 网卡枚举、DHCP、外网连通）、共享文件夹
（`prl_fs` + `prl_tg`，挂载 `/media/psf`、目录遍历、文件读写删除）、快照冻结
（`prl_fs_freeze` 加载正常）、`prltoolsd` 服务运行、`dmesg` 无 UBSAN 告警。

## 使用方法

前提：虚拟机光驱挂载 Parallels Tools ISO（PD 菜单 "Install Parallels Tools"），
并已安装当前内核的 headers 和编译工具链：

```bash
sudo apt install build-essential linux-headers-$(uname -r)
```

### 方式一：一键脚本（推荐）

```bash
./apply.sh /media/cdrom0/kmods/prl_mod.tar.gz
# 生成当前目录下的 prl_mod.tar.gz（已打好补丁）
```

### 方式二：手动打补丁

```bash
mkdir kmods && tar xzf /media/cdrom0/kmods/prl_mod.tar.gz -C kmods
chmod -R u+w kmods
cd kmods && patch -p1 < /path/to/prl_mod-kernel-7.x.patch
tar czf ../prl_mod.tar.gz .
```

### 安装

把打完补丁的 `prl_mod.tar.gz` 放进一份从 ISO 复制出来的安装文件树里替换原文件，然后：

```bash
sudo ./install --install
# 询问是否跳过 X server 模块时回答 yes（无桌面/X 环境时）
```

或者只验证编译（不动系统）：

```bash
cd kmods && make -f Makefile.kmods   # 应产出 4 个 .ko
```

安装完成后重启，或手动 `modprobe prl_tg prl_fs`，共享文件夹用
`sudo mount -t prl_fs <共享名> /media/psf` 挂载。

## 它修复了什么

按内核版本顺序，补丁处理的 API 变更（含少量虚构的 7.x 新 API，以头文件实测为准）：

**编译期被删除/改名的 API**
- `ethtool_ops.get_settings`（4.6 删除）、`eth_change_mtu`（5.15 删除）
- `SUBDIRS=` 构建参数（5.3 移除，改用 `M=`）、`EXTRA_CFLAGS`（kbuild 已废弃且静默忽略，改 `ccflags-y`）
- `set_fs()` / `segment_eq()` / `TIF_IA32`（5.10 移除；32 位 compat 判断改用 `in_ia32_syscall()`）
- `PDE_DATA` → `pde_data`（5.6）、`mm->mmap_sem` → `mmap_lock`（5.8）
- `pci_set_dma_mask` / `pci_map_page` / `PCI_DMA_BIDIRECTIONAL` → 通用 DMA API（`dma_set_mask` 等）
- `get_user_pages()` 的 `vmas` 参数（6.5 移除）
- `freeze_bdev` / `thaw_bdev` → `bdev_freeze` / `bdev_thaw`、`bdevname`/`BDEVNAME_SIZE` → `%pg` 格式
- `d_set_d_op()` → `set_default_d_op()`（按 superblock 设置一次）
- `del_timer_sync` → `timer_delete_sync`（6.2）、`DEFINE_TIMER` 四参数 → 两参数（4.15）
- 魔法函数名 `init_module()`/`cleanup_module()`（objtool 拒绝，改为具名 + `module_init/exit`）

**签名/类型变化**
- `proc_create*` 改用 `struct proc_ops`（5.6）——三处兼容层各写了一个转换垫片
- `file_system_type.mount` → fs_context API（`init_fs_context` + `get_tree_nodev`；
  并处理了新版 `mount(8)` 走 fsconfig 不触发 `parse_monolithic` 的问题：从 `fc->source` 兜底取共享名）
- inode_operations 多数回调新增 `struct mnt_idmap *` 首参（6.0）；`mkdir` 改返回 `struct dentry *`（7.x）
- `d_revalidate` 改为 `(inode, qstr, dentry, flags)` 四参（7.x）
- inode 时间戳改为访问器（`inode_set_mtime` 等，6.19+）；`i_state` 改为 `struct inode_state_flags`
  （7.x，经 `inode_state_read()` 访问）
- `setattr_copy`/`generic_fillattr` 新签名；`.fault` 回调返回 `vm_fault_t`（4.17）；
  `.iterate` → `.iterate_shared`（5.10）；`s_flags` 使用 `SB_*` 而非 `MS_*`
- `.remount_fs` 已从 `super_operations` 删除（直接移除，remount 降级为内核默认行为）

**构建系统**
- prl_fs 依赖 prl_tg 导出的 `call_tg_sync`：新版 kbuild 不再自动读取模块目录的
  `Module.symvers`，需显式 `KBUILD_EXTRA_SYMBOLS`
- 修复头文件搜索路径：`<Interfaces/*.h>`、`"Toolgate/..."` 等相对包含在新 kbuild 下
  解析不到，统一加 `-I$(src)/...`

**运行时告警清理（UBSAN / FORTIFY）**
- `struct page *p[0]` → 标准柔性数组 `p[]`（prltg.c）
- `de->name[name_len]` 下标越界误报 → 等价指针写法（file.c；此处**不能**改成柔性数组，
  否则 `sizeof(prlfs_dirent)` 变化会破坏与宿主机的目录记录对齐）
- `build_request`/`complete_request` 中写入 `RequestPages[dpages]` 触发 FORTIFY
  field-spanning 告警 → 改用未检查的 `__memcpy`（`RequestPages[1]` 同样是刻意的
  变长尾存储——`paged_request_size()` 的注释明确"first page index is part of
  TG_PAGED_REQUEST"，改柔性数组会破坏 dsize 计算）

## 无 KMS 环境的图形界面（可选）

PD 12 的虚拟显卡（`1ab8:4005`）在内核 7.x 没有任何 KMS/DRM 驱动，gdm 会因
"没有主 GPU"拒绝启动。已在 Kali 上验证的方案：

1. 让 logind 承认图形能力（`/etc/udev/rules.d/61-fb-master-of-seat.rules`）：
   ```
   SUBSYSTEM=="graphics", KERNEL=="fb0", TAG+="seat", TAG+="master-of-seat"
   ```
   之后 `udevadm control --reload && udevadm trigger -c add --subsystem-match=graphics`
2. Xorg 用 fbdev 直驱帧缓冲（`/etc/X11/xorg.conf.d/`）：
   ```
   Section "Device"
       Identifier "Parallels VGA"
       Driver     "fbdev"
       Option     "fbdev" "/dev/fb0"
   EndSection
   ```
3. 显示管理器换 lightdm（gdm 硬性要求 DRM 设备）。
4. 如需把虚拟显卡从 prl_tg 解绑（vesa 直驱场景），可在显示管理器启动前对
   `/sys/bus/pci/drivers/prl_tg/unbind` 写入 `0000:01:00.0`（fbdev 方案不需要）。

**许可证声明**
- 四个模块的 `MODULE_LICENSE("Parallels")` 改为 `("GPL")`：新内核 modpost 拒绝
  非 GPL 模块引用 GPL-only 符号（如 `cc_platform_has`）。这是社区对旧驱动的通行处理方式，
  但请知悉这改变了内核对该模块的许可声明，合规使用请自行评估。

## 已知限制

- 未实现 fs_context 的 `parse_param`：挂载选项必须通过 `mount -t prl_fs 共享名 挂载点`
  形式传入（共享名作为 source），`-o sf=共享名` 形式不支持。
- 手动 `xz` 压缩的 `.ko` 可能被内核解压器拒绝（`decompression failed with status 6`）；
  安装器自己生成的压缩没问题。手动安装模块时建议直接用未压缩 `.ko`。
- 只在内核 7.1.5 上验证过；其他版本的内核如遇差异，条件编译门槛按已知引入版本设置，
  个别 7.x 新 API 的版本判断可能需要微调。

## 许可

补丁本身以 [MIT](LICENSE) 发布。补丁所修改的原始内核模块源码版权归
Parallels International GmbH 所有，本仓库不包含、不分发原始代码；
请从你自己的 Parallels 安装介质获取原始文件后应用本补丁。
