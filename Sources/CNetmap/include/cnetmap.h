/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#pragma once

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <net/if.h>
#include <net/netmap.h>
#include <net/netmap_user.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

/*
 * Netmap API version
 */
static const int CNM_API_VERSION = NETMAP_API;

/*
 * Device path
 */
static const char *CNM_DEVICE_NAME = NETMAP_DEVICE_NAME;

/*
 * ioctl commands - Swift cannot import _IO/_IOR/_IOWR macros
 */
static const unsigned long CNM_NIOCCTRL = NIOCCTRL;
static const unsigned long CNM_NIOCTXSYNC = NIOCTXSYNC;
static const unsigned long CNM_NIOCRXSYNC = NIOCRXSYNC;

/*
 * Request types for NIOCCTRL
 */
static const uint16_t CNM_REQ_REGISTER = NETMAP_REQ_REGISTER;
static const uint16_t CNM_REQ_PORT_INFO_GET = NETMAP_REQ_PORT_INFO_GET;
static const uint16_t CNM_REQ_VALE_ATTACH = NETMAP_REQ_VALE_ATTACH;
static const uint16_t CNM_REQ_VALE_DETACH = NETMAP_REQ_VALE_DETACH;
static const uint16_t CNM_REQ_VALE_LIST = NETMAP_REQ_VALE_LIST;
static const uint16_t CNM_REQ_PORT_HDR_SET = NETMAP_REQ_PORT_HDR_SET;
static const uint16_t CNM_REQ_PORT_HDR_GET = NETMAP_REQ_PORT_HDR_GET;
static const uint16_t CNM_REQ_VALE_NEWIF = NETMAP_REQ_VALE_NEWIF;
static const uint16_t CNM_REQ_VALE_DELIF = NETMAP_REQ_VALE_DELIF;

/*
 * Registration modes (nr_mode in nmreq_register)
 */
static const uint32_t CNM_REG_DEFAULT = NR_REG_DEFAULT;
static const uint32_t CNM_REG_ALL_NIC = NR_REG_ALL_NIC;
static const uint32_t CNM_REG_SW = NR_REG_SW;
static const uint32_t CNM_REG_NIC_SW = NR_REG_NIC_SW;
static const uint32_t CNM_REG_ONE_NIC = NR_REG_ONE_NIC;
static const uint32_t CNM_REG_PIPE_MASTER = NR_REG_PIPE_MASTER;
static const uint32_t CNM_REG_PIPE_SLAVE = NR_REG_PIPE_SLAVE;
static const uint32_t CNM_REG_NULL = NR_REG_NULL;
static const uint32_t CNM_REG_ONE_SW = NR_REG_ONE_SW;

/*
 * Registration flags (nr_flags in nmreq_register)
 */
static const uint64_t CNM_NR_MONITOR_TX = NR_MONITOR_TX;
static const uint64_t CNM_NR_MONITOR_RX = NR_MONITOR_RX;
static const uint64_t CNM_NR_ZCOPY_MON = NR_ZCOPY_MON;
static const uint64_t CNM_NR_EXCLUSIVE = NR_EXCLUSIVE;
static const uint64_t CNM_NR_RX_RINGS_ONLY = NR_RX_RINGS_ONLY;
static const uint64_t CNM_NR_TX_RINGS_ONLY = NR_TX_RINGS_ONLY;
static const uint64_t CNM_NR_ACCEPT_VNET_HDR = NR_ACCEPT_VNET_HDR;
static const uint64_t CNM_NR_DO_RX_POLL = NR_DO_RX_POLL;
static const uint64_t CNM_NR_NO_TX_POLL = NR_NO_TX_POLL;

/*
 * Slot flags
 */
static const uint16_t CNM_NS_BUF_CHANGED = NS_BUF_CHANGED;
static const uint16_t CNM_NS_REPORT = NS_REPORT;
static const uint16_t CNM_NS_FORWARD = NS_FORWARD;
static const uint16_t CNM_NS_NO_LEARN = NS_NO_LEARN;
static const uint16_t CNM_NS_INDIRECT = NS_INDIRECT;
static const uint16_t CNM_NS_MOREFRAG = NS_MOREFRAG;
static const uint16_t CNM_NS_TXMON = NS_TXMON;

