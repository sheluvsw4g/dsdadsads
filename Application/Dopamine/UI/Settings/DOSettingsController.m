//
//  DOSettingsController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOSettingsController.h"
#import <objc/runtime.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <libjailbreak/util.h>
#import "DOUIManager.h"
#import "DOPkgManagerPickerViewController.h"
#import "DOHeaderCell.h"
#import "DOEnvironmentManager.h"
#import "DOExploitManager.h"
#import "DOPSListItemsController.h"
#import "DOPSExploitListItemsController.h"
#import "DOThemeManager.h"
#import "DOSceneDelegate.h"
#import "DOPSJetsamListItemsController.h"
#import "DOButtonCell.h"
#import <dlfcn.h>

@interface DOPhysicsPlaygroundViewController : UIViewController
@property (nonatomic, strong) UIDynamicAnimator *animator;
@property (nonatomic, strong) UIGravityBehavior *gravityBehavior;
@property (nonatomic, strong) UICollisionBehavior *collisionBehavior;
@property (nonatomic, strong) UIDynamicItemBehavior *itemBehavior;
@property (nonatomic, strong) UIAttachmentBehavior *attachmentBehavior;
@property (nonatomic, strong) UIView *activePanIcon;
@property (nonatomic, strong) NSMutableArray<UIView *> *iconContainers;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *originalCenters;
@property (nonatomic, assign) BOOL isPhysicsActive;
@property (nonatomic, strong) id motionManager;
@property (nonatomic, strong) UIImpactFeedbackGenerator *impactFeedback;
@end

@implementation DOPhysicsPlaygroundViewController

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:1.0];
    self.iconContainers = [NSMutableArray new];
    self.originalCenters = [NSMutableDictionary new];
    self.impactFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [self.impactFeedback prepare];

    CAGradientLayer *bgGrad = [CAGradientLayer layer];
    bgGrad.frame = [UIScreen mainScreen].bounds;
    bgGrad.colors = @[
        (id)[UIColor colorWithRed:0.08 green:0.09 blue:0.16 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.04 blue:0.08 alpha:1.0].CGColor
    ];
    [self.view.layer insertSublayer:bgGrad atIndex:0];

    [self setupTopControls];
    [self setupAppIcons];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.view addGestureRecognizer:pan];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    [self setupMotionUpdates];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self resignFirstResponder];
    if (self.motionManager && [self.motionManager respondsToSelector:@selector(stopDeviceMotionUpdates)]) {
        [self.motionManager performSelector:@selector(stopDeviceMotionUpdates)];
        self.motionManager = nil;
    }
    if (self.animator) {
        [self.animator removeAllBehaviors];
        self.animator = nil;
    }
}

- (void)setupMotionUpdates {
    void *cmLib = dlopen("/System/Library/Frameworks/CoreMotion.framework/CoreMotion", RTLD_NOW);
    if (!cmLib) return;
    Class cmClass = NSClassFromString(@"CMMotionManager");
    if (!cmClass) return;
    
    self.motionManager = [[cmClass alloc] init];
    BOOL isAvail = NO;
    NSInvocation *availInv = [NSInvocation invocationWithMethodSignature:[cmClass instanceMethodSignatureForSelector:@selector(isDeviceMotionAvailable)]];
    [availInv setSelector:@selector(isDeviceMotionAvailable)];
    [availInv setTarget:self.motionManager];
    [availInv invoke];
    [availInv getReturnValue:&isAvail];
    if (!isAvail) return;

    NSTimeInterval interval = 1.0 / 60.0;
    NSInvocation *intInv = [NSInvocation invocationWithMethodSignature:[cmClass instanceMethodSignatureForSelector:@selector(setDeviceMotionUpdateInterval:)]];
    [intInv setSelector:@selector(setDeviceMotionUpdateInterval:)];
    [intInv setTarget:self.motionManager];
    [intInv setArgument:&interval atIndex:2];
    [intInv invoke];

    __weak typeof(self) weakSelf = self;
    typedef void (^CMMotionHandler)(id motion, NSError *error);
    CMMotionHandler handler = ^(id motion, NSError *error) {
        if (!motion) return;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.isPhysicsActive || !strongSelf.gravityBehavior) return;
        
        NSMethodSignature *sig = [motion methodSignatureForSelector:@selector(gravity)];
        if (!sig) return;
        NSInvocation *gravInv = [NSInvocation invocationWithMethodSignature:sig];
        [gravInv setSelector:@selector(gravity)];
        [gravInv setTarget:motion];
        [gravInv invoke];
        struct { double x; double y; double z; } grav;
        [gravInv getReturnValue:&grav];
        
        CGFloat gx = (CGFloat)grav.x * 2.5;
        CGFloat gy = -(CGFloat)grav.y * 2.5;
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.gravityBehavior.gravityDirection = CGVectorMake(gx, gy);
        });
    };

    NSMethodSignature *startSig = [cmClass instanceMethodSignatureForSelector:@selector(startDeviceMotionUpdatesToQueue:withHandler:)];
    if (startSig) {
        NSInvocation *startInv = [NSInvocation invocationWithMethodSignature:startSig];
        [startInv setSelector:@selector(startDeviceMotionUpdatesToQueue:withHandler:)];
        [startInv setTarget:self.motionManager];
        NSOperationQueue *q = [NSOperationQueue mainQueue];
        [startInv setArgument:&q atIndex:2];
        [startInv setArgument:&handler atIndex:3];
        [startInv invoke];
    }
}

- (void)setupTopControls {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    blurView.frame = CGRectMake(16, 52, screenW - 32, 105);
    blurView.layer.cornerRadius = 20;
    blurView.layer.masksToBounds = YES;
    [self.view addSubview:blurView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, blurView.bounds.size.width - 32, 22)];
    titleLabel.text = DOLocalizedText(@"SpringBoard Physics (Gravity)", @"Гравитация SpringBoard");
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [blurView.contentView addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 32, blurView.bounds.size.width - 32, 28)];
    subLabel.text = DOLocalizedText(@"Shake to tumble • Tilt phone to steer • Fling icons • Shake to reset", @"Встряхните для падения • Наклоняйте • Бросайте иконки • Встряхните для сброса");
    subLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    subLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    subLabel.textAlignment = NSTextAlignmentCenter;
    subLabel.numberOfLines = 2;
    [blurView.contentView addSubview:subLabel];

    CGFloat btnW = (blurView.bounds.size.width - 48) / 3.0;
    CGFloat btnY = 66;
    CGFloat btnH = 30;

    UIButton *shakeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    shakeBtn.frame = CGRectMake(12, btnY, btnW, btnH);
    [shakeBtn setTitle:DOLocalizedText(@"Drop / Shake", @"Встряхнуть") forState:UIControlStateNormal];
    shakeBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [shakeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    shakeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.35];
    shakeBtn.layer.cornerRadius = 10;
    [shakeBtn addTarget:self action:@selector(togglePhysicsPressed) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:shakeBtn];

    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(12 + btnW + 12, btnY, btnW, btnH);
    [resetBtn setTitle:DOLocalizedText(@"Reset Grid", @"Сброс сетки") forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    resetBtn.layer.cornerRadius = 10;
    [resetBtn addTarget:self action:@selector(resetGridPressed) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:resetBtn];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(12 + (btnW + 12) * 2, btnY, btnW, btnH);
    [closeBtn setTitle:DOLocalizedText(@"Close", @"Закрыть") forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [closeBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.18];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn addTarget:self action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:closeBtn];
}

- (void)setupAppIcons {
    NSArray *apps = @[
        @{@"name": DOLocalizedText(@"Phone", @"Телефон"), @"c1": [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0], @"c2": [UIColor colorWithRed:0.18 green:0.82 blue:0.34 alpha:1.0], @"symbol": @"phone.fill"},
        @{@"name": DOLocalizedText(@"Messages", @"Сообщения"), @"c1": [UIColor colorWithRed:0.18 green:0.82 blue:0.34 alpha:1.0], @"c2": [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0], @"symbol": @"message.fill"},
        @{@"name": @"Safari", @"c1": [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0], @"c2": [UIColor colorWithRed:0.37 green:0.36 blue:0.90 alpha:1.0], @"symbol": @"safari.fill"},
        @{@"name": DOLocalizedText(@"Music", @"Музыка"), @"c1": [UIColor colorWithRed:1.0 green:0.22 blue:0.37 alpha:1.0], @"c2": [UIColor colorWithRed:0.99 green:0.18 blue:0.33 alpha:1.0], @"symbol": @"music.note"},
        @{@"name": DOLocalizedText(@"Photos", @"Фото"), @"c1": [UIColor whiteColor], @"c2": [UIColor colorWithWhite:0.92 alpha:1.0], @"symbol": @"photo.fill", @"dark": @YES},
        @{@"name": DOLocalizedText(@"Camera", @"Камера"), @"c1": [UIColor colorWithRed:0.55 green:0.55 blue:0.57 alpha:1.0], @"c2": [UIColor colorWithRed:0.39 green:0.39 blue:0.40 alpha:1.0], @"symbol": @"camera.fill"},
        @{@"name": DOLocalizedText(@"Settings", @"Настройки"), @"c1": [UIColor colorWithRed:0.55 green:0.55 blue:0.57 alpha:1.0], @"c2": [UIColor colorWithRed:0.28 green:0.28 blue:0.29 alpha:1.0], @"symbol": @"gearshape.fill"},
        @{@"name": @"Dopamine", @"c1": [UIColor colorWithRed:0.35 green:0.34 blue:0.84 alpha:1.0], @"c2": [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1.0], @"symbol": @"flame.fill"},
        @{@"name": @"Sileo", @"c1": [UIColor colorWithRed:0.0 green:0.78 blue:0.75 alpha:1.0], @"c2": [UIColor colorWithRed:0.19 green:0.69 blue:0.78 alpha:1.0], @"symbol": @"cube.box.fill"},
        @{@"name": DOLocalizedText(@"Files", @"Файлы"), @"c1": [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0], @"c2": [UIColor colorWithRed:0.0 green:0.25 blue:0.87 alpha:1.0], @"symbol": @"folder.fill"},
        @{@"name": DOLocalizedText(@"Notes", @"Заметки"), @"c1": [UIColor colorWithRed:1.0 green:0.84 blue:0.04 alpha:1.0], @"c2": [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1.0], @"symbol": @"note.text"},
        @{@"name": DOLocalizedText(@"Mail", @"Почта"), @"c1": [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0], @"c2": [UIColor colorWithRed:0.0 green:0.44 blue:0.89 alpha:1.0], @"symbol": @"envelope.fill"},
        @{@"name": DOLocalizedText(@"Weather", @"Погода"), @"c1": [UIColor colorWithRed:0.39 green:0.82 blue:1.0 alpha:1.0], @"c2": [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0], @"symbol": @"cloud.sun.fill"},
        @{@"name": DOLocalizedText(@"Clock", @"Часы"), @"c1": [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0], @"c2": [UIColor colorWithRed:0.17 green:0.17 blue:0.18 alpha:1.0], @"symbol": @"clock.fill"},
        @{@"name": DOLocalizedText(@"Health", @"Здоровье"), @"c1": [UIColor whiteColor], @"c2": [UIColor colorWithWhite:0.92 alpha:1.0], @"symbol": @"heart.fill", @"red": @YES},
        @{@"name": @"App Store", @"c1": [UIColor colorWithRed:0.0 green:0.47 blue:0.93 alpha:1.0], @"c2": [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0], @"symbol": @"bag.fill"}
    ];

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat iconW = 60;
    CGFloat iconH = 80;
    CGFloat startY = 175;
    CGFloat colW = (screenW - 32) / 4.0;
    CGFloat rowH = 92;

    for (NSInteger i = 0; i < apps.count; i++) {
        NSDictionary *app = apps[i];
        NSInteger col = i % 4;
        NSInteger row = i / 4;
        CGFloat x = 16 + col * colW + (colW - iconW) / 2.0;
        CGFloat y = startY + row * rowH;

        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(x, y, iconW, iconH)];
        
        UIView *squircle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, iconW, iconW)];
        NSString *shape = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_icon_shape"] ?: @"default";
        CGFloat cornerR = 13.5;
        if ([shape isEqualToString:@"circle"]) {
            cornerR = iconW / 2.0;
        } else if ([shape isEqualToString:@"square"]) {
            cornerR = 0.0;
        }
        squircle.layer.cornerRadius = cornerR;
        if (@available(iOS 13.0, *)) {
            squircle.layer.cornerCurve = kCACornerCurveContinuous;
        }
        squircle.layer.masksToBounds = YES;

        CAGradientLayer *grad = [CAGradientLayer layer];
        grad.frame = squircle.bounds;
        grad.colors = @[(id)((UIColor *)app[@"c1"]).CGColor, (id)((UIColor *)app[@"c2"]).CGColor];
        [squircle.layer insertSublayer:grad atIndex:0];

        UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectMake(13, 13, 34, 34)];
        glyph.contentMode = UIViewContentModeScaleAspectFit;
        if (@available(iOS 13.0, *)) {
            glyph.image = [UIImage systemImageNamed:app[@"symbol"]];
        }
        if ([app[@"dark"] boolValue]) {
            glyph.tintColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        } else if ([app[@"red"] boolValue]) {
            glyph.tintColor = [UIColor colorWithRed:1.0 green:0.18 blue:0.33 alpha:1.0];
        } else {
            glyph.tintColor = [UIColor whiteColor];
        }
        [squircle addSubview:glyph];
        [container addSubview:squircle];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(-8, 62, iconW + 16, 16)];
        label.text = app[@"name"];
        label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.layer.shadowColor = [UIColor blackColor].CGColor;
        label.layer.shadowOffset = CGSizeMake(0, 1);
        label.layer.shadowOpacity = 0.8;
        label.layer.shadowRadius = 1.5;
        [container addSubview:label];

        [self.view addSubview:container];
        [self.iconContainers addObject:container];
        self.originalCenters[[NSValue valueWithNonretainedObject:container]] = [NSValue valueWithCGPoint:container.center];
    }
}

- (void)startPhysics {
    if (self.isPhysicsActive) return;
    self.isPhysicsActive = YES;
    [self.impactFeedback impactOccurred];

    self.animator = [[UIDynamicAnimator alloc] initWithReferenceView:self.view];
    self.gravityBehavior = [[UIGravityBehavior alloc] initWithItems:self.iconContainers];
    self.gravityBehavior.gravityDirection = CGVectorMake(0.0, 1.2);

    self.collisionBehavior = [[UICollisionBehavior alloc] initWithItems:self.iconContainers];
    self.collisionBehavior.translatesReferenceBoundsIntoBoundary = YES;
    self.collisionBehavior.collisionMode = UICollisionModeEverything;

    self.itemBehavior = [[UIDynamicItemBehavior alloc] initWithItems:self.iconContainers];
    self.itemBehavior.elasticity = 0.58;
    self.itemBehavior.friction = 0.22;
    self.itemBehavior.resistance = 0.15;
    self.itemBehavior.allowsRotation = YES;

    [self.animator addBehavior:self.gravityBehavior];
    [self.animator addBehavior:self.collisionBehavior];
    [self.animator addBehavior:self.itemBehavior];

    for (UIView *icon in self.iconContainers) {
        CGFloat rx = ((arc4random_uniform(100) / 100.0) - 0.5) * 80.0;
        CGFloat ry = (arc4random_uniform(100) / 100.0) * 60.0;
        [self.itemBehavior addLinearVelocity:CGPointMake(rx, ry) forItem:icon];
        [self.itemBehavior addAngularVelocity:((arc4random_uniform(100) / 100.0) - 0.5) * 4.0 forItem:icon];
    }
}

