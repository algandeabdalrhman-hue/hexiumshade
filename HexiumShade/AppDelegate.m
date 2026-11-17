#import "AppDelegate.h"
#import "HexiumShadeOverlay.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.025 green:0.045 blue:0.085 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 100, root.view.bounds.size.width - 48, 42)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"HEXIUM SHADE";
    title.textColor = [UIColor colorWithRed:0.62 green:0.79 blue:1 alpha:1];
    title.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBlack];
    title.textAlignment = NSTextAlignmentCenter;
    [root.view addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(28, 150, root.view.bounds.size.width - 56, 54)];
    subtitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitle.text = @"Standalone graphics settings";
    subtitle.textColor = UIColor.whiteColor;
    subtitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    subtitle.textAlignment = NSTextAlignmentCenter;
    [root.view addSubview:subtitle];

    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    dispatch_async(dispatch_get_main_queue(), ^{
        [HexiumShadeOverlay showOverlay];
    });
    return YES;
}

@end