/*
 * Ring flags
 */
static const uint32_t CNM_NR_TIMESTAMP = NR_TIMESTAMP;
static const uint32_t CNM_NR_FORWARD = NR_FORWARD;

/*
 * Maximum fragments per packet
 */
static const int CNM_MAX_FRAGS = NETMAP_MAX_FRAGS;

/*
 * Interface name size
 */
static const int CNM_IFNAMSIZ = IFNAMSIZ;
static const int CNM_REQ_IFNAMSIZ = NETMAP_REQ_IFNAMSIZ;

/*
 * VALE switch name prefix
 */
static const char *CNM_BDG_NAME = NM_BDG_NAME;

/*
 * ioctl wrappers - Swift cannot call variadic C functions
 */

/// Perform NIOCCTRL ioctl
static inline int
cnm_ioctl_ctrl(int fd, struct nmreq_header *hdr) {
    return ioctl(fd, NIOCCTRL, hdr);
}

/// Synchronize TX ring
static inline int
cnm_ioctl_txsync(int fd) {
    return ioctl(fd, NIOCTXSYNC);
}

/// Synchronize RX ring
static inline int
cnm_ioctl_rxsync(int fd) {
    return ioctl(fd, NIOCRXSYNC);
}

/*
 * Helper functions that wrap netmap_user.h macros
 * (Swift cannot use C macros directly)
 *
 * Note: Many functions use void* instead of typed pointers because
 * netmap_ring and netmap_if are over-aligned and cannot be used
 * as Swift types directly. Swift passes them as OpaquePointer.
 */

/// Get pointer to netmap_if from mmap base and offset
static inline void *
cnm_if(void *base, uint64_t offset) {
    return (void *)NETMAP_IF(base, offset);
}

/// Get pointer to TX ring (nifp is void* for Swift compatibility)
static inline void *
cnm_txring(const void *nifp, uint32_t index) {
    return (void *)NETMAP_TXRING((struct netmap_if *)nifp, index);
}

/// Get pointer to RX ring (nifp is void* for Swift compatibility)
static inline void *
cnm_rxring(const void *nifp, uint32_t index) {
    return (void *)NETMAP_RXRING((struct netmap_if *)nifp, index);
}

/// Get pointer to buffer from ring and buffer index
static inline char *
cnm_buf(const void *ring_ptr, uint32_t index) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return NETMAP_BUF(ring, index);
}

/// Get buffer index from buffer pointer
static inline uint32_t
cnm_buf_idx(const void *ring_ptr, char *buf) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return NETMAP_BUF_IDX(ring, buf);
}

/// Get buffer pointer with offset from slot
static inline char *
cnm_buf_offset(const void *ring_ptr, struct netmap_slot *slot) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return NETMAP_BUF_OFFSET(ring, slot);
}

/// Read offset from slot
static inline uint64_t
cnm_roffset(const void *ring_ptr, struct netmap_slot *slot) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return NETMAP_ROFFSET(ring, slot);
}

/// Write offset to slot
static inline void
cnm_woffset(const void *ring_ptr, struct netmap_slot *slot, uint64_t offset) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    NETMAP_WOFFSET(ring, slot, offset);
}

/// Get next slot index (wraps around)
static inline uint32_t
cnm_ring_next(const void *ring_ptr, uint32_t i) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return nm_ring_next(ring, i);
}

/// Check if ring is empty
static inline int
cnm_ring_empty(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return nm_ring_empty(ring);
}

/// Get number of available slots
static inline uint32_t
cnm_ring_space(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return nm_ring_space(ring);
}

/// Check if there are pending TX packets
static inline int
cnm_tx_pending(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return nm_tx_pending(ring);
}

/// Optimized packet copy (rounds to 64 bytes)
static inline void
cnm_pkt_copy(const void *src, void *dst, int len) {
    nm_pkt_copy(src, dst, len);
}

/*
 * Structure access helpers
 * (Using void* for Swift OpaquePointer compatibility)
 */

