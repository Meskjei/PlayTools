#ifndef PLAYTOOLS_QWEN_BLOCK_COMPATIBILITY_H
#define PLAYTOOLS_QWEN_BLOCK_COMPATIBILITY_H

#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <os/log.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

// shortcut: only this exact 6.12.0.2486 binary is supported; revalidate each new IPA.
static const unsigned char qwen_compatible_uuid[16] = {
    0x28, 0x2e, 0xe8, 0x88, 0x85, 0x2e, 0x3c, 0x5b, 0x8f, 0x40, 0x91, 0x82, 0x0b, 0x03, 0x9b, 0x6f
};
struct QwenBlock {
    void *isa;
    int32_t flags;
    int32_t reserved;
    void *invoke;
    const void *descriptor;
};

static int qwen_image_matches(const struct mach_header_64 *header) {
    if (!header || header->magic != MH_MAGIC_64) return 0;
    const uint8_t *p = (const uint8_t *)(header + 1);
    size_t remaining = header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (remaining < sizeof(struct load_command)) return 0;
        const struct load_command *command = (const struct load_command *)p;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > remaining) return 0;
        if (command->cmd == LC_UUID) {
            if (command->cmdsize < sizeof(struct uuid_command)) return 0;
            return memcmp(((const struct uuid_command *)command)->uuid, qwen_compatible_uuid, 16) == 0;
        }
        p += command->cmdsize;
        remaining -= command->cmdsize;
    }
    return 0;
}

static int qwen_relocate_block(uintptr_t caller, uintptr_t expected_caller, struct QwenBlock *block,
                               const void *original, const void *replacement) {
    if (caller != expected_caller || !block) return 0;
    uint32_t flags = (uint32_t)block->flags;
    if (!(flags & (1u << 24)) || !(flags & (1u << 30)) || (flags & (1u << 25))) return 0;
    const void *expected = original;
    return __atomic_compare_exchange_n(&block->descriptor, &expected, replacement, 0,
                                       __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
}

#ifndef PLAYTOOLS_QWEN_COMPAT_TEST
static _Alignas(16) unsigned char qwen_descriptor_copy[32];
static const void *qwen_original_descriptor;
static uintptr_t qwen_retain_callsite;
static _Atomic int qwen_compat_enabled;
extern void *objc_retain(void *);

static void qwen_block_compat_prepare(void) {
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!qwen_image_matches(header)) return;
    const struct section_64 *section = getsectbynamefromheader_64(header, "__DATA_CONST", "__const");
    if (!section || section->addr != 0x10f0d7040ULL || section->size < sizeof(qwen_descriptor_copy)) return;
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    qwen_original_descriptor = (const void *)(section->addr + slide);
    memcpy(qwen_descriptor_copy, qwen_original_descriptor, sizeof(qwen_descriptor_copy));
    qwen_retain_callsite = (uintptr_t)(0x107bba14cULL + slide);
    atomic_store_explicit(&qwen_compat_enabled, 1, memory_order_release);
    os_log_info(OS_LOG_DEFAULT, "[PlayTools] Qwen 6.12.0.2486 block compatibility enabled");
}

__attribute__((noinline)) static void *qwen_compatible_retain(void *value) {
    if (!atomic_load_explicit(&qwen_compat_enabled, memory_order_acquire)) return objc_retain(value);
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    void *result = objc_retain(value);
    qwen_relocate_block(caller, qwen_retain_callsite, result, qwen_original_descriptor, qwen_descriptor_copy);
    return result;
}
DYLD_INTERPOSE(qwen_compatible_retain, objc_retain)
#endif
#endif
