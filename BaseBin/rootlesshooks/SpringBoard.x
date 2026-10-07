#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <substrate.h>
#import <objc/objc.h>
#import <libroot.h>
#import <fcntl.h>
#import <notify.h>
#import <QuartzCore/QuartzCore.h>

bool string_has_prefix(const char *str, const char* prefix)
{
	if (!str || !prefix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t prefix_len = strlen(prefix);

	if (str_len < prefix_len) {
		return false;
	}

	return !strncmp(str, prefix, prefix_len);
}

@interface XBSnapshotContainerIdentity : NSObject <NSCopying>
@property (nonatomic, readonly, copy) NSString* bundleIdentifier;
- (NSString*)snapshotContainerPath;
@end

%hook XBSnapshotContainerIdentity

- (NSString *)snapshotContainerPath
{
	NSString *path = %orig;
	if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && ![self.bundleIdentifier hasPrefix:@"com.apple."]) {
		return JBROOT_PATH_NSSTRING(path);
	}
	return path;
}

%end

%hookf(int, fcntl, int fildes, int cmd, ...) {
	if (cmd == F_SETPROTECTIONCLASS) {
		char filePath[PATH_MAX];
		if (fcntl(fildes, F_GETPATH, filePath) != -1) {
			// Skip setting protection class on jailbreak apps, this doesn't work and causes snapshots to not be saved correctly
			if (string_has_prefix(filePath, JBROOT_PATH_CSTRING("/var/mobile/Library/SplashBoard/Snapshots"))) {
				return 0;
			}
		}
	}

	va_list a;
	va_start(a, cmd);
	const char *arg1 = va_arg(a, void *);
	const void *arg2 = va_arg(a, void *);
	const void *arg3 = va_arg(a, void *);
	const void *arg4 = va_arg(a, void *);
	const void *arg5 = va_arg(a, void *);
	const void *arg6 = va_arg(a, void *);
	const void *arg7 = va_arg(a, void *);
	const void *arg8 = va_arg(a, void *);
	const void *arg9 = va_arg(a, void *);
	const void *arg10 = va_arg(a, void *);
	va_end(a);
	return %orig(fildes, cmd, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
}

static BOOL gGravityActive = NO;
static UIDynamicAnimator *gGravityAnimator = nil;
static UIGravityBehavior *gGravityBehavior = nil;
static UICollisionBehavior *gCollisionBehavior = nil;
static UIDynamicItemBehavior *gItemBehavior = nil;
static UIAttachmentBehavior *gPanAttachment = nil;
static id gMotionManager = nil;
static NSMutableArray *gAnimatedIcons = nil;
static NSMutableDictionary *gOriginalCenters = nil;
static UIPanGestureRecognizer *gGravityPanGesture = nil;
static UITapGestureRecognizer *gGravityTapGesture = nil;
static __weak UIWindow *gGravityWindow = nil;

static void stopSpringBoardGravity(void) {
	if (!gGravityActive) return;
	gGravityActive = NO;
	
	if (gMotionManager) {
		@try {
			[gMotionManager performSelector:@selector(stopDeviceMotionUpdates)];
		} @catch (id ex) {}
		gMotionManager = nil;
	}
	
	if (gGravityWindow) {
		if (gGravityPanGesture) {
			[gGravityWindow removeGestureRecognizer:gGravityPanGesture];
			gGravityPanGesture = nil;
		}
		if (gGravityTapGesture) {
			[gGravityWindow removeGestureRecognizer:gGravityTapGesture];
			gGravityTapGesture = nil;
		}
	}
	
	if (gGravityAnimator) {
		[gGravityAnimator removeAllBehaviors];
		gGravityAnimator = nil;
	}
	
	[UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
		for (UIView *icon in gAnimatedIcons) {
			NSValue *centerVal = gOriginalCenters[[NSValue valueWithNonretainedObject:icon]];
			if (centerVal) {
				icon.center = [centerVal CGPointValue];
			}
			icon.transform = CGAffineTransformIdentity;
		}
	} completion:^(BOOL finished) {
		[gAnimatedIcons removeAllObjects];
		[gOriginalCenters removeAllObjects];
		gGravityWindow = nil;
	}];
}