- (void)resetToGridAnimated:(BOOL)animated {
    if (!self.isPhysicsActive) return;
    self.isPhysicsActive = NO;
    [self.impactFeedback impactOccurred];

    if (self.attachmentBehavior) {
        [self.animator removeBehavior:self.attachmentBehavior];
        self.attachmentBehavior = nil;
    }
    [self.animator removeAllBehaviors];
    self.animator = nil;

    void (^animations)(void) = ^{
        for (UIView *icon in self.iconContainers) {
            NSValue *val = self.originalCenters[[NSValue valueWithNonretainedObject:icon]];
            if (val) {
                icon.center = [val CGPointValue];
            }
            icon.transform = CGAffineTransformIdentity;
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.7 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:animations completion:nil];
    } else {
        animations();
    }
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        if (self.isPhysicsActive) {
            [self resetToGridAnimated:YES];
        } else {
            [self startPhysics];
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint loc = [pan locationInView:self.view];

    if (pan.state == UIGestureRecognizerStateBegan) {
        UIView *hit = nil;
        for (UIView *icon in self.iconContainers) {
            if (CGRectContainsPoint(icon.frame, loc)) {
                hit = icon;
                break;
            }
        }
        if (hit) {
            if (!self.isPhysicsActive) {
                [self startPhysics];
            }
            self.activePanIcon = hit;
            self.attachmentBehavior = [[UIAttachmentBehavior alloc] initWithItem:hit attachedToAnchor:loc];
            [self.animator addBehavior:self.attachmentBehavior];
        }
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        if (self.attachmentBehavior) {
            self.attachmentBehavior.anchorPoint = loc;
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (self.attachmentBehavior) {
            CGPoint vel = [pan velocityInView:self.view];
            [self.animator removeBehavior:self.attachmentBehavior];
            self.attachmentBehavior = nil;
            if (self.activePanIcon && self.itemBehavior) {
                [self.itemBehavior addLinearVelocity:vel forItem:self.activePanIcon];
            }
            self.activePanIcon = nil;
            [self.impactFeedback impactOccurred];
        }
    }
}

- (void)togglePhysicsPressed {
    if (self.isPhysicsActive) {
        [self resetToGridAnimated:YES];
    } else {
        [self startPhysics];
    }
}

- (void)resetGridPressed {
    [self resetToGridAnimated:YES];
}

- (void)closePressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface DOAniTimePreviewViewController : UIViewController
@property (nonatomic, strong) UIView *clockContainer;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *standardTimeLabel;
@property (nonatomic, strong) UIStackView *anitimeStackView;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) UISegmentedControl *styleSegment;
@property (nonatomic, strong) UISegmentedControl *fontSegment;
@property (nonatomic, strong) UISegmentedControl *colorSegment;
@property (nonatomic, strong) UISwitch *anitimeSwitch;
@end

@implementation DOAniTimePreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    CAGradientLayer *bgGrad = [CAGradientLayer layer];
    bgGrad.frame = [UIScreen mainScreen].bounds;
    bgGrad.colors = @[
        (id)[UIColor colorWithRed:0.05 green:0.07 blue:0.15 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.03 blue:0.06 alpha:1.0].CGColor
    ];
    [self.view.layer insertSublayer:bgGrad atIndex:0];

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;

    // Top Header
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(16, 54, screenW - 32, 50)];
    UILabel *headerTitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, topBar.bounds.size.width - 70, 50)];
    headerTitle.text = DOLocalizedText(@"AniTime & AIM Pro Preview", @"Предпросмотр AniTime и AIM Pro");
    headerTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    headerTitle.textColor = [UIColor whiteColor];
    [topBar addSubview:headerTitle];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(topBar.bounds.size.width - 64, 8, 64, 34);
    [closeBtn setTitle:DOLocalizedText(@"Done", @"Готово") forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    closeBtn.layer.cornerRadius = 12;
    [closeBtn addTarget:self action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];
    [self.view addSubview:topBar];

    // Clock Preview Area (Mock Lock Screen)
    self.clockContainer = [[UIView alloc] initWithFrame:CGRectMake(20, 114, screenW - 40, 260)];
    self.clockContainer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    self.clockContainer.layer.cornerRadius = 24;
    self.clockContainer.layer.borderWidth = 1.0;
    self.clockContainer.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.clockContainer.clipsToBounds = YES;
    [self.view addSubview:self.clockContainer];

    // Date Label
    self.dateLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 24, self.clockContainer.bounds.size.width - 20, 24)];
    self.dateLabel.textAlignment = NSTextAlignmentCenter;
    self.dateLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.dateLabel.textColor = [UIColor colorWithWhite:0.9 alpha:0.9];
    [self.clockContainer addSubview:self.dateLabel];

    // Standard / AIM Pro Time Label
    self.standardTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 60, self.clockContainer.bounds.size.width - 20, 100)];
    self.standardTimeLabel.textAlignment = NSTextAlignmentCenter;
    self.standardTimeLabel.font = [UIFont systemFontOfSize:82 weight:UIFontWeightBold];
    self.standardTimeLabel.textColor = [UIColor whiteColor];
    [self.clockContainer addSubview:self.standardTimeLabel];

    // AniTime Stack View
    self.anitimeStackView = [[UIStackView alloc] initWithFrame:CGRectMake(10, 60, self.clockContainer.bounds.size.width - 20, 150)];
    self.anitimeStackView.axis = UILayoutConstraintAxisHorizontal;
    self.anitimeStackView.alignment = UIStackViewAlignmentCenter;
    self.anitimeStackView.distribution = UIStackViewDistributionEqualCentering;
    self.anitimeStackView.spacing = 2;
    [self.clockContainer addSubview:self.anitimeStackView];

    // Subtitle inside clock box
    UILabel *lockSubtitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 222, self.clockContainer.bounds.size.width - 20, 22)];
    lockSubtitle.textAlignment = NSTextAlignmentCenter;
    lockSubtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    lockSubtitle.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    lockSubtitle.text = DOLocalizedText(@"Live Lock Screen Simulation", @"Симуляция экрана блокировки");
    [self.clockContainer addSubview:lockSubtitle];

    // Controls Card (ScrollView / Stack)
    UIScrollView *controlsScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(16, 388, screenW - 32, self.view.bounds.size.height - 398)];
    controlsScroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:controlsScroll];

    CGFloat ctrlY = 0;
    CGFloat ctrlW = screenW - 32;

    // Toggle AniTime
    UIView *toggleRow = [[UIView alloc] initWithFrame:CGRectMake(0, ctrlY, ctrlW, 44)];
    UILabel *toggleLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, ctrlW - 70, 44)];
    toggleLbl.text = DOLocalizedText(@"AniTime Mode (Anime Characters)", @"Режим AniTime (Аниме фигурки)");
    toggleLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    toggleLbl.textColor = [UIColor whiteColor];
    [toggleRow addSubview:toggleLbl];

    self.anitimeSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(ctrlW - 55, 7, 50, 30)];
    self.anitimeSwitch.on = [[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"dopamine_anitime_enabled" fallback:YES];
    [self.anitimeSwitch addTarget:self action:@selector(anitimeSwitchToggled:) forControlEvents:UIControlEventValueChanged];
    [toggleRow addSubview:self.anitimeSwitch];
    [controlsScroll addSubview:toggleRow];
    ctrlY += 52;

    // AniTime Style Segment
    UILabel *styleLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, ctrlY, ctrlW, 22)];
    styleLbl.text = DOLocalizedText(@"AniTime Character Style:", @"Стиль аниме персонажей:");
    styleLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    styleLbl.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    [controlsScroll addSubview:styleLbl];
    ctrlY += 26;

    NSArray *styleItems = @[@"animated", @"static", @"m-static", @"s-static", @"s-animated"];
    self.styleSegment = [[UISegmentedControl alloc] initWithItems:styleItems];
    self.styleSegment.frame = CGRectMake(0, ctrlY, ctrlW, 34);
    NSString *currStyle = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_anitime_style"] ?: @"animated";
    NSInteger styleIdx = [styleItems indexOfObject:currStyle];
    self.styleSegment.selectedSegmentIndex = (styleIdx != NSNotFound) ? styleIdx : 0;
    [self.styleSegment addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
    [controlsScroll addSubview:self.styleSegment];
    ctrlY += 46;

    // AIM Pro Font Segment
    UILabel *fontLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, ctrlY, ctrlW, 22)];
    fontLbl.text = DOLocalizedText(@"AIM Pro Clock Font:", @"Шрифт часов AIM Pro:");
    fontLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    fontLbl.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    [controlsScroll addSubview:fontLbl];
    ctrlY += 26;

    NSArray *fontItems = @[@"rounded", @"stencil", @"serif", @"mono", @"heavy"];
    self.fontSegment = [[UISegmentedControl alloc] initWithItems:fontItems];
    self.fontSegment.frame = CGRectMake(0, ctrlY, ctrlW, 34);
    NSString *currFont = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_aim_font"] ?: @"rounded";
    NSInteger fontIdx = [fontItems indexOfObject:currFont];
    self.fontSegment.selectedSegmentIndex = (fontIdx != NSNotFound) ? fontIdx : 0;
    [self.fontSegment addTarget:self action:@selector(fontChanged:) forControlEvents:UIControlEventValueChanged];
    [controlsScroll addSubview:self.fontSegment];
    ctrlY += 46;

    // AIM Pro Color Segment
    UILabel *colorLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, ctrlY, ctrlW, 22)];
    colorLbl.text = DOLocalizedText(@"AIM Pro Clock Color:", @"Цвет часов AIM Pro:");
    colorLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    colorLbl.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    [controlsScroll addSubview:colorLbl];
    ctrlY += 26;

    NSArray *colorItems = @[@"white", @"sakura", @"cyan", @"sunset", @"gold"];
    self.colorSegment = [[UISegmentedControl alloc] initWithItems:colorItems];
    self.colorSegment.frame = CGRectMake(0, ctrlY, ctrlW, 34);
    NSString *currColor = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_aim_color"] ?: @"white";
    NSInteger colorIdx = [colorItems indexOfObject:currColor];
    self.colorSegment.selectedSegmentIndex = (colorIdx != NSNotFound) ? colorIdx : 0;
    [self.colorSegment addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];
    [controlsScroll addSubview:self.colorSegment];
    ctrlY += 56;

    controlsScroll.contentSize = CGSizeMake(ctrlW, ctrlY + 30);

    [self updateClockDisplay];
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateClockDisplay) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

- (void)closePressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)anitimeSwitchToggled:(UISwitch *)sender {
    [[DOPreferenceManager sharedManager] setPreferenceValue:@(sender.isOn) forKey:@"dopamine_anitime_enabled"];
    [self updateClockDisplay];
}

- (void)styleChanged:(UISegmentedControl *)sender {
    NSArray *styleItems = @[@"animated", @"static", @"m-static", @"s-static", @"s-animated"];
    NSString *val = styleItems[sender.selectedSegmentIndex];
    [[DOPreferenceManager sharedManager] setPreferenceValue:val forKey:@"dopamine_anitime_style"];
    [self updateClockDisplay];
}

- (void)fontChanged:(UISegmentedControl *)sender {
    NSArray *fontItems = @[@"rounded", @"stencil", @"serif", @"mono", @"heavy"];
    NSString *val = fontItems[sender.selectedSegmentIndex];
    [[DOPreferenceManager sharedManager] setPreferenceValue:val forKey:@"dopamine_aim_font"];
    [self updateClockDisplay];
}

- (void)colorChanged:(UISegmentedControl *)sender {
    NSArray *colorItems = @[@"white", @"sakura", @"cyan", @"sunset", @"gold"];
    NSString *val = colorItems[sender.selectedSegmentIndex];
    [[DOPreferenceManager sharedManager] setPreferenceValue:val forKey:@"dopamine_aim_color"];
    [self updateClockDisplay];
}

- (UIFont *)selectedAIMFontWithSize:(CGFloat)size {
    NSString *currFont = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_aim_font"] ?: @"rounded";
    if ([currFont isEqualToString:@"rounded"]) {
        UIFontDescriptor *desc = [[UIFont systemFontOfSize:size weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorDesignRounded];
        return desc ? [UIFont fontWithDescriptor:desc size:size] : [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    } else if ([currFont isEqualToString:@"serif"]) {
        UIFontDescriptor *desc = [[UIFont systemFontOfSize:size weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorDesignSerif];
        return desc ? [UIFont fontWithDescriptor:desc size:size] : [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    } else if ([currFont isEqualToString:@"mono"]) {
        UIFontDescriptor *desc = [[UIFont systemFontOfSize:size weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorDesignMonospaced];
        return desc ? [UIFont fontWithDescriptor:desc size:size] : [UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightBold];
    } else if ([currFont isEqualToString:@"stencil"]) {
        return [UIFont fontWithName:@"Impact" size:size] ?: [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
    } else {
        return [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
    }
}

- (UIColor *)selectedAIMColor {
    NSString *currColor = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_aim_color"] ?: @"white";
    if ([currColor isEqualToString:@"sakura"]) {
        return [UIColor colorWithRed:1.0 green:0.62 blue:0.78 alpha:1.0];
    } else if ([currColor isEqualToString:@"cyan"]) {
        return [UIColor colorWithRed:0.25 green:0.88 blue:1.0 alpha:1.0];
    } else if ([currColor isEqualToString:@"sunset"]) {
        return [UIColor colorWithRed:1.0 green:0.48 blue:0.25 alpha:1.0];
    } else if ([currColor isEqualToString:@"gold"]) {
        return [UIColor colorWithRed:1.0 green:0.84 blue:0.0 alpha:1.0];
    }
    return [UIColor whiteColor];
}

- (UIImage *)anitimeImageForCharacter:(NSString *)ch style:(NSString *)style {
    NSString *resBundlePath = [[NSBundle mainBundle] pathForResource:@"AniTime" ofType:nil];
    if (!resBundlePath) {
        resBundlePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"AniTime"];
    }
    NSString *styleDir = [resBundlePath stringByAppendingPathComponent:style];
    NSString *filename = [ch isEqualToString:@":"] ? @"colon.png" : [NSString stringWithFormat:@"%@.png", ch];
    NSString *imgPath = [styleDir stringByAppendingPathComponent:filename];
    return [UIImage imageWithContentsOfFile:imgPath];
}

- (void)updateClockDisplay {
    NSDate *now = [NSDate date];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale currentLocale];
    df.dateFormat = @"EEEE, d MMMM";
    self.dateLabel.text = [df stringFromDate:now];

    df.dateFormat = @"HH:mm";
    NSString *timeStr = [df stringFromDate:now];

    BOOL anitimeEnabled = self.anitimeSwitch.isOn;
    NSString *currStyle = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_anitime_style"] ?: @"m-static";

    if (anitimeEnabled) {
        self.standardTimeLabel.hidden = YES;
        self.anitimeStackView.hidden = NO;
        for (UIView *sub in self.anitimeStackView.arrangedSubviews) {
            [self.anitimeStackView removeArrangedSubview:sub];
            [sub removeFromSuperview];
        }

        CGFloat digitH = 120.0;
        for (NSUInteger i = 0; i < timeStr.length; i++) {
            NSString *ch = [timeStr substringWithRange:NSMakeRange(i, 1)];
            UIImage *img = [self anitimeImageForCharacter:ch style:currStyle];
            if (img) {
                UIImageView *iv = [[UIImageView alloc] initWithImage:img];
                iv.contentMode = UIViewContentModeScaleAspectFit;
                CGFloat w = (img.size.height > 0) ? (img.size.width / img.size.height * digitH) : 55.0;
                [iv.widthAnchor constraintEqualToConstant:w].active = YES;
                [iv.heightAnchor constraintEqualToConstant:digitH].active = YES;
                [self.anitimeStackView addArrangedSubview:iv];
            } else {
                UILabel *lbl = [UILabel new];
                lbl.text = ch;
                lbl.font = [self selectedAIMFontWithSize:70];
                lbl.textColor = [self selectedAIMColor];
                lbl.textAlignment = NSTextAlignmentCenter;
                [self.anitimeStackView addArrangedSubview:lbl];
            }
        }
    } else {
        self.anitimeStackView.hidden = YES;
        self.standardTimeLabel.hidden = NO;
        self.standardTimeLabel.text = timeStr;
        self.standardTimeLabel.font = [self selectedAIMFontWithSize:82];
        self.standardTimeLabel.textColor = [self selectedAIMColor];
    }
}

@end

@interface DOSettingsController ()

@end

@implementation DOSettingsController

- (void)viewDidLoad
{
    _lastKnownTheme = [[DOThemeManager sharedInstance] enabledTheme].key;
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)arg1
{
    [super viewWillAppear:arg1];
    if (_lastKnownTheme != [[DOThemeManager sharedInstance] enabledTheme].key)
    {
        [DOSceneDelegate relaunch];
        NSString *icon = [[DOThemeManager sharedInstance] enabledTheme].icon;
        [[UIApplication sharedApplication] setAlternateIconName:icon completionHandler:^(NSError * _Nullable error) {
            if (error)
                NSLog(@"Error changing app icon: %@", error);
        }];

        if ([DOEnvironmentManager sharedManager].isJailbroken) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [[DOEnvironmentManager sharedManager] updateBootLogo];
            });
        }
    }
}

- (NSArray *)availableKernelExploitIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (DOExploit *exploit in _availableKernelExploits) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availableKernelExploitNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (DOExploit *exploit in _availableKernelExploits) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)availablePACBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    if (![DOEnvironmentManager sharedManager].isPACBypassRequired) {
        [identifiers addObject:@"none"];
    }
    for (DOExploit *exploit in _availablePACBypasses) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availablePACBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    if (![DOEnvironmentManager sharedManager].isPACBypassRequired) {
        [names addObject:DOLocalizedString(@"None")];
    }
    for (DOExploit *exploit in _availablePACBypasses) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)availablePPLBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (DOExploit *exploit in _availablePPLBypasses) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availablePPLBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (DOExploit *exploit in _availablePPLBypasses) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)themeIdentifiers
{
    return [[DOThemeManager sharedInstance] getAvailableThemeKeys];
}

- (NSArray *)themeNames
{
    return [[DOThemeManager sharedInstance] getAvailableThemeNames];
}

- (NSArray *)jetsamOptionNumbers
{
    return @[
    @2,
    @3,
    @4,
    @5,
    @6,
    @7,
    @8,
    ];
}

- (NSArray *)jetsamOptionTitles
{
    return @[
        @"1x",
        @"1.5x",
        @"2x",
        @"2.5x",
        [NSString stringWithFormat:@"3x (%@)", DOLocalizedString(@"Recommended")],
        @"3.5x",
        @"4x",
    ];
}

