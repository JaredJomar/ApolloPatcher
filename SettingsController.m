#import "SettingsController.h"
#import "header.h"
#import "Image.h"
#import <SafariServices/SafariServices.h>
#import <MobileCoreServices/MobileCoreServices.h>

static NSString *const kCustomIDKey = @"Custom_ID";
static NSString *const kImgurIDKey = @"IMGUR_ID";
static NSString *const kRedirectURIKey = @"REDIRECT_URI";
static NSString *const kUserAgentKey = @"USER_AGENT";
static NSString *const kUnmuteCommentsKey = @"UNMUTE_COMMENTS";
static NSString *const kUnmuteFeedKey = @"UNMUTE_FEED";
static NSString *const kFeedUnmutedMemoryKey = @"FEED_UNMUTED_MEMORY";
static NSString *const kHoldSpeedKey = @"HOLD_SPEED";

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

@interface SettingsController ()

@property (nonatomic, strong) NSUserDefaults *defaults;

@end

@implementation SettingsController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _defaults = [NSUserDefaults standardUserDefaults];
        self.title = @"ApolloPatcher";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(resetTapped)];
    
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1.0];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Settings"
                                                                   message:@"This will clear all ApolloPatcher settings and restart Apollo. Continue?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [_defaults removeObjectForKey:kCustomIDKey];
        [_defaults removeObjectForKey:kImgurIDKey];
        [_defaults removeObjectForKey:kRedirectURIKey];
        [_defaults removeObjectForKey:kUserAgentKey];
        [_defaults removeObjectForKey:kUnmuteCommentsKey];
        [_defaults removeObjectForKey:kUnmuteFeedKey];
        [_defaults removeObjectForKey:kFeedUnmutedMemoryKey];
        [_defaults removeObjectForKey:kHoldSpeedKey];
        [_defaults synchronize];
        [[UIApplication sharedApplication] closeAppAnimatedExit];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // Info (version + video audio engine diag)
        case 1: return 4; // Custom API
        case 2: return 3; // Video Playback
        case 3: return 3; // Auto-unmute
        case 4: return 1; // Hold Speed
        case 5: return 3; // Backup + Links
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.tintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        
        UIView *bgView = [[UIView alloc] init];
        bgView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        cell.selectedBackgroundView = bgView;
    }
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
    
    switch (indexPath.section) {
        case 0: // Info
            if (indexPath.row == 0) {
                cell.textLabel.text = @"ApolloPatcher";
                cell.detailTextLabel.text = @"v0.1.1";
            } else {
                cell.textLabel.text = @"Video Audio Engine";
                cell.detailTextLabel.text = [_defaults stringForKey:@"UNMUTE_DIAG"] ?: @"not run yet";
            }
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
            
        case 1: // Custom API
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"Reddit Client ID";
                    cell.detailTextLabel.text = [_defaults stringForKey:kCustomIDKey] ?: @"Not set";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 1:
                    cell.textLabel.text = @"Imgur Client ID";
                    cell.detailTextLabel.text = [_defaults stringForKey:kImgurIDKey] ?: @"Not set";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2:
                    cell.textLabel.text = @"Redirect URI";
                    cell.detailTextLabel.text = [_defaults stringForKey:kRedirectURIKey] ?: @"dystopia://response";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 3:
                    cell.textLabel.text = @"User Agent";
                    cell.detailTextLabel.text = [_defaults stringForKey:kUserAgentKey] ?: @"Dystopia default";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
            }
            break;
            
        case 2: // Video Playback
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Playback Speed";
                cell.detailTextLabel.text = @"0.75×, 1.25× added to menu";
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Hold Speed (long press)";
                float holdSpeed = [_defaults floatForKey:kHoldSpeedKey];
                if (holdSpeed == 0) holdSpeed = 2.0f;
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1fx", holdSpeed];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = @"Reset on App Restart";
                cell.detailTextLabel.text = @"Settings apply after restart";
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            break;
            
        case 3: // Auto-unmute
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Unmute in Comments";
                NSInteger mode = [_defaults integerForKey:kUnmuteCommentsKey];
                static NSArray *titles = @[@"Never", @"Remember from Fullscreen", @"Always"];
                cell.detailTextLabel.text = titles[mode];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Unmute in Feed";
                NSInteger mode = [_defaults integerForKey:kUnmuteFeedKey];
                static NSArray *titles = @[@"Never", @"Remember", @"Always"];
                cell.detailTextLabel.text = titles[mode];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = @"Requires App Restart";
                cell.detailTextLabel.text = @"Changes take effect after restart";
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            break;
            
        case 4: // Hold Speed
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Hold Speed";
                float holdSpeed = [_defaults floatForKey:kHoldSpeedKey];
                if (holdSpeed == 0) holdSpeed = 2.0f;
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1fx (default 2.0x)", holdSpeed];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
            
        case 5: // Backup
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Export Backup";
                cell.detailTextLabel.text = @"Export settings, favorites, API keys";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Import Backup";
                cell.detailTextLabel.text = @"Import from .plist file";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"Links & Credits";
                cell.detailTextLabel.text = @"GitHub, Twitter, Donate, How to Use";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
            
        
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return nil;
        case 1: return @"Custom API (Dystopia Method)";
        case 2: return @"Video Playback Speed";
        case 3: return @"Auto-Unmute Videos";
        case 4: return @"Hold Speed";
        case 5: return @"Backup";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 1: return @"Get Client IDs from reddit.com/prefs/apps and api.imgur.com/oauth2/addclient. Redirect URI & User Agent pre-filled for Dystopia method.";
        case 2: return @"Long-press video → Playback Speed menu now includes 0.75× and 1.25×. Requires app restart.";
        case 3: return @"Controls automatic unmuting of videos. 'Remember' modes persist your manual mute/unmute choice.";
        case 4: return @"Playback speed when holding on a video. Default is 2.0x. Requires app restart.";
        case 5: return @"Export/Import settings, favorites, and API keys. Links to GitHub, Twitter, Donate, How to Use.";
        default: return nil;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    switch (indexPath.section) {
        case 1: // Custom API
            [self showTextFieldAlertForRow:indexPath.row];
            break;
        case 2: // Video Playback
            if (indexPath.row == 1) {
                [self showHoldSpeedAlert];
            }
            break;
        case 3: // Auto-unmute
            if (indexPath.row == 0) {
                [self showSegmentedAlertForKey:kUnmuteCommentsKey title:@"Unmute in Comments" options:@[@"Never", @"Remember from Fullscreen", @"Always"]];
            } else if (indexPath.row == 1) {
                [self showSegmentedAlertForKey:kUnmuteFeedKey title:@"Unmute in Feed" options:@[@"Never", @"Remember", @"Always"]];
            }
            break;
        case 4: // Hold Speed
            [self showHoldSpeedAlert];
            break;
        case 5: // Backup
            if (indexPath.row == 0) {
                [self exportBackup];
            } else if (indexPath.row == 1) {
                [self importBackup];
            } else if (indexPath.row == 2) {
                [self handleLinkRow:indexPath.row];
            }
            break;
    }
}