/// Get number of TX rings from netmap_if
static inline uint32_t
cnm_if_tx_rings(const void *nifp_ptr) {
    struct netmap_if *nifp = (struct netmap_if *)nifp_ptr;
    return nifp->ni_tx_rings;
}

/// Get number of RX rings from netmap_if
static inline uint32_t
cnm_if_rx_rings(const void *nifp_ptr) {
    struct netmap_if *nifp = (struct netmap_if *)nifp_ptr;
    return nifp->ni_rx_rings;
}

/// Get number of host TX rings from netmap_if
static inline uint32_t
cnm_if_host_tx_rings(const void *nifp_ptr) {
    struct netmap_if *nifp = (struct netmap_if *)nifp_ptr;
    return nifp->ni_host_tx_rings;
}

/// Get number of host RX rings from netmap_if
static inline uint32_t
cnm_if_host_rx_rings(const void *nifp_ptr) {
    struct netmap_if *nifp = (struct netmap_if *)nifp_ptr;
    return nifp->ni_host_rx_rings;
}

/// Get interface name from netmap_if
static inline const char *
cnm_if_name(const void *nifp_ptr) {
    struct netmap_if *nifp = (struct netmap_if *)nifp_ptr;
    return nifp->ni_name;
}

/// Get ring direction (0=TX, 1=RX)
static inline uint16_t
cnm_ring_dir(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->dir;
}

/// Get ring id
static inline uint16_t
cnm_ring_id(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->ringid;
}

/// Get number of slots in ring
static inline uint32_t
cnm_ring_num_slots(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->num_slots;
}

/// Get buffer size for ring
static inline uint32_t
cnm_ring_buf_size(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->nr_buf_size;
}

/// Get slot at index
static inline struct netmap_slot *
cnm_ring_slot(const void *ring_ptr, uint32_t i) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return &ring->slot[i];
}

/// Get ring head
static inline uint32_t
cnm_ring_head(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->head;
}

/// Set ring head
static inline void
cnm_ring_set_head(void *ring_ptr, uint32_t head) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    ring->head = head;
}

/// Get ring cur
static inline uint32_t
cnm_ring_cur(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->cur;
}

/// Set ring cur
static inline void
cnm_ring_set_cur(void *ring_ptr, uint32_t cur) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    ring->cur = cur;
}

/// Get ring tail
static inline uint32_t
cnm_ring_tail(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->tail;
}

/// Get ring flags
static inline uint32_t
cnm_ring_flags(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->flags;
}

/// Set ring flags
static inline void
cnm_ring_set_flags(void *ring_ptr, uint32_t flags) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    ring->flags = flags;
}

/// Get ring timestamp seconds
static inline long
cnm_ring_ts_sec(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->ts.tv_sec;
}

/// Get ring timestamp microseconds
static inline long
cnm_ring_ts_usec(const void *ring_ptr) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    return ring->ts.tv_usec;
}

/*
 * Poll helper
 */

/// Poll for netmap events with timeout
/// Returns the actual revents if successful, -1 on error
static inline int
cnm_poll(int fd, short events, int timeout_ms) {
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = events;
    pfd.revents = 0;
    int result = poll(&pfd, 1, timeout_ms);
    if (result < 0) {
        return -1;  // Error
    }
    if (result == 0) {
        return 0;  // Timeout
    }
    return pfd.revents;  // Return actual events
}

/// Poll constants
static const short CNM_POLLIN = POLLIN;
static const short CNM_POLLOUT = POLLOUT;
static const short CNM_POLLERR = POLLERR;

/*
 * mmap helper
 */

/// Memory map the netmap region
static inline void *
cnm_mmap(int fd, size_t size) {
    return mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
}

/// Unmap the netmap region
static inline int
cnm_munmap(void *addr, size_t size) {
    return munmap(addr, size);
}

/// Check for MAP_FAILED
static inline int
cnm_mmap_failed(void *addr) {
    return addr == MAP_FAILED;
}

/*
 * nmreq_header initialization helper
 */