- (id)specifiers
{
    if(_specifiers == nil) {
        NSMutableArray *specifiers = [NSMutableArray new];
        DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
        DOExploitManager *exploitManager = [DOExploitManager sharedManager];

        NSNumber *buttonHeight = @(44);
        
        SEL defGetter = @selector(readPreferenceValue:);
        SEL defSetter = @selector(setPreferenceValue:specifier:);
        SEL expGetter = @selector(readExploitPreferenceValue:);
        
        NSSortDescriptor *prioritySortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"priority" ascending:NO];
        
        _availableKernelExploits = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_KERNEL] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
        if (envManager.isArm64e) {
            _availablePACBypasses = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_PAC] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
            _availablePPLBypasses = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_PPL] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
        }
        
        PSSpecifier *headerSpecifier = [PSSpecifier emptyGroupSpecifier];
        [headerSpecifier setProperty:@"DOHeaderCell" forKey:@"headerCellClass"];
        [headerSpecifier setProperty:[NSString stringWithFormat:@"Settings"] forKey:@"title"];
        [specifiers addObject:headerSpecifier];
        
        if (envManager.isSupported) {
            if (!envManager.isJailbroken) {
                PSSpecifier *exploitGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
                exploitGroupSpecifier.name = DOLocalizedString(@"Section_Exploits");
                [specifiers addObject:exploitGroupSpecifier];
                
                PSSpecifier *kernelExploitSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Kernel Exploit") target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                [kernelExploitSpecifier setProperty:@YES forKey:@"enabled"];
                [kernelExploitSpecifier setProperty:exploitManager.preferredKernelExploit.identifier forKey:@"default"];
                kernelExploitSpecifier.detailControllerClass = [DOPSExploitListItemsController class];
                [kernelExploitSpecifier setProperty:@"availableKernelExploitIdentifiers" forKey:@"valuesDataSource"];
                [kernelExploitSpecifier setProperty:@"availableKernelExploitNames" forKey:@"titlesDataSource"];
                [kernelExploitSpecifier setProperty:@"selectedKernelExploit" forKey:@"key"];
                [kernelExploitSpecifier setProperty:(_availableKernelExploits.firstObject.identifier ?: @"none") forKey:@"recommendedExploitIdentifier"];
                [specifiers addObject:kernelExploitSpecifier];
                
                if (envManager.isArm64e) {
                    PSSpecifier *pacBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"PAC Bypass") target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                    [pacBypassSpecifier setProperty:@YES forKey:@"enabled"];
                    DOExploit *preferredPACBypass = exploitManager.preferredPACBypass;
                    if (!preferredPACBypass) {
                        [pacBypassSpecifier setProperty:@"none" forKey:@"default"];
                    }
                    else {
                        [pacBypassSpecifier setProperty:preferredPACBypass.identifier forKey:@"default"];
                    }
                    pacBypassSpecifier.detailControllerClass = [DOPSExploitListItemsController class];
                    [pacBypassSpecifier setProperty:@"availablePACBypassIdentifiers" forKey:@"valuesDataSource"];
                    [pacBypassSpecifier setProperty:@"availablePACBypassNames" forKey:@"titlesDataSource"];
                    [pacBypassSpecifier setProperty:@"selectedPACBypass" forKey:@"key"];
                    [pacBypassSpecifier setProperty:([envManager isPACBypassRequired] ? _availablePACBypasses.firstObject.identifier : @"none") forKey:@"recommendedExploitIdentifier"];
                    [specifiers addObject:pacBypassSpecifier];
                    
                    NSString *pplBypassName = @"PPL Bypass";
                    if ([DOEnvironmentManager sharedManager].isSPTM) {
                        // SPTM bypasses are also handled as PPL bypasses in the code, we just change the name of the setting in the UI
                        pplBypassName = @"SPTM Bypass";
                    }

                    PSSpecifier *pplBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(pplBypassName) target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                    [pplBypassSpecifier setProperty:@YES forKey:@"enabled"];
                    [pplBypassSpecifier setProperty:exploitManager.preferredPPLBypass.identifier forKey:@"default"];
                    pplBypassSpecifier.detailControllerClass = [DOPSExploitListItemsController class];
                    [pplBypassSpecifier setProperty:@"availablePPLBypassIdentifiers" forKey:@"valuesDataSource"];
                    [pplBypassSpecifier setProperty:@"availablePPLBypassNames" forKey:@"titlesDataSource"];
                    [pplBypassSpecifier setProperty:@"selectedPPLBypass" forKey:@"key"];
                    [pplBypassSpecifier setProperty:(_availablePPLBypasses.firstObject.identifier ?: @"none") forKey:@"recommendedExploitIdentifier"];
                    [specifiers addObject:pplBypassSpecifier];
                }
            }
            
            PSSpecifier *settingsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            settingsGroupSpecifier.name = DOLocalizedString(@"Section_Jailbreak_Settings");
            [specifiers addObject:settingsGroupSpecifier];
            
            PSSpecifier *tweakInjectionSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Tweak_Injection") target:self set:@selector(setTweakInjectionEnabled:specifier:) get:@selector(readTweakInjectionEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [tweakInjectionSpecifier setProperty:@YES forKey:@"enabled"];
            [tweakInjectionSpecifier setProperty:@"tweakInjectionEnabled" forKey:@"key"];
            [tweakInjectionSpecifier setProperty:@YES forKey:@"default"];
            [specifiers addObject:tweakInjectionSpecifier];
            
            if (!envManager.isJailbroken) {
                PSSpecifier *verboseLogSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Verbose_Logs") target:self set:defSetter get:defGetter detail:nil cell:PSSwitchCell edit:nil];
                [verboseLogSpecifier setProperty:@YES forKey:@"enabled"];
                [verboseLogSpecifier setProperty:@"verboseLogsEnabled" forKey:@"key"];
                [verboseLogSpecifier setProperty:@NO forKey:@"default"];
                [specifiers addObject:verboseLogSpecifier];
            }
            
            PSSpecifier *idownloadSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_iDownload") target:self set:@selector(setIDownloadEnabled:specifier:) get:@selector(readIDownloadEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [idownloadSpecifier setProperty:@YES forKey:@"enabled"];
            [idownloadSpecifier setProperty:@"idownloadEnabled" forKey:@"key"];
            [idownloadSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:idownloadSpecifier];
            
            PSSpecifier *appJitSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Apps_JIT") target:self set:@selector(setAppJITEnabled:specifier:) get:@selector(readAppJITEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [appJitSpecifier setProperty:@YES forKey:@"enabled"];
            [appJitSpecifier setProperty:@"appJITEnabled" forKey:@"key"];
            [appJitSpecifier setProperty:@YES forKey:@"default"];
            [specifiers addObject:appJitSpecifier];
            
            PSSpecifier *jetsamSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Jetsam_Multiplier") target:self set:@selector(setJetsamMultiplier:specifier:) get:@selector(readJetsamMultiplier:) detail:nil cell:PSLinkListCell edit:nil];
            [jetsamSpecifier setProperty:@YES forKey:@"enabled"];
            [jetsamSpecifier setProperty:@"jetsamMultiplier" forKey:@"key"];
            [jetsamSpecifier setProperty:@6 forKey:@"default"];
            jetsamSpecifier.detailControllerClass = [DOPSJetsamListItemsController class];
            [jetsamSpecifier setProperty:@"jetsamOptionNumbers" forKey:@"valuesDataSource"];
            [jetsamSpecifier setProperty:@"jetsamOptionTitles" forKey:@"titlesDataSource"];
            [specifiers addObject:jetsamSpecifier];
            
            if (!envManager.isJailbroken && !envManager.isInstalledThroughTrollStore) {
                PSSpecifier *removeJailbreakSwitchSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Button_Remove_Jailbreak") target:self set:@selector(setRemoveJailbreakEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
                [removeJailbreakSwitchSpecifier setProperty:@YES forKey:@"enabled"];
                [removeJailbreakSwitchSpecifier setProperty:@"removeJailbreakEnabled" forKey:@"key"];
                [specifiers addObject:removeJailbreakSwitchSpecifier];
            }

            if (envManager.isBootstrapped) {
                PSSpecifier *actionsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
                actionsGroupSpecifier.name = DOLocalizedString(@"Section_Actions");
                [specifiers addObject:actionsGroupSpecifier];

                if (envManager.isJailbroken) {
                    PSSpecifier *refreshAppsSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [refreshAppsSpecifier setProperty:@"Button_Refresh_Jailbreak_Apps" forKey:@"title"];
                    [refreshAppsSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [refreshAppsSpecifier setProperty:buttonHeight forKey:@"height"];
                    [refreshAppsSpecifier setProperty:@"arrow.triangle.2.circlepath" forKey:@"image"];
                    [refreshAppsSpecifier setProperty:@"refreshJailbreakAppsPressed" forKey:@"action"];
                    [specifiers addObject:refreshAppsSpecifier];
                    
                    PSSpecifier *changeMobilePasswordSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [changeMobilePasswordSpecifier setProperty:@"Button_Change_Mobile_Password" forKey:@"title"];
                    [changeMobilePasswordSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [changeMobilePasswordSpecifier setProperty:buttonHeight forKey:@"height"];
                    [changeMobilePasswordSpecifier setProperty:@"key" forKey:@"image"];
                    [changeMobilePasswordSpecifier setProperty:@"changeMobilePasswordWithAuthenticationPressed" forKey:@"action"];
                    [specifiers addObject:changeMobilePasswordSpecifier];
                    
                    PSSpecifier *reinstallPackageManagersSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [reinstallPackageManagersSpecifier setProperty:@"Button_Reinstall_Package_Managers" forKey:@"title"];
                    [reinstallPackageManagersSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [reinstallPackageManagersSpecifier setProperty:buttonHeight forKey:@"height"];
                    if (@available(iOS 16.0, *))
                        [reinstallPackageManagersSpecifier setProperty:@"shippingbox.and.arrow.backward" forKey:@"image"];
                    else
                        [reinstallPackageManagersSpecifier setProperty:@"shippingbox" forKey:@"image"];
                    [reinstallPackageManagersSpecifier setProperty:@"reinstallPackageManagersPressed" forKey:@"action"];
                    [specifiers addObject:reinstallPackageManagersSpecifier];
                }

                if (envManager.isJailbroken || envManager.isInstalledThroughTrollStore) {
                    PSSpecifier *removeJailbreakSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [removeJailbreakSpecifier setProperty:@"Button_Remove_Jailbreak" forKey:@"title"];
                    [removeJailbreakSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
                    [removeJailbreakSpecifier setProperty:buttonHeight forKey:@"height"];
                    [removeJailbreakSpecifier setProperty:@"trash" forKey:@"image"];
                    [removeJailbreakSpecifier setProperty:@"removeJailbreakPressed" forKey:@"action"];
                    [specifiers addObject:removeJailbreakSpecifier];
                }
            }
        }

        PSSpecifier *langGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
        langGroupSpecifier.name = DOLocalizedText(@"Language", @"Язык");
        [specifiers addObject:langGroupSpecifier];

        PSSpecifier *languageSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"App Language", @"Язык приложения") target:self set:@selector(setAppLanguage:specifier:) get:@selector(readAppLanguage:) detail:nil cell:PSLinkListCell edit:nil];
        languageSpecifier.detailControllerClass = [DOPSListItemsController class];
        [languageSpecifier setProperty:@YES forKey:@"enabled"];
        [languageSpecifier setProperty:@"appLanguage" forKey:@"key"];
        [languageSpecifier setProperty:@"default" forKey:@"default"];
        [languageSpecifier setProperty:@"languageIdentifiers" forKey:@"valuesDataSource"];
        [languageSpecifier setProperty:@"languageNames" forKey:@"titlesDataSource"];
        [specifiers addObject:languageSpecifier];
        
        PSSpecifier *themingGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
        themingGroupSpecifier.name = DOLocalizedString(@"Section_Customization");
        [specifiers addObject:themingGroupSpecifier];
        
        PSSpecifier *themeSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Theme") target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
        themeSpecifier.detailControllerClass = [DOPSListItemsController class];
        [themeSpecifier setProperty:@YES forKey:@"enabled"];
        [themeSpecifier setProperty:@"theme" forKey:@"key"];
        [themeSpecifier setProperty:[[self themeIdentifiers] firstObject] forKey:@"default"];
        [themeSpecifier setProperty:@"themeIdentifiers" forKey:@"valuesDataSource"];
        [themeSpecifier setProperty:@"themeNames" forKey:@"titlesDataSource"];
        [specifiers addObject:themeSpecifier];

        PSSpecifier *bootlogoGropSpecifier = [PSSpecifier emptyGroupSpecifier];
        bootlogoGropSpecifier.name = DOLocalizedString(@"Section_Boot_Logo");
        [specifiers addObject:bootlogoGropSpecifier];

        PSSpecifier *bootlogoEnabledSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Enabled") target:self set:@selector(setBootlogoEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
        [bootlogoEnabledSpecifier setProperty:@YES forKey:@"enabled"];
        [bootlogoEnabledSpecifier setProperty:@"bootlogoEnabled" forKey:@"key"];
        [bootlogoEnabledSpecifier setProperty:@YES forKey:@"default"];
        bootlogoEnabledSpecifier.identifier = @"bootlogoEnabled";
        [specifiers addObject:bootlogoEnabledSpecifier];

        _customBootlogoEnabledSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Custom_Boot_Logo") target:self set:@selector(setCustomBootlogoEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
        [_customBootlogoEnabledSpecifier setProperty:@YES forKey:@"enabled"];
        [_customBootlogoEnabledSpecifier setProperty:@"customBootlogoEnabled" forKey:@"key"];
        [_customBootlogoEnabledSpecifier setProperty:@NO forKey:@"default"];
        _customBootlogoEnabledSpecifier.identifier = @"customBootlogoEnabled";

        _customBootlogoSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Select_Image") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
        _customBootlogoSpecifier.buttonAction = @selector(selectCustomBootlogoPressed);
        [_customBootlogoSpecifier setProperty:@YES forKey:@"enabled"];
        [_customBootlogoSpecifier setProperty:@"customBootlogo" forKey:@"key"];
        _customBootlogoSpecifier.identifier = @"customBootlogo";

        if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"bootlogoEnabled" fallback:YES]) {
            [specifiers addObject:_customBootlogoEnabledSpecifier];

            if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"customBootlogoEnabled" fallback:NO]) {
                [specifiers addObject:_customBootlogoSpecifier];
            }
        }

        // --- Dopamine System Tweaks & Customizations (Available after Jailbreak) ---
        if (envManager.isJailbroken) {
            PSSpecifier *dopamineActionsGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineActionsGroup.name = DOLocalizedText(@"Dopamine Tweaks Management", @"Управление твиками");
            [specifiers addObject:dopamineActionsGroup];

            PSSpecifier *applyModificationsSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
            [applyModificationsSpecifier setProperty:DOLocalizedText(@"Apply Dopamine Tweaks & Respring", @"Применить твики Dopamine и респринг") forKey:@"title"];
            [applyModificationsSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
            [applyModificationsSpecifier setProperty:buttonHeight forKey:@"height"];
            [applyModificationsSpecifier setProperty:@"checkmark.circle" forKey:@"image"];
            [applyModificationsSpecifier setProperty:@"applyDopamineChangesPressed" forKey:@"action"];
            [specifiers addObject:applyModificationsSpecifier];

            PSSpecifier *resetTweaksSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
            [resetTweaksSpecifier setProperty:DOLocalizedText(@"Reset All Tweaks to Default", @"Сбросить все кастомные твики") forKey:@"title"];
            [resetTweaksSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
            [resetTweaksSpecifier setProperty:buttonHeight forKey:@"height"];
            [resetTweaksSpecifier setProperty:@"arrow.counterclockwise.circle" forKey:@"image"];
            [resetTweaksSpecifier setProperty:@"resetAllTweaksPressed" forKey:@"action"];
            [specifiers addObject:resetTweaksSpecifier];

            PSSpecifier *sideloadSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
            [sideloadSpecifier setProperty:DOLocalizedText(@"Sideload IPA / Install DEB (LiveContainer)", @"Установить IPA / DEB (LiveContainer)") forKey:@"title"];
            [sideloadSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
            [sideloadSpecifier setProperty:buttonHeight forKey:@"height"];
            [sideloadSpecifier setProperty:@"square.and.arrow.down" forKey:@"image"];
            [sideloadSpecifier setProperty:@"sideloadIPAPressed" forKey:@"action"];
            [specifiers addObject:sideloadSpecifier];

            PSSpecifier *dopamineWallpaperGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineWallpaperGroup.name = DOLocalizedText(@"Dopamine - Custom Wallpapers & PosterBoard", @"Dopamine - Кастомные обои и PosterBoard");
            [specifiers addObject:dopamineWallpaperGroup];

            PSSpecifier *liveWallpaperSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Import Animated / Video Wallpaper (Files)", @"Загрузить анимированные обои (Файлы)") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            liveWallpaperSpecifier.buttonAction = @selector(selectLiveVideoWallpaperPressed);
            [liveWallpaperSpecifier setProperty:@YES forKey:@"enabled"];
            [liveWallpaperSpecifier setProperty:@"liveWallpaperBtn" forKey:@"key"];
            [specifiers addObject:liveWallpaperSpecifier];

            PSSpecifier *resetPosterboardSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Reset Wallpapers & PosterBoard", @"Сбросить обои и PosterBoard") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            resetPosterboardSpecifier.buttonAction = @selector(resetPosterboardPressed);
            [resetPosterboardSpecifier setProperty:@YES forKey:@"enabled"];
            [resetPosterboardSpecifier setProperty:@"resetPosterboardBtn" forKey:@"key"];
            [specifiers addObject:resetPosterboardSpecifier];

            // 1. Dynamic Island & Hardware (Gestalt)
            PSSpecifier *dopamineGestaltGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineGestaltGroup.name = DOLocalizedText(@"Dopamine - Dynamic Island & Hardware", @"Dopamine - Dynamic Island и оборудование");
            [specifiers addObject:dopamineGestaltGroup];

            PSSpecifier *dynamicIslandSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Dynamic Island", @"Dynamic Island") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [dynamicIslandSpecifier setProperty:@YES forKey:@"enabled"];
            [dynamicIslandSpecifier setProperty:@"dopamine_dynamic_island" forKey:@"key"];
            [dynamicIslandSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:dynamicIslandSpecifier];

            PSSpecifier *stageManagerSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Stage Manager UI", @"Интерфейс Stage Manager") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [stageManagerSpecifier setProperty:@YES forKey:@"enabled"];
            [stageManagerSpecifier setProperty:@"dopamine_stage_manager" forKey:@"key"];
            [stageManagerSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:stageManagerSpecifier];

            PSSpecifier *aodSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Always-On Display (AOD)", @"Всегда включенный экран (AOD)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [aodSpecifier setProperty:@YES forKey:@"enabled"];
            [aodSpecifier setProperty:@"dopamine_always_on_display" forKey:@"key"];
            [aodSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:aodSpecifier];

            PSSpecifier *aodVibrancySpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"AOD Full Vibrancy / Brightness", @"AOD полная яркость и контраст") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [aodVibrancySpecifier setProperty:@YES forKey:@"enabled"];
            [aodVibrancySpecifier setProperty:@"dopamine_aod_vibrancy" forKey:@"key"];
            [aodVibrancySpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:aodVibrancySpecifier];

            PSSpecifier *bootChimeSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Mac Boot Chime on Power", @"Звук включения Mac при запуске") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [bootChimeSpecifier setProperty:@YES forKey:@"enabled"];
            [bootChimeSpecifier setProperty:@"dopamine_boot_chime" forKey:@"key"];
            [bootChimeSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:bootChimeSpecifier];

            PSSpecifier *chargeLimitSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"80% Charge Limit Option", @"Ограничение заряда 80%") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [chargeLimitSpecifier setProperty:@YES forKey:@"enabled"];
            [chargeLimitSpecifier setProperty:@"dopamine_charge_limit" forKey:@"key"];
            [chargeLimitSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:chargeLimitSpecifier];

            PSSpecifier *tapToWakeSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Tap To Wake", @"Касание для активации") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [tapToWakeSpecifier setProperty:@YES forKey:@"enabled"];
            [tapToWakeSpecifier setProperty:@"dopamine_tap_to_wake" forKey:@"key"];
            [tapToWakeSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:tapToWakeSpecifier];

            PSSpecifier *actionButtonSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Action Button Settings", @"Настройки Action Button") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [actionButtonSpecifier setProperty:@YES forKey:@"enabled"];
            [actionButtonSpecifier setProperty:@"dopamine_action_button" forKey:@"key"];
            [actionButtonSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:actionButtonSpecifier];

            PSSpecifier *cameraButtonSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Camera Control Button", @"Кнопка управления камерой") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [cameraButtonSpecifier setProperty:@YES forKey:@"enabled"];
            [cameraButtonSpecifier setProperty:@"dopamine_camera_button" forKey:@"key"];
            [cameraButtonSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:cameraButtonSpecifier];

            PSSpecifier *collisionSosSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Crash Detection / Collision SOS", @"Детекция аварий / SOS") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [collisionSosSpecifier setProperty:@YES forKey:@"enabled"];
            [collisionSosSpecifier setProperty:@"dopamine_collision_sos" forKey:@"key"];
            [collisionSosSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:collisionSosSpecifier];

            PSSpecifier *ipadAppsSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"iPad Multitasking & Apps", @"Разрешить iPad приложения") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [ipadAppsSpecifier setProperty:@YES forKey:@"enabled"];
            [ipadAppsSpecifier setProperty:@"dopamine_ipad_apps" forKey:@"key"];
            [ipadAppsSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:ipadAppsSpecifier];

            PSSpecifier *shutterMuteSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Mute Camera Shutter (US Region)", @"Отключить звук затвора камеры") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [shutterMuteSpecifier setProperty:@YES forKey:@"enabled"];
            [shutterMuteSpecifier setProperty:@"dopamine_shutter_mute" forKey:@"key"];
            [shutterMuteSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:shutterMuteSpecifier];

            PSSpecifier *pencilSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Apple Pencil UI Support", @"Поддержка Apple Pencil") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [pencilSpecifier setProperty:@YES forKey:@"enabled"];
            [pencilSpecifier setProperty:@"dopamine_apple_pencil" forKey:@"key"];
            [pencilSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:pencilSpecifier];

            PSSpecifier *internalStorageSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Internal Storage Diagnostics", @"Интерфейс внутренней памяти") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [internalStorageSpecifier setProperty:@YES forKey:@"enabled"];
            [internalStorageSpecifier setProperty:@"dopamine_internal_storage" forKey:@"key"];
            [internalStorageSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:internalStorageSpecifier];

            // 2. SpringBoard & System Options
            PSSpecifier *dopamineSpringboardGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineSpringboardGroup.name = DOLocalizedText(@"Dopamine - SpringBoard & System", @"Dopamine - SpringBoard и система");
            [specifiers addObject:dopamineSpringboardGroup];

            PSSpecifier *gravityToggleSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"SpringBoard Physics (Gravity)", @"Гравитация иконок (SpringBoard Physics)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [gravityToggleSpecifier setProperty:@YES forKey:@"enabled"];
            [gravityToggleSpecifier setProperty:@"dopamine_icon_gravity" forKey:@"key"];
            [gravityToggleSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:gravityToggleSpecifier];

            PSSpecifier *gravityPlaygroundSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Launch Physics Playground", @"Открыть симуляцию физики") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            gravityPlaygroundSpecifier.buttonAction = @selector(launchPhysicsPlaygroundPressed);
            [gravityPlaygroundSpecifier setProperty:@YES forKey:@"enabled"];
            [gravityPlaygroundSpecifier setProperty:@"gravityPlaygroundBtn" forKey:@"key"];
            [specifiers addObject:gravityPlaygroundSpecifier];

            PSSpecifier *appleInternalSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"AppleInternal & PrototypeTools", @"AppleInternal и PrototypeTools") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [appleInternalSpecifier setProperty:@YES forKey:@"enabled"];
            [appleInternalSpecifier setProperty:@"dopamine_apple_internal" forKey:@"key"];
            [appleInternalSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:appleInternalSpecifier];

            PSSpecifier *iconShapeSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"App Icon Shape", @"Форма иконок приложений") target:self set:@selector(setDopamineValue:specifier:) get:@selector(readDopamineValue:) detail:[DOPSListItemsController class] cell:PSLinkListCell edit:nil];
            [iconShapeSpecifier setProperty:@"iconShapeIdentifiers" forKey:@"valuesDataSource"];
            [iconShapeSpecifier setProperty:@"iconShapeNames" forKey:@"titlesDataSource"];
            [iconShapeSpecifier setProperty:@"dopamine_icon_shape" forKey:@"key"];
            [iconShapeSpecifier setProperty:@"default" forKey:@"default"];
            [specifiers addObject:iconShapeSpecifier];

            PSSpecifier *animSpeedSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Animation Speed Scale", @"Скорость системных анимаций") target:self set:@selector(setDopamineValue:specifier:) get:@selector(readDopamineValue:) detail:[DOPSListItemsController class] cell:PSLinkListCell edit:nil];
            [animSpeedSpecifier setProperty:@"animSpeedIdentifiers" forKey:@"valuesDataSource"];
            [animSpeedSpecifier setProperty:@"animSpeedNames" forKey:@"titlesDataSource"];
            [animSpeedSpecifier setProperty:@"dopamine_anim_speed" forKey:@"key"];
            [animSpeedSpecifier setProperty:@"1.0" forKey:@"default"];
            [specifiers addObject:animSpeedSpecifier];

            PSSpecifier *pageFxSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Page Transition Effect", @"Эффект перелистывания страниц") target:self set:@selector(setDopamineValue:specifier:) get:@selector(readDopamineValue:) detail:[DOPSListItemsController class] cell:PSLinkListCell edit:nil];
            [pageFxSpecifier setProperty:@"pageFxIdentifiers" forKey:@"valuesDataSource"];
            [pageFxSpecifier setProperty:@"pageFxNames" forKey:@"titlesDataSource"];
            [pageFxSpecifier setProperty:@"dopamine_page_scroll_fx" forKey:@"key"];
            [pageFxSpecifier setProperty:@"default" forKey:@"default"];
            [specifiers addObject:pageFxSpecifier];

            // 2.5 AniTime & AIM Pro Lock Screen Clock
            PSSpecifier *dopamineLockScreenGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineLockScreenGroup.name = DOLocalizedText(@"Dopamine - AniTime & AIM Pro Clock", @"Dopamine - AniTime и AIM Pro часы");
            [specifiers addObject:dopamineLockScreenGroup];

            PSSpecifier *anitimeToggleSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"AniTime (Anime Clock)", @"AniTime (Аниме фигурки часов)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [anitimeToggleSpecifier setProperty:@YES forKey:@"enabled"];
            [anitimeToggleSpecifier setProperty:@"dopamine_anitime_enabled" forKey:@"key"];
            [anitimeToggleSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:anitimeToggleSpecifier];

            PSSpecifier *anitimePreviewSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Preview AniTime & AIM Pro Clock", @"Предпросмотр AniTime и AIM Pro") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            anitimePreviewSpecifier.buttonAction = @selector(previewAniTimePressed);
            [anitimePreviewSpecifier setProperty:@YES forKey:@"enabled"];
            [anitimePreviewSpecifier setProperty:@"previewAniTimeBtn" forKey:@"key"];
            [specifiers addObject:anitimePreviewSpecifier];

            PSSpecifier *anitimeStyleSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"AniTime Character Style", @"Стиль аниме персонажей") target:self set:@selector(setDopamineValue:specifier:) get:@selector(readDopamineValue:) detail:[DOPSListItemsController class] cell:PSLinkListCell edit:nil];
            [anitimeStyleSpecifier setProperty:@"anitimeStyleIdentifiers" forKey:@"valuesDataSource"];
            [anitimeStyleSpecifier setProperty:@"anitimeStyleNames" forKey:@"titlesDataSource"];
            [anitimeStyleSpecifier setProperty:@"dopamine_anitime_style" forKey:@"key"];
            [anitimeStyleSpecifier setProperty:@"m-static" forKey:@"default"];
            [specifiers addObject:anitimeStyleSpecifier];

            PSSpecifier *aimProToggleSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"AIM Pro (Custom Lock Clock)", @"AIM Pro (Кастомизация часов)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [aimProToggleSpecifier setProperty:@YES forKey:@"enabled"];
            [aimProToggleSpecifier setProperty:@"dopamine_aim_pro_enabled" forKey:@"key"];
            [aimProToggleSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:aimProToggleSpecifier];

            PSSpecifier *aimFontSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"AIM Pro Clock Font", @"Шрифт часов AIM Pro") target:self set:@selector(setDopamineValue:specifier:) get:@selector(readDopamineValue:) detail:[DOPSListItemsController class] cell:PSLinkListCell edit:nil];
            [aimFontSpecifier setProperty:@"aimFontIdentifiers" forKey:@"valuesDataSource"];
            [aimFontSpecifier setProperty:@"aimFontNames" forKey:@"titlesDataSource"];
            [aimFontSpecifier setProperty:@"dopamine_aim_font" forKey:@"key"];
            [aimFontSpecifier setProperty:@"rounded" forKey:@"default"];
            [specifiers addObject:aimFontSpecifier];

            PSSpecifier *aimColorSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"AIM Pro Clock Color", @"Цвет часов AIM Pro") target:self set:@selector(setDopamineValue:specifier:) get:@selector(readDopamineValue:) detail:[DOPSListItemsController class] cell:PSLinkListCell edit:nil];
            [aimColorSpecifier setProperty:@"aimColorIdentifiers" forKey:@"valuesDataSource"];
            [aimColorSpecifier setProperty:@"aimColorNames" forKey:@"titlesDataSource"];
            [aimColorSpecifier setProperty:@"dopamine_aim_color" forKey:@"key"];
            [aimColorSpecifier setProperty:@"white" forKey:@"default"];
            [specifiers addObject:aimColorSpecifier];

            PSSpecifier *footnoteSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Lock Screen Footnote Text", @"Текст внизу экрана блокировки") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            footnoteSpecifier.buttonAction = @selector(setLockscreenFootnotePressed);
            [footnoteSpecifier setProperty:@YES forKey:@"enabled"];
            [footnoteSpecifier setProperty:@"footnoteBtn" forKey:@"key"];
            [specifiers addObject:footnoteSpecifier];

            PSSpecifier *hideDIInScreenshotsSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Show Dynamic Island in Screenshots", @"Dynamic Island на скриншотах") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [hideDIInScreenshotsSpecifier setProperty:@YES forKey:@"enabled"];
            [hideDIInScreenshotsSpecifier setProperty:@"dopamine_di_in_screenshots" forKey:@"key"];
            [hideDIInScreenshotsSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:hideDIInScreenshotsSpecifier];

            PSSpecifier *hideDICompletelySpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Hide Dynamic Island Completely", @"Полностью скрыть Dynamic Island") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [hideDICompletelySpecifier setProperty:@YES forKey:@"enabled"];
            [hideDICompletelySpecifier setProperty:@"dopamine_hide_di_completely" forKey:@"key"];
            [hideDICompletelySpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:hideDICompletelySpecifier];

            PSSpecifier *disableLowPowerAlertsSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Low Power 20% Alert", @"Отключить уведомление о 20% заряда") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableLowPowerAlertsSpecifier setProperty:@YES forKey:@"enabled"];
            [disableLowPowerAlertsSpecifier setProperty:@"dopamine_disable_lpm_alert" forKey:@"key"];
            [disableLowPowerAlertsSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableLowPowerAlertsSpecifier];

            PSSpecifier *disableAirDropLimitSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable 10-Min AirDrop Limit", @"AirDrop Для всех без таймаута") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableAirDropLimitSpecifier setProperty:@YES forKey:@"enabled"];
            [disableAirDropLimitSpecifier setProperty:@"dopamine_airdrop_limit" forKey:@"key"];
            [disableAirDropLimitSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableAirDropLimitSpecifier];

            PSSpecifier *clockAnimSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"SwiftUI Clock Flip Animation", @"Анимация часов SwiftUI") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [clockAnimSpecifier setProperty:@YES forKey:@"enabled"];
            [clockAnimSpecifier setProperty:@"dopamine_clock_animation" forKey:@"key"];
            [clockAnimSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:clockAnimSpecifier];

            PSSpecifier *dontDimOnACSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Never Dim/Lock While Charging", @"Не гасить экран при зарядке") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [dontDimOnACSpecifier setProperty:@YES forKey:@"enabled"];
            [dontDimOnACSpecifier setProperty:@"dopamine_sb_dont_dim_ac" forKey:@"key"];
            [dontDimOnACSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:dontDimOnACSpecifier];

            PSSpecifier *dontLockCrashSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Don't Lock After Crash", @"Не блокировать при сбое") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [dontLockCrashSpecifier setProperty:@YES forKey:@"enabled"];
            [dontLockCrashSpecifier setProperty:@"dopamine_sb_dont_lock_crash" forKey:@"key"];
            [dontLockCrashSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:dontLockCrashSpecifier];

            PSSpecifier *hideACPowerSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Hide AC Power / Charging Icon", @"Скрыть иконку зарядки") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [hideACPowerSpecifier setProperty:@YES forKey:@"enabled"];
            [hideACPowerSpecifier setProperty:@"dopamine_sb_hide_ac_power" forKey:@"key"];
            [hideACPowerSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:hideACPowerSpecifier];

            PSSpecifier *neverBreadcrumbSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Hide Breadcrumb Back Button", @"Скрыть стрелку возврата в приложение") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [neverBreadcrumbSpecifier setProperty:@YES forKey:@"enabled"];
            [neverBreadcrumbSpecifier setProperty:@"dopamine_sb_never_breadcrumb" forKey:@"key"];
            [neverBreadcrumbSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:neverBreadcrumbSpecifier];

            PSSpecifier *supervisionTextSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Show Supervision Notice on Lockscreen", @"Текст управления на экране блокировки") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [supervisionTextSpecifier setProperty:@YES forKey:@"enabled"];
            [supervisionTextSpecifier setProperty:@"dopamine_sb_supervision_text" forKey:@"key"];
            [supervisionTextSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:supervisionTextSpecifier];

            PSSpecifier *floatingTabBarSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"iPad Floating Tab Bar", @"Плавающая панель вкладок (iPad/iOS 18)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [floatingTabBarSpecifier setProperty:@YES forKey:@"enabled"];
            [floatingTabBarSpecifier setProperty:@"dopamine_floating_tab_bar" forKey:@"key"];
            [floatingTabBarSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:floatingTabBarSpecifier];

            PSSpecifier *airplaySupportSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Extended Display AirPlay Support", @"Расширенный AirPlay / Повтор экрана") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [airplaySupportSpecifier setProperty:@YES forKey:@"enabled"];
            [airplaySupportSpecifier setProperty:@"dopamine_airplay_support" forKey:@"key"];
            [airplaySupportSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:airplaySupportSpecifier];

            // 3. Internal & Developer Options
            PSSpecifier *dopamineInternalGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineInternalGroup.name = DOLocalizedText(@"Dopamine - Internal & Developer Tweaks", @"Dopamine - Внутренние и отладочные твики");
            [specifiers addObject:dopamineInternalGroup];

            PSSpecifier *sbBuildNumberSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Show Build Number in Status Bar", @"Номер сборки iOS в статусбаре") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [sbBuildNumberSpecifier setProperty:@YES forKey:@"enabled"];
            [sbBuildNumberSpecifier setProperty:@"dopamine_show_build_number" forKey:@"key"];
            [sbBuildNumberSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:sbBuildNumberSpecifier];

            PSSpecifier *metalHudSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Metal Force HUD Overlay", @"Metal HUD (счетчик FPS) во всех играх") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [metalHudSpecifier setProperty:@YES forKey:@"enabled"];
            [metalHudSpecifier setProperty:@"dopamine_metal_force_hud" forKey:@"key"];
            [metalHudSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:metalHudSpecifier];

            PSSpecifier *visualizeTouchesSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Visualize Screen Touches", @"Отображать точки касания экрана") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [visualizeTouchesSpecifier setProperty:@YES forKey:@"enabled"];
            [visualizeTouchesSpecifier setProperty:@"dopamine_visualize_touches" forKey:@"key"];
            [visualizeTouchesSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:visualizeTouchesSpecifier];

            PSSpecifier *hideAppleLogoSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Hide Apple Logo on App Launch", @"Скрыть логотип Apple при запуске") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [hideAppleLogoSpecifier setProperty:@YES forKey:@"enabled"];
            [hideAppleLogoSpecifier setProperty:@"dopamine_hide_apple_logo_launch" forKey:@"key"];
            [hideAppleLogoSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:hideAppleLogoSpecifier];

            PSSpecifier *wakeHapticSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Enable Wake Gesture Haptic", @"Тактильный отклик при поднятии") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [wakeHapticSpecifier setProperty:@YES forKey:@"enabled"];
            [wakeHapticSpecifier setProperty:@"dopamine_wake_gesture_haptic" forKey:@"key"];
            [wakeHapticSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:wakeHapticSpecifier];

            PSSpecifier *playSoundOnPasteSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Play Sound on Paste", @"Звук при вставке из буфера") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [playSoundOnPasteSpecifier setProperty:@YES forKey:@"enabled"];
            [playSoundOnPasteSpecifier setProperty:@"dopamine_play_sound_on_paste" forKey:@"key"];
            [playSoundOnPasteSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:playSoundOnPasteSpecifier];

            PSSpecifier *announceAllPastesSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Announce All Clipboard Pastes", @"Уведомлять о вставке из буфера") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [announceAllPastesSpecifier setProperty:@YES forKey:@"enabled"];
            [announceAllPastesSpecifier setProperty:@"dopamine_announce_all_pastes" forKey:@"key"];
            [announceAllPastesSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:announceAllPastesSpecifier];

            PSSpecifier *notesDebugSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Apple Notes Debug Mode", @"Режим отладки в Заметках") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [notesDebugSpecifier setProperty:@YES forKey:@"enabled"];
            [notesDebugSpecifier setProperty:@"dopamine_notes_debug_mode" forKey:@"key"];
            [notesDebugSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:notesDebugSpecifier];

            PSSpecifier *appStoreDebugSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"App Store Debug Gesture", @"Жест отладки в App Store") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [appStoreDebugSpecifier setProperty:@YES forKey:@"enabled"];
            [appStoreDebugSpecifier setProperty:@"dopamine_appstore_debug" forKey:@"key"];
            [appStoreDebugSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:appStoreDebugSpecifier];

            PSSpecifier *disableSecondsHandSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Clock Seconds Hand", @"Отключить секундную стрелку часов") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableSecondsHandSpecifier setProperty:@YES forKey:@"enabled"];
            [disableSecondsHandSpecifier setProperty:@"dopamine_disable_seconds_hand" forKey:@"key"];
            [disableSecondsHandSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableSecondsHandSpecifier];

            PSSpecifier *keyFlickSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"iPad Key Flick Gestures", @"Свайпы по клавиатуре (Key Flick)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [keyFlickSpecifier setProperty:@YES forKey:@"enabled"];
            [keyFlickSpecifier setProperty:@"dopamine_key_flick" forKey:@"key"];
            [keyFlickSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:keyFlickSpecifier];

            PSSpecifier *hardwareButtonHintsSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Button Droplet Hints in Snapshots", @"Анимация нажатия кнопок") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [hardwareButtonHintsSpecifier setProperty:@YES forKey:@"enabled"];
            [hardwareButtonHintsSpecifier setProperty:@"dopamine_button_hints" forKey:@"key"];
            [hardwareButtonHintsSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:hardwareButtonHintsSpecifier];

            // 4. Solarium & Liquid Glass (iOS 18+)
            PSSpecifier *dopamineLiquidGlassGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineLiquidGlassGroup.name = DOLocalizedText(@"Dopamine - Liquid Glass & Solarium (iOS 18+)", @"Dopamine - Liquid Glass и Solarium (iOS 18+)");
            [specifiers addObject:dopamineLiquidGlassGroup];

            PSSpecifier *disableSolariumSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Solarium (SwiftUI)", @"Отключить Solarium (SwiftUI)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableSolariumSpecifier setProperty:@YES forKey:@"enabled"];
            [disableSolariumSpecifier setProperty:@"dopamine_disable_solarium" forKey:@"key"];
            [disableSolariumSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableSolariumSpecifier];

            PSSpecifier *forceSolariumFallbackSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Force Solarium Fallback Rendering", @"Принудительный Solarium рендеринг") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [forceSolariumFallbackSpecifier setProperty:@YES forKey:@"enabled"];
            [forceSolariumFallbackSpecifier setProperty:@"dopamine_solarium_fallback" forKey:@"key"];
            [forceSolariumFallbackSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:forceSolariumFallbackSpecifier];

            PSSpecifier *noLiquidClockSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Liquid Glass Clock", @"Отключить стеклянные часы") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [noLiquidClockSpecifier setProperty:@YES forKey:@"enabled"];
            [noLiquidClockSpecifier setProperty:@"dopamine_no_liquid_clock" forKey:@"key"];
            [noLiquidClockSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:noLiquidClockSpecifier];

            PSSpecifier *noLiquidDockSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Liquid Glass Dock", @"Отключить стеклянный Dock") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [noLiquidDockSpecifier setProperty:@YES forKey:@"enabled"];
            [noLiquidDockSpecifier setProperty:@"dopamine_no_liquid_dock" forKey:@"key"];
            [noLiquidDockSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:noLiquidDockSpecifier];

            PSSpecifier *disableSpecularMotionSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Specular Motion Everywhere", @"Отключить блики Specular Motion") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableSpecularMotionSpecifier setProperty:@YES forKey:@"enabled"];
            [disableSpecularMotionSpecifier setProperty:@"dopamine_disable_specular_motion" forKey:@"key"];
            [disableSpecularMotionSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableSpecularMotionSpecifier];

            PSSpecifier *disableOuterRefractionSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Outer Refraction", @"Отключить внешнее преломление") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableOuterRefractionSpecifier setProperty:@YES forKey:@"enabled"];
            [disableOuterRefractionSpecifier setProperty:@"dopamine_disable_outer_refraction" forKey:@"key"];
            [disableOuterRefractionSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableOuterRefractionSpecifier];

            PSSpecifier *disableSolariumHDRSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Solarium HDR Glass", @"Отключить HDR стекло Solarium") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableSolariumHDRSpecifier setProperty:@YES forKey:@"enabled"];
            [disableSolariumHDRSpecifier setProperty:@"dopamine_disable_solarium_hdr" forKey:@"key"];
            [disableSolariumHDRSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableSolariumHDRSpecifier];

            // 5. System Daemons Management
            PSSpecifier *dopamineDaemonsGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineDaemonsGroup.name = DOLocalizedText(@"Dopamine - System Daemons Management", @"Dopamine - Управление системными демонами");
            [specifiers addObject:dopamineDaemonsGroup];

            PSSpecifier *disableOTADaemonsSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable OTA Software Update Daemons", @"Отключить демоны обновлений OTA") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableOTADaemonsSpecifier setProperty:@YES forKey:@"enabled"];
            [disableOTADaemonsSpecifier setProperty:@"dopamine_daemon_ota" forKey:@"key"];
            [disableOTADaemonsSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableOTADaemonsSpecifier];

            PSSpecifier *disableCrashDaemonsSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Crash & Analytics Daemons", @"Отключить демоны сбоев и аналитики") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableCrashDaemonsSpecifier setProperty:@YES forKey:@"enabled"];
            [disableCrashDaemonsSpecifier setProperty:@"dopamine_daemon_crash" forKey:@"key"];
            [disableCrashDaemonsSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableCrashDaemonsSpecifier];

            PSSpecifier *disableGameCenterSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Game Center Daemon", @"Отключить демон Game Center") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableGameCenterSpecifier setProperty:@YES forKey:@"enabled"];
            [disableGameCenterSpecifier setProperty:@"dopamine_daemon_gamecenter" forKey:@"key"];
            [disableGameCenterSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableGameCenterSpecifier];

            PSSpecifier *disableScreenTimeSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Screen Time Agent", @"Отключить агент экранного времени") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableScreenTimeSpecifier setProperty:@YES forKey:@"enabled"];
            [disableScreenTimeSpecifier setProperty:@"dopamine_daemon_screentime" forKey:@"key"];
            [disableScreenTimeSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableScreenTimeSpecifier];

            PSSpecifier *disableUsageTrackingSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Usage Tracking Agent", @"Отключить агент отслеживания использования") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableUsageTrackingSpecifier setProperty:@YES forKey:@"enabled"];
            [disableUsageTrackingSpecifier setProperty:@"dopamine_daemon_usage_tracking" forKey:@"key"];
            [disableUsageTrackingSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableUsageTrackingSpecifier];

            PSSpecifier *disableTipsSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Disable Tips Daemon", @"Отключить демон Советов") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [disableTipsSpecifier setProperty:@YES forKey:@"enabled"];
            [disableTipsSpecifier setProperty:@"dopamine_daemon_tips" forKey:@"key"];
            [disableTipsSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:disableTipsSpecifier];

            PSSpecifier *clearScreenTimeCacheSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Clear Screen Time Agent Cache", @"Очистить кэш экранного времени") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            clearScreenTimeCacheSpecifier.buttonAction = @selector(clearScreenTimeCachePressed);
            [clearScreenTimeCacheSpecifier setProperty:@YES forKey:@"enabled"];
            [clearScreenTimeCacheSpecifier setProperty:@"clearScreenTimeBtn" forKey:@"key"];
            [specifiers addObject:clearScreenTimeCacheSpecifier];

            // 6. Status Bar Customization
            PSSpecifier *dopamineStatusBarGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineStatusBarGroup.name = DOLocalizedText(@"Dopamine - Status Bar Overrides", @"Dopamine - Статусбар и кастомизация");
            [specifiers addObject:dopamineStatusBarGroup];

            PSSpecifier *customCarrierSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Custom Carrier Name", @"Кастомное имя оператора связи") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            customCarrierSpecifier.buttonAction = @selector(setCustomCarrierPressed);
            [customCarrierSpecifier setProperty:@YES forKey:@"enabled"];
            [customCarrierSpecifier setProperty:@"customCarrierBtn" forKey:@"key"];
            [specifiers addObject:customCarrierSpecifier];

            PSSpecifier *customTimeSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Custom Time String", @"Кастомное время статусбара") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            customTimeSpecifier.buttonAction = @selector(setCustomTimePressed);
            [customTimeSpecifier setProperty:@YES forKey:@"enabled"];
            [customTimeSpecifier setProperty:@"customTimeBtn" forKey:@"key"];
            [specifiers addObject:customTimeSpecifier];

            PSSpecifier *signalStrengthSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Cellular Signal Strength (0-4)", @"Кастомные полосы сигнала связи") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            signalStrengthSpecifier.buttonAction = @selector(setSignalStrengthPressed);
            [signalStrengthSpecifier setProperty:@YES forKey:@"enabled"];
            [signalStrengthSpecifier setProperty:@"signalStrengthBtn" forKey:@"key"];
            [specifiers addObject:signalStrengthSpecifier];

            PSSpecifier *batteryLevelSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Battery Percentage Override (0-100)", @"Кастомный процент батареи") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            batteryLevelSpecifier.buttonAction = @selector(setBatteryLevelPressed);
            [batteryLevelSpecifier setProperty:@YES forKey:@"enabled"];
            [batteryLevelSpecifier setProperty:@"batteryLevelBtn" forKey:@"key"];
            [specifiers addObject:batteryLevelSpecifier];

            // 7. Experimental & Advanced Options
            PSSpecifier *dopamineExperimentalGroup = [PSSpecifier emptyGroupSpecifier];
            dopamineExperimentalGroup.name = DOLocalizedText(@"Dopamine - Experimental & Advanced Options", @"Dopamine - Дополнительные и экспериментальные опции");
            [specifiers addObject:dopamineExperimentalGroup];

            PSSpecifier *experimentalToggleSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Experimental Features", @"Экспериментальные функции") target:self set:@selector(setExperimentalToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
            [experimentalToggleSpecifier setProperty:@YES forKey:@"enabled"];
            [experimentalToggleSpecifier setProperty:@"dopamine_experimental_enabled" forKey:@"key"];
            [experimentalToggleSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:experimentalToggleSpecifier];

            BOOL experimentalEnabled = [[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"dopamine_experimental_enabled" fallback:NO];
            if (experimentalEnabled) {
                PSSpecifier *disableOTASpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Block OTA via MobileAsset", @"Блокировать OTA через MobileAsset") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
                [disableOTASpecifier setProperty:@YES forKey:@"enabled"];
                [disableOTASpecifier setProperty:@"dopamine_disable_ota_mobileasset" forKey:@"key"];
                [disableOTASpecifier setProperty:@NO forKey:@"default"];
                [specifiers addObject:disableOTASpecifier];

                PSSpecifier *customResolutionSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Custom Screen Resolution", @"Кастомное разрешение экрана") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
                customResolutionSpecifier.buttonAction = @selector(setCustomResolutionPressed);
                [customResolutionSpecifier setProperty:@YES forKey:@"enabled"];
                [customResolutionSpecifier setProperty:@"customResBtn" forKey:@"key"];
                [specifiers addObject:customResolutionSpecifier];

                PSSpecifier *spoofModelSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Spoof Model to iPhone 16 Pro", @"Спуфинг модели в iPhone 16 Pro") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
                [spoofModelSpecifier setProperty:@YES forKey:@"enabled"];
                [spoofModelSpecifier setProperty:@"dopamine_spoof_model" forKey:@"key"];
                [spoofModelSpecifier setProperty:@NO forKey:@"default"];
                [specifiers addObject:spoofModelSpecifier];

                PSSpecifier *euEnablerSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"EU Enabler (Alt App Stores)", @"EU Enabler (Сторонние магазины ЕС)") target:self set:@selector(setDopamineToggle:specifier:) get:@selector(readDopamineToggle:) detail:nil cell:PSSwitchCell edit:nil];
                [euEnablerSpecifier setProperty:@YES forKey:@"enabled"];
                [euEnablerSpecifier setProperty:@"dopamine_eu_enabler" forKey:@"key"];
                [euEnablerSpecifier setProperty:@NO forKey:@"default"];
                [specifiers addObject:euEnablerSpecifier];
            }

            // Apply Button
            PSSpecifier *dopamineApplyGroup = [PSSpecifier emptyGroupSpecifier];
            [specifiers addObject:dopamineApplyGroup];

            PSSpecifier *applyDopamineSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedText(@"Apply Changes & Respring", @"Применить изменения и респринг") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
            applyDopamineSpecifier.buttonAction = @selector(applyDopamineChangesPressed);
            [applyDopamineSpecifier setProperty:@YES forKey:@"enabled"];
            [applyDopamineSpecifier setProperty:@"applyDopamineBtn" forKey:@"key"];
            [specifiers addObject:applyDopamineSpecifier];
        }

        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - Getters & Setters

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    [[DOPreferenceManager sharedManager] setPreferenceValue:value forKey:key];
}

