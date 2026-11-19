#import "HexiumShadeOverlay.h"
#import "HexiumShade.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface HexiumShadeOverlay () <UIDocumentPickerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *cube;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSMutableArray<NSString *> *iniLines;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *effects;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UISwitch *> *effectSwitches;
@property (nonatomic, strong) UILabel *qualityLabel;
@property (nonatomic, strong) UILabel *fileNameLabel;
@property (nonatomic, strong) UILabel *fileDetailLabel;
@property (nonatomic, copy) NSString *selectedQuality;
@property (nonatomic, copy) NSString *importedFileName;
@end

@implementation HexiumShadeOverlay

+ (void)installPresentationObservers {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        // A host can request presentation before its first key window exists.
        // Retry on activation/key-window changes instead of silently giving up.
        [center addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
            [self showOverlay];
        }];
        [center addObserverForName:UIWindowDidBecomeKeyNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *note) {
            UIWindow *window = note.object;
            if (window && window.windowScene.activationState == UISceneActivationStateForegroundActive) {
                [self attachOverlayToWindow:window];
            } else {
                [self showOverlay];
            }
        }];
        [center addObserverForName:UISceneDidActivateNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
            [self showOverlay];
        }];
    });
}

+ (void)showOverlay {
    [self installPresentationObservers];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *application = UIApplication.sharedApplication;
        if (application.applicationState != UIApplicationStateActive) {
            NSLog(@"SHADES: waiting for the host app to become active before presenting the panel.");
            return;
        }

        UIWindow *window = nil;
        // Prefer the key window from a foreground-active scene.
        for (UIScene *scene in application.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *candidate in windowScene.windows) {
                if (candidate.isKeyWindow && !candidate.hidden && candidate.alpha > 0.01) {
                    window = candidate;
                    break;
                }
            }
            if (window) break;
            for (UIWindow *candidate in windowScene.windows) {
                if (!candidate.hidden && candidate.alpha > 0.01 && candidate.rootViewController) {
                    window = candidate;
                    break;
                }
            }
            if (window) break;
        }

        // Legacy-window fallback for hosts without a connected UIWindowScene.
        if (!window) {
            for (UIWindow *candidate in application.windows) {
                if (candidate.isKeyWindow && !candidate.hidden && candidate.alpha > 0.01) {
                    window = candidate;
                    break;
                }
            }
        }
        if (!window) {
            for (UIWindow *candidate in application.windows) {
                if (!candidate.hidden && candidate.alpha > 0.01 && candidate.rootViewController) {
                    window = candidate;
                    break;
                }
            }
        }
        if (!window) {
            NSLog(@"SHADES: no visible foreground host window yet; will retry when the host becomes active or a window becomes key.");
            return;
        }
        [self attachOverlayToWindow:window];
    });
}

+ (void)attachOverlayToWindow:(UIWindow *)window {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self attachOverlayToWindow:window]; });
        return;
    }
    if (!window || window.hidden || window.alpha <= 0.01) return;

    HexiumShadeOverlay *existing = objc_getAssociatedObject(window, "HexiumShadeOverlay");
    if (existing) {
        if (existing.panel.superview != window) {
            [existing.panel removeFromSuperview];
            [window addSubview:existing.panel];
        }
        existing.panel.hidden = NO;
        [window bringSubviewToFront:existing.panel];
        if (existing.cube) [window bringSubviewToFront:existing.cube];
        return;
    }

    HexiumShadeOverlay *overlay = [HexiumShadeOverlay new];
    objc_setAssociatedObject(window, "HexiumShadeOverlay", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [overlay buildInterfaceInWindow:window];
    [window bringSubviewToFront:overlay.panel];
    NSLog(@"SHADES: GUI attached to foreground host window (%@).", NSStringFromCGRect(window.bounds));
}