static inline void
cnm_init_header(struct nmreq_header *hdr, const char *name, uint16_t reqtype, void *body) {
    memset(hdr, 0, sizeof(*hdr));
    hdr->nr_version = NETMAP_API;
    hdr->nr_reqtype = reqtype;
    if (name != NULL) {
        strncpy(hdr->nr_name, name, sizeof(hdr->nr_name) - 1);
    }
    hdr->nr_body = (uint64_t)(uintptr_t)body;
    hdr->nr_options = 0;
}

/*
 * nmreq_register initialization helper
 */
static inline void
cnm_init_register(struct nmreq_register *reg, uint32_t mode, uint64_t flags) {
    memset(reg, 0, sizeof(*reg));
    reg->nr_mode = mode;
    reg->nr_flags = flags;
}

/// Set extra buffers request
static inline void
cnm_register_set_extra_bufs(struct nmreq_register *reg, uint32_t count) {
    reg->nr_extra_bufs = count;
}

/// Get actual extra buffers allocated
static inline uint32_t
cnm_register_get_extra_bufs(const struct nmreq_register *reg) {
    return reg->nr_extra_bufs;
}

/*
 * VALE switch management helpers
 */

/// Initialize nmreq_vale_attach structure
static inline void
cnm_init_vale_attach(struct nmreq_vale_attach *attach, uint32_t mode, uint64_t flags) {
    memset(attach, 0, sizeof(*attach));
    attach->reg.nr_mode = mode;
    attach->reg.nr_flags = flags;
}

/// Get port index from vale_attach result
static inline uint32_t
cnm_vale_attach_port_index(const struct nmreq_vale_attach *attach) {
    return attach->port_index;
}

/// Initialize nmreq_vale_detach structure
static inline void
cnm_init_vale_detach(struct nmreq_vale_detach *detach) {
    memset(detach, 0, sizeof(*detach));
}

/// Get port index from vale_detach result
static inline uint32_t
cnm_vale_detach_port_index(const struct nmreq_vale_detach *detach) {
    return detach->port_index;
}

/// Initialize nmreq_vale_list structure
static inline void
cnm_init_vale_list(struct nmreq_vale_list *list) {
    memset(list, 0, sizeof(*list));
}

/// Get bridge index from vale_list
static inline uint16_t
cnm_vale_list_bridge_idx(const struct nmreq_vale_list *list) {
    return list->nr_bridge_idx;
}

/// Get port index from vale_list
static inline uint32_t
cnm_vale_list_port_idx(const struct nmreq_vale_list *list) {
    return list->nr_port_idx;
}

/// Set port index for vale_list iteration
static inline void
cnm_vale_list_set_port_idx(struct nmreq_vale_list *list, uint32_t idx) {
    list->nr_port_idx = idx;
}

/// Initialize nmreq_vale_newif structure
static inline void
cnm_init_vale_newif(struct nmreq_vale_newif *newif,
                    uint32_t tx_slots, uint32_t rx_slots,
                    uint16_t tx_rings, uint16_t rx_rings,
                    uint16_t mem_id) {
    memset(newif, 0, sizeof(*newif));
    newif->nr_tx_slots = tx_slots;
    newif->nr_rx_slots = rx_slots;
    newif->nr_tx_rings = tx_rings;
    newif->nr_rx_rings = rx_rings;
    newif->nr_mem_id = mem_id;
}

/// Get memory ID from vale_newif result
static inline uint16_t
cnm_vale_newif_mem_id(const struct nmreq_vale_newif *newif) {
    return newif->nr_mem_id;
}

/*
 * Port header management (for virtio-net headers)
 * Request type constants CNM_REQ_PORT_HDR_SET/GET are defined above.
 */

/// Initialize nmreq_port_hdr structure
static inline void
cnm_init_port_hdr(struct nmreq_port_hdr *hdr, uint32_t hdr_len) {
    memset(hdr, 0, sizeof(*hdr));
    hdr->nr_hdr_len = hdr_len;
}

/// Get header length from port_hdr
static inline uint32_t
cnm_port_hdr_len(const struct nmreq_port_hdr *hdr) {
    return hdr->nr_hdr_len;
}

/*
 * VALE polling control
 */