- (id)readPreferenceValue:(PSSpecifier*)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    id value = [[DOPreferenceManager sharedManager] preferenceValueForKey:key];
    if (!value) {
        return [specifier propertyForKey:@"default"];
    }
    return value;
}

- (id)readExploitPreferenceValue:(PSSpecifier *)specifier
{
    id value = [self readPreferenceValue:specifier];

    SEL dataSourceSel = nil;
    NSString *selString = [specifier propertyForKey:@"valuesDataSource"];
    if (selString) {
        dataSourceSel = NSSelectorFromString(selString);
    }

    if (dataSourceSel && [value isKindOfClass:[NSString class]]) {
        NSString *valueString = (NSString *)value;

        IMP imp = [specifier.target methodForSelector:dataSourceSel];
        if (imp) {
            NSArray *(*func)(id, SEL) = (void *)imp;
            NSArray *availableIdentifiers = func(specifier.target, dataSourceSel);
            if (![availableIdentifiers containsObject:valueString]) {
                return [specifier propertyForKey:@"default"];
            }
        }
    }

    return value;
}

- (id)readIDownloadEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].isIDownloadEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setIDownloadEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setIDownloadLoaded:((NSNumber *)value).boolValue needsUnsandbox:YES];
    }
}

- (id)readTweakInjectionEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].isTweakInjectionEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setTweakInjectionEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setTweakInjectionEnabled:((NSNumber *)value).boolValue];
        UIAlertController *userspaceRebootAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Title") message:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *rebootNowAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Now") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[DOEnvironmentManager sharedManager] rebootUserspace];
        }];
        UIAlertAction *rebootLaterAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Later") style:UIAlertActionStyleCancel handler:nil];
        
        [userspaceRebootAlertController addAction:rebootNowAction];
        [userspaceRebootAlertController addAction:rebootLaterAction];
        [self presentViewController:userspaceRebootAlertController animated:YES completion:nil];
    }
}