static void handleGravityPan(UIPanGestureRecognizer *gesture) {
	if (!gGravityActive || !gGravityAnimator) return;
	CGPoint location = [gesture locationInView:gesture.view];
	
	if (gesture.state == UIGestureRecognizerStateBegan) {
		for (UIView *icon in gAnimatedIcons) {
			if (CGRectContainsPoint(icon.frame, location)) {
				UIOffset offset = UIOffsetMake(location.x - icon.center.x, location.y - icon.center.y);
				gPanAttachment = [[UIAttachmentBehavior alloc] initWithItem:icon offsetFromCenter:offset attachedToAnchor:location];
				[gGravityAnimator addBehavior:gPanAttachment];
				break;
			}
		}
	} else if (gesture.state == UIGestureRecognizerStateChanged) {
		if (gPanAttachment) {
			gPanAttachment.anchorPoint = location;
		}
	} else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
		if (gPanAttachment) {
			[gGravityAnimator removeBehavior:gPanAttachment];
			gPanAttachment = nil;
			CGPoint vel = [gesture velocityInView:gesture.view];
			for (UIView *icon in gAnimatedIcons) {
				if (CGRectContainsPoint(icon.frame, location)) {
					[gItemBehavior addLinearVelocity:CGPointMake(vel.x * 0.8, vel.y * 0.8) forItem:icon];
					break;
				}
			}
		}
	}
}

static void handleGravityTap(UITapGestureRecognizer *gesture) {
	if (!gGravityActive) return;
	CGPoint location = [gesture locationInView:gesture.view];
	for (UIView *icon in gAnimatedIcons) {
		if (CGRectContainsPoint(icon.frame, location)) {
			// Find icon model and launch application if possible
			@try {
				if ([icon respondsToSelector:@selector(icon)]) {
					id iconModel = [icon performSelector:@selector(icon)];
					if ([iconModel respondsToSelector:@selector(applicationBundleID)]) {
						NSString *bundleID = [iconModel performSelector:@selector(applicationBundleID)];
						if (bundleID) {
							Class appWorkspace = NSClassFromString(@"LSApplicationWorkspace");
							if (appWorkspace) {
								id ws = [appWorkspace performSelector:@selector(defaultWorkspace)];
								[ws performSelector:@selector(openApplicationWithBundleID:) withObject:bundleID];
							}
						}
					}
				}
			} @catch (id ex) {}
			break;
		}
	}
}