- (void)showTextFieldAlertForRow:(NSInteger)row {
    NSString *key, *title, *placeholder, *currentValue;
    switch (row) {
        case 0: key = kCustomIDKey; title = @"Reddit Client ID"; placeholder = @"Reddit API Key"; break;
        case 1: key = kImgurIDKey; title = @"Imgur Client ID"; placeholder = @"Imgur API Key"; break;
        case 2: key = kRedirectURIKey; title = @"Redirect URI"; placeholder = @"dystopia://response"; break;
        case 3: key = kUserAgentKey; title = @"User Agent"; placeholder = @"ios:com.CarbonDev.Dystopia:v1.0.1(by /u/DystopiaForReddit)"; break;
        default: return;
    }
    currentValue = [_defaults stringForKey:key] ?: @"";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = placeholder;
        field.text = currentValue;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields[0];
        if (field.text.length > 0) {
            [_defaults setObject:field.text forKey:key];
            [_defaults synchronize];
            [self.tableView reloadData];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSegmentedAlertForKey:(NSString *)key title:(NSString *)title options:(NSArray *)options {
    NSInteger current = [_defaults integerForKey:key];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:@"Select default behavior" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < options.count; i++) {
        UIAlertActionStyle style = (i == current) ? UIAlertActionStyleDefault : UIAlertActionStyleDefault;
        [alert addAction:[UIAlertAction actionWithTitle:options[i] style:style handler:^(UIAlertAction *action) {
            [_defaults setInteger:i forKey:key];
            [_defaults synchronize];
            [self.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showHoldSpeedAlert {
    float current = [_defaults floatForKey:kHoldSpeedKey];
    if (current == 0) current = 2.0f;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hold Speed" message:@"Enter playback speed for long-press (0.5 - 4.0)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"2.0";
        field.text = [NSString stringWithFormat:@"%.1f", current];
        field.keyboardType = UIKeyboardTypeDecimalPad;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *field = alert.textFields[0];
        float value = [field.text floatValue];
        if (value >= 0.5 && value <= 4.0) {
            [_defaults setFloat:value forKey:kHoldSpeedKey];
            [_defaults synchronize];
            [self.tableView reloadData];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleLinkRow:(NSInteger)row {
    NSURL *url = nil;
    switch (row) {
        case 0: url = [NSURL URLWithString:@"https://github.com/ichitaso/ApolloPatcher"]; break;
        case 1: url = [NSURL URLWithString:@"https://twitter.com/ichitaso"]; break;
        case 2: url = [NSURL URLWithString:@"https://cydia.ichitaso.com/donation.html"]; break;
        case 3: url = [NSURL URLWithString:@"https://cydia.ichitaso.com/depiction/apollopatcher.html"]; break;
    }
    if (url) {
        SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safari animated:YES completion:nil];
    }
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

- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end