- (id)readAppJITEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        bool v = jbclient_jbsettings_get_bool("markAppsAsDebugged");
        return @(v);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setAppJITEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        jbclient_platform_jbsettings_set_bool("markAppsAsDebugged", ((NSNumber *)value).boolValue);
    }
}

- (id)readJetsamMultiplier:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken && gSystemInfo.jailbreakInfo.rootPath) {
        double v = jbclient_jbsettings_get_double("jetsamMultiplier");
        return @((v < 1 || isnan(v)) ? 6 : ceil(v * 2));
    }
    return [self readPreferenceValue:specifier];
}

- (void)setJetsamMultiplier:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken && gSystemInfo.jailbreakInfo.rootPath) {
        jbclient_platform_jbsettings_set_double("jetsamMultiplier", ((NSNumber *)value).doubleValue / 2);
    }
}

- (void)setRemoveJailbreakEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    if (((NSNumber *)value).boolValue) {
        UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Remove_Jailbreak_Title") message:DOLocalizedString(@"Alert_Remove_Jailbreak_Enabled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:nil];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self setPreferenceValue:@NO specifier:specifier];
            [self reloadSpecifiers];
        }];
        [confirmationAlertController addAction:uninstallAction];
        [confirmationAlertController addAction:cancelAction];
        [self presentViewController:confirmationAlertController animated:YES completion:nil];
    }
}

- (void)setBootlogoEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    bool prevValueBool = ((NSNumber *)[self readPreferenceValue:specifier]).boolValue;
    [self setPreferenceValue:value specifier:specifier];
    bool valueBool = ((NSNumber *)value).boolValue;

    if (prevValueBool != valueBool) {
        NSMutableArray *affectedSpecifiers = [NSMutableArray new];
        [affectedSpecifiers addObject:_customBootlogoEnabledSpecifier];

        if (valueBool == ![self containsSpecifier:_customBootlogoSpecifier]) {
            [affectedSpecifiers addObject:_customBootlogoSpecifier];
        }

        if (valueBool) {
            [self insertContiguousSpecifiers:affectedSpecifiers afterSpecifier:specifier animated:YES];
        }
        else {
            [self removeContiguousSpecifiers:affectedSpecifiers animated:YES];
        }
    }

    if ([DOEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[DOEnvironmentManager sharedManager] updateBootLogo];
        });
    }
}

- (void)setCustomBootlogoEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    bool prevValueBool = ((NSNumber *)[self readPreferenceValue:specifier]).boolValue;
    [self setPreferenceValue:value specifier:specifier];
    bool valueBool = ((NSNumber *)value).boolValue;

    if (prevValueBool != valueBool) {
        if (valueBool) {
            [self insertSpecifier:_customBootlogoSpecifier afterSpecifier:specifier animated:YES];
        }
        else {
            [self removeSpecifier:_customBootlogoSpecifier animated:YES];
        }
    }

    if ([DOEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[DOEnvironmentManager sharedManager] updateBootLogo];
        });
    }
}

- (void)selectCustomBootlogoPressed
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        return;
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self selectCustomBootlogoPressed];
                });
            }
        }];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Boot Logo Picker

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *chosenImage = info[UIImagePickerControllerEditedImage];
    if (!chosenImage) {
        chosenImage = info[UIImagePickerControllerOriginalImage];
    }

    // Force correct the orientation
    // For some reason without rerendering the image, the stored file will have a wrong orientation for photos taken with the camera‚
    UIGraphicsBeginImageContextWithOptions(chosenImage.size, NO, 1.0);
    [chosenImage drawInRect:CGRectMake(0,0, chosenImage.size.width, chosenImage.size.height)];
    chosenImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    [UIImagePNGRepresentation(chosenImage) writeToFile:[DOUIManager sharedInstance].bootlogoPath atomically:YES];

    if ([DOEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[DOEnvironmentManager sharedManager] updateBootLogo];
        });
    }

    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Button Actions

- (void)refreshJailbreakAppsPressed
{
    [[DOEnvironmentManager sharedManager] refreshJailbreakApps];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Button_Refresh_Jailbreak_Apps") message:@"Icon cache successfully refreshed!" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reinstallPackageManagersPressed
{
    [self.navigationController pushViewController:[[DOPkgManagerPickerViewController alloc] init] animated:YES];
}

- (void)changeMobilePasswordWithAuthenticationPressed
{
	LAContext *context = [[LAContext alloc] init];
	NSError *authError = nil;
	NSString *reason = DOLocalizedString(@"Password_Auth_Required");
	
	if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&authError]) {
		[context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
			localizedReason:reason
			reply:^(BOOL success, NSError * _Nullable error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					[self changeMobilePassword];
				}
			});
		}];
	}
	else {
		[self changeMobilePassword];
	}
}