- (UIColor *)blue:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha {
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

- (void)buildInterfaceInWindow:(UIWindow *)window {
    self.iniLines = [NSMutableArray array];
    self.effects = [@{@"MXAO": @NO, @"DepthHaze": @NO, @"ADOF": @NO, @"SSR": @NO} mutableCopy];
    self.effectSwitches = [NSMutableDictionary dictionary];
    self.selectedQuality = HexiumShade.qualityPreset ?: @"High";
    self.importedFileName = @"No preset imported";
    
    CGFloat width = MIN(340.0, window.bounds.size.width - 24.0);
    CGFloat height = MIN(560.0, window.bounds.size.height - 40.0);
    CGFloat x = MAX(12.0, (window.bounds.size.width - width) * 0.5);
    CGFloat y = MAX(20.0, MIN(70.0, window.bounds.size.height - height - 12.0));
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    self.panel.backgroundColor = [self blue:0.025 green:0.055 blue:0.12 alpha:0.98];
    self.panel.layer.cornerRadius = 17;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [self blue:0.16 green:0.43 blue:0.82 alpha:1].CGColor;
    self.panel.layer.shadowColor = [self blue:0.02 green:0.30 blue:0.95 alpha:1].CGColor;
    self.panel.layer.shadowOpacity = 0.28;
    self.panel.layer.shadowRadius = 16;
    self.panel.layer.shadowOffset = CGSizeMake(0, 5);
    // Keep the panel's shadow visible; the scroll view and file card clip their own contents.
    self.panel.clipsToBounds = NO;
    [window addSubview:self.panel];
    [self buildHeaderWithWidth:width];
    [self buildButtonsWithWidth:width];
    [self buildFileInfoWithWidth:width];
    [self buildEffectControlsWithWidth:width];
    [self buildScrollViewWithWidth:width height:height];
}

- (UILabel *)label:(NSString *)text frame:(CGRect)frame {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

- (UIButton *)button:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [self blue:0.055 green:0.27 blue:0.55 alpha:1];
    button.layer.cornerRadius = 8;
    button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildHeaderWithWidth:(CGFloat)width {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 42)];
    header.backgroundColor = [self blue:0.045 green:0.13 blue:0.28 alpha:1];
    [self.panel addSubview:header];
    UILabel *title = [self label:@"SHADES" frame:CGRectMake(13, 0, width - 65, 42)];
    title.textColor = [self blue:0.62 green:0.81 blue:1 alpha:1];
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBlack];
    [header addSubview:title];
    UIButton *minimize = [self button:@"−" frame:CGRectMake(width - 38, 5, 30, 30) action:@selector(minimizePanel)];
    minimize.backgroundColor = [self blue:0.01 green:0.055 blue:0.17 alpha:1];
    minimize.layer.borderWidth = 1.4;
    minimize.layer.borderColor = [self blue:0.04 green:0.48 blue:1 alpha:1].CGColor;
    minimize.layer.shadowColor = [self blue:0.02 green:0.38 blue:1 alpha:1].CGColor;
    minimize.layer.shadowOpacity = 0.85;
    minimize.layer.shadowRadius = 7;
    minimize.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [header addSubview:minimize];
    [header addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];
}

- (void)buildButtonsWithWidth:(CGFloat)width {
    CGFloat gap = 7.0;
    CGFloat buttonWidth = (width - 24.0 - gap * 2.0) / 3.0;
    [self.panel addSubview:[self button:@"Import Preset" frame:CGRectMake(9, 50, buttonWidth, 32) action:@selector(importPreset)]];
    [self.panel addSubview:[self button:@"Export" frame:CGRectMake(9 + buttonWidth + gap, 50, buttonWidth, 32) action:@selector(exportPreset)]];
    [self.panel addSubview:[self button:@"Apply" frame:CGRectMake(9 + (buttonWidth + gap) * 2, 50, buttonWidth, 32) action:@selector(applyPreset)]];
    self.qualityLabel = [self label:[NSString stringWithFormat:@"QUALITY  /  %@", self.selectedQuality.uppercaseString]
                              frame:CGRectMake(11, 86, width - 22, 20)];
    self.qualityLabel.textColor = [self blue:0.66 green:0.81 blue:1 alpha:1];
    [self.panel addSubview:self.qualityLabel];
    NSArray *titles = @[@"Ultra", @"High", @"Medium", @"Low"];
    NSArray *actions = @[@"selectUltra", @"selectHigh", @"selectMedium", @"selectLow"];
    CGFloat presetGap = 6.0;
    CGFloat presetWidth = (width - 24.0 - presetGap * 3.0) / 4.0;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *preset = [self button:titles[i]
                                   frame:CGRectMake(9 + i * (presetWidth + presetGap), 108, presetWidth, 28)
                                  action:NSSelectorFromString(actions[i])];
        if ([titles[i] isEqualToString:self.selectedQuality]) preset.backgroundColor = [self blue:0.08 green:0.48 blue:0.32 alpha:1];
        [self.panel addSubview:preset];
    }
}

