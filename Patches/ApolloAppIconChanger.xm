// ApolloAppIconChanger.xm
//
// App Icon Changer feature for ApolloPatcher.
// Allows users to change the app icon from Settings.

#import "header.h"
#import <UIKit/UIKit.h>

static NSString *const kAppIconKey = @"AppIcon";

%hook UIApplication

- (BOOL)setAlternateIconName:(NSString * _Nullable)iconName completionHandler:(void (^ _Nullable)(NSError * _Nullable))completionHandler {
    NSString *selectedIcon = [[NSUserDefaults standardUserDefaults] stringForKey:kAppIconKey];
    if (selectedIcon && selectedIcon.length > 0 && ![selectedIcon isEqualToString:@"default"]) {
        return %orig(selectedIcon, completionHandler);
    }
    return %orig(iconName, completionHandler);
}

%new
- (NSArray<NSString *> * _Nullable)supportsAlternateIcons {
    return @[@"default", @"icon-blue", @"icon-red", @"icon-green", @"icon-purple", @"icon-orange", @"icon-pink", @"icon-teal", @"icon-gold", @"icon-dark"];
}
%end

%end