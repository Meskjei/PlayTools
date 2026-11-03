#import <Foundation/Foundation.h>
#include <assert.h>
#define PLAYTOOLS_SHANGOU_ACTIVITY_TEST 1
#include "../../PlayTools/ShangouLiveActivityCompatibility.h"

extern void *_Block_copy(const void *);
extern void _Block_release(const void *);
static int calls, destroyed;
@interface Capture : NSObject
- (void)run;
@end
@implementation Capture
- (void)run { calls++; }
- (void)dealloc { destroyed++; [super dealloc]; }
@end
static void callback(void) { calls++; }

int main(void) {
    @autoreleasepool {
        struct { struct mach_header_64 header; struct uuid_command uuid; } image = {0};
        image.header.magic = MH_MAGIC_64; image.header.cputype = CPU_TYPE_ARM64;
        image.header.ncmds = 1; image.header.sizeofcmds = sizeof(image.uuid);
        image.uuid.cmd = LC_UUID; image.uuid.cmdsize = sizeof(image.uuid);
        memcpy(image.uuid.uuid, shangou_activity_app_uuid, 16);
        assert(shangou_activity_host_matches(&image.header, "23C71"));
        assert(shangou_activity_host_matches(&image.header, "26B123"));
        assert(!shangou_activity_host_matches(&image.header, "23C72"));
        assert(!shangou_activity_host_matches(&image.header, NULL));
        image.uuid.uuid[0] ^= 1;
        assert(!shangou_activity_host_matches(&image.header, "23C71"));
        memcpy(image.uuid.uuid, shangou_activity_widget_uuid, 16);
        assert(shangou_activity_image_matches(&image.header, shangou_activity_widget_uuid));
        image.uuid.cmdsize++;
        assert(!shangou_activity_image_matches(&image.header, shangou_activity_widget_uuid));

        uintptr_t base = 0x100000000;
        struct ShangouActivityBlock block = { .flags = (1u << 25) | (1u << 30),
            .invoke = (void *)(base + 0x25ebc), .function = (void *)(base + 0x46834) };
        assert(shangou_activity_is_initializer(base + 0x38b20, base, &block));
        assert(!shangou_activity_is_initializer(base + 0x38b24, base, &block));
        assert(!shangou_activity_is_initializer(base + 0x38b20, 0, &block));
        assert(!shangou_activity_is_initializer(base + 0x38b20, base, NULL));
        block.flags |= 1u << 24;
        assert(!shangou_activity_is_initializer(base + 0x38b20, base, &block));
        block.flags ^= 1u << 24; block.function = (void *)(base + 0x46838);
        assert(!shangou_activity_is_initializer(base + 0x38b20, base, &block));

        // A real compiler-generated block proves retained captures are disposed by the original descriptor.
        Capture *capture = [Capture new];
        void (*fn)(void) = callback;
        void (^source)(void) = ^{ fn(); [capture run]; };
        const struct ShangouActivityBlock *raw = (const void *)source;
        void (*invoke)(void *) = raw->invoke;
        const void *descriptor = raw->descriptor;
        struct ShangouActivityBlock *normal = _Block_copy(source);
        ((void (^)(void))normal)();
        assert(calls == 2); _Block_release(normal);
        struct ShangouActivityBlock *copy = _Block_copy(source);
        assert(shangou_activity_disable_copy(copy, raw));
        assert(raw->invoke == invoke && copy->descriptor == descriptor);
        [capture release]; assert(destroyed == 0);
        ((void (^)(void))copy)(); assert(calls == 2);
        assert(!shangou_activity_disable_copy(copy, copy));
        _Block_release(copy); assert(destroyed == 1);
        puts("Shangou Live Activity identity, callback isolation and capture lifetime passed");
    }
}