- (void)changeMobilePassword
{
    UIAlertController *changeMobilePasswordAlert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Button_Change_Mobile_Password") message:DOLocalizedString(@"Alert_Change_Mobile_Password_Body") preferredStyle:UIAlertControllerStyleAlert];
    
    [changeMobilePasswordAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = DOLocalizedString(@"Password_Placeholder");
        textField.secureTextEntry = YES;
    }];
    
    [changeMobilePasswordAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = DOLocalizedString(@"Repeat_Password_Placeholder");
        textField.secureTextEntry = YES;
    }];
    
    UIAlertAction *changeButton = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Change") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action){
        NSString *password = changeMobilePasswordAlert.textFields[0].text;
        NSString *repeatPassword = changeMobilePasswordAlert.textFields[1].text;
        if (![password isEqualToString:repeatPassword]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self changeMobilePassword];
            });
        }
        else {
            [[DOEnvironmentManager sharedManager] changeMobilePassword:password];
            UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Button_Change_Mobile_Password") message:@"Password successfully updated!" preferredStyle:UIAlertControllerStyleAlert];
            [doneAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:doneAlert animated:YES completion:nil];
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil];
    [changeMobilePasswordAlert addAction:changeButton];
    [changeMobilePasswordAlert addAction:cancelAction];
    [self presentViewController:changeMobilePasswordAlert animated:YES completion:nil];
}

- (void)hideUnhideJailbreakPressed
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    [envManager setJailbreakHidden:!envManager.isJailbreakHidden];
    [self reloadSpecifiers];
}

- (void)removeJailbreakPressed
{
    UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Remove_Jailbreak_Title") message:DOLocalizedString(@"Alert_Remove_Jailbreak_Pressed_Body") preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        BOOL wasJailbroken = [DOEnvironmentManager sharedManager].isJailbroken;
        [[DOEnvironmentManager sharedManager] deleteBootstrap];
        if (gSystemInfo.jailbreakInfo.rootPath) {
            free(gSystemInfo.jailbreakInfo.rootPath);
            gSystemInfo.jailbreakInfo.rootPath = NULL;
            [[DOEnvironmentManager sharedManager] locateJailbreakRoot];
        }
        if (wasJailbroken) {
            UIAlertController *rebootAlert = [UIAlertController alertControllerWithTitle:@"Jailbreak Removed" message:@"Jailbreak environment has been removed. Would you like to reboot the device now?" preferredStyle:UIAlertControllerStyleAlert];
            [rebootAlert addAction:[UIAlertAction actionWithTitle:@"Reboot Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [[DOEnvironmentManager sharedManager] reboot];
            }]];
            [rebootAlert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [self reloadSpecifiers];
            }]];
            [self presentViewController:rebootAlert animated:YES completion:nil];
        }
        else {
            [self reloadSpecifiers];
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:nil];
    [confirmationAlertController addAction:uninstallAction];
    [confirmationAlertController addAction:cancelAction];
    [self presentViewController:confirmationAlertController animated:YES completion:nil];
}

- (void)resetSettingsPressed
{
    [[DOUIManager sharedInstance] resetSettings];
    [self.navigationController popToRootViewControllerAnimated:YES];
    [self reloadSpecifiers];
}

#pragma mark - Dopamine Customization Actions

- (id)readDopamineToggle:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    return [[DOPreferenceManager sharedManager] preferenceValueForKey:key] ?: [specifier propertyForKey:@"default"];
}

- (void)setDopamineToggle:(id)value specifier:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    [[DOPreferenceManager sharedManager] setPreferenceValue:value forKey:key];
}

- (void)setExperimentalToggle:(id)value specifier:(PSSpecifier *)specifier
{
    [self setDopamineToggle:value specifier:specifier];
    [self reloadSpecifiers];
}

- (id)readDopamineValue:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    id val = [[DOPreferenceManager sharedManager] preferenceValueForKey:key];
    if (!val) {
        val = [specifier propertyForKey:@"default"];
    }
    return val;
}

- (void)setDopamineValue:(id)value specifier:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    [[DOPreferenceManager sharedManager] setPreferenceValue:value forKey:key];
}

- (NSArray *)iconShapeIdentifiers {
    return @[@"default", @"circle", @"square"];
}

- (NSArray *)iconShapeNames {
    return @[
        DOLocalizedText(@"Default (Squircle)", @"Стандартные (сквиркл)"),
        DOLocalizedText(@"Round / Circle", @"Круглые иконки"),
        DOLocalizedText(@"Square / Sharp", @"Квадратные иконки")
    ];
}

- (NSArray *)animSpeedIdentifiers {
    return @[@"1.0", @"0.5", @"0.25", @"0.0"];
}

- (NSArray *)animSpeedNames {
    return @[
        DOLocalizedText(@"Default (1.0x)", @"По умолчанию (1.0x)"),
        DOLocalizedText(@"Fast (0.5x)", @"Быстрые (0.5x)"),
        DOLocalizedText(@"Super Fast (0.25x)", @"Турбо (0.25x)"),
        DOLocalizedText(@"Instant (0.0x)", @"Без анимаций (0.0x)")
    ];
}

- (NSArray *)pageFxIdentifiers {
    return @[@"default", @"cube", @"fade", @"accordion"];
}

- (NSArray *)pageFxNames {
    return @[
        DOLocalizedText(@"Default", @"По умолчанию"),
        DOLocalizedText(@"Cube / Barrel", @"Куб / Бочка"),
        DOLocalizedText(@"Fade", @"Плавное угасание"),
        DOLocalizedText(@"Accordion", @"Гармошка")
    ];
}

- (NSArray *)anitimeStyleIdentifiers {
    return @[@"animated", @"static", @"m-static", @"s-static", @"s-animated"];
}

- (NSArray *)anitimeStyleNames {
    return @[
        DOLocalizedText(@"Official AniTime (Animated)", @"Оригинал AniTime (Анимированные)"),
        DOLocalizedText(@"Official AniTime (Static)", @"Оригинал AniTime (Статичные)"),
        DOLocalizedText(@"Waifu Pack (m-static)", @"Аниме фигурки (m-static)"),
        DOLocalizedText(@"Chibi Pack (s-static)", @"Чиби фигурки (s-static)"),
        DOLocalizedText(@"Chibi Pack (s-animated)", @"Чиби анимация (s-animated)")
    ];
}

- (NSArray *)aimFontIdentifiers {
    return @[@"rounded", @"stencil", @"serif", @"mono", @"heavy"];
}

- (NSArray *)aimFontNames {
    return @[
        DOLocalizedText(@"Rounded Bold", @"Скругленный жирный"),
        DOLocalizedText(@"Stencil / Impact", @"Трафарет / Impact"),
        DOLocalizedText(@"Classic Serif", @"Классический с засечками"),
        DOLocalizedText(@"Monospace Digital", @"Моноширинный цифровой"),
        DOLocalizedText(@"Ultra Heavy", @"Сверхжирный Heavy")
    ];
}

- (NSArray *)aimColorIdentifiers {
    return @[@"white", @"sakura", @"cyan", @"sunset", @"gold"];
}

- (NSArray *)aimColorNames {
    return @[
        DOLocalizedText(@"Classic White", @"Классический белый"),
        DOLocalizedText(@"Sakura Pink", @"Сакура розовый"),
        DOLocalizedText(@"Neon Cyan", @"Неоновый бирюзовый"),
        DOLocalizedText(@"Sunset Coral", @"Закатный коралловый"),
        DOLocalizedText(@"Cyber Gold", @"Золотой")
    ];
}

- (void)previewAniTimePressed {
    DOAniTimePreviewViewController *previewVC = [DOAniTimePreviewViewController new];
    previewVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:previewVC animated:YES completion:nil];
}

#pragma mark - Language & Tweak Management

- (NSArray *)languageIdentifiers
{
    return @[@"default", @"en", @"ru"];
}

- (NSArray *)languageNames
{
    return @[DOLocalizedText(@"System Default", @"По умолчанию"), @"English", @"Русский"];
}

- (id)readAppLanguage:(PSSpecifier *)specifier
{
    return [[DOUIManager sharedInstance] selectedLanguage];
}

- (void)setAppLanguage:(id)value specifier:(PSSpecifier *)specifier
{
    [[DOUIManager sharedInstance] setSelectedLanguage:value];
    [self reloadSpecifiers];
}

- (void)resetAllTweaksPressed
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Reset All Tweaks", @"Сброс всех твиков") message:DOLocalizedText(@"Are you sure you want to reset all modifications to system defaults?", @"Вы уверены, что хотите сбросить все модификации к системным значениям?") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"Reset & Respring", @"Сбросить и перезапустить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        DOPreferenceManager *prefs = [DOPreferenceManager sharedManager];
        NSArray *keysToReset = @[
            @"dopamine_dynamic_island", @"dopamine_stage_manager", @"dopamine_always_on_display",
            @"dopamine_aod_vibrancy", @"dopamine_boot_chime", @"dopamine_charge_limit",
            @"dopamine_tap_to_wake", @"dopamine_action_button", @"dopamine_camera_button",
            @"dopamine_collision_sos", @"dopamine_ipad_apps", @"dopamine_shutter_mute",
            @"dopamine_apple_pencil", @"dopamine_internal_storage", @"dopamine_floating_tab_bar",
            @"dopamine_airdrop_limit", @"dopamine_di_in_screenshots", @"dopamine_hide_di_completely",
            @"dopamine_disable_lpm_alert", @"dopamine_sb_dont_dim_ac", @"dopamine_sb_dont_lock_crash",
            @"dopamine_sb_hide_ac_power", @"dopamine_sb_never_breadcrumb", @"dopamine_sb_supervision_text",
            @"dopamine_airplay_support", @"dopamine_clock_animation", @"dopamine_show_build_number",
            @"dopamine_metal_force_hud", @"dopamine_visualize_touches", @"dopamine_hide_apple_logo_launch",
            @"dopamine_wake_gesture_haptic", @"dopamine_play_sound_on_paste", @"dopamine_announce_all_pastes",
            @"dopamine_notes_debug_mode", @"dopamine_appstore_debug", @"dopamine_disable_seconds_hand",
            @"dopamine_key_flick", @"dopamine_button_hints", @"dopamine_disable_solarium",
            @"dopamine_solarium_fallback", @"dopamine_no_liquid_clock", @"dopamine_no_liquid_dock",
            @"dopamine_disable_specular_motion", @"dopamine_disable_outer_refraction", @"dopamine_disable_solarium_hdr",
            @"dopamine_daemon_ota", @"dopamine_daemon_crash", @"dopamine_daemon_gamecenter",
            @"dopamine_daemon_screentime", @"dopamine_daemon_usage_tracking", @"dopamine_daemon_tips",
            @"dopamine_disable_ota_mobileasset", @"dopamine_spoof_model", @"dopamine_eu_enabler",
            @"dopamine_lockscreen_footnote", @"dopamine_custom_carrier", @"dopamine_custom_time",
            @"dopamine_numeric_signal", @"dopamine_override_battery", @"dopamine_custom_res_w", @"dopamine_custom_res_h",
            @"dopamine_icon_gravity", @"dopamine_apple_internal",
            @"dopamine_icon_shape", @"dopamine_anim_speed", @"dopamine_page_scroll_fx",
            @"dopamine_anitime_enabled", @"dopamine_anitime_style",
            @"dopamine_aim_pro_enabled", @"dopamine_aim_font", @"dopamine_aim_color"
        ];
        for (NSString *key in keysToReset) {
            [prefs setPreferenceValue:nil forKey:key];
        }
        
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.springboard.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.UIKit.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.sharingd.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/preferences/FeatureFlags/Global.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/.GlobalPreferences.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.backboardd.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.CoreMotion.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.Pasteboard.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.mobilenotes.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.AppStore.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/Managed Preferences/mobile/com.apple.MobileAsset.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/db/com.apple.xpc.launchd/disabled.plist" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/db/os_eligibility/eligibility.plist" error:nil];
        
        NSString *mgPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
        NSMutableDictionary *mgDict = [NSMutableDictionary dictionaryWithContentsOfFile:mgPath];
        if (mgDict) {
            [mgDict removeObjectForKey:@"CacheExtra"];
            [mgDict writeToFile:mgPath atomically:YES];
        }
        
        [self reloadSpecifiers];
        [[DOEnvironmentManager sharedManager] respring];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sideloadIPAPressed
{
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        NSArray *types = @[
            [UTType typeWithIdentifier:@"com.apple.itunes.ipa"] ?: [UTType typeWithIdentifier:@"public.item"],
            [UTType typeWithIdentifier:@"public.archive"],
            [UTType typeWithIdentifier:@"public.data"],
            [UTType typeWithIdentifier:@"public.item"]
        ];
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item", @"public.archive"] inMode:UIDocumentPickerModeImport];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)launchPhysicsPlaygroundPressed
{
    DOPhysicsPlaygroundViewController *vc = [[DOPhysicsPlaygroundViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)selectLiveVideoWallpaperPressed
{
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        NSArray *types = @[
            [UTType typeWithIdentifier:@"public.movie"],
            [UTType typeWithIdentifier:@"public.video"],
            [UTType typeWithIdentifier:@"com.apple.quicktime-movie"],
            [UTType typeWithIdentifier:@"public.mpeg-4"],
            [UTType typeWithIdentifier:@"public.item"],
            [UTType typeWithIdentifier:@"public.data"],
            [UTType typeWithIdentifier:@"public.archive"],
            [UTType typeWithIdentifier:@"com.apple.heic"]
        ];
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.movie", @"public.video", @"com.apple.quicktime-movie", @"public.item"] inMode:UIDocumentPickerModeImport];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (!urls.count) return;
    NSURL *url = urls.firstObject;
    NSString *ext = [url.pathExtension lowercaseString];
    
    if ([ext isEqualToString:@"ipa"] || [ext isEqualToString:@"deb"]) {
        [self handlePackageOrIPAUpload:url];
    } else {
        [self installAnimatedWallpaperFromURL:url];
    }
}

- (void)installAnimatedWallpaperFromURL:(NSURL *)url
{
    NSString *sourcePath = url.path;
    NSString *ext = [url.pathExtension lowercaseString];
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Installing Wallpaper", @"Установка обоев") message:DOLocalizedText(@"Processing video / PosterBoard files...", @"Обработка видео и файлов PosterBoard...") preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *destBaseDir = @"/var/mobile/Library/Application Support/PRBPosterExtensionDataStore/1/Extensions/com.apple.PhotosUIPrivate.PhotosPosterProvider/descriptors";
        [[NSFileManager defaultManager] createDirectoryAtPath:destBaseDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *uniqueId = [[NSUUID UUID].UUIDString uppercaseString];
        NSString *descriptorDir = [destBaseDir stringByAppendingPathComponent:uniqueId];
        NSString *contentsDir = [descriptorDir stringByAppendingPathComponent:@"versions/0/contents/0EFB6A0F-7052-4D24-8859-AB22BADF2E93"];
        NSString *outputLayerStack = [contentsDir stringByAppendingPathComponent:@"output.layerStack"];
        NSString *inputSegRes = [contentsDir stringByAppendingPathComponent:@"input.segmentation/asset.resource"];
        
        [[NSFileManager defaultManager] createDirectoryAtPath:outputLayerStack withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:inputSegRes withIntermediateDirectories:YES attributes:nil error:nil];
        
        if ([ext isEqualToString:@"mov"] || [ext isEqualToString:@"mp4"]) {
            NSString *videoDest = [outputLayerStack stringByAppendingPathComponent:@"portrait-layer_settling-video.MOV"];
            [[NSFileManager defaultManager] removeItemAtPath:videoDest error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:videoDest error:nil];
            
            AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:nil];
            AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            gen.appliesPreferredTrackTransform = YES;
            CMTime time = CMTimeMakeWithSeconds(0.0, 600);
            CGImageRef imgRef = [gen copyCGImageAtTime:time actualTime:NULL error:nil];
            if (imgRef) {
                UIImage *img = [UIImage imageWithCGImage:imgRef];
                NSData *heicData = UIImageJPEGRepresentation(img, 0.95);
                CGImageRelease(imgRef);
                if (heicData) {
                    [heicData writeToFile:[inputSegRes stringByAppendingPathComponent:@"Adjusted.HEIC"] atomically:YES];
                    [heicData writeToFile:[inputSegRes stringByAppendingPathComponent:@"proxy.heic"] atomically:YES];
                    [heicData writeToFile:[outputLayerStack stringByAppendingPathComponent:@"portrait-layer_background.HEIC"] atomically:YES];
                }
            }
            
            [@"com.apple.PhotosUIPrivate.PhotosPosterProvider" writeToFile:[descriptorDir stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [@"PRPosterRoleLockScreen" writeToFile:[descriptorDir stringByAppendingPathComponent:@"com.apple.posterkit.role.identifier"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            
            NSDictionary *providerInfo = @{@"preferredTitle": @"Dopamine Live", @"galleryItem": @YES};
            [providerInfo writeToFile:[descriptorDir stringByAppendingPathComponent:@"providerInfo.plist"] atomically:YES];
        } else if ([ext isEqualToString:@"wallpaper"] || [ext isEqualToString:@"ca"] || [ext isEqualToString:@"zip"]) {
            NSString *customDest = [destBaseDir stringByAppendingPathComponent:sourcePath.lastPathComponent];
            [[NSFileManager defaultManager] removeItemAtPath:customDest error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:customDest error:nil];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Wallpaper Installed", @"Обои установлены") message:DOLocalizedText(@"Animated wallpaper imported into PosterBoard! Respring to load it in Lock Screen gallery.", @"Анимированные обои загружены в PosterBoard! Перезапустите SpringBoard для отображения в галерее.") preferredStyle:UIAlertControllerStyleAlert];
                [doneAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"Respring", @"Респринг") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [[DOEnvironmentManager sharedManager] respring];
                }]];
                [doneAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:doneAlert animated:YES completion:nil];
            }];
        });
    });
}

