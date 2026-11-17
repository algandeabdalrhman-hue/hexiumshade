#import "HexiumShadeOverlay.h"
#import "HexiumShade.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

static HexiumShadeApplyHandler HexiumCurrentApplyHandler = nil;

@interface HexiumShadeOverlay () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *cube;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSMutableArray<NSString *> *iniLines;
@property (nonatomic, strong) UILabel *qualityLabel;
@property (nonatomic, copy) NSString *selectedQuality;
@end

@implementation HexiumShadeOverlay

+ (void)setApplyHandler:(HexiumShadeApplyHandler)handler {
    HexiumCurrentApplyHandler = [handler copy];
}

+ (void)showOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
            if (window) break;
        }

        if (!window) {
            for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
        }
        if (!window) return;
        HexiumShadeOverlay *overlay = [HexiumShadeOverlay new];
        objc_setAssociatedObject(window, "HexiumShadeOverlay", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [overlay buildInterfaceInWindow:window];
    });
}

- (void)buildInterfaceInWindow:(UIWindow *)window {
    self.iniLines = [NSMutableArray array];
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(35, 100, 340, 520)];
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
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 340, 45)];
    header.backgroundColor = [UIColor colorWithRed:0.06 green:0.16 blue:0.32 alpha:1];
    [self.panel addSubview:header];
    UILabel *title = [self label:@"HEXIUM GRAPHICS" frame:CGRectMake(13, 0, 190, 45)];
    title.textColor = [UIColor colorWithRed:0.62 green:0.79 blue:1 alpha:1];
    title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBlack];
    [header addSubview:title];
    [header addSubview:[self button:@"−" frame:CGRectMake(298, 7, 32, 30) action:@selector(minimizePanel)]];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    [header addGestureRecognizer:pan];
}

- (void)buildButtons {
    [self.panel addSubview:[self button:@"＋ Import INI" frame:CGRectMake(10, 55, 100, 35) action:@selector(importPreset)]];
    [self.panel addSubview:[self button:@"Export" frame:CGRectMake(118, 55, 85, 35) action:@selector(exportPreset)]];
    [self.panel addSubview:[self button:@"Apply" frame:CGRectMake(211, 55, 119, 35) action:@selector(applyPreset)]];
    self.qualityLabel = [self label:@"QUALITY: Medium" frame:CGRectMake(12, 96, 200, 24)];
    self.qualityLabel.textColor = [UIColor colorWithRed:0.65 green:0.79 blue:1 alpha:1];
    self.selectedQuality = @"Medium";
    [self.panel addSubview:self.qualityLabel];

    NSArray *names = @[@"Low", @"Medium", @"High", @"Ultra"];
    CGFloat x = 10.0;
    for (NSInteger i = 0; i < names.count; i++) {
        UIButton *preset = [self button:names[i] frame:CGRectMake(x, 124, 77, 31) action:@selector(selectQuality:)];
        preset.tag = i;
        if (i == 1) preset.backgroundColor = [UIColor colorWithRed:0.12 green:0.48 blue:0.82 alpha:1];
        [self.panel addSubview:preset];
        x += 82.0;
    }
}

- (void)selectQuality:(UIButton *)sender {
    NSArray *names = @[@"Low", @"Medium", @"High", @"Ultra"];
    NSArray *presets = @[
        @{@"Quality":@0, @"Bloom":@0, @"Sharpen":@0, @"ColorCorrection":@1, @"AmbientLight":@0,
          @"Exposure":@0.0, @"Contrast":@1.0, @"Saturation":@1.0, @"BloomIntensity":@0.0,
          @"SharpenAmount":@0.0, @"AmbientIntensity":@0.0},
        @{@"Quality":@1, @"Bloom":@0, @"Sharpen":@0, @"ColorCorrection":@1, @"AmbientLight":@0,
          @"Exposure":@0.02, @"Contrast":@1.02, @"Saturation":@1.0, @"BloomIntensity":@0.0,
          @"SharpenAmount":@0.12, @"AmbientIntensity":@0.04},
        @{@"Quality":@2, @"Bloom":@0, @"Sharpen":@1, @"ColorCorrection":@1, @"AmbientLight":@1,
          @"Exposure":@0.03, @"Contrast":@1.05, @"Saturation":@1.02, @"BloomIntensity":@0.0,
          @"SharpenAmount":@0.28, @"AmbientIntensity":@0.10},
        @{@"Quality":@3, @"Bloom":@1, @"Sharpen":@1, @"ColorCorrection":@1, @"AmbientLight":@1,
          @"Exposure":@0.05, @"Contrast":@1.06, @"Saturation":@1.04, @"BloomIntensity":@0.10,
          @"SharpenAmount":@0.42, @"AmbientIntensity":@0.14}
    ];
    self.selectedQuality = names[sender.tag];
    self.qualityLabel.text = [NSString stringWithFormat:@"QUALITY: %@", self.selectedQuality];
    for (UIView *view in self.panel.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button=(UIButton *)view;
        if (button.tag>=0 && button.tag<4 && [names containsObject:button.currentTitle]) {
            button.backgroundColor = (button.tag==sender.tag)
                ? [UIColor colorWithRed:0.12 green:0.48 blue:0.82 alpha:1]
                : [UIColor colorWithRed:0.07 green:0.30 blue:0.59 alpha:1];
        }
    }
    HexiumShadeApplyHandler handler=HexiumCurrentApplyHandler;
    if (handler) handler(presets[sender.tag], ^(BOOL success, NSError *error) {
        if (!success) dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:@"Quality change failed" message:error.localizedDescription ?: @"Renderer rejected this preset."];
        });
    });
}

