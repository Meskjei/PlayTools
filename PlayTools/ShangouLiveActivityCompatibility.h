#ifndef PLAYTOOLS_SHANGOU_LIVE_ACTIVITY_COMPATIBILITY_H
#define PLAYTOOLS_SHANGOU_LIVE_ACTIVITY_COMPATIBILITY_H

#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <os/log.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <sys/sysctl.h>

// shortcut: revalidate the Swift callback and its ownership when either IPA/framework UUID changes.
static int shangou_activity_image_matches(const struct mach_header_64 *header, const unsigned char uuid[16]) {
    if (!header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64) return 0;
    const unsigned char *cursor = (const unsigned char *)(header + 1);
    size_t remaining = header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (remaining < sizeof(struct load_command)) return 0;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > remaining) return 0;
        if (command->cmd == LC_UUID) return command->cmdsize >= sizeof(struct uuid_command) &&
            memcmp(((const struct uuid_command *)command)->uuid, uuid, 16) == 0;
        cursor += command->cmdsize;
        remaining -= command->cmdsize;
    }
    return 0;
}

static const unsigned char shangou_activity_app_uuid[16] = {
    0x54,0x31,0x15,0x7e,0x30,0x50,0x3d,0x18,0xad,0xf1,0xd0,0xd6,0x2d,0x65,0xc0,0xf9
};
static const unsigned char shangou_activity_widget_uuid[16] = {
    0xab,0xaf,0x96,0xdd,0x57,0xbc,0x4e,0x3d,0x94,0x7a,0x28,0xa3,0x6f,0xa1,0xa7,0x95
};
static int shangou_activity_host_matches(const struct mach_header_64 *app, const char *build) {
    return build && (strcmp(build, "23C71") == 0 || strcmp(build, "26B123") == 0) &&
        shangou_activity_image_matches(app, shangou_activity_app_uuid);
}

// ABI of this framework's void Dispatch block: normal block header, then a Swift function/context pair.
struct ShangouActivityBlock {
    void *isa;
    int32_t flags, reserved;
    void (*invoke)(void *);
    const void *descriptor;
    const void *function, *context;
};
static int shangou_activity_is_initializer(uintptr_t caller, uintptr_t base, const struct ShangouActivityBlock *block) {
    const uint32_t stackFlags = (1u << 25) | (1u << 30); // copy/dispose + signature; not global/heap
    return base && caller == base + 0x38b20 && block &&
        ((uint32_t)block->flags & (stackFlags | (1u << 24) | (1u << 28))) == stackFlags &&
        (uintptr_t)block->invoke == base + 0x25ebc && (uintptr_t)block->function == base + 0x46834;
}
static void shangou_activity_unavailable(void *block) { (void)block; }
static int shangou_activity_disable_copy(struct ShangouActivityBlock *copy, const struct ShangouActivityBlock *source) {
    if (!copy || copy == source || !((uint32_t)copy->flags & (1u << 24)) ||
        copy->invoke != source->invoke || copy->descriptor != source->descriptor ||
        copy->function != source->function || copy->context != source->context) return 0;
    // Only the new heap copy's void invocation changes. Preserve capture retain/dispose and refcount metadata.
    copy->invoke = shangou_activity_unavailable;
    return 1;
}

#ifndef PLAYTOOLS_SHANGOU_ACTIVITY_TEST
static _Atomic uintptr_t shangou_activity_base;
static _Atomic int shangou_activity_reported;
extern void *_Block_copy(const void *block);

static void shangou_activity_image_added(const struct mach_header *image, intptr_t slide) {
    const struct mach_header_64 *header = (const struct mach_header_64 *)image;
    if (!shangou_activity_image_matches(header, shangou_activity_widget_uuid)) return;
    const struct section_64 *text = getsectbynamefromheader_64(header, "__TEXT", "__text");
    if (!text || text->addr > 0x25ebc || text->size < 0x46844 - text->addr) return;
    uintptr_t base = (uintptr_t)image;
    const uint32_t invoke[] = {0xa9be4ff4, 0xa9017bfd, 0x910043fd, 0xa9425013};
    const uint32_t initializer[] = {0xd101c3ff, 0xa9035ff8, 0xa90457f6, 0xa9054ff4};
    const uint32_t copyCall = 0x9401268d;
    if (memcmp((void *)(base + 0x25ebc), invoke, sizeof(invoke)) ||
        memcmp((void *)(base + 0x46834), initializer, sizeof(initializer)) ||
        memcmp((void *)(base + 0x38b1c), &copyCall, sizeof(copyCall))) return;
    atomic_store_explicit(&shangou_activity_base, base, memory_order_release);
}
static void shangou_activity_prepare(void) {
    char build[64] = {0}; size_t size = sizeof(build);
    if (sysctlbyname("kern.osversion", build, &size, NULL, 0) != 0 || size >= sizeof(build) ||
        !shangou_activity_host_matches((const struct mach_header_64 *)_dyld_get_image_header(0), build)) return;
    // dyld calls this for existing images and future dlopen images; no Objective-C/Swift metadata lookup in the loader callback.
    _dyld_register_func_for_add_image(shangou_activity_image_added);
}
__attribute__((noinline)) static void *shangou_activity_copy(const void *value) {
    uintptr_t base = atomic_load_explicit(&shangou_activity_base, memory_order_acquire);
    int selected = shangou_activity_is_initializer((uintptr_t)__builtin_return_address(0), base, value);
    void *copy = _Block_copy(value);
    if (selected && shangou_activity_disable_copy(copy, value) &&
        !atomic_exchange_explicit(&shangou_activity_reported, 1, memory_order_relaxed)) {
        os_log_error(OS_LOG_DEFAULT, "[PlayTools] Shangou delivery Live Activity unavailable on this Mac runtime; initialization skipped");
    }
    return copy;
}
DYLD_INTERPOSE(shangou_activity_copy, _Block_copy)
#endif
#endif