static void startSpringBoardGravity(UIWindow *window) {
	if (gGravityActive) return;
	
	NSMutableArray *icons = [NSMutableArray new];
	NSMutableArray *queue = [NSMutableArray arrayWithObject:window];
	while (queue.count) {
		UIView *curr = queue.firstObject;
		[queue removeObjectAtIndex:0];
		NSString *className = NSStringFromClass([curr class]);
		if ([className containsString:@"IconView"] && ![className containsString:@"FolderIcon"]) {
			[icons addObject:curr];
		} else {
			[queue addObjectsFromArray:curr.subviews];
		}
	}
	
	if (icons.count == 0) return;
	
	gGravityActive = YES;
	gAnimatedIcons = icons;
	gGravityWindow = window;
	gOriginalCenters = [NSMutableDictionary new];
	for (UIView *icon in icons) {
		gOriginalCenters[[NSValue valueWithNonretainedObject:icon]] = [NSValue valueWithCGPoint:icon.center];
	}
	
	gGravityAnimator = [[UIDynamicAnimator alloc] initWithReferenceView:window];
	gGravityBehavior = [[UIGravityBehavior alloc] initWithItems:icons];
	gGravityBehavior.gravityDirection = CGVectorMake(0.0, 1.5);
	
	gCollisionBehavior = [[UICollisionBehavior alloc] initWithItems:icons];
	gCollisionBehavior.translatesReferenceBoundsIntoBoundary = YES;
	gCollisionBehavior.collisionMode = UICollisionBehaviorModeEverything;
	
	gItemBehavior = [[UIDynamicItemBehavior alloc] initWithItems:icons];
	gItemBehavior.elasticity = 0.62;
	gItemBehavior.friction = 0.18;
	gItemBehavior.allowsRotation = YES;
	
	[gGravityAnimator addBehavior:gGravityBehavior];
	[gGravityAnimator addBehavior:gCollisionBehavior];
	[gGravityAnimator addBehavior:gItemBehavior];
	
	// Add interactive pan and tap gestures
	gGravityPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:window action:@selector(handleGravityPanGesture:)];
	gGravityTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:window action:@selector(handleGravityTapGesture:)];
	[window addGestureRecognizer:gGravityPanGesture];
	[window addGestureRecognizer:gGravityTapGesture];
	
	// Real accelerometer & device tilt support
	Class motionClass = NSClassFromString(@"CMMotionManager");
	if (!motionClass) {
		dlopen("/System/Library/Frameworks/CoreMotion.framework/CoreMotion", RTLD_NOW);
		motionClass = NSClassFromString(@"CMMotionManager");
	}
	if (motionClass) {
		@try {
			gMotionManager = [[motionClass alloc] init];
			if ([gMotionManager respondsToSelector:@selector(isDeviceMotionAvailable)] &&
				((BOOL (*)(id, SEL))objc_msgSend)(gMotionManager, @selector(isDeviceMotionAvailable))) {
				
				[gMotionManager setValue:@(1.0 / 40.0) forKey:@"deviceMotionUpdateInterval"];
				NSOperationQueue *queue = [NSOperationQueue mainQueue];
				void (^motionHandler)(id, NSError *) = ^(id motion, NSError *error) {
					if (!gGravityActive || !gGravityBehavior || !motion) return;
					@try {
						id gravityObj = [motion valueForKey:@"gravity"];
						if (gravityObj) {
							NSNumber *gxNum = [gravityObj valueForKey:@"x"];
							NSNumber *gyNum = [gravityObj valueForKey:@"y"];
							if (gxNum && gyNum) {
								double gx = [gxNum doubleValue];
								double gy = [gyNum doubleValue];
								gGravityBehavior.gravityDirection = CGVectorMake(gx * 2.5, -gy * 2.5);
							}
						}
					} @catch (id ex) {}
				};
				
				SEL startSel = NSSelectorFromString(@"startDeviceMotionUpdatesToQueue:withHandler:");
				if ([gMotionManager respondsToSelector:startSel]) {
					((void (*)(id, SEL, id, id))objc_msgSend)(gMotionManager, startSel, queue, motionHandler);
				}
			}
		} @catch (id ex) {}
	}
}

%hook UIWindow

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
	%orig;
	if (motion == UIEventSubtypeMotionShake) {
		NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.opa334.Dopamine.plist"];
		if ([prefs[@"dopamine_icon_gravity"] boolValue]) {
			if (gGravityActive) {
				stopSpringBoardGravity();
			} else {
				startSpringBoardGravity(self);
			}
		}
	}
}

%new
- (void)handleGravityPanGesture:(UIPanGestureRecognizer *)gesture
{
	handleGravityPan(gesture);
}

%new
- (void)handleGravityTapGesture:(UITapGestureRecognizer *)gesture
{
	handleGravityTap(gesture);
}

%end

%hook SpringBoard

- (void)_lockButtonDown:(id)arg1 fromSource:(int)arg2
{
	%orig;
	if (gGravityActive) {
		stopSpringBoardGravity();
	}
}

- (void)applicationDidFinishLaunching:(id)application
{
	%orig;
	[[NSNotificationCenter defaultCenter] addObserverForName:@"com.opa334.dopamine.togglegravity" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		UIWindow *keyWin = nil;
		for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
			if ([scene isKindOfClass:[UIWindowScene class]]) {
				for (UIWindow *w in ((UIWindowScene *)scene).windows) {
					if (w.isKeyWindow || [NSStringFromClass([w class]) containsString:@"HomeScreen"]) {
						keyWin = w;
						break;
					}
					if (!keyWin) keyWin = w;
				}
			}
			if (keyWin) break;
		}
		if (keyWin) {
			if (gGravityActive) stopSpringBoardGravity();
			else startSpringBoardGravity(keyWin);
		}
	}];
}

