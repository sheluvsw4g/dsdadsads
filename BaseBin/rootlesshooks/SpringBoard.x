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
#import <CoreMotion/CoreMotion.h>

static BOOL gGravityActive = NO;
static UIDynamicAnimator *gGravityAnimator = nil;
static UIGravityBehavior *gGravityBehavior = nil;
static UICollisionBehavior *gCollisionBehavior = nil;
static UIDynamicItemBehavior *gItemBehavior = nil;
static CMMotionManager *gMotionManager = nil;
static NSMutableArray *gAnimatedIcons = nil;
static NSMutableDictionary *gOriginalCenters = nil;

static void stopSpringBoardGravity(void) {
	if (!gGravityActive) return;
	gGravityActive = NO;
	if (gMotionManager) {
		[gMotionManager stopDeviceMotionUpdates];
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
	
	gMotionManager = [[CMMotionManager alloc] init];
	if (gMotionManager.isDeviceMotionAvailable) {
		gMotionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
		[gMotionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMDeviceMotion *motion, NSError *error) {
			if (motion && gGravityBehavior) {
				gGravityBehavior.gravityDirection = CGVectorMake(motion.gravity.x * 2.5, -motion.gravity.y * 2.5);
			}
		}];
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

void springboardInit(void)
{
	%init();
}
