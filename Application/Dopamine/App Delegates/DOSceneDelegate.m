//
//  SceneDelegate.m
//  Dopamine
//
//  Created by Lars Fröder on 23.09.23.
//

#import "DOSceneDelegate.h"
#import "DONavigationController.h"

@interface DOSceneDelegate ()

@end

@implementation DOSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [[DONavigationController alloc] init];
    [window makeKeyAndVisible];
    self.window = window;

    if (connectionOptions.shortcutItem) {
        [self handleShortcutItem:connectionOptions.shortcutItem];
    }
}

- (void)handleShortcutItem:(UIApplicationShortcutItem *)shortcutItem {
    if (!shortcutItem) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *root = self.window.rootViewController;
        if ([shortcutItem.type isEqualToString:@"safe_mode"]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Запуск без модулей" message:@"Режим Safe Mode: инъекция твиков временно приостановлена." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [root presentViewController:alert animated:YES completion:nil];
        } else if ([shortcutItem.type isEqualToString:@"appdata"]) {
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
            NSString *version = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: @"3.x";
            NSString *msg = [NSString stringWithFormat:@"Bundle ID: %@\nVersion: %@\nData: %@", bundleId, version, docs];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AppData" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [root presentViewController:alert animated:YES completion:nil];
        } else if ([shortcutItem.type isEqualToString:@"edit_layout"]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Layout" message:@"Параметры сетки рабочего стола и растяга экрана активны в разделе Настроек." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [root presentViewController:alert animated:YES completion:nil];
        } else if ([shortcutItem.type isEqualToString:@"edit_labels"] || [shortcutItem.type isEqualToString:@"edit_dots"]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:shortcutItem.localizedTitle message:@"Настройки отображения подписей и точек страниц перенесены в раздел SpringBoard." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [root presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    [self handleShortcutItem:shortcutItem];
    if (completionHandler) completionHandler(YES);
}

+ (void)relaunch
{
    UIWindowScene *windowScene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
    DOSceneDelegate *instance = (DOSceneDelegate *)windowScene.delegate;

    [UIView animateWithDuration:0.3 animations:^{
        instance.window.alpha = 0;
    } completion:^(BOOL finished) {
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)instance.window.windowScene];
        window.rootViewController = [[DONavigationController alloc] init];
        [window makeKeyAndVisible];
        instance.window = window;
        instance.window.alpha = 0;
        [UIView animateWithDuration:0.3 animations:^{
            instance.window.alpha = 1;
        }];
    }];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
}


@end
