#import <UIKit/UIKit.h>
#import "HexiumShadeOverlay.h"

@interface SHADESRootViewController : UIViewController
@end

@implementation SHADESRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.012 green:0.025 blue:0.055 alpha:1];

    // A visible fallback makes it clear the standalone app launched even if
    // UIKit is still transitioning its window into the foreground.
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.text = @"SHADES";
    status.textColor = [UIColor colorWithRed:0.35 green:0.65 blue:1 alpha:0.32];
    status.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBlack];
    status.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:status];
    [NSLayoutConstraint activateConstraints:@[
        [status.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [status.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // viewDidAppear runs after the root controller is attached to a visible
    // window, avoiding the launch-time race where no presentable window exists.
    [HexiumShadeOverlay showOverlay];
}

@end

@interface SHADESAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SHADESAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = [UIColor colorWithRed:0.012 green:0.025 blue:0.055 alpha:1];
    self.window.rootViewController = [SHADESRootViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Retry whenever the app returns from the background.
    [HexiumShadeOverlay showOverlay];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SHADESAppDelegate.class));
    }
}