%end

@interface SBIconImageView : UIView
@end

%hook SBIconImageView

- (void)layoutSubviews
{
	%orig;
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.opa334.Dopamine.plist"];
	NSString *shape = prefs[@"dopamine_icon_shape"];
	if ([shape isEqualToString:@"circle"]) {
		CGFloat r = self.bounds.size.width / 2.0;
		self.layer.cornerRadius = r;
		self.layer.masksToBounds = YES;
		self.clipsToBounds = YES;
		self.layer.cornerCurve = kCACornerCurveCircular;
		for (CALayer *sub in self.layer.sublayers) {
			sub.cornerRadius = r;
			sub.masksToBounds = YES;
		}
	} else if ([shape isEqualToString:@"square"]) {
		self.layer.cornerRadius = 0.0;
		self.layer.masksToBounds = YES;
		self.clipsToBounds = YES;
		for (CALayer *sub in self.layer.sublayers) {
			sub.cornerRadius = 0.0;
			sub.masksToBounds = YES;
		}
	}
}

%end

@interface SBIconView : UIView
@end

%hook SBIconView

- (void)layoutSubviews
{
	%orig;
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.opa334.Dopamine.plist"];
	NSString *shape = prefs[@"dopamine_icon_shape"];
	if ([shape isEqualToString:@"circle"] || [shape isEqualToString:@"square"]) {
		CGFloat r = [shape isEqualToString:@"circle"] ? (self.bounds.size.width / 2.0) : 0.0;
		for (UIView *sub in self.subviews) {
			if ([NSStringFromClass([sub class]) containsString:@"IconImage"]) {
				sub.layer.cornerRadius = r;
				sub.layer.masksToBounds = YES;
				sub.clipsToBounds = YES;
			}
		}
	}
}

%end

static NSString *findAniTimeBundlePath(void) {
	NSArray *candidates = @[
		@"/var/jb/Library/Application Support/AniTime.bundle",
		@"/Library/Application Support/AniTime.bundle",
		@"/var/jb/Applications/Dopamine.app/AniTime",
		@"/Applications/Dopamine.app/AniTime",
	];
	for (NSString *path in candidates) {
		if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
			return path;
		}
	}
	NSString *appsDir = @"/var/containers/Bundle/Application";
	NSArray *appDirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appsDir error:nil];
	for (NSString *d in appDirs) {
		NSString *sub = [appsDir stringByAppendingPathComponent:d];
		NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sub error:nil];
		for (NSString *item in items) {
			if ([item hasSuffix:@".app"]) {
				NSString *check = [[sub stringByAppendingPathComponent:item] stringByAppendingPathComponent:@"AniTime"];
				if ([[NSFileManager defaultManager] fileExistsAtPath:check]) {
					return check;
				}
			}
		}
	}
	return @"/var/jb/Library/Application Support/AniTime.bundle";
}

@interface SBFLockScreenDateView : UIView
@property (nonatomic, strong) UIView *timeLabel;
- (void)updateFormat;
@end

static __weak SBFLockScreenDateView *gCurrentDateView = nil;
static NSTimer *gAniTimeTimer = nil;