- (void)buildFileInfoWithWidth:(CGFloat)width {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(9, 144, width - 18, 48)];
    card.backgroundColor = [self blue:0.045 green:0.105 blue:0.20 alpha:1];
    card.layer.cornerRadius = 9;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [self blue:0.13 green:0.29 blue:0.48 alpha:1].CGColor;
    [self.panel addSubview:card];
    UILabel *caption = [self label:@"IMPORTED PRESET" frame:CGRectMake(10, 4, card.bounds.size.width - 20, 13)];
    caption.font = [UIFont systemFontOfSize:9 weight:UIFontWeightHeavy];
    caption.textColor = [self blue:0.48 green:0.70 blue:0.96 alpha:1];
    [card addSubview:caption];
    self.fileNameLabel = [self label:self.importedFileName frame:CGRectMake(10, 17, card.bounds.size.width - 20, 17)];
    self.fileNameLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [card addSubview:self.fileNameLabel];
    self.fileDetailLabel = [self label:@"Choose an .ini or text preset to begin" frame:CGRectMake(10, 33, card.bounds.size.width - 20, 12)];
    self.fileDetailLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
    self.fileDetailLabel.textColor = [UIColor colorWithWhite:0.68 alpha:1];
    [card addSubview:self.fileDetailLabel];
}

- (void)buildEffectControlsWithWidth:(CGFloat)width {
    UILabel *heading = [self label:@"SHADER EFFECTS" frame:CGRectMake(11, 197, width - 22, 18)];
    heading.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBlack];
    heading.textColor = [self blue:0.55 green:0.75 blue:1 alpha:1];
    [self.panel addSubview:heading];
    NSArray *names = @[@"MXAO", @"DepthHaze", @"ADOF", @"SSR"];
    NSArray *descriptions = @[@"Ambient occlusion", @"Depth-based haze", @"Adaptive depth of field", @"Screen-space reflections"];
    for (NSUInteger i = 0; i < names.count; i++) {
        CGFloat rowY = 216 + i * 35;
        UILabel *name = [self label:names[i] frame:CGRectMake(12, rowY, 112, 18)];
        name.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        [self.panel addSubview:name];
        UILabel *detail = [self label:descriptions[i] frame:CGRectMake(12, rowY + 15, 190, 13)];
        detail.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
        detail.textColor = [UIColor colorWithWhite:0.62 alpha:1];
        [self.panel addSubview:detail];
        UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
        toggle.on = [self.effects[names[i]] boolValue];
        toggle.onTintColor = [self blue:0.08 green:0.48 blue:0.92 alpha:1];
        toggle.accessibilityIdentifier = names[i];
        [toggle addTarget:self action:@selector(effectSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        toggle.frame = CGRectMake(width - 67, rowY + 1, 51, 31);
        [self.panel addSubview:toggle];
        self.effectSwitches[names[i]] = toggle;
        if (i < names.count - 1) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12, rowY + 33, width - 24, 0.5)];
            line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
            [self.panel addSubview:line];
        }
    }
    UILabel *presetHeading = [self label:@"PRESET VALUES" frame:CGRectMake(11, 360, width - 22, 18)];
    presetHeading.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBlack];
    presetHeading.textColor = [self blue:0.55 green:0.75 blue:1 alpha:1];
    [self.panel addSubview:presetHeading];
}

- (void)addLabel:(NSString *)text frame:(CGRect)frame {
    UILabel *label = [self label:text frame:frame];
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    label.textColor = [UIColor colorWithWhite:0.72 alpha:1];
    [self.scroll addSubview:label];
}

- (void)buildScrollViewWithWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat scrollTop = MIN(381.0, MAX(250.0, height - 76.0));
    CGFloat scrollHeight = MAX(44.0, height - scrollTop - 8.0);
    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(7, scrollTop, width - 14, scrollHeight)];
    self.scroll.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
    self.scroll.layer.cornerRadius = 8;
    self.scroll.alwaysBounceVertical = YES;
    [self.panel addSubview:self.scroll];
    [self addLabel:@"Import an INI preset to inspect and edit its values." frame:CGRectMake(8, 8, width - 34, 34)];
}

- (void)selectQuality:(NSString *)quality {
    self.selectedQuality = quality;
    self.qualityLabel.text = [NSString stringWithFormat:@"QUALITY  /  %@", quality.uppercaseString];
    for (UIView *view in self.panel.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        NSString *title = button.titleLabel.text;
        if ([@[@"Ultra", @"High", @"Medium", @"Low"] containsObject:title]) {
            button.backgroundColor = [title isEqualToString:quality]
                ? [self blue:0.08 green:0.48 blue:0.32 alpha:1]
                : [self blue:0.055 green:0.27 blue:0.55 alpha:1];
        }
    }
}
- (void)selectUltra { [self selectQuality:@"Ultra"]; }
- (void)selectHigh { [self selectQuality:@"High"]; }
- (void)selectMedium { [self selectQuality:@"Medium"]; }
- (void)selectLow { [self selectQuality:@"Low"]; }

