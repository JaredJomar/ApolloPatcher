#import "header.h"
#import "Image.h"

UITextField *editField;

// Backup/restore schema
static NSString *const kBackupVersionKey = @"ApolloPatcherBackupVersion";
static NSString *const kBackupCreatedAtKey = @"createdAt";
static NSString *const kBackupSourceBundleKey = @"sourceBundleIdentifier";
static NSString *const kBackupAppDefaultsKey = @"appDefaults";
static NSString *const kBackupPreferenceFilesKey = @"preferenceFiles";
static NSString *const kBackupWarningsKey = @"warnings";
static NSString *const kBackupDomainKey = @"domain";
static NSString *const kBackupFileNameKey = @"fileName";
static NSString *const kBackupSourcePathKey = @"sourcePath";
static NSString *const kBackupScopeKey = @"scope";
static NSString *const kBackupContentsKey = @"contents";
static NSString *const kBackupScopeApp = @"app";
static NSString *const kBackupScopeGroup = @"appGroup";
static NSInteger const kBackupCurrentVersion = 1;

@interface PSTableCell (ApolloPatcher)
@property(readonly, assign, nonatomic) UILabel *textLabel;
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(id)specifier;
@end

@interface CustomButtonCell : PSTableCell
@end

@implementation CustomButtonCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier specifier:specifier];

    if (self) {
        self.detailTextLabel.text = specifier.properties[@"subtitle"] ?: nil;
        //self.detailTextLabel.textColor = [UIColor grayColor];
    }

    return self;
}
@end

@interface redButtonCell : PSTableCell
@end

@implementation redButtonCell
- (void)layoutSubviews {
    [super layoutSubviews];
    // PSButtonCell
    self.textLabel.textColor = [UIColor redColor];
}
@end

@implementation SettingsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"ApolloPatcher";

    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonTapped:)];
    self.navigationItem.rightBarButtonItem = doneButton;
}

- (void)doneButtonTapped:(UIBarButtonItem *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (UIImage *)decodeAndResizeBase64Image:(NSString *)base64String {
    NSURL *imageUrl = [NSURL URLWithString:base64String];
    NSData *imageData = [NSData dataWithContentsOfURL:imageUrl options:NSDataReadingUncached error:nil];
    UIImage *image = [UIImage imageWithData:imageData];

    const CGFloat imageSize = 40;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(imageSize, imageSize)];
    UIImage *resizedImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, imageSize, imageSize) cornerRadius:20.0] addClip];
        [image drawInRect:CGRectMake(0, 0, imageSize, imageSize)];
    }];

    return resizedImage;
}

- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *specifiers = [NSMutableArray array];
        PSSpecifier *spec;

        spec = [PSSpecifier preferenceSpecifierNamed:@"How to Use"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSGroupCell
                                                edit:nil];
        [spec setProperty:@"You will need to set up \"Apollo for Reddit\" to use it as your personal app." forKey:@"footerText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Description"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSLinkCell
                                                edit:nil];
        spec->action = @selector(howtoUse);
        [spec setProperty:[self decodeAndResizeBase64Image:b64Willfeeltips] forKey:@"iconImage"];
        [spec setProperty:@1 forKey:@"alignment"];
        [spec setProperty:NSClassFromString(@"PSSubtitleDisclosureTableCell") forKey:@"cellClass"];
        [spec setProperty:@"ApolloPatcher | ichitaso's Repository" forKey:@"cellSubtitleText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Custom API"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSGroupCell
                                                edit:nil];
        [spec setProperty:@"Get the Client IDs of Reddit and Imgur and enter them separately. Redirect URI and User Agent are pre-filled for the Dystopia method and can be changed." forKey:@"footerText"];
        [specifiers addObject:spec];

        PSTextFieldSpecifier *textspec;

        textspec = [PSTextFieldSpecifier preferenceSpecifierNamed:@"Reddit API Key"
                                                           target:self
                                                              set:@selector(setPreferenceValue:specifier:)
                                                              get:@selector(readPreferenceValue:)
                                                           detail:nil
                                                             cell:PSEditTextCell
                                                             edit:nil];
        [textspec setProperty:@"Custom_ID" forKey:@"key"];
        [textspec setPlaceholder:@"Reddit API Key"];
        [specifiers addObject:textspec];

        textspec = [PSTextFieldSpecifier preferenceSpecifierNamed:@"Imgur API Key"
                                                           target:self
                                                              set:@selector(setPreferenceValue:specifier:)
                                                              get:@selector(readPreferenceValue:)
                                                           detail:nil
                                                             cell:PSEditTextCell
                                                             edit:nil];
