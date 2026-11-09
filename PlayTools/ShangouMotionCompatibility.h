#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <string.h>
#include <sys/sysctl.h>

// shortcut: revalidate the virtual-device failure before supporting another IPA or macOS build.
static int shangou_motion_image_matches(const struct mach_header_64 *header) {
    static const unsigned char uuid[16] = {
        0x54, 0x31, 0x15, 0x7e, 0x30, 0x50, 0x3d, 0x18,
        0xad, 0xf1, 0xd0, 0xd6, 0x2d, 0x65, 0xc0, 0xf9
    };
    if (!header || header->magic != MH_MAGIC_64) return 0;
    const unsigned char *cursor = (const unsigned char *)(header + 1);
    size_t remaining = header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (remaining < sizeof(struct load_command)) return 0;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > remaining) return 0;
        if (command->cmd == LC_UUID) {
            return command->cmdsize >= sizeof(struct uuid_command) &&
                memcmp(((const struct uuid_command *)command)->uuid, uuid, sizeof(uuid)) == 0;
        }
        cursor += command->cmdsize;
        remaining -= command->cmdsize;
    }
    return 0;
}

static int shangou_motion_is_unsupported(const struct mach_header_64 *header,
                                          const char *hostBuild, int hasVirtualDevice) {
    return hasVirtualDevice && hostBuild &&
        (strcmp(hostBuild, "26B123") == 0 || strcmp(hostBuild, "23C71") == 0 ||
         strcmp(hostBuild, "24G517") == 0) &&
        shangou_motion_image_matches(header);
}

@interface CMMotionManager (ShangouMotionCompatibility)
+ (instancetype)allocPlayToolsUnavailableMotionWithZone:(NSZone *)zone __attribute__((objc_method_family(alloc)));
@end

@implementation CMMotionManager (ShangouMotionCompatibility)
+ (instancetype)allocPlayToolsUnavailableMotionWithZone:(NSZone *)zone {
    // No instance is allocated: even deallocating an uninitialized CoreMotion manager is unsafe here.
    return nil;
}
@end

static void shangou_install_unavailable_motion(void) {
    Method replacement = class_getClassMethod(CMMotionManager.class, @selector(allocPlayToolsUnavailableMotionWithZone:));
    class_replaceMethod(object_getClass(CMMotionManager.class), @selector(allocWithZone:),
                        method_getImplementation(replacement), method_getTypeEncoding(replacement));
}

static int shangou_should_disable_motion(void) {
    char build[64] = {0};
    size_t size = sizeof(build);
    if (sysctlbyname("kern.osversion", build, &size, NULL, 0) != 0 || size >= sizeof(build)) return 0;
    return shangou_motion_is_unsupported((const struct mach_header_64 *)_dyld_get_image_header(0),
                                         build, objc_getClass("UINSVirtualMotionDevice") != Nil);
}