- (void)handlePackageOrIPAUpload:(NSURL *)url
{
    NSString *sourcePath = url.path;
    NSString *ext = [url.pathExtension lowercaseString];
    
    UIAlertController *installingAlert = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Installing Package", @"Установка пакета") message:DOLocalizedText(@"Installing application / package via helper...", @"Установка приложения / пакета...") preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:installingAlert animated:YES completion:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int result = -1;
        if ([ext isEqualToString:@"ipa"]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/TrollStore.app/trollstorehelper"]) {
                result = exec_cmd("/Applications/TrollStore.app/trollstorehelper", "install", sourcePath.fileSystemRepresentation, NULL);
            } else {
                NSString *appsDir = @"/var/jb/Applications";
                if (![[NSFileManager defaultManager] fileExistsAtPath:appsDir]) {
                    appsDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"InstalledApps"];
                }
                [[NSFileManager defaultManager] createDirectoryAtPath:appsDir withIntermediateDirectories:YES attributes:nil error:nil];
                result = exec_cmd("/usr/bin/unzip", "-o", sourcePath.fileSystemRepresentation, "-d", appsDir.fileSystemRepresentation, NULL);
                if (result != 0) {
                    result = exec_cmd("/var/jb/usr/bin/unzip", "-o", sourcePath.fileSystemRepresentation, "-d", appsDir.fileSystemRepresentation, NULL);
                }
                exec_cmd("/var/jb/usr/bin/uicache", "-a", NULL);
                exec_cmd("/usr/bin/uicache", "-a", NULL);
            }
        } else if ([ext isEqualToString:@"deb"]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/dpkg"]) {
                result = exec_cmd_trusted("/var/jb/usr/bin/dpkg", "-i", sourcePath.fileSystemRepresentation, NULL);
            } else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/dpkg"]) {
                result = exec_cmd_trusted("/usr/bin/dpkg", "-i", sourcePath.fileSystemRepresentation, NULL);
            } else {
                result = exec_cmd("/var/jb/usr/bin/dpkg-deb", "-x", sourcePath.fileSystemRepresentation, "/var/jb", NULL);
            }
            exec_cmd("/var/jb/usr/bin/uicache", "-a", NULL);
            exec_cmd("/usr/bin/uicache", "-a", NULL);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [installingAlert dismissViewControllerAnimated:YES completion:^{
                NSString *msg = (result == 0) ? DOLocalizedText(@"Installation successful! App registered.", @"Установка успешно завершена! Приложение зарегистрировано.") : [NSString stringWithFormat:DOLocalizedText(@"Installation completed with code: %d", @"Установка завершена с кодом: %d"), result];
                UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Package Installer", @"Установщик пакетов") message:msg preferredStyle:UIAlertControllerStyleAlert];
                [doneAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"Respring", @"Респринг") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [[DOEnvironmentManager sharedManager] respring];
                }]];
                [doneAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:doneAlert animated:YES completion:nil];
            }];
        });
    });
}

