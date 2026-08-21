#import "SettingsController.h"
#import "header.h"
#import "Image.h"
#import <SafariServices/SafariServices.h>

static NSString *const kCustomIDKey = @"Custom_ID";
static NSString *const kImgurIDKey = @"IMGUR_ID";
static NSString *const kRedirectURIKey = @"REDIRECT_URI";
static NSString *const kUserAgentKey = @"USER_AGENT";
static NSString *const kUnmuteCommentsKey = @"UNMUTE_COMMENTS";
static NSString *const kUnmuteFeedKey = @"UNMUTE_FEED";
static NSString *const kFeedUnmutedMemoryKey = @"FEED_UNMUTED_MEMORY";
static NSString *const kHoldSpeedKey = @"HOLD_SPEED";

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
        case 0: return 1; // Info
        case 1: return 4; // Custom API
        case 2: return 3; // Video Playback
        case 3: return 3; // Auto-unmute
        case 4: return 1; // Hold Speed
        case 5: return 4; // Links & Credits
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
            cell.textLabel.text = @"ApolloPatcher";
            cell.detailTextLabel.text = @"v0.1.1";
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
            
        case 5: // Links & Credits
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"GitHub Repository";
                    cell.detailTextLabel.text = @"github.com/ichitaso/ApolloPatcher";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 1:
                    cell.textLabel.text = @"Twitter / X";
                    cell.detailTextLabel.text = @"@ichitaso";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2:
                    cell.textLabel.text = @"Donate";
                    cell.detailTextLabel.text = @"Support the developer";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 3:
                    cell.textLabel.text = @"How to Use";
                    cell.detailTextLabel.text = @"Setup guide";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
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
        case 5: return @"Links & Credits";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 1: return @"Get Client IDs from reddit.com/prefs/apps and api.imgur.com/oauth2/addclient. Redirect URI & User Agent pre-filled for Dystopia method.";
        case 2: return @"Long-press video → Playback Speed menu now includes 0.75× and 1.25×. Requires app restart.";
        case 3: return @"Controls automatic unmuting of videos. 'Remember' modes persist your manual mute/unmute choice.";
        case 4: return @"Playback speed when holding on a video. Default is 2.0x. Requires app restart.";
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
        case 5: // Links
            [self handleLinkRow:indexPath.row];
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

@end