/// Request type constants for VALE polling
static const uint16_t CNM_REQ_VALE_POLLING_ENABLE = NETMAP_REQ_VALE_POLLING_ENABLE;
static const uint16_t CNM_REQ_VALE_POLLING_DISABLE = NETMAP_REQ_VALE_POLLING_DISABLE;

/// Polling mode constants
static const uint32_t CNM_POLLING_MODE_SINGLE_CPU = NETMAP_POLLING_MODE_SINGLE_CPU;
static const uint32_t CNM_POLLING_MODE_MULTI_CPU = NETMAP_POLLING_MODE_MULTI_CPU;

/// Initialize nmreq_vale_polling structure
static inline void
cnm_init_vale_polling(struct nmreq_vale_polling *poll,
                      uint32_t mode, uint32_t first_cpu, uint32_t num_cpus) {
    memset(poll, 0, sizeof(*poll));
    poll->nr_mode = mode;
    poll->nr_first_cpu_id = first_cpu;
    poll->nr_num_polling_cpus = num_cpus;
}

/*
 * Memory pools info
 */

/// Request type for pools info
static const uint16_t CNM_REQ_POOLS_INFO_GET = NETMAP_REQ_POOLS_INFO_GET;

/// Initialize nmreq_pools_info structure
static inline void
cnm_init_pools_info(struct nmreq_pools_info *info, uint16_t mem_id) {
    memset(info, 0, sizeof(*info));
    info->nr_mem_id = mem_id;
}

/*
 * Extra buffers list management
 */

/// Get extra buffers head index from netmap_if
static inline uint32_t
cnm_if_bufs_head(const void *nifp_ptr) {
    struct netmap_if *nifp = (struct netmap_if *)nifp_ptr;
    return nifp->ni_bufs_head;
}

/// Set extra buffers head index in netmap_if
static inline void
cnm_if_set_bufs_head(void *nifp_ptr, uint32_t head) {
    struct netmap_if *nifp = (struct netmap_if *)nifp_ptr;
    nifp->ni_bufs_head = head;
}

/// Get next buffer index from extra buffer (first uint32_t of buffer)
static inline uint32_t
cnm_extra_buf_next(const void *ring_ptr, uint32_t buf_idx) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    char *buf = NETMAP_BUF(ring, buf_idx);
    return *(uint32_t *)buf;
}

/// Set next buffer index in extra buffer
static inline void
cnm_extra_buf_set_next(const void *ring_ptr, uint32_t buf_idx, uint32_t next_idx) {
    struct netmap_ring *ring = (struct netmap_ring *)ring_ptr;
    char *buf = NETMAP_BUF(ring, buf_idx);
    *(uint32_t *)buf = next_idx;
}

/*
 * Sync Kloop (kernel busy-poll loop)
 */

/// Request types for sync kloop
static const uint16_t CNM_REQ_SYNC_KLOOP_START = NETMAP_REQ_SYNC_KLOOP_START;
static const uint16_t CNM_REQ_SYNC_KLOOP_STOP = NETMAP_REQ_SYNC_KLOOP_STOP;

/// Initialize nmreq_sync_kloop_start structure
static inline void
cnm_init_sync_kloop_start(struct nmreq_sync_kloop_start *kloop, uint32_t sleep_us) {
    memset(kloop, 0, sizeof(*kloop));
    kloop->sleep_us = sleep_us;
}

/*
 * CSB (Control/Status Block) mode
 */

/// Request type for CSB enable
static const uint16_t CNM_REQ_CSB_ENABLE = NETMAP_REQ_CSB_ENABLE;

/*
 * Options system - nmreq_option linked list
 */

/// Option type constants
static const uint32_t CNM_OPT_EXTMEM = NETMAP_REQ_OPT_EXTMEM;
static const uint32_t CNM_OPT_SYNC_KLOOP_EVENTFDS = NETMAP_REQ_OPT_SYNC_KLOOP_EVENTFDS;
static const uint32_t CNM_OPT_CSB = NETMAP_REQ_OPT_CSB;
static const uint32_t CNM_OPT_SYNC_KLOOP_MODE = NETMAP_REQ_OPT_SYNC_KLOOP_MODE;
static const uint32_t CNM_OPT_OFFSETS = NETMAP_REQ_OPT_OFFSETS;