[textspec setProperty:@"IMGUR_ID" forKey:@"key"];
[textspec setPlaceholder:@"Imgur API Key"];
[specifiers addObject:textspec];

textspec = [PSTextFieldSpecifier preferenceSpecifierNamed:@"Redirect URI"
                                                   target:self
                                                      set:@selector(setPreferenceValue:specifier:)
                                                      get:@selector(readPreferenceValue:)
                                                   detail:nil
                                                     cell:PSEditTextCell
                                                     edit:nil];
[textspec setProperty:@"REDIRECT_URI" forKey:@"key"];
[textspec setProperty:@"dystopia://response" forKey:@"default"];
[textspec setPlaceholder:@"dystopia://response"];
[specifiers addObject:textspec];

textspec = [PSTextFieldSpecifier preferenceSpecifierNamed:@"User Agent"
                                                   target:self
                                                      set:@selector(setPreferenceValue:specifier:)
                                                      get:@selector(readPreferenceValue:)
                                                   detail:nil
                                                     cell:PSEditTextCell
                                                     edit:nil];
[textspec setProperty:@"USER_AGENT" forKey:@"key"];
[textspec setProperty:@"ios:com.CarbonDev.Dystopia:v1.0.1(by /u/DystopiaForReddit)" forKey:@"default"];
[textspec setPlaceholder:@"ios:com.CarbonDev.Dystopia:v1.0.1(by /u/DystopiaForReddit)"];
[specifiers addObject:textspec];

        spec = [PSSpecifier emptyGroupSpecifier];
        [spec setProperty:@"After setting, tap Apply and close the application to activate it." forKey:@"footerText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Video"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSGroupCell
                                                edit:nil];
        [spec setProperty:@"Video playback and audio behavior." forKey:@"footerText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Playback Speed"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSGroupCell
                                                edit:nil];
        [spec setProperty:@"Long-press video → Playback Speed menu now includes 0.75× and 1.25×." forKey:@"footerText"];
        [specifiers addObject:spec];

        PSSegmentedControlSpecifier *segmentspec = [PSSegmentedControlSpecifier preferenceSpecifierNamed:@"Unmute Videos in Comments"
                                                                      target:self
                                                                         set:@selector(setPreferenceValue:specifier:)
                                                                         get:@selector(readPreferenceValue:)
                                                                      detail:nil
                                                                        cell:PSSegmentedControlCell
                                                                        edit:nil];
        [segmentspec setProperty:@"UNMUTE_COMMENTS" forKey:@"key"];
        [segmentspec setProperty:@[@"Never", @"Remember from Full Screen", @"Always"] forKey:@"segmentTitles"];
        [segmentspec setProperty:@0 forKey:@"default"];
        [specifiers addObject:segmentspec];

        segmentspec = [PSSegmentedControlSpecifier preferenceSpecifierNamed:@"Unmute Videos in Feed"
                                                                      target:self
                                                                         set:@selector(setPreferenceValue:specifier:)
                                                                         get:@selector(readPreferenceValue:)
                                                                      detail:nil
                                                                        cell:PSSegmentedControlCell
                                                                        edit:nil];
        [segmentspec setProperty:@"UNMUTE_FEED" forKey:@"key"];
        [segmentspec setProperty:@[@"Never", @"Remember", @"Always"] forKey:@"segmentTitles"];
        [segmentspec setProperty:@0 forKey:@"default"];
        [specifiers addObject:segmentspec];

        spec = [PSSpecifier emptyGroupSpecifier];
        [spec setProperty:@"After setting, tap Apply and close the application to activate it." forKey:@"footerText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Apply"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSButtonCell
                                                edit:nil];

        spec->action = @selector(tapClose);
        [spec setProperty:@2 forKey:@"alignment"];
        [specifiers addObject:spec];

        spec = [PSSpecifier emptyGroupSpecifier];
        [spec setProperty:@"Reset settings and close the application." forKey:@"footerText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Reset Settings"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSButtonCell
                                                edit:nil];

        spec->action = @selector(tapReset);
        [spec setProperty:@2 forKey:@"alignment"];
        [spec setProperty:NSClassFromString(@"redButtonCell") forKey:@"cellClass"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Backup"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSGroupCell
                                                edit:nil];
        [spec setProperty:@"Exports Apollo settings, favorites, and API keys. Subscriptions and followed users sync from your Reddit account after login." forKey:@"footerText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Export Backup"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSButtonCell
                                                edit:nil];
        spec->action = @selector(exportBackup);
        [spec setProperty:@2 forKey:@"alignment"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Import Backup"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSButtonCell
                                                edit:nil];
        spec->action = @selector(importBackup);
        [spec setProperty:@2 forKey:@"alignment"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Credits"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSGroupCell
                                                edit:nil];
        [spec setProperty:@"© Will feel Tips by ichitaso" forKey:@"footerText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"X (Twitter)"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSButtonCell
                                                edit:nil];

        spec->action = @selector(openTwitter);
        [spec setProperty:[self decodeAndResizeBase64Image:b64ichitaso] forKey:@"iconImage"];
        [spec setProperty:@1 forKey:@"alignment"];
        [spec setProperty:NSClassFromString(@"CustomButtonCell") forKey:@"cellClass"];
        [spec setProperty:@"@ichitaso" forKey:@"subtitle"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Souce Code"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSLinkCell
                                                edit:nil];
        spec->action = @selector(openGitHub);
        [spec setProperty:[self decodeAndResizeBase64Image:b64GitHub] forKey:@"iconImage"];
        [spec setProperty:@1 forKey:@"alignment"];
        [spec setProperty:NSClassFromString(@"PSSubtitleDisclosureTableCell") forKey:@"cellClass"];
        [spec setProperty:@"Open source on GitHub" forKey:@"cellSubtitleText"];
        [specifiers addObject:spec];

        spec = [PSSpecifier preferenceSpecifierNamed:@"Donate"
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:nil
                                                cell:PSLinkCell
                                                edit:nil];
        spec->action = @selector(donate);
        [spec setProperty:[self decodeAndResizeBase64Image:b64Paypal] forKey:@"iconImage"];
        [spec setProperty:@1 forKey:@"alignment"];
        [spec setProperty:NSClassFromString(@"PSSubtitleDisclosureTableCell") forKey:@"cellClass"];
        [spec setProperty:@"If you like my work, Please a donation." forKey:@"cellSubtitleText"];
        [specifiers addObject:spec];

        _specifiers = [specifiers copy];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    @autoreleasepool {
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:[specifier identifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self reloadSpecifiers];
    }
}

