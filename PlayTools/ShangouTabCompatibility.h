// shortcut: only this imported Shangou build has been validated on Mac; revalidate other IPAs before extending the guard.
static BOOL shangou_tab_has_visible_color(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) > 0.01;
}
static BOOL shangou_tab_needs_backdrop(UITabBar *bar) {
    if (shangou_tab_has_visible_color(bar.backgroundColor) || bar.backgroundImage) return NO;
    UITabBarAppearance *standard = bar.standardAppearance, *edge = bar.scrollEdgeAppearance;
    return !shangou_tab_has_visible_color(standard.backgroundColor) && !standard.backgroundEffect &&
           !shangou_tab_has_visible_color(edge.backgroundColor) && !edge.backgroundEffect;
}
static IMP shangou_tab_original_layout;
static void shangou_tab_layout(UITabBar *bar, SEL command) {
    ((void (*)(id, SEL))shangou_tab_original_layout)(bar, command);
    // This build explicitly hides both appearance backgrounds. Supply a themed base on Mac
    // without replacing the app's item appearance, custom cover views, or hit targets.
    if (shangou_tab_needs_backdrop(bar)) bar.backgroundColor = UIColor.systemBackgroundColor;
}
static void shangou_install_tab_compatibility(void) {
    if (!shangou_motion_image_matches((const struct mach_header_64 *)_dyld_get_image_header(0))) return;
    Class cls = NSClassFromString(@"NVMTabBar");
    if (!cls || ![cls isSubclassOfClass:UITabBar.class]) return;
    Method method = class_getInstanceMethod(cls, @selector(layoutSubviews));
    if (!method) return;
    shangou_tab_original_layout = method_getImplementation(method);
    class_replaceMethod(cls, @selector(layoutSubviews), (IMP)shangou_tab_layout, method_getTypeEncoding(method));
}