/// Kloop mode flags
static const uint32_t CNM_KLOOP_DIRECT_TX = NM_OPT_SYNC_KLOOP_DIRECT_TX;
static const uint32_t CNM_KLOOP_DIRECT_RX = NM_OPT_SYNC_KLOOP_DIRECT_RX;

/// Initialize nmreq_option header
static inline void
cnm_init_option(struct nmreq_option *opt, uint32_t reqtype, uint64_t size) {
    memset(opt, 0, sizeof(*opt));
    opt->nro_reqtype = reqtype;
    opt->nro_size = size;
    opt->nro_next = 0;
    opt->nro_status = 0;
}

/// Chain an option to a header
static inline void
cnm_header_add_option(struct nmreq_header *hdr, struct nmreq_option *opt) {
    if (hdr->nr_options == 0) {
        hdr->nr_options = (uint64_t)(uintptr_t)opt;
    } else {
        // Find end of chain
        struct nmreq_option *curr = (struct nmreq_option *)(uintptr_t)hdr->nr_options;
        while (curr->nro_next != 0) {
            curr = (struct nmreq_option *)(uintptr_t)curr->nro_next;
        }
        curr->nro_next = (uint64_t)(uintptr_t)opt;
    }
}

/// Get option status after ioctl
static inline uint32_t
cnm_option_status(const struct nmreq_option *opt) {
    return opt->nro_status;
}

/*
 * OPT_EXTMEM - External memory (hugepages)
 */

/// Initialize nmreq_opt_extmem structure
static inline void
cnm_init_opt_extmem(struct nmreq_opt_extmem *ext,
                    void *usrptr,
                    uint16_t mem_id,
                    uint32_t if_objtotal, uint32_t if_objsize,
                    uint32_t ring_objtotal, uint32_t ring_objsize,
                    uint32_t buf_objtotal, uint32_t buf_objsize) {
    memset(ext, 0, sizeof(*ext));
    cnm_init_option(&ext->nro_opt, NETMAP_REQ_OPT_EXTMEM, 0);
    ext->nro_usrptr = (uint64_t)(uintptr_t)usrptr;
    ext->nro_info.nr_mem_id = mem_id;
    ext->nro_info.nr_if_pool_objtotal = if_objtotal;
    ext->nro_info.nr_if_pool_objsize = if_objsize;
    ext->nro_info.nr_ring_pool_objtotal = ring_objtotal;
    ext->nro_info.nr_ring_pool_objsize = ring_objsize;
    ext->nro_info.nr_buf_pool_objtotal = buf_objtotal;
    ext->nro_info.nr_buf_pool_objsize = buf_objsize;
}

/// Get the resulting memory size after registration
static inline uint64_t
cnm_opt_extmem_memsize(const struct nmreq_opt_extmem *ext) {
    return ext->nro_info.nr_memsize;
}

/*
 * OPT_OFFSETS - Packet offset support
 */

/// Initialize nmreq_opt_offsets structure
static inline void
cnm_init_opt_offsets(struct nmreq_opt_offsets *off,
                     uint64_t max_offset,
                     uint64_t initial_offset,
                     uint32_t offset_bits) {
    memset(off, 0, sizeof(*off));
    cnm_init_option(&off->nro_opt, NETMAP_REQ_OPT_OFFSETS, 0);
    off->nro_max_offset = max_offset;
    off->nro_initial_offset = initial_offset;
    off->nro_offset_bits = offset_bits;
}

/// Get the effective max offset after registration
static inline uint64_t
cnm_opt_offsets_max(const struct nmreq_opt_offsets *off) {
    return off->nro_max_offset;
}

/*
 * OPT_CSB - Control/Status Block mode
 */

/// Initialize nmreq_opt_csb structure
static inline void
cnm_init_opt_csb(struct nmreq_opt_csb *csb,
                 struct nm_csb_atok *atok,
                 struct nm_csb_ktoa *ktoa) {
    memset(csb, 0, sizeof(*csb));
    cnm_init_option(&csb->nro_opt, NETMAP_REQ_OPT_CSB, 0);
    csb->csb_atok = (uint64_t)(uintptr_t)atok;
    csb->csb_ktoa = (uint64_t)(uintptr_t)ktoa;
}