- (id)readPreferenceValue:(PSSpecifier*)specifier {
    @autoreleasepool {
        return [[NSUserDefaults standardUserDefaults] objectForKey:[specifier identifier]] ?:[[specifier properties] objectForKey:@"default"];
    }
}

- (void)_returnKeyPressed:(id)arg1 {
    [super _returnKeyPressed:arg1];
    [self.view endEditing:YES];
}

- (void)tapClose {
    [[UIApplication sharedApplication] closeAppAnimatedExit];
}

- (void)tapReset {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"Custom_ID"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"IMGUR_ID"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"REDIRECT_URI"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"USER_AGENT"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UNMUTE_COMMENTS"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UNMUTE_FEED"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"FEED_UNMUTED_MEMORY"];
    [[UIApplication sharedApplication] closeAppAnimatedExit];
}

- (void)openTwitter {
    NSString *twitterID = @"ichitaso";

    alertController = [UIAlertController
                       alertControllerWithTitle:[NSString stringWithFormat:@"Follow @%@",twitterID]
                       message:nil
                       preferredStyle:UIAlertControllerStyleActionSheet];

    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitter://"]]) {
        [alertController addAction:[UIAlertAction actionWithTitle:@"Open in Twitter" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"twitter://user?screen_name=%@",twitterID]]
                                               options:@{}
                                     completionHandler:nil];
        }]];
    }
    [alertController addAction:[UIAlertAction actionWithTitle:@"Open in Browser" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self openURLInBrowser:[NSString stringWithFormat:@"https://twitter.com/%@",twitterID]];
        });
    }]];
    // Fix Crash for iPad
    if (IS_PAD) {
        CGRect rect = self.view.frame;
        alertController.popoverPresentationController.sourceView = self.view;
        alertController.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(rect)-60,rect.size.height-50, 120,50);
        alertController.popoverPresentationController.permittedArrowDirections = 0;
    } else {
        [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {}]];
    }

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)howtoUse {
    NSString *urlStr = @"https://cydia.ichitaso.com/depiction/apollopatcher.html";

    alertController = [UIAlertController
                       alertControllerWithTitle:nil
                       message:nil
                       preferredStyle:UIAlertControllerStyleActionSheet];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Open in Safari" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr]
                                           options:@{}
                                 completionHandler:nil];
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Open in Browser" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self openURLInBrowser:urlStr];
        });
    }]];
    // Fix Crash for iPad
    if (IS_PAD) {
        CGRect rect = self.view.frame;
        alertController.popoverPresentationController.sourceView = self.view;
        alertController.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(rect)-60,rect.size.height-50, 120,50);
        alertController.popoverPresentationController.permittedArrowDirections = 0;
    } else {
        [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {}]];
    }

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)openGitHub {
    [self openURLInBrowser:@"https://github.com/ichitaso/ApolloPatcher"];
}

