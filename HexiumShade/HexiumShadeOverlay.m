#import "HexiumShadeOverlay.h"
#import "HexiumShade.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface HexiumShadeOverlay () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *cube;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSMutableArray<NSString *> *iniLines;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *effects;
@property (nonatomic, strong) UILabel *qualityLabel;
@property (nonatomic, copy) NSString *selectedQuality;
@end

@implementation HexiumShadeOverlay

+ (void)showOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        if (!window) return;
        HexiumShadeOverlay *overlay = [HexiumShadeOverlay new];
        objc_setAssociatedObject(window, "HexiumShadeOverlay", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [overlay buildInterfaceInWindow:window];
    });
}

- (void)buildInterfaceInWindow:(UIWindow *)window {
    self.iniLines = [NSMutableArray array];
    self.effects = [NSMutableDictionary dictionary];
    self.selectedQuality = HexiumShade.qualityPreset;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(20, 80, 300, 430)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.035 green:0.075 blue:0.15 alpha:0.97];
    self.panel.layer.cornerRadius = 15;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithRed:0.18 green:0.43 blue:0.78 alpha:1].CGColor;
    self.panel.clipsToBounds = YES;
    [window addSubview:self.panel];
    [self buildHeader];
    [self buildButtons];
    [self buildScrollView];
}

- (UILabel *)label:(NSString *)text frame:(CGRect)frame {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    return label;
}

- (UIButton *)button:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithRed:0.07 green:0.30 blue:0.59 alpha:1];
    button.layer.cornerRadius = 7;
    button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 42)];
    header.backgroundColor = [UIColor colorWithRed:0.06 green:0.16 blue:0.32 alpha:1];
    [self.panel addSubview:header];
    UILabel *title = [self label:@"HEXIUM GRAPHICS" frame:CGRectMake(12, 0, 185, 42)];
    title.textColor = [UIColor colorWithRed:0.62 green:0.79 blue:1 alpha:1];
    title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBlack];
    [header addSubview:title];
    UIButton *minimize = [self button:@"−" frame:CGRectMake(262, 5, 30, 30) action:@selector(minimizePanel)];
    minimize.backgroundColor = [UIColor colorWithRed:0.015 green:0.07 blue:0.20 alpha:0.98];
    minimize.layer.cornerRadius = 9;
    minimize.layer.borderWidth = 1.5;
    minimize.layer.borderColor = [UIColor colorWithRed:0.04 green:0.48 blue:1 alpha:1].CGColor;
    minimize.layer.shadowColor = [UIColor colorWithRed:0.02 green:0.38 blue:1 alpha:1].CGColor;
    minimize.layer.shadowOpacity = 0.9;
    minimize.layer.shadowRadius = 8;
    minimize.layer.shadowOffset = CGSizeZero;
    minimize.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [header addSubview:minimize];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    [header addGestureRecognizer:pan];
}

- (void)buildButtons {
    [self.panel addSubview:[self button:@"＋ Import INI" frame:CGRectMake(9, 51, 92, 32) action:@selector(importPreset)]];
    [self.panel addSubview:[self button:@"Export" frame:CGRectMake(108, 51, 76, 32) action:@selector(exportPreset)]];
    [self.panel addSubview:[self button:@"Apply" frame:CGRectMake(191, 51, 100, 32) action:@selector(applyPreset)]];
    self.qualityLabel = [self label:[NSString stringWithFormat:@"QUALITY: %@", self.selectedQuality.uppercaseString]
                              frame:CGRectMake(10, 87, 280, 20)];
    self.qualityLabel.textColor = [UIColor colorWithRed:0.65 green:0.79 blue:1 alpha:1];
    [self.panel addSubview:self.qualityLabel];

    NSArray *titles = @[@"Ultra", @"High", @"Medium", @"Low"];
    NSArray *actions = @[@"selectUltra", @"selectHigh", @"selectMedium", @"selectLow"];
    CGFloat width = 65;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *preset = [self button:titles[i]
                                   frame:CGRectMake(9 + i * 72, 111, width, 28)
                                  action:NSSelectorFromString(actions[i])];
        if ([titles[i] isEqualToString:self.selectedQuality]) preset.backgroundColor = [UIColor colorWithRed:0.10 green:0.52 blue:0.34 alpha:1];
        [self.panel addSubview:preset];
    }
}

- (void)selectQuality:(NSString *)quality {
    self.selectedQuality = quality;
    self.qualityLabel.text = [NSString stringWithFormat:@"QUALITY: %@", quality.uppercaseString];
    for (UIView *view in self.panel.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        NSString *title = button.titleLabel.text;
        if ([@[@"Ultra", @"High", @"Medium", @"Low"] containsObject:title]) {
            button.backgroundColor = [title isEqualToString:quality]
                ? [UIColor colorWithRed:0.10 green:0.52 blue:0.34 alpha:1]
                : [UIColor colorWithRed:0.07 green:0.30 blue:0.59 alpha:1];
        }
    }
}
- (void)selectUltra { [self selectQuality:@"Ultra"]; }
- (void)selectHigh { [self selectQuality:@"High"]; }
- (void)selectMedium { [self selectQuality:@"Medium"]; }
- (void)selectLow { [self selectQuality:@"Low"]; }

- (void)buildScrollView {
    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(7, 146, 286, 276)];
    self.scroll.backgroundColor = UIColor.clearColor;
    [self.panel addSubview:self.scroll];
    [self addLabel:@"Import an INI preset to inspect and edit its values." frame:CGRectMake(8, 8, 270, 34)];
}

- (void)addLabel:(NSString *)text frame:(CGRect)frame {
    [self.scroll addSubview:[self label:text frame:frame]];
}