- (void)effectSwitchChanged:(UISwitch *)sender {
    NSString *name = sender.accessibilityIdentifier;
    if (name.length) self.effects[name] = @(sender.isOn);
}

- (void)minimizePanel {
    self.panel.hidden = YES;
    UIView *host = self.panel.superview;
    CGFloat cubeX = MAX(12, host.bounds.size.width - 68);
    CGFloat cubeY = MAX(12, self.panel.frame.origin.y - 18);
    self.cube = [self button:@"H" frame:CGRectMake(cubeX, cubeY, 54, 54) action:@selector(restorePanel)];
    self.cube.backgroundColor = [self blue:0.01 green:0.055 blue:0.19 alpha:1];
    self.cube.layer.cornerRadius = 15;
    self.cube.titleLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBlack];
    self.cube.layer.borderWidth = 2;
    self.cube.layer.borderColor = [self blue:0.02 green:0.52 blue:1 alpha:1].CGColor;
    self.cube.layer.shadowColor = [self blue:0.02 green:0.40 blue:1 alpha:1].CGColor;
    self.cube.layer.shadowOpacity = 1;
    self.cube.layer.shadowRadius = 12;
    UIPanGestureRecognizer *cubePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragCube:)];
    cubePan.cancelsTouchesInView = YES;
    [self.cube addGestureRecognizer:cubePan];
    [host addSubview:self.cube];
}

- (void)restorePanel {
    UIView *host = self.panel.superview;
    CGFloat width = self.panel.bounds.size.width;
    CGFloat height = self.panel.bounds.size.height;
    CGFloat x = MIN(MAX(12, self.cube.frame.origin.x), MAX(12, host.bounds.size.width - width - 12));
    CGFloat y = MIN(MAX(12, self.cube.frame.origin.y), MAX(12, host.bounds.size.height - height - 12));
    self.panel.frame = CGRectMake(x, y, width, height);
    self.panel.hidden = NO;
    [self.cube removeFromSuperview];
    self.cube = nil;
}

- (void)dragCube:(UIPanGestureRecognizer *)gesture {
    UIView *host = self.cube.superview;
    CGPoint delta = [gesture translationInView:host];
    CGPoint center = self.cube.center;
    center.x += delta.x; center.y += delta.y;
    CGFloat half = 27;
    center.x = MIN(MAX(half, center.x), host.bounds.size.width - half);
    center.y = MIN(MAX(half, center.y), host.bounds.size.height - half);
    self.cube.center = center;
    [gesture setTranslation:CGPointMake(0, 0) inView:host];
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.panel.superview];
    CGPoint center = CGPointMake(self.panel.center.x + translation.x, self.panel.center.y + translation.y);
    CGFloat halfW = self.panel.bounds.size.width * 0.5;
    CGFloat halfH = self.panel.bounds.size.height * 0.5;
    center.x = MIN(MAX(halfW, center.x), self.panel.superview.bounds.size.width - halfW);
    center.y = MIN(MAX(halfH, center.y), self.panel.superview.bounds.size.height - halfH);
    self.panel.center = center;
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
    if (error || !contents) {
        self.fileNameLabel.text = @"Couldn't read selected file";
        self.fileDetailLabel.text = error.localizedDescription ?: @"Unsupported or empty text file";
        return;
    }
    self.iniLines = [[contents componentsSeparatedByString:@"\n"] mutableCopy];
    self.importedFileName = url.lastPathComponent ?: @"Imported preset";
    self.fileNameLabel.text = self.importedFileName;
    self.fileDetailLabel.text = [NSString stringWithFormat:@"%lu lines  •  INI/text preset", (unsigned long)self.iniLines.count];
    [self syncEffectStatesFromINI];
    [self renderPreset];
}