- (void)donate {
    [self openURLInBrowser:@"https://cydia.ichitaso.com/donation.html"];
}

- (void)openURLInBrowser:(NSString *)url {
    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:url]];
    [self presentViewController:safari animated:YES completion:nil];
}
// PSEDitCell Add Clear Button
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];

    if ([cell isKindOfClass:objc_getClass("PSEditableTableCell")]) {
        PSEditableTableCell *editableCell = (PSEditableTableCell *)cell;
        if (editableCell.textField) {
            editField = editableCell.textField;
            editField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }
    }
    
    return cell;
}

// MARK: Backup

- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportBackup {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Export Backup"
                                                                    message:@"The backup will contain your Apollo settings, favorites, and API keys. It does not contain your Reddit login. Continue?"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Export" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self performExport];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performExport {
    NSMutableArray *preferenceFiles = [NSMutableArray array];
    NSMutableArray *warnings = [NSMutableArray array];

    NSString *appBundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *appPrefsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"];
    NSString *appDomainPlist = [appBundleId stringByAppendingString:@".plist"];
    [self collectPreferenceFilesFromDirectory:appPrefsDir
                                 excludedFile:appDomainPlist
                                        scope:kBackupScopeApp
                                    intoFiles:preferenceFiles
                                     warnings:warnings];

    NSString *appGroupRoot = @"/var/mobile/Containers/Shared/AppGroup";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *groupDirs = [fm contentsOfDirectoryAtPath:appGroupRoot error:NULL];
    if (groupDirs) {
        for (NSString *groupDir in groupDirs) {
            NSString *groupPrefsDir = [appGroupRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/Library/Preferences", groupDir]];
            [self collectPreferenceFilesFromDirectory:groupPrefsDir
                                         excludedFile:nil
                                                scope:kBackupScopeGroup
                                            intoFiles:preferenceFiles
                                             warnings:warnings];
        }
    } else {
        [warnings addObject:@"App group container is not accessible on this device."];
    }

    NSDictionary *appDefaults = [[NSUserDefaults standardUserDefaults] persistentDomainForName:appBundleId];

    NSMutableDictionary *backup = [NSMutableDictionary dictionary];
    backup[kBackupVersionKey] = @(kBackupCurrentVersion);
    backup[kBackupCreatedAtKey] = [NSDate date];
    backup[kBackupSourceBundleKey] = appBundleId;
    backup[kBackupAppDefaultsKey] = appDefaults ?: @{};
    backup[kBackupPreferenceFilesKey] = preferenceFiles;
    if (warnings.count > 0) {
        backup[kBackupWarningsKey] = warnings;
    }

    NSError *error = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:backup
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&error];
    if (error || !plistData) {
        [self showErrorAlertWithTitle:@"Export Failed" message:(error.localizedDescription ?: @"Could not create the backup file.")];
        return;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *fileName = [NSString stringWithFormat:@"ApolloPatcher-backup-%@.plist", [formatter stringFromDate:[NSDate date]]];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    if (![plistData writeToFile:tempPath atomically:YES]) {
        [self showErrorAlertWithTitle:@"Export Failed" message:@"Could not write the backup file."];
        return;
    }

    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:tempPath]] applicationActivities:nil];
    if (IS_PAD) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)collectPreferenceFilesFromDirectory:(NSString *)dirPath
                               excludedFile:(NSString *)excludedFile
                                      scope:(NSString *)scope
                                  intoFiles:(NSMutableArray *)files
                                   warnings:(NSMutableArray *)warnings {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:dirPath error:NULL];
    for (NSString *name in names) {
        if (![name hasSuffix:@".plist"]) continue;
        if (excludedFile && [name isEqualToString:excludedFile]) continue;
        if ([name hasPrefix:@"com.apple."]) continue;
        if ([scope isEqualToString:kBackupScopeGroup] && ![self isApolloRelatedPreferenceFile:name]) {
            [warnings addObject:[NSString stringWithFormat:@"Skipped unrelated app-group file: %@", name]];
            continue;
        }
        NSString *fullPath = [dirPath stringByAppendingPathComponent:name];
        NSDictionary *contents = [NSDictionary dictionaryWithContentsOfFile:fullPath];
        if (!contents) {
            [warnings addObject:[NSString stringWithFormat:@"Skipped unreadable file: %@", name]];
            continue;
        }
        [files addObject:@{
            kBackupDomainKey: [name stringByDeletingPathExtension],
            kBackupFileNameKey: name,
            kBackupSourcePathKey: fullPath,
            kBackupScopeKey: scope,
            kBackupContentsKey: contents
        }];
    }
}

