#define PLAYTOOLS_QWEN_COMPAT_TEST 1
#include "../../PlayTools/QwenBlockCompatibility.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    struct {
        struct mach_header_64 header;
        struct uuid_command uuid;
    } image = {0};
    image.header.magic = MH_MAGIC_64;
    image.header.ncmds = 1;
    image.header.sizeofcmds = sizeof(image.uuid);
    image.uuid.cmd = LC_UUID;
    image.uuid.cmdsize = sizeof(image.uuid);
    memcpy(image.uuid.uuid, qwen_compatible_uuid, 16);
    assert(qwen_image_matches(&image.header));
    image.uuid.uuid[0] ^= 1;
    assert(!qwen_image_matches(&image.header));
    image.uuid.uuid[0] ^= 1;
    image.uuid.cmdsize = sizeof(image.uuid) + 1;
    assert(!qwen_image_matches(&image.header));
    image.uuid.cmdsize = sizeof(image.uuid);
    image.header.sizeofcmds = sizeof(struct load_command) - 1;
    assert(!qwen_image_matches(&image.header));
    assert(!qwen_image_matches(NULL));

    int original = 1, other = 2, replacement = 3;
    struct QwenBlock block = {.flags = (1u << 24) | (1u << 30), .descriptor = &original};
    assert(!qwen_relocate_block(11, 12, &block, &original, &replacement));
    assert(block.descriptor == &original);
    assert(!qwen_relocate_block(12, 12, NULL, &original, &replacement));
    block.flags |= 1u << 25;
    assert(!qwen_relocate_block(12, 12, &block, &original, &replacement));
    block.flags &= ~(1u << 25);
    block.flags &= ~(1u << 30);
    assert(!qwen_relocate_block(12, 12, &block, &original, &replacement));
    block.flags |= 1u << 30;
    block.flags &= ~(1u << 24);
    assert(!qwen_relocate_block(12, 12, &block, &original, &replacement));
    block.flags |= 1u << 24;
    block.descriptor = &other;
    assert(!qwen_relocate_block(12, 12, &block, &original, &replacement));
    assert(block.descriptor == &other);
    block.descriptor = &original;
    assert(qwen_relocate_block(12, 12, &block, &original, &replacement));
    assert(block.descriptor == &replacement);
    assert(!qwen_relocate_block(12, 12, &block, &original, &replacement));
    puts("Qwen compatibility guard smoke passed");
    return 0;
}