- (void)resetPosterboardPressed
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Wallpapers & PosterBoard" message:@"This will purge saved wallpaper caches and reset PosterBoard configurations." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset & Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *pbCache = [docs stringByAppendingPathComponent:@"PosterBoardCaches"];
        [[NSFileManager defaultManager] removeItemAtPath:pbCache error:nil];
        
        UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:@"Success" message:@"PosterBoard caches reset! Respringing SpringBoard..." preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:doneAlert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[DOEnvironmentManager sharedManager] respring];
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setLockscreenFootnotePressed
{
    NSString *currentFootnote = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_lockscreen_footnote"] ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lock Screen Footnote" message:@"Enter custom text to display at the bottom of the lock screen:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"e.g. iPhone of W4G";
        textField.text = currentFootnote;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newText = alert.textFields.firstObject.text ?: @"";
        [[DOPreferenceManager sharedManager] setPreferenceValue:newText forKey:@"dopamine_lockscreen_footnote"];
        UIAlertController *savedAlert = [UIAlertController alertControllerWithTitle:@"Saved" message:@"Lock screen footnote saved! Apply changes to activate." preferredStyle:UIAlertControllerStyleAlert];
        [savedAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:savedAlert animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearScreenTimeCachePressed
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Screen Time Cache" message:@"This will remove Screen Time Agent cache plist files." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSString *stPath = @"/var/mobile/Library/Preferences/ScreenTimeAgent.plist";
        [[NSFileManager defaultManager] removeItemAtPath:stPath error:nil];
        UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:@"Cleared" message:@"Screen Time cache cleared successfully." preferredStyle:UIAlertControllerStyleAlert];
        [doneAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:doneAlert animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setCustomCarrierPressed
{
    NSString *currentCarrier = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_custom_carrier"] ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Carrier Name" message:@"Enter text to display as the cellular network carrier:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"e.g. Dopamine OS";
        textField.text = currentCarrier;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newText = alert.textFields.firstObject.text ?: @"";
        [[DOPreferenceManager sharedManager] setPreferenceValue:newText forKey:@"dopamine_custom_carrier"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setCustomTimePressed
{
    NSString *currentTime = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_custom_time"] ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Time String" message:@"Enter custom text to display instead of the clock time in status bar:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"e.g. 9:41 AM";
        textField.text = currentTime;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newText = alert.textFields.firstObject.text ?: @"";
        [[DOPreferenceManager sharedManager] setPreferenceValue:newText forKey:@"dopamine_custom_time"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setSignalStrengthPressed
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cellular Signal Strength" message:@"Select number of signal bars to display:" preferredStyle:UIAlertControllerStyleActionSheet];
    for (int i = 0; i <= 4; i++) {
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%d Bars", i] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[DOPreferenceManager sharedManager] setPreferenceValue:@(i) forKey:@"dopamine_numeric_signal"];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset to Default" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[DOPreferenceManager sharedManager] setPreferenceValue:nil forKey:@"dopamine_numeric_signal"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setBatteryLevelPressed
{
    id currentVal = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_override_battery"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Battery Percentage" message:@"Enter battery level (0-100) or leave empty for real level:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"e.g. 100";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.text = currentVal ? [NSString stringWithFormat:@"%@", currentVal] : @"";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newText = alert.textFields.firstObject.text ?: @"";
        [[DOPreferenceManager sharedManager] setPreferenceValue:newText.length ? @(newText.integerValue) : nil forKey:@"dopamine_override_battery"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setCustomResolutionPressed
{
    id currW = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_custom_res_w"];
    id currH = [[DOPreferenceManager sharedManager] preferenceValueForKey:@"dopamine_custom_res_h"];
    
    NSString *currDesc = (currW && currH) ? [NSString stringWithFormat:DOLocalizedText(@"Current: %@ x %@", @"Текущее: %@ x %@"), currW, currH] : DOLocalizedText(@"Current: Native default", @"Текущее: По умолчанию");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Screen Resolution / Stretch", @"Разрешение экрана / Растяг") message:currDesc preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"Stretch Wide (1440 x 2560)", @"Растяг в ширину (1440 x 2560)") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[DOPreferenceManager sharedManager] setPreferenceValue:@(1440) forKey:@"dopamine_custom_res_w"];
        [[DOPreferenceManager sharedManager] setPreferenceValue:@(2560) forKey:@"dopamine_custom_res_h"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"iPad Mini Canvas (1488 x 2266)", @"Формат iPad Mini (1488 x 2266)") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[DOPreferenceManager sharedManager] setPreferenceValue:@(1488) forKey:@"dopamine_custom_res_w"];
        [[DOPreferenceManager sharedManager] setPreferenceValue:@(2266) forKey:@"dopamine_custom_res_h"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"iPhone 15 Pro Max (1290 x 2796)", @"iPhone 15 Pro Max (1290 x 2796)") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[DOPreferenceManager sharedManager] setPreferenceValue:@(1290) forKey:@"dopamine_custom_res_w"];
        [[DOPreferenceManager sharedManager] setPreferenceValue:@(2796) forKey:@"dopamine_custom_res_h"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"Custom Width & Height...", @"Задать вручную...") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *customPrompt = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Custom Screen Resolution", @"Пользовательское разрешение") message:DOLocalizedText(@"Enter Canvas Width and Height (e.g. 1179 x 2556):", @"Введите ширину и высоту экрана:") preferredStyle:UIAlertControllerStyleAlert];
        [customPrompt addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"Width (e.g. 1440)";
            textField.keyboardType = UIKeyboardTypeNumberPad;
            textField.text = currW ? [NSString stringWithFormat:@"%@", currW] : @"";
        }];
        [customPrompt addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"Height (e.g. 2560)";
            textField.keyboardType = UIKeyboardTypeNumberPad;
            textField.text = currH ? [NSString stringWithFormat:@"%@", currH] : @"";
        }];
        [customPrompt addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
            NSString *wText = customPrompt.textFields[0].text ?: @"";
            NSString *hText = customPrompt.textFields[1].text ?: @"";
            if (wText.length && hText.length) {
                [[DOPreferenceManager sharedManager] setPreferenceValue:@(wText.integerValue) forKey:@"dopamine_custom_res_w"];
                [[DOPreferenceManager sharedManager] setPreferenceValue:@(hText.integerValue) forKey:@"dopamine_custom_res_h"];
            }
        }]];
        [customPrompt addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:customPrompt animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedText(@"Reset to Native", @"Сбросить к оригиналу") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[DOPreferenceManager sharedManager] setPreferenceValue:nil forKey:@"dopamine_custom_res_w"];
        [[DOPreferenceManager sharedManager] setPreferenceValue:nil forKey:@"dopamine_custom_res_h"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyDopamineChangesPressed
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apply Dopamine Tweaks" message:@"Writing preferences and configurations to device..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DOPreferenceManager *prefs = [DOPreferenceManager sharedManager];

        // 1. SpringBoard Managed Preferences Plist
        NSString *sbPlistPath = @"/var/Managed Preferences/mobile/com.apple.springboard.plist";
        NSMutableDictionary *sbDict = [NSMutableDictionary dictionaryWithContentsOfFile:sbPlistPath] ?: [NSMutableDictionary new];
        sbDict[@"SBAlwaysShowSystemApertureInSnapshots"] = @([prefs boolPreferenceValueForKey:@"dopamine_di_in_screenshots" fallback:NO]);
        sbDict[@"SBSuppressDynamicIslandCompletely"] = @([prefs boolPreferenceValueForKey:@"dopamine_hide_di_completely" fallback:NO]);
        sbDict[@"SBHideLowPowerAlerts"] = @([prefs boolPreferenceValueForKey:@"dopamine_disable_lpm_alert" fallback:NO]);
        sbDict[@"SBDontDimOrLockOnAC"] = @([prefs boolPreferenceValueForKey:@"dopamine_sb_dont_dim_ac" fallback:NO]);
        sbDict[@"SBDontLockAfterCrash"] = @([prefs boolPreferenceValueForKey:@"dopamine_sb_dont_lock_crash" fallback:NO]);
        sbDict[@"SBHideACPower"] = @([prefs boolPreferenceValueForKey:@"dopamine_sb_hide_ac_power" fallback:NO]);
        sbDict[@"SBNeverBreadcrumb"] = @([prefs boolPreferenceValueForKey:@"dopamine_sb_never_breadcrumb" fallback:NO]);
        sbDict[@"SBShowSupervisionTextOnLockScreen"] = @([prefs boolPreferenceValueForKey:@"dopamine_sb_supervision_text" fallback:NO]);
        sbDict[@"SBExtendedDisplayOverrideSupportForAirPlayAndDontFileRadars"] = @([prefs boolPreferenceValueForKey:@"dopamine_airplay_support" fallback:NO]);
        NSString *animSpeedStr = [prefs preferenceValueForKey:@"dopamine_anim_speed"] ?: @"1.0";
        double animSpeed = [animSpeedStr doubleValue];
        if (animSpeed < 0.99) {
            sbDict[@"SBAnimationDurationScale"] = @(animSpeed);
            sbDict[@"SBFastAnimations"] = @YES;
        } else {
            [sbDict removeObjectForKey:@"SBAnimationDurationScale"];
            [sbDict removeObjectForKey:@"SBFastAnimations"];
        }
        [sbDict writeToFile:sbPlistPath atomically:YES];

        // 2. UIKit Managed Preferences Plist
        NSString *uikitPath = @"/var/Managed Preferences/mobile/com.apple.UIKit.plist";
        NSMutableDictionary *uikitDict = [NSMutableDictionary dictionaryWithContentsOfFile:uikitPath] ?: [NSMutableDictionary new];
        uikitDict[@"UseFloatingTabBar"] = @([prefs boolPreferenceValueForKey:@"dopamine_floating_tab_bar" fallback:NO]);
        [uikitDict writeToFile:uikitPath atomically:YES];

        // 3. AirDrop Managed Preferences Plist
        NSString *airdropPath = @"/var/Managed Preferences/mobile/com.apple.sharingd.plist";
        NSMutableDictionary *airdropDict = [NSMutableDictionary dictionaryWithContentsOfFile:airdropPath] ?: [NSMutableDictionary new];
        airdropDict[@"OverrideTimeLimitEveryoneMode"] = @([prefs boolPreferenceValueForKey:@"dopamine_airdrop_limit" fallback:NO]);
        [airdropDict writeToFile:airdropPath atomically:YES];

        // 4. Lockscreen Footnote
        NSString *footnote = [prefs preferenceValueForKey:@"dopamine_lockscreen_footnote"] ?: @"";
        if (footnote.length) {
            NSString *footnotePath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/SharedDeviceConfiguration.plist";
            NSMutableDictionary *fnDict = [NSMutableDictionary dictionaryWithContentsOfFile:footnotePath] ?: [NSMutableDictionary new];
            fnDict[@"LockScreenFootnote"] = footnote;
            [fnDict writeToFile:footnotePath atomically:YES];
        }

        // 5. Feature Flags Global Plist
        NSString *ffPath = @"/var/preferences/FeatureFlags/Global.plist";
        NSMutableDictionary *ffDict = [NSMutableDictionary dictionaryWithContentsOfFile:ffPath] ?: [NSMutableDictionary new];
        NSMutableDictionary *sbFF = [ffDict[@"SpringBoard"] mutableCopy] ?: [NSMutableDictionary new];
        sbFF[@"SwiftUITimeAnimation"] = @{@"Enabled": @([prefs boolPreferenceValueForKey:@"dopamine_clock_animation" fallback:NO])};
        ffDict[@"SpringBoard"] = sbFF;
        [ffDict writeToFile:ffPath atomically:YES];

        // 6. Global Preferences (.GlobalPreferences.plist)
        NSString *gpPath = @"/var/Managed Preferences/mobile/.GlobalPreferences.plist";
        NSMutableDictionary *gpDict = [NSMutableDictionary dictionaryWithContentsOfFile:gpPath] ?: [NSMutableDictionary new];
        gpDict[@"UIStatusBarShowBuildVersion"] = @([prefs boolPreferenceValueForKey:@"dopamine_show_build_number" fallback:NO]);
        gpDict[@"MetalForceHudEnabled"] = @([prefs boolPreferenceValueForKey:@"dopamine_metal_force_hud" fallback:NO]);
        gpDict[@"GesturesEnabled"] = @([prefs boolPreferenceValueForKey:@"dopamine_key_flick" fallback:NO]);
        gpDict[@"SBDisableClockIconSecondsHand"] = @([prefs boolPreferenceValueForKey:@"dopamine_disable_seconds_hand" fallback:NO]);
        gpDict[@"SBHardwareButtonHintDropletsAlwaysVisibleInSnapshots"] = @([prefs boolPreferenceValueForKey:@"dopamine_button_hints" fallback:NO]);
        gpDict[@"com.apple.SwiftUI.DisableSolarium"] = @([prefs boolPreferenceValueForKey:@"dopamine_disable_solarium" fallback:NO]);
        gpDict[@"SolariumForceFallback"] = @([prefs boolPreferenceValueForKey:@"dopamine_solarium_fallback" fallback:NO]);
        gpDict[@"SBDisallowGlassTime"] = @([prefs boolPreferenceValueForKey:@"dopamine_no_liquid_clock" fallback:NO]);
        gpDict[@"SBDisableGlassDock"] = @([prefs boolPreferenceValueForKey:@"dopamine_no_liquid_dock" fallback:NO]);
        gpDict[@"SBDisableSpecularEverywhereUsingLSSAssertion"] = @([prefs boolPreferenceValueForKey:@"dopamine_disable_specular_motion" fallback:NO]);
        gpDict[@"SolariumDisableOuterRefraction"] = @([prefs boolPreferenceValueForKey:@"dopamine_disable_outer_refraction" fallback:NO]);
        gpDict[@"SolariumAllowHDR"] = @(![prefs boolPreferenceValueForKey:@"dopamine_disable_solarium_hdr" fallback:NO]);
        [gpDict writeToFile:gpPath atomically:YES];

        // 7. Backboardd Managed Preferences Plist
        NSString *bbPath = @"/var/Managed Preferences/mobile/com.apple.backboardd.plist";
        NSMutableDictionary *bbDict = [NSMutableDictionary dictionaryWithContentsOfFile:bbPath] ?: [NSMutableDictionary new];
        bbDict[@"BKDigitizerVisualizeTouches"] = @([prefs boolPreferenceValueForKey:@"dopamine_visualize_touches" fallback:NO]);
        bbDict[@"BKHideAppleLogoOnLaunch"] = @([prefs boolPreferenceValueForKey:@"dopamine_hide_apple_logo_launch" fallback:NO]);
        [bbDict writeToFile:bbPath atomically:YES];

        // 8. CoreMotion Managed Preferences Plist
        NSString *cmPath = @"/var/Managed Preferences/mobile/com.apple.CoreMotion.plist";
        NSMutableDictionary *cmDict = [NSMutableDictionary dictionaryWithContentsOfFile:cmPath] ?: [NSMutableDictionary new];
        cmDict[@"EnableWakeGestureHaptic"] = @([prefs boolPreferenceValueForKey:@"dopamine_wake_gesture_haptic" fallback:NO]);
        [cmDict writeToFile:cmPath atomically:YES];

        // 9. Pasteboard Managed Preferences Plist
        NSString *pbPath = @"/var/Managed Preferences/mobile/com.apple.Pasteboard.plist";
        NSMutableDictionary *pbDict = [NSMutableDictionary dictionaryWithContentsOfFile:pbPath] ?: [NSMutableDictionary new];
        pbDict[@"PlaySoundOnPaste"] = @([prefs boolPreferenceValueForKey:@"dopamine_play_sound_on_paste" fallback:NO]);
        pbDict[@"AnnounceAllPastes"] = @([prefs boolPreferenceValueForKey:@"dopamine_announce_all_pastes" fallback:NO]);
        [pbDict writeToFile:pbPath atomically:YES];

        // 10. Notes & AppStore Managed Preferences
        NSString *notesPath = @"/var/Managed Preferences/mobile/com.apple.mobilenotes.plist";
        NSMutableDictionary *notesDict = [NSMutableDictionary dictionaryWithContentsOfFile:notesPath] ?: [NSMutableDictionary new];
        notesDict[@"DebugModeEnabled"] = @([prefs boolPreferenceValueForKey:@"dopamine_notes_debug_mode" fallback:NO]);
        [notesDict writeToFile:notesPath atomically:YES];

        NSString *asPath = @"/var/Managed Preferences/mobile/com.apple.AppStore.plist";
        NSMutableDictionary *asDict = [NSMutableDictionary dictionaryWithContentsOfFile:asPath] ?: [NSMutableDictionary new];
        asDict[@"debugGestureEnabled"] = @([prefs boolPreferenceValueForKey:@"dopamine_appstore_debug" fallback:NO]);
        [asDict writeToFile:asPath atomically:YES];

        // 11. Daemons Launchd Disabled Plist
        NSString *daemonsPath = @"/var/db/com.apple.xpc.launchd/disabled.plist";
        NSMutableDictionary *daemonsDict = [NSMutableDictionary dictionaryWithContentsOfFile:daemonsPath] ?: [NSMutableDictionary new];
        if ([prefs boolPreferenceValueForKey:@"dopamine_daemon_ota" fallback:NO]) {
            daemonsDict[@"com.apple.mobile.softwareupdated"] = @YES;
            daemonsDict[@"com.apple.OTATaskingAgent"] = @YES;
            daemonsDict[@"com.apple.softwareupdateservicesd"] = @YES;
            daemonsDict[@"com.apple.mobile.NRDUpdated"] = @YES;
        } else {
            [daemonsDict removeObjectForKey:@"com.apple.mobile.softwareupdated"];
            [daemonsDict removeObjectForKey:@"com.apple.OTATaskingAgent"];
            [daemonsDict removeObjectForKey:@"com.apple.softwareupdateservicesd"];
            [daemonsDict removeObjectForKey:@"com.apple.mobile.NRDUpdated"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_daemon_crash" fallback:NO]) {
            daemonsDict[@"com.apple.ReportCrash"] = @YES;
            daemonsDict[@"com.apple.analyticsd"] = @YES;
            daemonsDict[@"com.apple.crashreportcopymobile"] = @YES;
            daemonsDict[@"com.apple.DumpPanic"] = @YES;
        } else {
            [daemonsDict removeObjectForKey:@"com.apple.ReportCrash"];
            [daemonsDict removeObjectForKey:@"com.apple.analyticsd"];
            [daemonsDict removeObjectForKey:@"com.apple.crashreportcopymobile"];
            [daemonsDict removeObjectForKey:@"com.apple.DumpPanic"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_daemon_gamecenter" fallback:NO]) {
            daemonsDict[@"com.apple.gamed"] = @YES;
        } else {
            [daemonsDict removeObjectForKey:@"com.apple.gamed"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_daemon_screentime" fallback:NO]) {
            daemonsDict[@"com.apple.ScreenTimeAgent"] = @YES;
            daemonsDict[@"com.apple.homed"] = @YES;
        } else {
            [daemonsDict removeObjectForKey:@"com.apple.ScreenTimeAgent"];
            [daemonsDict removeObjectForKey:@"com.apple.homed"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_daemon_usage_tracking" fallback:NO]) {
            daemonsDict[@"com.apple.UsageTrackingAgent"] = @YES;
        } else {
            [daemonsDict removeObjectForKey:@"com.apple.UsageTrackingAgent"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_daemon_tips" fallback:NO]) {
            daemonsDict[@"com.apple.tipsd"] = @YES;
        } else {
            [daemonsDict removeObjectForKey:@"com.apple.tipsd"];
        }
        if (daemonsDict.count) {
            [daemonsDict writeToFile:daemonsPath atomically:YES];
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:daemonsPath error:nil];
        }

        // 12. MobileGestalt Cache Plist
        NSString *mgPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
        NSMutableDictionary *mgDict = [NSMutableDictionary dictionaryWithContentsOfFile:mgPath] ?: [NSMutableDictionary new];
        NSMutableDictionary *mgCache = [mgDict[@"CacheExtra"] mutableCopy] ?: [NSMutableDictionary new];
        if ([prefs boolPreferenceValueForKey:@"dopamine_dynamic_island" fallback:NO]) {
            mgCache[@"oPeik/9e8lQWMszEjbPzng"] = @{@"ArtworkDeviceSubType": @(2556)};
            mgCache[@"YlEtTtHlNesRBMal1CqRaA"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"oPeik/9e8lQWMszEjbPzng"];
            [mgCache removeObjectForKey:@"YlEtTtHlNesRBMal1CqRaA"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_boot_chime" fallback:NO]) {
            mgCache[@"QHxt+hGLaBPbQJbXiUJX3w"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"QHxt+hGLaBPbQJbXiUJX3w"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_charge_limit" fallback:NO]) {
            mgCache[@"37NVydb//GP/GrhuTN+exg"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"37NVydb//GP/GrhuTN+exg"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_tap_to_wake" fallback:NO]) {
            mgCache[@"yZf3GTRMGTuwSV/lD7Cagw"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"yZf3GTRMGTuwSV/lD7Cagw"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_stage_manager" fallback:NO]) {
            mgCache[@"qeaj75wk3HF4DwQ8qbIi7g"] = @(1);
        } else {
            [mgCache removeObjectForKey:@"qeaj75wk3HF4DwQ8qbIi7g"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_always_on_display" fallback:NO]) {
            mgCache[@"2OOJf1VhaM7NxfRok3HbWQ"] = @(1);
            mgCache[@"j8/Omm6s1lsmTDFsXjsBfA"] = @(1);
        } else {
            [mgCache removeObjectForKey:@"2OOJf1VhaM7NxfRok3HbWQ"];
            [mgCache removeObjectForKey:@"j8/Omm6s1lsmTDFsXjsBfA"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_aod_vibrancy" fallback:NO]) {
            mgCache[@"ykpu7qyhqFweVMKtxNylWA"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"ykpu7qyhqFweVMKtxNylWA"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_action_button" fallback:NO]) {
            mgCache[@"cT44WE1EohiwRzhsZ8xEsw"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"cT44WE1EohiwRzhsZ8xEsw"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_camera_button" fallback:NO]) {
            mgCache[@"CwvKxM2cEogD3p+HYgaW0Q"] = @(1);
            mgCache[@"oOV1jhJbdV3AddkcCg0AEA"] = @(1);
        } else {
            [mgCache removeObjectForKey:@"CwvKxM2cEogD3p+HYgaW0Q"];
            [mgCache removeObjectForKey:@"oOV1jhJbdV3AddkcCg0AEA"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_collision_sos" fallback:NO]) {
            mgCache[@"HCzWusHQwZDea6nNhaKndw"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"HCzWusHQwZDea6nNhaKndw"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_ipad_apps" fallback:NO]) {
            mgCache[@"9MZ5AdH43csAUajl/dU+IQ"] = @[@(1), @(2)];
        } else {
            [mgCache removeObjectForKey:@"9MZ5AdH43csAUajl/dU+IQ"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_shutter_mute" fallback:NO]) {
            mgCache[@"h63QSdBCiT/z0WU6rdQv6Q"] = @"US";
            mgCache[@"zHeENZu+wbg7PUprwNwBWg"] = @"LL/A";
        } else {
            [mgCache removeObjectForKey:@"h63QSdBCiT/z0WU6rdQv6Q"];
            [mgCache removeObjectForKey:@"zHeENZu+wbg7PUprwNwBWg"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_apple_pencil" fallback:NO]) {
            mgCache[@"yhHcB0iH0d1XzPO/CFd3ow"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"yhHcB0iH0d1XzPO/CFd3ow"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_internal_storage" fallback:NO]) {
            mgCache[@"LBJfwOEzExRxzlAnSuI7eg"] = @YES;
        } else {
            [mgCache removeObjectForKey:@"LBJfwOEzExRxzlAnSuI7eg"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_spoof_model" fallback:NO]) {
            mgCache[@"h9jDsbgj7xIVeIQ8S3/X3Q"] = @"iPhone16,1";
            mgCache[@"oYicEKzVTz4/CxxE05pEgQ"] = @"D83AP";
            mgCache[@"5pYKlGnYYBzGvAlIU8RjEQ"] = @"t8130";
        } else {
            [mgCache removeObjectForKey:@"h9jDsbgj7xIVeIQ8S3/X3Q"];
            [mgCache removeObjectForKey:@"oYicEKzVTz4/CxxE05pEgQ"];
            [mgCache removeObjectForKey:@"5pYKlGnYYBzGvAlIU8RjEQ"];
        }
        if ([prefs boolPreferenceValueForKey:@"dopamine_apple_internal" fallback:NO]) {
            mgCache[@"qG2k0N11mmVZmiFiSs/GsQ"] = @YES; // InternalBuild
            mgCache[@"gL4Ic0R/5g8Su8KJGHLYSw"] = @YES; // AppleInternal
            mgCache[@"qywF0C2BKZmVpKX5qAZjMA"] = @YES; // AppleInternalInstallCapability
            mgCache[@"1+4E8BBeaNGPSivmq7uM6Q"] = @YES; // InternalInstallCapability
            mgCache[@"jUjeT6UDHrGLhoZhAfXOSA"] = @YES; // PrototypeTools
        } else {
            [mgCache removeObjectForKey:@"qG2k0N11mmVZmiFiSs/GsQ"];
            [mgCache removeObjectForKey:@"gL4Ic0R/5g8Su8KJGHLYSw"];
            [mgCache removeObjectForKey:@"qywF0C2BKZmVpKX5qAZjMA"];
            [mgCache removeObjectForKey:@"1+4E8BBeaNGPSivmq7uM6Q"];
            [mgCache removeObjectForKey:@"jUjeT6UDHrGLhoZhAfXOSA"];
        }
        mgDict[@"CacheExtra"] = mgCache;
        [mgDict writeToFile:mgPath atomically:YES];

        // 12.1 Dopamine Icon Gravity & Appearance Preferences
        NSString *doPrefPath = @"/var/mobile/Library/Preferences/com.opa334.Dopamine.plist";
        NSMutableDictionary *doPrefDict = [NSMutableDictionary dictionaryWithContentsOfFile:doPrefPath] ?: [NSMutableDictionary new];
        doPrefDict[@"dopamine_icon_gravity"] = @([prefs boolPreferenceValueForKey:@"dopamine_icon_gravity" fallback:NO]);
        doPrefDict[@"dopamine_icon_shape"] = [prefs preferenceValueForKey:@"dopamine_icon_shape"] ?: @"default";
        doPrefDict[@"dopamine_anim_speed"] = [prefs preferenceValueForKey:@"dopamine_anim_speed"] ?: @"1.0";
        doPrefDict[@"dopamine_page_scroll_fx"] = [prefs preferenceValueForKey:@"dopamine_page_scroll_fx"] ?: @"default";
        doPrefDict[@"dopamine_anitime_enabled"] = @([prefs boolPreferenceValueForKey:@"dopamine_anitime_enabled" fallback:NO]);
        doPrefDict[@"dopamine_anitime_style"] = [prefs preferenceValueForKey:@"dopamine_anitime_style"] ?: @"m-static";
        doPrefDict[@"dopamine_aim_pro_enabled"] = @([prefs boolPreferenceValueForKey:@"dopamine_aim_pro_enabled" fallback:NO]);
        doPrefDict[@"dopamine_aim_font"] = [prefs preferenceValueForKey:@"dopamine_aim_font"] ?: @"rounded";
        doPrefDict[@"dopamine_aim_color"] = [prefs preferenceValueForKey:@"dopamine_aim_color"] ?: @"white";
        [doPrefDict writeToFile:doPrefPath atomically:YES];

        // 12.2 AniTime Tweak Files Installation
        BOOL anitimeOn = [prefs boolPreferenceValueForKey:@"dopamine_anitime_enabled" fallback:NO];
        NSString *jbPrefix = @"/var/jb";
        NSString *aniBundleDest = [jbPrefix stringByAppendingPathComponent:@"Library/Application Support/AniTime.bundle"];
        NSString *aniDylibDest = [jbPrefix stringByAppendingPathComponent:@"Library/MobileSubstrate/DynamicLibraries/AniTime.dylib"];
        NSString *aniPlistDest = [jbPrefix stringByAppendingPathComponent:@"Library/MobileSubstrate/DynamicLibraries/AniTime.plist"];
        NSString *appAniDir = [[NSBundle mainBundle] pathForResource:@"AniTime" ofType:nil];
        if (!appAniDir) {
            appAniDir = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"AniTime"];
        }

        if (anitimeOn && [[NSFileManager defaultManager] fileExistsAtPath:appAniDir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[aniBundleDest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            [[NSFileManager defaultManager] createDirectoryAtPath:[aniDylibDest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            
            // Copy AniTime bundle assets
            [[NSFileManager defaultManager] removeItemAtPath:aniBundleDest error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:appAniDir toPath:aniBundleDest error:nil];

            // Copy AniTime tweak dylib & filter plist
            NSString *bundledDylib = [appAniDir stringByAppendingPathComponent:@"AniTime.dylib"];
            NSString *bundledPlist = [appAniDir stringByAppendingPathComponent:@"AniTime.plist"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:bundledDylib]) {
                [[NSFileManager defaultManager] removeItemAtPath:aniDylibDest error:nil];
                [[NSFileManager defaultManager] copyItemAtPath:bundledDylib toPath:aniDylibDest error:nil];
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:bundledPlist]) {
                [[NSFileManager defaultManager] removeItemAtPath:aniPlistDest error:nil];
                [[NSFileManager defaultManager] copyItemAtPath:bundledPlist toPath:aniPlistDest error:nil];
            }
        } else if (!anitimeOn) {
            [[NSFileManager defaultManager] removeItemAtPath:aniDylibDest error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:aniPlistDest error:nil];
        }

        // 13. Custom Resolution
        NSNumber *resW = [prefs preferenceValueForKey:@"dopamine_custom_res_w"];
        NSNumber *resH = [prefs preferenceValueForKey:@"dopamine_custom_res_h"];
        NSString *resPath = @"/var/Managed Preferences/mobile/com.apple.iokit.IOMobileGraphicsFamily.plist";
        NSMutableDictionary *resDict = [NSMutableDictionary dictionaryWithContentsOfFile:resPath] ?: [NSMutableDictionary new];
        if (resW && resH) {
            resDict[@"canvas_width"] = resW;
            resDict[@"canvas_height"] = resH;
            [resDict writeToFile:resPath atomically:YES];
        } else {
            [resDict removeObjectForKey:@"canvas_width"];
            [resDict removeObjectForKey:@"canvas_height"];
            if (resDict.count) {
                [resDict writeToFile:resPath atomically:YES];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:resPath error:nil];
            }
        }

        // 14. MobileAsset OTA Blocking
        NSString *otaPath = @"/var/Managed Preferences/mobile/com.apple.MobileAsset.plist";
        NSMutableDictionary *otaDict = [NSMutableDictionary dictionaryWithContentsOfFile:otaPath] ?: [NSMutableDictionary new];
        if ([prefs boolPreferenceValueForKey:@"dopamine_disable_ota_mobileasset" fallback:NO]) {
            otaDict[@"MobileAssetServerURL-com.apple.MobileAsset.MobileSoftwareUpdate.UpdateBrain"] = @"https://mesu.apple.com/assets/tvOS16DeveloperSeed";
            otaDict[@"MobileAssetSUAllowOSVersionChange"] = @NO;
            otaDict[@"MobileAssetSUAllowSameVersionFullReplacement"] = @NO;
            otaDict[@"MobileAssetServerURL-com.apple.MobileAsset.RecoveryOSUpdate"] = @"https://mesu.apple.com/assets/tvOS16DeveloperSeed";
            otaDict[@"MobileAssetServerURL-com.apple.MobileAsset.RecoveryOSUpdateBrain"] = @"https://mesu.apple.com/assets/tvOS16DeveloperSeed";
            otaDict[@"MobileAssetServerURL-com.apple.MobileAsset.SoftwareUpdate"] = @"https://mesu.apple.com/assets/tvOS16DeveloperSeed";
            otaDict[@"MobileAssetAssetAudience"] = @"65254ac3-f331-4c19-8559-cbe22f5bc1a6";
            [otaDict writeToFile:otaPath atomically:YES];
        } else {
            [otaDict removeObjectForKey:@"MobileAssetServerURL-com.apple.MobileAsset.MobileSoftwareUpdate.UpdateBrain"];
            [otaDict removeObjectForKey:@"MobileAssetSUAllowOSVersionChange"];
            [otaDict removeObjectForKey:@"MobileAssetSUAllowSameVersionFullReplacement"];
            [otaDict removeObjectForKey:@"MobileAssetServerURL-com.apple.MobileAsset.RecoveryOSUpdate"];
            [otaDict removeObjectForKey:@"MobileAssetServerURL-com.apple.MobileAsset.RecoveryOSUpdateBrain"];
            [otaDict removeObjectForKey:@"MobileAssetServerURL-com.apple.MobileAsset.SoftwareUpdate"];
            [otaDict removeObjectForKey:@"MobileAssetAssetAudience"];
            if (otaDict.count) {
                [otaDict writeToFile:otaPath atomically:YES];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:otaPath error:nil];
            }
        }

        // 15. EU Enabler
        NSString *euPath = @"/var/db/os_eligibility/eligibility.plist";
        NSMutableDictionary *euDict = [NSMutableDictionary dictionaryWithContentsOfFile:euPath] ?: [NSMutableDictionary new];
        if ([prefs boolPreferenceValueForKey:@"dopamine_eu_enabler" fallback:NO]) {
            NSMutableDictionary *mDict = [euDict[@"OS_ELIGIBILITY_DOMAIN_MARKETPLACE"] mutableCopy] ?: [NSMutableDictionary new];
            mDict[@"os_eligibility_answer_t"] = @(4);
            euDict[@"OS_ELIGIBILITY_DOMAIN_MARKETPLACE"] = mDict;
            [euDict writeToFile:euPath atomically:YES];
        } else {
            [euDict removeObjectForKey:@"OS_ELIGIBILITY_DOMAIN_MARKETPLACE"];
            if (euDict.count) {
                [euDict writeToFile:euPath atomically:YES];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:euPath error:nil];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:DOLocalizedText(@"Modifications Applied", @"Модификации применены") message:DOLocalizedText(@"Configurations saved directly to device system. Restarting SpringBoard...", @"Конфигурации сохранены в систему. Перезапуск SpringBoard...") preferredStyle:UIAlertControllerStyleAlert];
                [self presentViewController:doneAlert animated:YES completion:nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [[DOEnvironmentManager sharedManager] respring];
                });
            }];
        });
    });
}

@end