- (void)syncEffectStatesFromINI {
    NSDictionary *tokens = @{@"MXAO": @[@"mxao"], @"DepthHaze": @[@"depthhaze", @"depth_haze"], @"ADOF": @[@"adof", @"dof"], @"SSR": @[@"ssr"]};
    for (NSString *effect in tokens) {
        BOOL found = NO;
        BOOL enabled = NO;
        for (NSString *line in self.iniLines) {
            NSString *lower = [line lowercaseString];
            NSRange equal = [lower rangeOfString:@"="];
            if (equal.location == NSNotFound) continue;
            NSString *key = [[lower substringToIndex:equal.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *value = [[lower substringFromIndex:equal.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            BOOL matches = NO;
            for (NSString *token in tokens[effect]) if ([key containsString:token]) { matches = YES; break; }
            if (!matches) continue;
            found = YES;
            enabled = !([@[@"0", @"false", @"off", @"no", @"disabled"] containsObject:value]);
        }
        if (found) {
            self.effects[effect] = @(enabled);
            self.effectSwitches[effect].on = enabled;
        }
    }
}

- (void)renderPreset {
    for (UIView *view in self.scroll.subviews) [view removeFromSuperview];
    CGFloat y = 8;
    CGFloat width = self.scroll.bounds.size.width;
    for (NSUInteger index = 0; index < self.iniLines.count; index++) {
        NSString *line = self.iniLines[index];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0 || [trimmed hasPrefix:@";"] || [trimmed hasPrefix:@"#"]) continue;
        if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
            UILabel *section = [self label:trimmed frame:CGRectMake(8, y, width - 16, 24)];
            section.textColor = [self blue:0.55 green:0.76 blue:1 alpha:1];
            [self.scroll addSubview:section];
            y += 27;
            continue;
        }
        NSRange separator = [trimmed rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [[trimmed substringToIndex:separator.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = [[trimmed substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        UILabel *name = [self label:key frame:CGRectMake(8, y, width * 0.48, 28)];
        name.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
        [self.scroll addSubview:name];
        UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(width * 0.50, y, width * 0.46, 27)];
        field.text = value;
        field.delegate = self;
        field.returnKeyType = UIReturnKeyDone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.textColor = UIColor.whiteColor;
        field.font = [UIFont systemFontOfSize:9];
        field.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1];
        field.layer.cornerRadius = 5;
        field.layer.borderWidth = 1;
        field.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1].CGColor;
        field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 0)];
        field.leftViewMode = UITextFieldViewModeAlways;
        field.tag = (NSInteger)index;
        [self.scroll addSubview:field];
        y += 32;
    }
    self.scroll.contentSize = CGSizeMake(width, MAX(y + 8, self.scroll.bounds.size.height + 1));
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (NSString *)updatedINI {
    NSMutableArray *output = [self.iniLines mutableCopy] ?: [NSMutableArray array];
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
    NSInteger shadesStart = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)output.count; i++) {
        NSString *trimmed = [output[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([trimmed.lowercaseString isEqualToString:@"[shades]"]) { shadesStart = i; break; }
    }
    if (shadesStart != NSNotFound) {
        NSInteger end = shadesStart + 1;
        while (end < (NSInteger)output.count) {
            NSString *trimmed = [output[end] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) break;
            end++;
        }
        [output removeObjectsInRange:NSMakeRange((NSUInteger)shadesStart, (NSUInteger)(end - shadesStart))];
    }
    if (output.count && [output.lastObject length] > 0) [output addObject:@""];
    [output addObject:@"[SHADES]"];
    for (NSString *effect in @[@"MXAO", @"DepthHaze", @"ADOF", @"SSR"]) {
        [output addObject:[NSString stringWithFormat:@"%@=%@", effect, [self.effects[effect] boolValue] ? @"1" : @"0"]];
    }
    return [output componentsJoinedByString:@"\n"];
}

- (void)exportPreset {
    NSString *contents = [self updatedINI];
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"SHADES-Edited.ini"]];
    NSError *error = nil;
    [contents writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        self.fileDetailLabel.text = [NSString stringWithFormat:@"Export failed: %@", error.localizedDescription];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    UIPopoverPresentationController *popover = share.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.panel;
        popover.sourceRect = CGRectMake(self.panel.bounds.size.width * 0.5, self.panel.bounds.size.height * 0.5, 1, 1);
    }
    UIViewController *controller = self.panel.window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    [controller presentViewController:share animated:YES completion:nil];
}

- (void)applyPreset {
    if (![HexiumShade setQualityPreset:self.selectedQuality]) return;
    if (self.iniLines.count > 0) {
        [NSUserDefaults.standardUserDefaults setObject:[self updatedINI] forKey:@"HexiumShade.importedPresetINI"];
    }
    [NSUserDefaults.standardUserDefaults setObject:self.effects forKey:@"HexiumShade.effectStates"];
    self.qualityLabel.text = [NSString stringWithFormat:@"QUALITY  /  %@  •  SAVED", self.selectedQuality.uppercaseString];
    self.fileDetailLabel.text = @"Preset and shader switches saved";
    NSLog(@"SHADES: %@ profile and effect switches saved. Render passes require a host-supplied frame.", self.selectedQuality);
}




@end

// Public entry point for hosts that explicitly integrate SHADES.
__attribute__((visibility("default")))
void SHADESPresentOverlay(void) {
    [HexiumShadeOverlay showOverlay];
}
