// ApolloAppIconChanger.xm
//
// App Icon Changer feature for ApolloPatcher.
// Allows users to change the app icon from Settings.

#import "header.h"
#import <UIKit/UIKit.h>

static NSString *const kAppIconKey = @"AppIcon";

%hook UIApplication

- (void)setAlternateIconName:(NSString *)iconName completionHandler:(void (^)(NSError *))completionHandler {
    NSString *selectedIcon = [[NSUserDefaults standardUserDefaults] stringForKey:kAppIconKey];
    if (selectedIcon && selectedIcon.length > 0 && ![selectedIcon isEqualToString:@"default"]) {
        %orig(selectedIcon, completionHandler);
    } else {
        %orig(iconName, completionHandler);
    }
}

- (NSArray<NSString *> *)supportsAlternateIcons {
    return @[@"default", @"icon-blue", @"icon-red", @"icon-green", @"icon-purple", @"icon-orange", @"icon-pink", @"icon-teal", @"icon-gold", @"icon-dark"];
}

%end