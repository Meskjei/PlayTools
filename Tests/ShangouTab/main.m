#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <assert.h>

@interface UIColor : NSObject
@property(nonatomic) CGFloat alpha;
@property(nonatomic,readonly) CGColorRef CGColor;
+ (instancetype)systemBackgroundColor;
@end
@implementation UIColor
- (CGColorRef)CGColor { return (__bridge CGColorRef)self; }
+ (instancetype)systemBackgroundColor { static UIColor *color; if (!color) { color = [UIColor new]; color.alpha = 1; } return color; }
@end
static CGFloat testColorAlpha(CGColorRef color) { return ((__bridge UIColor *)color).alpha; }
#define CGColorGetAlpha testColorAlpha
@interface UITabBarAppearance : NSObject
@property(nonatomic,strong) UIColor *backgroundColor;
@property(nonatomic,strong) id backgroundEffect;
@end
@implementation UITabBarAppearance @end
static int layouts;
@interface UITabBar : NSObject
@property(nonatomic,strong) UIColor *backgroundColor;
@property(nonatomic,strong) id backgroundImage;
@property(nonatomic,strong) UITabBarAppearance *standardAppearance;
@property(nonatomic,strong) UITabBarAppearance *scrollEdgeAppearance;
- (void)layoutSubviews;
@end
@implementation UITabBar
- (void)layoutSubviews { layouts++; }
@end
@interface NVMTabBar : UITabBar @end
@implementation NVMTabBar @end
static BOOL targetImage;
static int shangou_motion_image_matches(const struct mach_header_64 *header) { return targetImage; }
#include "../../PlayTools/ShangouTabCompatibility.h"
int main(void) {
 @autoreleasepool {
  NVMTabBar *bar = [NVMTabBar new];
  bar.standardAppearance = [UITabBarAppearance new]; bar.scrollEdgeAppearance = [UITabBarAppearance new];
  shangou_install_tab_compatibility(); [bar layoutSubviews]; assert(!bar.backgroundColor && layouts == 1);
  targetImage = YES; shangou_install_tab_compatibility(); [bar layoutSubviews];
  assert(bar.backgroundColor == UIColor.systemBackgroundColor && layouts == 2);
  UIColor *custom = [UIColor new]; custom.alpha = 1; bar.backgroundColor = custom; [bar layoutSubviews]; assert(bar.backgroundColor == custom);
  bar.backgroundColor = nil; bar.backgroundImage = [NSObject new]; [bar layoutSubviews]; assert(!bar.backgroundColor); bar.backgroundImage = nil;
  bar.standardAppearance.backgroundEffect = [NSObject new]; [bar layoutSubviews]; assert(!bar.backgroundColor); bar.standardAppearance.backgroundEffect = nil;
  bar.scrollEdgeAppearance.backgroundColor = custom; [bar layoutSubviews]; assert(!bar.backgroundColor); bar.scrollEdgeAppearance.backgroundColor = nil;
  bar.backgroundColor = [UIColor new]; bar.backgroundColor.alpha = 0; [bar layoutSubviews]; assert(bar.backgroundColor == UIColor.systemBackgroundColor);
  UITabBar *other = [UITabBar new]; [other layoutSubviews]; assert(!other.backgroundColor);
  puts("Shangou-only backdrop fallback preserves custom backgrounds, material, superclass layout and other tab bars");
 }
}
