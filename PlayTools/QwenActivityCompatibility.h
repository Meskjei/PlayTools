#ifndef PLAYTOOLS_QWEN_ACTIVITY_COMPATIBILITY_H
#define PLAYTOOLS_QWEN_ACTIVITY_COMPATIBILITY_H

#include "QwenBlockCompatibility.h"
#include <mach/mach.h>

// shortcut: these void entry points belong only to the verified Qwen 6.12.0.2486 image.
struct QwenActivityEntry {
    uintptr_t thunk, slot, implementation;
    uint32_t instructions[4];
};
static const struct QwenActivityEntry qwen_activity_entries[] = {
    {0x100b3bb78, 0x111510c40, 0x100b3bb88,
        {0xd503201f, 0xb0084eb1, 0xf9462231, 0xd61f0220}}, // QWLiveActivityManager.startAll
    {0x100b42158, 0x111510d40, 0x100b42168,
        {0xd503201f, 0xd0084e71, 0xf946a231, 0xd61f0220}}, // QWGaoDeLiveActivityService.startTokenObservation
};
static int qwen_activity_contains(const struct section_64 *section, uintptr_t address, size_t size) {
    return section && address >= section->addr && size <= section->size &&
        address - section->addr <= section->size - size;
}
static int qwen_activity_missing_types(const void *activity, const void *updates, const void *iterator) {
    return !activity || !updates || !iterator;
}
static int qwen_activity_writable(void *slot) {
    vm_address_t address = (vm_address_t)slot;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &address, &size,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (MACH_PORT_VALID(object)) mach_port_deallocate(mach_task_self(), object);
    return result == KERN_SUCCESS && (uintptr_t)slot >= address &&
        (uintptr_t)slot - address <= size && sizeof(void *) <= size - ((uintptr_t)slot - address) &&
        (info.protection & VM_PROT_WRITE);
}
static int qwen_activity_entry_matches(const struct QwenActivityEntry *entry,
        const uint32_t *instructions, const void *current, intptr_t slide) {
    return entry && instructions &&
        memcmp(instructions, entry->instructions, sizeof(entry->instructions)) == 0 &&
        (uintptr_t)current == entry->implementation + slide;
}
static int qwen_activity_replace(void **slot, void *expected, void *replacement) {
    if (!slot || !replacement || !qwen_activity_writable(slot)) return 0;
    return __atomic_compare_exchange_n(slot, &expected, replacement, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
}
static void qwen_activity_unavailable(void) {}

#ifndef PLAYTOOLS_QWEN_ACTIVITY_TEST
static void qwen_activity_prepare(void) {
    const struct mach_header_64 *app = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!qwen_image_matches(app) || app->cputype != CPU_TYPE_ARM64) return;
    const struct section_64 *got = getsectbynamefromheader_64(app, "__DATA_CONST", "__got");
    const struct section_64 *table = getsectbynamefromheader_64(app, "__DATA", "__br_tb");
    const struct section_64 *text = getsectbynamefromheader_64(app, "__TEXT", "__text");
    const uintptr_t typeSlots[] = {0x10f0d27b0, 0x10f0d2788, 0x10f0d2780};
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    for (unsigned i = 0; i < 3; i++) if (!qwen_activity_contains(got, typeSlots[i], sizeof(void *))) return;
    if (!qwen_activity_missing_types(*(void **)(typeSlots[0] + slide),
            *(void **)(typeSlots[1] + slide), *(void **)(typeSlots[2] + slide))) return;
    // Check every entry before changing process-owned, writable branch-table data.
    for (unsigned i = 0; i < 2; i++) {
        const struct QwenActivityEntry *entry = &qwen_activity_entries[i];
        if (!qwen_activity_contains(text, entry->thunk, sizeof(entry->instructions)) ||
            !qwen_activity_contains(table, entry->slot, sizeof(void *)) ||
            !qwen_activity_writable((void *)(entry->slot + slide)) ||
            !qwen_activity_entry_matches(entry, (void *)(entry->thunk + slide),
                *(void **)(entry->slot + slide), slide)) return;
    }
    for (unsigned i = 0; i < 2; i++) {
        const struct QwenActivityEntry *entry = &qwen_activity_entries[i];
        if (!qwen_activity_replace((void **)(entry->slot + slide),
                (void *)(entry->implementation + slide), qwen_activity_unavailable)) return;
    }
    os_log_error(OS_LOG_DEFAULT, "[PlayTools] Qwen Live Activities unavailable: ActivityKit types missing; startup observers skipped");
}
#endif
#endif