static void updateAniTimeView(SBFLockScreenDateView *dateView)
{
	if (!dateView) return;
	gCurrentDateView = dateView;

	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.opa334.Dopamine.plist"];
	BOOL aniEnabled = [prefs[@"dopamine_anitime_enabled"] boolValue];
	BOOL aimEnabled = [prefs[@"dopamine_aim_pro_enabled"] boolValue];

	const NSInteger kAniStackTag = 948210;
	UIView *existingStack = [dateView viewWithTag:kAniStackTag];

	UIView *timeLbl = nil;
	if ([dateView respondsToSelector:@selector(timeLabel)]) {
		timeLbl = [dateView timeLabel];
	}
	if (!timeLbl) {
		for (UIView *sub in dateView.subviews) {
			if ([NSStringFromClass([sub class]) containsString:@"Label"] || [NSStringFromClass([sub class]) containsString:@"Legibility"]) {
				timeLbl = sub;
				break;
			}
		}
	}

	if (aniEnabled) {
		if (timeLbl) {
			timeLbl.alpha = 0.0;
		}

		if (!existingStack) {
			existingStack = [[UIStackView alloc] initWithFrame:CGRectZero];
			existingStack.tag = kAniStackTag;
			UIStackView *sv = (UIStackView *)existingStack;
			sv.axis = UILayoutConstraintAxisHorizontal;
			sv.alignment = UIStackViewAlignmentCenter;
			sv.distribution = UIStackViewDistributionEqualCentering;
			sv.spacing = 3;
			[dateView addSubview:existingStack];
		}

		existingStack.hidden = NO;
		UIStackView *sv = (UIStackView *)existingStack;
		sv.frame = CGRectMake(10, 30, dateView.bounds.size.width - 20, 110);

		NSDateFormatter *df = [NSDateFormatter new];
		df.dateFormat = @"HH:mm";
		NSString *timeStr = [df stringFromDate:[NSDate date]];
		NSString *style = prefs[@"dopamine_anitime_style"] ?: @"m-static";

		NSString *anitimeBase = findAniTimeBundlePath();
		NSString *styleDir = [anitimeBase stringByAppendingPathComponent:style];

		CGFloat digitH = 95.0;
		NSArray *arranged = sv.arrangedSubviews;
		BOOL needsRebuild = (arranged.count != timeStr.length);

		if (needsRebuild) {
			for (UIView *sub in [arranged copy]) {
				[sv removeArrangedSubview:sub];
				[sub removeFromSuperview];
			}
		}

		for (NSUInteger i = 0; i < timeStr.length; i++) {
			NSString *ch = [timeStr substringWithRange:NSMakeRange(i, 1)];
			NSString *fn = [ch isEqualToString:@":"] ? @"colon.png" : [NSString stringWithFormat:@"%@.png", ch];
			NSString *imgPath = [styleDir stringByAppendingPathComponent:fn];
			UIImage *img = [UIImage imageWithContentsOfFile:imgPath];

			if (needsRebuild) {
				if (img) {
					UIImageView *iv = [[UIImageView alloc] initWithImage:img];
					iv.contentMode = UIViewContentModeScaleAspectFit;
					iv.accessibilityIdentifier = ch;
					CGFloat w = (img.size.height > 0) ? (img.size.width / img.size.height * digitH) : 48.0;
					[iv.widthAnchor constraintEqualToConstant:w].active = YES;
					[iv.heightAnchor constraintEqualToConstant:digitH].active = YES;
					[sv addArrangedSubview:iv];
				} else {
					UILabel *digitLbl = [UILabel new];
					digitLbl.text = ch;
					digitLbl.font = [UIFont systemFontOfSize:65 weight:UIFontWeightBold];
					digitLbl.textColor = [UIColor whiteColor];
					[sv addArrangedSubview:digitLbl];
				}
			} else {
				UIView *slotView = arranged[i];
				if ([slotView isKindOfClass:[UIImageView class]]) {
					UIImageView *iv = (UIImageView *)slotView;
					if (![iv.accessibilityIdentifier isEqualToString:ch]) {
						CATransition *transition = [CATransition animation];
						transition.duration = 0.35;
						transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
						transition.type = kCATransitionPush;
						transition.subtype = kCATransitionFromBottom;
						[iv.layer addAnimation:transition forKey:@"digitChange"];
						iv.image = img;
						iv.accessibilityIdentifier = ch;
					}
				}
			}
		}
	} else {
		if (existingStack) {
			existingStack.hidden = YES;
		}
		if (timeLbl) {
			timeLbl.alpha = 1.0;
			if (aimEnabled) {
				NSString *colorPref = prefs[@"dopamine_aim_color"] ?: @"white";
				UIColor *clockColor = [UIColor whiteColor];
				if ([colorPref isEqualToString:@"sakura"]) clockColor = [UIColor colorWithRed:1.0 green:0.62 blue:0.78 alpha:1.0];
				else if ([colorPref isEqualToString:@"cyan"]) clockColor = [UIColor colorWithRed:0.25 green:0.88 blue:1.0 alpha:1.0];
				else if ([colorPref isEqualToString:@"sunset"]) clockColor = [UIColor colorWithRed:1.0 green:0.48 blue:0.25 alpha:1.0];
				else if ([colorPref isEqualToString:@"gold"]) clockColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.0 alpha:1.0];

				if ([timeLbl respondsToSelector:@selector(setTextColor:)]) {
					[(id)timeLbl setTextColor:clockColor];
				}

				NSString *fontPref = prefs[@"dopamine_aim_font"] ?: @"rounded";
				UIFont *clockFont = nil;
				if ([fontPref isEqualToString:@"rounded"]) {
					UIFontDescriptor *d = [[UIFont systemFontOfSize:80 weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
					clockFont = d ? [UIFont fontWithDescriptor:d size:80] : [UIFont systemFontOfSize:80 weight:UIFontWeightBold];
				} else if ([fontPref isEqualToString:@"serif"]) {
					UIFontDescriptor *d = [[UIFont systemFontOfSize:80 weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
					clockFont = d ? [UIFont fontWithDescriptor:d size:80] : [UIFont systemFontOfSize:80 weight:UIFontWeightBold];
				} else if ([fontPref isEqualToString:@"mono"]) {
					clockFont = [UIFont monospacedDigitSystemFontOfSize:80 weight:UIFontWeightBold];
				} else if ([fontPref isEqualToString:@"stencil"]) {
					clockFont = [UIFont fontWithName:@"Impact" size:80] ?: [UIFont systemFontOfSize:80 weight:UIFontWeightHeavy];
				} else {
					clockFont = [UIFont systemFontOfSize:80 weight:UIFontWeightHeavy];
				}
				if (clockFont && [timeLbl respondsToSelector:@selector(setFont:)]) {
					[(id)timeLbl setFont:clockFont];
				}
			}
		}
	}
}

%hook SBFLockScreenDateView

- (void)didMoveToWindow
{
	%orig;
	if (self.window) {
		updateAniTimeView(self);
		if (!gAniTimeTimer) {
			gAniTimeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
				if (gCurrentDateView) {
					updateAniTimeView(gCurrentDateView);
				}
			}];
		}
	}
}

- (void)layoutSubviews
{
	%orig;
	updateAniTimeView(self);
}

- (void)updateFormat
{
	%orig;
	updateAniTimeView(self);
}

%end

static void toggleGravityCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIWindow *keyWin = nil;
		for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
			if ([scene isKindOfClass:[UIWindowScene class]]) {
				for (UIWindow *w in ((UIWindowScene *)scene).windows) {
					if (w.isKeyWindow || [NSStringFromClass([w class]) containsString:@"HomeScreen"]) {
						keyWin = w;
						break;
					}
					if (!keyWin) keyWin = w;
				}
			}
			if (keyWin) break;
		}
		if (keyWin) {
			if (gGravityActive) stopSpringBoardGravity();
			else startSpringBoardGravity(keyWin);
		}
	});
}

static void prefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (gCurrentDateView) {
			updateAniTimeView(gCurrentDateView);
		}
		for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
			if ([scene isKindOfClass:[UIWindowScene class]]) {
				for (UIWindow *w in ((UIWindowScene *)scene).windows) {
					[w setNeedsLayout];
					[w layoutIfNeeded];
				}
			}
		}
	});
}

void springboardInit(void)
{
	%init();
	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		NULL,
		(CFNotificationCallback)toggleGravityCallback,
		CFSTR("com.opa334.dopamine.togglegravity"),
		NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately
	);
	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		NULL,
		(CFNotificationCallback)prefsChangedCallback,
		CFSTR("com.opa334.dopamine.prefs_changed"),
		NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately
	);
}