- (BOOL)isApolloRelatedPreferenceFile:(NSString *)name {
    NSString *lower = [name lowercaseString];
    return [lower containsString:@"christianselig"] || [lower containsString:@"apollo"];
}

- (void)importBackup {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.apple.property-list", @"public.data"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self handlePickedBackupURL:url];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    [self handlePickedBackupURL:urls[0]];
}

- (void)handlePickedBackupURL:(NSURL *)url {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) {
        [self showErrorAlertWithTitle:@"Import Failed" message:@"Could not read the selected file."];
        return;
    }
    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
    if (error || ![plist isKindOfClass:[NSDictionary class]]) {
        [self showErrorAlertWithTitle:@"Import Failed" message:@"The selected file is not a valid ApolloPatcher backup."];
        return;
    }
    NSDictionary *backup = plist;

    NSNumber *version = backup[kBackupVersionKey];
    if (![version isKindOfClass:[NSNumber class]] || version.integerValue != kBackupCurrentVersion) {
        [self showErrorAlertWithTitle:@"Import Failed" message:@"This backup was created by an unsupported version."];
        return;
    }
    if (![backup[kBackupAppDefaultsKey] isKindOfClass:[NSDictionary class]] || ![backup[kBackupPreferenceFilesKey] isKindOfClass:[NSArray class]]) {
        [self showErrorAlertWithTitle:@"Import Failed" message:@"The backup file is malformed."];
        return;
    }

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Restore Backup"
                                                                    message:@"This will replace Apollo's settings and favorites with the backup, then restart Apollo. Continue?"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self applyBackup:backup];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)applyBackup:(NSDictionary *)backup {
    NSString *appBundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSDictionary *appDefaults = backup[kBackupAppDefaultsKey];
    NSArray *preferenceFiles = backup[kBackupPreferenceFilesKey];

    [[NSUserDefaults standardUserDefaults] setPersistentDomain:appDefaults forName:appBundleId];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSInteger restoredCount = 0;
    NSMutableArray *failedFiles = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSDictionary *entry in preferenceFiles) {
        NSString *fileName = entry[kBackupFileNameKey];
        NSString *domain = entry[kBackupDomainKey];
        NSString *scope = entry[kBackupScopeKey];
        NSDictionary *contents = entry[kBackupContentsKey];
        if (![fileName isKindOfClass:[NSString class]] || ![contents isKindOfClass:[NSDictionary class]]) {
            [failedFiles addObject:(fileName ?: @"unknown")];
            continue;
        }

        BOOL restored = NO;

        // Prefer the suite API so cfprefsd keeps its cache coherent.
        if ([domain isKindOfClass:[NSString class]] && domain.length > 0) {
            NSUserDefaults *suiteDefaults = [[NSUserDefaults alloc] initWithSuiteName:domain];
            if (suiteDefaults) {
                for (NSString *key in contents) {
                    [suiteDefaults setObject:contents[key] forKey:key];
                }
                restored = [suiteDefaults synchronize];
            }
        }

        // Also ensure the file lands on disk at the current container path.
        NSString *destination = [self resolvedDestinationForFile:fileName scope:scope];
        if (destination) {
            NSString *dir = [destination stringByDeletingLastPathComponent];
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
            NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:contents format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
            if (plistData && [plistData writeToFile:destination atomically:YES]) {
                restored = YES;
            }
        }

        if (restored) {
            restoredCount++;
        } else {
            [failedFiles addObject:fileName];
        }
    }

    NSMutableString *summary = [NSMutableString stringWithFormat:@"Restored %lu settings and %ld preference file(s).", (unsigned long)appDefaults.count, (long)restoredCount];
    if (failedFiles.count > 0) {
        [summary appendFormat:@"\n\nCould not restore %lu file(s): %@", (unsigned long)failedFiles.count, [failedFiles componentsJoinedByString:@", "]];
    }

    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Backup Restored" message:summary preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"Restart Apollo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] closeAppAnimatedExit];
    }]];
    [self presentViewController:done animated:YES completion:nil];
}

- (NSString *)resolvedDestinationForFile:(NSString *)fileName scope:(NSString *)scope {
    if ([scope isEqualToString:kBackupScopeApp]) {
        return [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/Preferences/%@", fileName]];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = @"/var/mobile/Containers/Shared/AppGroup";
    NSArray *groupDirs = [fm contentsOfDirectoryAtPath:root error:NULL];
    for (NSString *groupDir in groupDirs) {
        NSString *candidate = [root stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/Library/Preferences/%@", groupDir, fileName]];
        if ([fm fileExistsAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

@end