/// CSB entry size (for allocation)
static const size_t CNM_CSB_ATOK_SIZE = sizeof(struct nm_csb_atok);
static const size_t CNM_CSB_KTOA_SIZE = sizeof(struct nm_csb_ktoa);

/// Read CSB atok fields
static inline uint32_t
cnm_csb_atok_head(const struct nm_csb_atok *csb) {
    return csb->head;
}

static inline uint32_t
cnm_csb_atok_cur(const struct nm_csb_atok *csb) {
    return csb->cur;
}

static inline uint32_t
cnm_csb_atok_appl_need_kick(const struct nm_csb_atok *csb) {
    return csb->appl_need_kick;
}

/// Write CSB atok fields
static inline void
cnm_csb_atok_set_head(struct nm_csb_atok *csb, uint32_t head) {
    csb->head = head;
}

static inline void
cnm_csb_atok_set_cur(struct nm_csb_atok *csb, uint32_t cur) {
    csb->cur = cur;
}

static inline void
cnm_csb_atok_set_appl_need_kick(struct nm_csb_atok *csb, uint32_t need_kick) {
    csb->appl_need_kick = need_kick;
}

static inline void
cnm_csb_atok_set_sync_flags(struct nm_csb_atok *csb, uint32_t flags) {
    csb->sync_flags = flags;
}

/// Read CSB ktoa fields
static inline uint32_t
cnm_csb_ktoa_hwcur(const struct nm_csb_ktoa *csb) {
    return csb->hwcur;
}

static inline uint32_t
cnm_csb_ktoa_hwtail(const struct nm_csb_ktoa *csb) {
    return csb->hwtail;
}

static inline uint32_t
cnm_csb_ktoa_kern_need_kick(const struct nm_csb_ktoa *csb) {
    return csb->kern_need_kick;
}

/*
 * OPT_SYNC_KLOOP_EVENTFDS - Eventfd notifications for kloop
 */

/// Get size needed for eventfds option with N rings
static inline size_t
cnm_opt_sync_kloop_eventfds_size(uint32_t num_rings) {
    return sizeof(struct nmreq_opt_sync_kloop_eventfds) +
           num_rings * 3 * sizeof(uint32_t);  // ioeventfd, irqfd, (pad) per ring
}

/// Initialize the eventfds option header
/// Note: The caller must allocate enough space for the ring entries
static inline void
cnm_init_opt_sync_kloop_eventfds(struct nmreq_opt_sync_kloop_eventfds *evfds,
                                  uint32_t num_entries) {
    memset(evfds, 0, sizeof(*evfds));
    cnm_init_option(&evfds->nro_opt, NETMAP_REQ_OPT_SYNC_KLOOP_EVENTFDS,
                    cnm_opt_sync_kloop_eventfds_size(num_entries));
}

/// Set eventfd for a ring entry
static inline void
cnm_opt_sync_kloop_set_eventfd(struct nmreq_opt_sync_kloop_eventfds *evfds,
                                uint32_t ring_idx,
                                int32_t ioeventfd,
                                int32_t irqfd) {
    // The entries array follows the structure
    uint32_t *entries = (uint32_t *)(evfds + 1);
    entries[ring_idx * 3 + 0] = (uint32_t)ioeventfd;
    entries[ring_idx * 3 + 1] = (uint32_t)irqfd;
    entries[ring_idx * 3 + 2] = 0;  // padding
}

/*
 * OPT_SYNC_KLOOP_MODE - Kloop direct TX/RX mode
 */

/// Initialize nmreq_opt_sync_kloop_mode structure
static inline void
cnm_init_opt_sync_kloop_mode(struct nmreq_opt_sync_kloop_mode *mode,
                              uint32_t mode_flags) {
    memset(mode, 0, sizeof(*mode));
    cnm_init_option(&mode->nro_opt, NETMAP_REQ_OPT_SYNC_KLOOP_MODE, 0);
    mode->mode = mode_flags;
}