- (void)buildScrollView {
    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(8, 164, 324, 346)];
    self.scroll.backgroundColor = UIColor.clearColor;
    [self.panel addSubview:self.scroll];
    [self addLabel:@"Import an INI preset to begin." frame:CGRectMake(10, 10, 300, 30)];
}

- (void)addLabel:(NSString *)text frame:(CGRect)frame {
    [self.scroll addSubview:[self label:text frame:frame]];
}

- (void)minimizePanel {
    self.panel.hidden = YES;
    self.cube = [self button:@"H" frame:CGRectMake(35, 100, 45, 45) action:@selector(restorePanel)];
    self.cube.layer.cornerRadius = 12;
    self.cube.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.panel.superview addSubview:self.cube];
}

- (void)restorePanel {
    self.panel.hidden = NO;
    [self.cube removeFromSuperview];
    self.cube = nil;
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
    if (error || !contents) {
        [self showMessage:@"Import failed" message:error.localizedDescription ?: @"Could not read this file."];
        return;
    }
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
    NSURL *directory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *file = [directory URLByAppendingPathComponent:@"Hexium-Edited.ini"];
    NSError *error = nil;
    [contents writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        [self showMessage:@"Export failed" message:error.localizedDescription];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    UIViewController *controller = self.panel.window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    [controller presentViewController:share animated:YES completion:nil];
}

- (NSDictionary<NSString *, NSNumber *> *)rendererOptionsFromINI:(NSString *)ini {
    NSDictionary<NSString *, NSString *> *values = [HexiumShade parseINI:ini];
    NSArray *booleanKeys = @[@"Bloom", @"Sharpen", @"ColorCorrection", @"AmbientLight"];
    NSArray *numberKeys = @[@"Exposure", @"Contrast", @"Saturation", @"BloomIntensity", @"SharpenAmount", @"AmbientIntensity"];
    NSMutableDictionary *options = [NSMutableDictionary dictionary];

    for (NSString *key in booleanKeys) {
        NSString *value = [values[key] lowercaseString];
        options[key] = @([@[@"1", @"true", @"yes", @"on", @"enabled"] containsObject:value]);
    }
    for (NSString *key in numberKeys) {
        NSString *value = values[key];
        if (value.length == 0) continue;
        NSScanner *scanner = [NSScanner scannerWithString:value];
        float number = 0;
        if ([scanner scanFloat:&number] && scanner.isAtEnd && isfinite(number)) options[key] = @(number);
    }
    return options;
}

- (void)applyPreset {
    if (self.iniLines.count == 0) {
        [self showMessage:@"No preset loaded" message:@"Import an INI file before applying settings."];
        return;
    }
    HexiumShadeApplyHandler handler = HexiumCurrentApplyHandler;
    if (!handler) {
        [self showMessage:@"Renderer not connected" message:@"The host app must register its own Metal renderer callback before Apply can process a frame."];
        return;
    }
    NSMutableDictionary *options = [[self rendererOptionsFromINI:[self updatedINI]] mutableCopy];
    options[@"Quality"] = @([@[@"Low", @"Medium", @"High", @"Ultra"] indexOfObject:self.selectedQuality] == NSNotFound ? 1 : [@[@"Low", @"Medium", @"High", @"Ultra"] indexOfObject:self.selectedQuality]);
    HexiumShadeOverlay *overlay = self;
    handler(options, ^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [overlay showMessage:@"Settings submitted" message:@"The host renderer reported that the frame was processed."];
            } else {
                [overlay showMessage:@"Apply failed" message:error.localizedDescription ?: @"The host renderer could not process the frame."];
            }
        });
    });
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIViewController *controller = self.panel.window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if (!controller) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@end
