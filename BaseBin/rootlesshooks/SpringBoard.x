#import <Foundation/Foundation.h>
#import <substrate.h>
#import <objc/objc.h>
#import <libroot.h>
#import <fcntl.h>

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

#import <UIKit/UIKit.h>
#import <dlfcn.h>

static BOOL gGravityActive = NO;
static UIDynamicAnimator *gGravityAnimator = nil;
static UIGravityBehavior *gGravityBehavior = nil;
static UICollisionBehavior *gCollisionBehavior = nil;
static UIDynamicItemBehavior *gItemBehavior = nil;
static id gMotionManager = nil;
static NSMutableArray *gAnimatedIcons = nil;
static NSMutableDictionary *gOriginalCenters = nil;

static void stopSpringBoardGravity(void) {
	if (!gGravityActive) return;
	gGravityActive = NO;
	if (gMotionManager) {
		@try {
			[gMotionManager performSelector:@selector(stopDeviceMotionUpdates)];
		} @catch (id ex) {}
		gMotionManager = nil;
	}
	if (gGravityAnimator) {
		[gGravityAnimator removeAllBehaviors];
		gGravityAnimator = nil;
	}
	[UIView animateWithDuration:0.65 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
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
	}];
}

static void startSpringBoardGravity(UIWindow *window) {
	if (gGravityActive) return;
	
	NSMutableArray *icons = [NSMutableArray new];
	NSMutableArray *queue = [NSMutableArray arrayWithObject:window];
	while (queue.count) {
		UIView *curr = queue.firstObject;
		[queue removeObjectAtIndex:0];
		if ([NSStringFromClass([curr class]) containsString:@"IconView"]) {
			[icons addObject:curr];
		} else {
			[queue addObjectsFromArray:curr.subviews];
		}
	}
	
	if (icons.count == 0) return;
	
	gGravityActive = YES;
	gAnimatedIcons = icons;
	gOriginalCenters = [NSMutableDictionary new];
	for (UIView *icon in icons) {
		gOriginalCenters[[NSValue valueWithNonretainedObject:icon]] = [NSValue valueWithCGPoint:icon.center];
	}
	
	gGravityAnimator = [[UIDynamicAnimator alloc] initWithReferenceView:window];
	gGravityBehavior = [[UIGravityBehavior alloc] initWithItems:icons];
	gGravityBehavior.gravityDirection = CGVectorMake(0.0, 1.2);
	
	gCollisionBehavior = [[UICollisionBehavior alloc] initWithItems:icons];
	gCollisionBehavior.translatesReferenceBoundsIntoBoundary = YES;
	gCollisionBehavior.collisionMode = UICollisionModeEverything;
	
	gItemBehavior = [[UIDynamicItemBehavior alloc] initWithItems:icons];
	gItemBehavior.elasticity = 0.58;
	gItemBehavior.friction = 0.22;
	gItemBehavior.allowsRotation = YES;
	
	[gGravityAnimator addBehavior:gGravityBehavior];
	[gGravityAnimator addBehavior:gCollisionBehavior];
	[gGravityAnimator addBehavior:gItemBehavior];
	
	Class motionClass = NSClassFromString(@"CMMotionManager");
	if (!motionClass) {
		dlopen("/System/Library/Frameworks/CoreMotion.framework/CoreMotion", RTLD_NOW);
		motionClass = NSClassFromString(@"CMMotionManager");
	}
	if (motionClass) {
		@try {
			gMotionManager = [[motionClass alloc] init];
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

%end

%hook SpringBoard

- (void)_lockButtonDown:(id)arg1 fromSource:(int)arg2
{
	%orig;
	if (gGravityActive) {
		stopSpringBoardGravity();
	}
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
		self.layer.cornerRadius = self.bounds.size.width / 2.0;
		self.layer.masksToBounds = YES;
	} else if ([shape isEqualToString:@"square"]) {
		self.layer.cornerRadius = 0.0;
		self.layer.masksToBounds = YES;
	}
}

%end

@interface SBFLockScreenDateView : UIView
@property (nonatomic, strong) UIView *timeLabel;
- (void)updateFormat;
@end

static void updateAniTimeView(SBFLockScreenDateView *dateView)
{
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

		for (UIView *sub in [sv.arrangedSubviews copy]) {
			[sv removeArrangedSubview:sub];
			[sub removeFromSuperview];
		}

		NSDateFormatter *df = [NSDateFormatter new];
		df.dateFormat = @"HH:mm";
		NSString *timeStr = [df stringFromDate:[NSDate date]];
		NSString *style = prefs[@"dopamine_anitime_style"] ?: @"m-static";

		NSString *anitimeBase = @"/var/jb/Applications/Dopamine.app/AniTime";
		if (![[NSFileManager defaultManager] fileExistsAtPath:anitimeBase]) {
			anitimeBase = @"/Applications/Dopamine.app/AniTime";
		}
		NSString *styleDir = [anitimeBase stringByAppendingPathComponent:style];

		CGFloat digitH = 95.0;
		for (NSUInteger i = 0; i < timeStr.length; i++) {
			NSString *ch = [timeStr substringWithRange:NSMakeRange(i, 1)];
			NSString *fn = [ch isEqualToString:@":"] ? @"colon.png" : [NSString stringWithFormat:@"%@.png", ch];
			NSString *imgPath = [styleDir stringByAppendingPathComponent:fn];
			UIImage *img = [UIImage imageWithContentsOfFile:imgPath];

			if (img) {
				UIImageView *iv = [[UIImageView alloc] initWithImage:img];
				iv.contentMode = UIViewContentModeScaleAspectFit;
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
					UIFontDescriptor *d = [[UIFont systemFontOfSize:80 weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorDesignRounded];
					clockFont = d ? [UIFont fontWithDescriptor:d size:80] : [UIFont systemFontOfSize:80 weight:UIFontWeightBold];
				} else if ([fontPref isEqualToString:@"serif"]) {
					UIFontDescriptor *d = [[UIFont systemFontOfSize:80 weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorDesignSerif];
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

void springboardInit(void)
{
	%init();
}
