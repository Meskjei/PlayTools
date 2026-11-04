#define PLAYTOOLS_QWEN_COMPAT_TEST 1
#define PLAYTOOLS_QWEN_ACTIVITY_TEST 1
#include "../../PlayTools/QwenActivityCompatibility.h"
#include <assert.h>
#include <sys/mman.h>
#include <unistd.h>

static int calls;
static void ordinary(void) { calls++; }
int main(void) {
    struct { struct mach_header_64 header; struct uuid_command uuid; } image = {0};
    image.header.magic = MH_MAGIC_64; image.header.ncmds = 1;
    image.header.sizeofcmds = sizeof(image.uuid);
    image.uuid.cmd = LC_UUID; image.uuid.cmdsize = sizeof(image.uuid);
    memcpy(image.uuid.uuid, qwen_compatible_uuid, 16);
    assert(qwen_image_matches(&image.header));
    image.uuid.uuid[0] ^= 1;
    assert(!qwen_image_matches(&image.header));
    assert(!qwen_relocate_block(0, 0, NULL, NULL, NULL));
    assert(qwen_activity_missing_types(NULL, NULL, NULL));
    assert(qwen_activity_missing_types(ordinary, NULL, ordinary));
    assert(!qwen_activity_missing_types(ordinary, ordinary, ordinary));
    struct section_64 section = {.addr = 0x1000, .size = 0x100};
    assert(qwen_activity_contains(&section, 0x10f8, 8));
    assert(!qwen_activity_contains(&section, 0x10f9, 8));
    assert(!qwen_activity_contains(&section, UINTPTR_MAX, 8));
    assert(!qwen_activity_contains(NULL, 0x1000, 8));
    for (unsigned i = 0; i < 2; i++) {
        const struct QwenActivityEntry *entry = &qwen_activity_entries[i];
        uint32_t instructions[4]; memcpy(instructions, entry->instructions, sizeof(instructions));
        assert(qwen_activity_entry_matches(entry, instructions, (void *)(entry->implementation + 0x4000), 0x4000));
        assert(!qwen_activity_entry_matches(entry, instructions, (void *)(entry->implementation + 4), 0));
        instructions[3] ^= 1;
        assert(!qwen_activity_entry_matches(entry, instructions, (void *)entry->implementation, 0));
    }
    void *slot = ordinary;
    assert(!qwen_activity_replace(&slot, qwen_activity_unavailable, qwen_activity_unavailable));
    ((void (*)(void))slot)(); assert(calls == 1);
    assert(qwen_activity_replace(&slot, ordinary, qwen_activity_unavailable));
    ((void (*)(void))slot)(); assert(calls == 1);
    assert(!qwen_activity_replace(&slot, ordinary, qwen_activity_unavailable));
    size_t page = (size_t)getpagesize();
    void **readonly = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(readonly != MAP_FAILED); *readonly = ordinary;
    assert(mprotect(readonly, page, PROT_READ) == 0);
    assert(!qwen_activity_replace(readonly, ordinary, qwen_activity_unavailable));
    assert(*readonly == ordinary); assert(munmap(readonly, page) == 0);
    return 0;
}
