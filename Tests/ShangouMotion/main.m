#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <assert.h>

static int initialized, destroyed, started;
@interface CMMotionManager : NSObject
- (BOOL)isAccelerometerAvailable;
- (void)startAccelerometerUpdates;
- (void)startAccelerometerUpdatesToQueue:(id)queue withHandler:(id)handler;
@end
@implementation CMMotionManager
- (instancetype)init { initialized++; return [super init]; }
- (void)dealloc { destroyed++; }
- (BOOL)isAccelerometerAvailable { return YES; }
- (void)startAccelerometerUpdates { started++; }
- (void)startAccelerometerUpdatesToQueue:(id)queue withHandler:(id)handler { started++; }
@end

#include "../../PlayTools/ShangouMotionCompatibility.h"

int main(void) {
    @autoreleasepool {
        struct { struct mach_header_64 header; struct uuid_command uuid; } image = {0};
        image.header.magic = MH_MAGIC_64;
        image.header.ncmds = 1;
        image.header.sizeofcmds = sizeof(image.uuid);
        image.uuid.cmd = LC_UUID;
        image.uuid.cmdsize = sizeof(image.uuid);
        const unsigned char uuid[] = {0x54,0x31,0x15,0x7e,0x30,0x50,0x3d,0x18,0xad,0xf1,0xd0,0xd6,0x2d,0x65,0xc0,0xf9};
        memcpy(image.uuid.uuid, uuid, sizeof(uuid));
        assert(shangou_motion_is_unsupported(&image.header, "26B123", 1));
        assert(shangou_motion_is_unsupported(&image.header, "23C71", 1));
        assert(shangou_motion_is_unsupported(&image.header, "24G517", 1));
        assert(!shangou_motion_is_unsupported(&image.header, "24G516", 1));
        assert(!shangou_motion_is_unsupported(&image.header, "24G518", 1));
        assert(!shangou_motion_is_unsupported(&image.header, "24G517", 0));
        assert(!shangou_motion_is_unsupported(&image.header, "23C72", 1));
        assert(!shangou_motion_is_unsupported(&image.header, "23C71", 0));
        assert(!shangou_motion_is_unsupported(&image.header, "26B124", 1));
        assert(!shangou_motion_is_unsupported(&image.header, "26B123", 0));
        assert(!shangou_motion_is_unsupported(&image.header, NULL, 1));
        image.uuid.uuid[0] ^= 1;
        assert(!shangou_motion_is_unsupported(&image.header, "26B123", 1));
        assert(!shangou_motion_is_unsupported(&image.header, "23C71", 1));
        assert(!shangou_motion_is_unsupported(&image.header, "24G517", 1));
        image.uuid.uuid[0] ^= 1;
        image.uuid.cmdsize++;
        assert(!shangou_motion_image_matches(&image.header));
        assert(!shangou_motion_image_matches(NULL));

        @autoreleasepool {
            CMMotionManager *normal = [[CMMotionManager alloc] init]; assert(normal.isAccelerometerAvailable);
            [normal startAccelerometerUpdates];
        }
        assert(initialized == 1 && destroyed == 1);
        shangou_install_unavailable_motion();
        for (int i = 0; i < 100; i++) {
            assert([[CMMotionManager alloc] init] == nil);
            assert([CMMotionManager new] == nil);
            assert([CMMotionManager allocWithZone:NULL] == nil);
        }
        assert(initialized == 1 && destroyed == 1 && started == 1);
        puts("Shangou motion guards and no-allocation ownership passed");
    }
}