- (void)minimizePanel {
    self.panel.hidden = YES;
    UIView *host = self.panel.superview;
    CGFloat cubeX = MAX(12, host.bounds.size.width - 68);
    CGFloat cubeY = MAX(12, self.panel.frame.origin.y - 18);
    self.cube = [self button:@"H" frame:CGRectMake(cubeX, cubeY, 54, 54) action:@selector(restorePanel)];
    self.cube.backgroundColor = [UIColor colorWithRed:0.015 green:0.07 blue:0.22 alpha:0.98];
    self.cube.layer.cornerRadius = 15;
    self.cube.titleLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBlack];
    self.cube.layer.borderWidth = 2;
    self.cube.layer.borderColor = [UIColor colorWithRed:0.02 green:0.52 blue:1 alpha:1].CGColor;
    self.cube.layer.shadowColor = [UIColor colorWithRed:0.02 green:0.40 blue:1 alpha:1].CGColor;
    self.cube.layer.shadowOpacity = 1;
    self.cube.layer.shadowRadius = 12;
    self.cube.layer.shadowOffset = CGSizeZero;
    UIPanGestureRecognizer *cubePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCube:)];
    cubePan.cancelsTouchesInView = YES;
    [self.cube addGestureRecognizer:cubePan];
    [self.panel.superview addSubview:self.cube];
}
- (void)restorePanel {
    if (self.cube) self.panel.frame = CGRectMake(self.cube.frame.origin.x, self.cube.frame.origin.y, 300, 430);
    self.panel.hidden = NO;
    [self.cube removeFromSuperview];
    self.cube = nil;
}

- (void)dragCube:(UIPanGestureRecognizer *)gesture {
    UIView *host = self.cube.superview;
    CGPoint delta = [gesture translationInView:host];
    CGPoint center = self.cube.center;
    center.x += delta.x;
    center.y += delta.y;
    CGFloat half = 27;
    center.x = MIN(MAX(half, center.x), host.bounds.size.width - half);
    center.y = MIN(MAX(half, center.y), host.bounds.size.height - half);
    self.cube.center = center;
    [gesture setTranslation:CGPointZero inView:host];
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.panel.superview];
    self.panel.center = CGPointMake(self.panel.center.x + translation.x, self.panel.center.y + translation.y);
    [gesture setTranslation:CGPointMake(0, 0) inView:self.panel.superview];
}

- (void)importPreset {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePlainText] asCopy:YES];
    picker.delegate = self;
    UIViewController *controller = self.panel.window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    [controller presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    if (accessed) [url stopAccessingSecurityScopedResource];
    if (error || !contents) return;
    self.iniLines = [[contents componentsSeparatedByString:@"\n"] mutableCopy];
    [self renderPreset];
}

- (void)renderPreset {
    for (UIView *view in self.scroll.subviews) [view removeFromSuperview];
    CGFloat y = 8;
    for (NSUInteger index = 0; index < self.iniLines.count; index++) {
        NSString *line = self.iniLines[index];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0) continue;
        if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
            UILabel *section = [self label:trimmed frame:CGRectMake(8, y, 300, 28)];
            section.textColor = [UIColor colorWithRed:0.55 green:0.76 blue:1 alpha:1];
            [self.scroll addSubview:section];
            y += 32;
            continue;
        }
        NSRange separator = [trimmed rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [[trimmed substringToIndex:separator.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = [[trimmed substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        UILabel *name = [self label:key frame:CGRectMake(8, y, 155, 32)];
        name.font = [UIFont systemFontOfSize:10];
        [self.scroll addSubview:name];
        UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(165, y, 145, 30)];
        field.text = value;
        field.textColor = UIColor.whiteColor;
        field.font = [UIFont systemFontOfSize:10];
        field.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1];
        field.layer.cornerRadius = 5;
        field.layer.borderWidth = 1;
        field.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1].CGColor;
        field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 0)];
        field.leftViewMode = UITextFieldViewModeAlways;
        field.tag = (NSInteger)index;
        [self.scroll addSubview:field];
        y += 38;
    }
    self.scroll.contentSize = CGSizeMake(324, y + 10);
}

- (NSString *)updatedINI {
    NSMutableArray *output = [self.iniLines mutableCopy];
    for (UIView *view in self.scroll.subviews) {
        if (![view isKindOfClass:UITextField.class]) continue;
        UITextField *field = (UITextField *)view;
        NSInteger index = field.tag;
        if (index < 0 || index >= (NSInteger)output.count) continue;
        NSString *original = output[index];
        NSRange separator = [original rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [original substringToIndex:separator.location];
        output[index] = [NSString stringWithFormat:@"%@=%@", key, field.text ?: @""];
    }
    return [output componentsJoinedByString:@"\n"];
}

- (void)exportPreset {
    NSString *contents = [self updatedINI];
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"Hexium-Edited.ini"]];
    NSError *error = nil;
    [contents writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) { NSLog(@"HexiumShade export error: %@", error); return; }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    UIViewController *controller = self.panel.window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    [controller presentViewController:share animated:YES completion:nil];
}

- (void)applyPreset {
    if (![HexiumShade setQualityPreset:self.selectedQuality]) return;
    if (self.iniLines.count > 0) {
        // Keep the imported/editable preset available to the host for its next supported render pass.
        [NSUserDefaults.standardUserDefaults setObject:[self updatedINI] forKey:@"HexiumShade.importedPresetINI"];
    }
    self.qualityLabel.text = [NSString stringWithFormat:@"QUALITY: %@ (SAVED)", self.selectedQuality.uppercaseString];
    NSLog(@"HexiumShade: %@ quality profile saved; imported INI stored when present.", self.selectedQuality);
}

@end
