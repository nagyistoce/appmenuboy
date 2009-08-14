//
//  AppMenu.m
//  AppMenu
//
//  Created by David Oster on 1/20/08.
//  Copyright 2008-2009 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not
//  use this file except in compliance with the License.  You may obtain a copy
//  of the License at
// 
//  http://www.apache.org/licenses/LICENSE-2.0
// 
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
//  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
//  License for the specific language governing permissions and limitations under
//  the License.
//
// Purpose: in OS X 10.4, you could drag the Applications folder in Finder to
//    the Dock to get a poor man's "Start" menu. 
//    This function is broken in OS X 10.5.0. This app has a dock menu that shows
//    your applications. It also puts a copy in the menu bar, with small icons.
//
//
// Theory of operation:
//   applicationDidFinishLaunching: calls rebuildMenus, which:
//    * discards the contents of the array of KQueue listeners.
//    * rebuilds the hierarchical menu of apps in the menu bar.
//      (which, as a side-effect, rebuilds the array of KQueue listeners)
//    * copies that menu as the dock menu.
//  
// - (void)buildTree:(NSString *)path intoMenu:(NSMenu *)menu depth:(int)depth;
//   does the actual work of building a directory into a menu.
// It loops over all the files in the directory, for each file, categorizing, 
//    then dispatching to a handler.
//
// There are three handlers, each making a menu item:
// - (void)appBundle:(NSString *)file path:(NSString *)path into:(NSMutableArray *)items;
// - (void)carbonApp:(NSString *)file path:(NSString *)path into:(NSMutableArray *)items;
//
// Makes a sub menu menu item for following subfolders.
// - (void)subDir:(NSString *)file path:(NSString *)path into:(NSMutableArray *)items depth:(int)depth;
//
// The O.S. handles hard links and soft links automatically, but Finder Alias
//    Files require us to do some work. 
//
// The "depth" parameter artificially restricts the submenu tree to being at 
//    most N deep.

// DONE:
// * icon for this app.
// * If a subfolder contains only one app, then replace the subfolder by the app.
// * icons with sub menus
// * treat non-app subfolders as hierarchical menus. restrict depths
// * handle Finder Alias files.
// * when clicked, tell application "Finder" to open path
// * put copy of app menu on main menu bar
// 1.0.1 12/12/07
// * folder icons.
// * File menu removed
//  6/16/08
// * Changed format of Interface Builder file for also building on Tiger.
// 1.0.2 8/10/09
// * Listens for directory changes, and rebuild the menu automatically.
// * Uses the localized name from the en.lproj/InfoPlist.strings file.
// * Reports its version in the Finder about box.
// * Refactored to build a NSMutableArray, sort, build the menu from that
// * Added a BOOL preference, "ignoringParens", to skip parenthesized folders.
// ? Add a BOOL preference dialog to set the ignoringParens preference.

#import "AppMenu.h"
#import <Carbon/Carbon.h>
#import "GTMFileSystemKQueue.h" // see http://code.google.com/mac/
#import "NSString+ResolveAlias.h"

@interface NSMenuItem(AppMenu)

- (NSComparisonResult)compareAsFinder:(NSMenuItem *)other;

@end

@implementation NSMenuItem(AppMenu)

- (NSComparisonResult)compareAsFinder:(NSMenuItem *)other {
  return [[self title] localizedCaseInsensitiveCompare:[other title]];
}

@end

typedef enum  {
  kIgnore,
  kAppBundle,
  kSubDir,
  kCarbonApp
} FileCategoryEnum;

@interface AppMenu(ForwardDeclarations)

// main routine of this program: loop over a directory building menus
- (void)buildTree:(NSString *)path into:(NSMutableArray *)items depth:(int)depth;
- (void)buildTree:(NSString *)path intoMenu:(NSMenu *)menu depth:(int)depth;

- (void)rebuildMenus;

@end

@implementation AppMenu

- (void)removeAllItemsOf:(NSMenu *)menu {
  int i, iCount = [menu numberOfItems];
  for (i = iCount - 1;0 <= i; --i) {
    [menu removeItemAtIndex:i];
  }
}

- (void)openAppItem:(id)sender {
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSString *path = [sender representedObject];
  if (path) {
    [ws openFile:path];
  }
}

// helper routine: give each item a small icon for app at fullPath.
- (void)setImagePath:(NSString *)fullPath forItem:(NSMenuItem *)item {
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSImage *image = [ws iconForFile:fullPath];
  if (image) {
    [image setSize:NSMakeSize(16,16)];  // makes it small
    [item setImage:image];
  }
}

- (void)addKQueueForPath:(NSString *)fullPath {
  GTMFileSystemKQueue *kq = [[[GTMFileSystemKQueue alloc] 
      initWithPath:fullPath
         forEvents:kGTMFileSystemKQueueDeleteEvent |
                   kGTMFileSystemKQueueWriteEvent |
                   kGTMFileSystemKQueueLinkChangeEvent |
                   kGTMFileSystemKQueueRenameEvent
     acrossReplace:NO
            target:self
            action:@selector(fileSystemKQueue:events:)] autorelease];
  if (nil != kq) {
    [kqueues_ addObject:kq];
  }
}


- (void)fileSystemKQueue:(GTMFileSystemKQueue *)fskq
                  events:(GTMFileSystemKQueueEvents)events {
  [self rebuildMenus];
}

#pragma mark -
// an ordinary OS X app.
// 
- (void)appBundle:(NSString *)file path:(NSString *)fullPath into:(NSMutableArray *)items {
  NSString *trimmedFile = nil;

  CFStringRef displayName = NULL;
  // Prefer the localized name from the Info.plist.
  if (noErr == LSCopyDisplayNameForURL((CFURLRef) [NSURL fileURLWithPath:fullPath], &displayName) &&
    NULL != displayName) {
    trimmedFile = [(NSString *)displayName autorelease];
  }
  if (nil == trimmedFile) {
    // Should never happen because Launch Services shoudl already have looked up the correct name.
    NSRange matchRange = [file rangeOfString:@".app" options:NSCaseInsensitiveSearch|NSBackwardsSearch|NSAnchoredSearch];
    if (0 != matchRange.length) {
      trimmedFile = [file substringToIndex:matchRange.location];
    }
  }
  NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:trimmedFile action:@selector(openAppItem:) keyEquivalent:@""] autorelease];
  [item setRepresentedObject:fullPath];
  [items addObject:item];
  [self setImagePath:fullPath forItem:item];
}

// a subdirectory
- (void)subDir:(NSString *)file path:(NSString *)fullPath  into:(NSMutableArray *)items depth:(int)depth {
  NSMenu *subMenu = [[[NSMenu alloc] initWithTitle:file] autorelease];
  if (depth < 6) {  // limit recursion depth.
    [self buildTree:fullPath intoMenu:subMenu depth:1+depth];
  }
  [self addKQueueForPath:fullPath];
  if (0 < [subMenu numberOfItems]) {
    NSMenuItem *item = nil;
    if (1 == [subMenu numberOfItems]) {
      item = [subMenu itemAtIndex:0];
      [[item retain] autorelease];
      [subMenu removeItemAtIndex:0];
    } else {
      item = [[[NSMenuItem alloc] initWithTitle:file action:@selector(openAppItem:) keyEquivalent:@""] autorelease];
      [item setRepresentedObject:fullPath];
      [item setSubmenu:subMenu];
      [self setImagePath:fullPath forItem:item];
    }
    [items addObject:item];
  }
}

// a all in one file GUI app.
- (void)carbonApp:(NSString *)file path:(NSString *)fullPath into:(NSMutableArray *)items {
  NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:file action:@selector(openAppItem:) keyEquivalent:@""] autorelease];
  [item setRepresentedObject:fullPath];
  [items addObject:item];
  [self setImagePath:fullPath forItem:item];
}
#pragma mark -

// what kind of file system object is this? returns enum.
- (FileCategoryEnum)categorizeFile:(NSString *)file path:(NSString *)fullPath {
  if (nil == file || [file hasPrefix:@"."]) {
    return kIgnore;
  }
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDirectory = NO;
  if ([fm fileExistsAtPath:fullPath isDirectory:&isDirectory] && 
          isDirectory) {
          
    NSString *trimmedFile = file;
    NSRange matchRange = [trimmedFile rangeOfString:@".app" options:NSCaseInsensitiveSearch|NSBackwardsSearch|NSAnchoredSearch];
    if (0 != matchRange.length) {
      return kAppBundle;
    }

    // a few early OS X apps don't end in a .app extension. Dig deeper for them.
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    if ([ws isFilePackageAtPath:fullPath]) {
      NSBundle *bundle = [NSBundle bundleWithPath:fullPath];
      NSDictionary *info = [bundle infoDictionary];
      if ([[info objectForKey:@"CFBundlePackageType"] isEqual:@"APPL"]) {
        return kAppBundle;
      }
    }
    if (isIgnoringParentheses_ && [file hasPrefix:@"("] && [file hasSuffix:@")"]) {
      return kIgnore;
    }
    return kSubDir;
  } else {
    NSDictionary *fileAttributes = [fm fileAttributesAtPath:fullPath traverseLink:YES];
    OSType typeCode = [fileAttributes fileHFSTypeCode];
    if (typeCode == 'APPL') {
      return kCarbonApp;
    }
  }
  return kIgnore;
}


// main routine of this program: loop over a directory building menus
- (void)buildTree:(NSString *)path into:(NSMutableArray *)items depth:(int)depth {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *files = [fm directoryContentsAtPath:path];
  NSEnumerator *fileEnumerator = [files objectEnumerator];
  NSString *file;
  while (nil != (file = [fileEnumerator nextObject])) {
    NSString *fullPath = [path stringByAppendingPathComponent:file];
    if ([fullPath isAliasFile]) {
      fullPath = [fullPath resolveAliasFile];
    }
    switch ([self categorizeFile:file path:fullPath]) {
    case kAppBundle: [self appBundle:file path:fullPath into:items]; break;
    case kSubDir:    [self subDir:file path:fullPath into:items depth:depth + 1]; break;
    case kCarbonApp: [self carbonApp:file path:fullPath into:items];break;
    default:
    case kIgnore:    break;
    }
  }
}

- (void)buildTree:(NSString *)path intoMenu:(NSMenu *)menu depth:(int)depth {
  NSMutableArray *items = [NSMutableArray array];
  [self buildTree:path into:items depth:depth];
  [items sortUsingSelector:@selector(compareAsFinder:)];
  NSEnumerator *itemsEnumerator = [items objectEnumerator];
  NSMenuItem *item;
  while (nil != (item = [itemsEnumerator nextObject])) {
    [menu addItem:item];
  }
}


- (void)replaceAllItemsOfDockMenuWithAllItemsOfAppMenu {
  [self removeAllItemsOf:dockMenu_];
  NSMenuItem *item;
  NSEnumerator *items = [[appMenu_ itemArray] objectEnumerator];
  while (nil != (item = [items nextObject])) {
    [dockMenu_ addItem:[[item copy] autorelease]];
  }
}

- (void)rebuildAppMenu {
  if (nil == appMenu_) {
    appMenu_ = [[NSMenu alloc] initWithTitle:@"Apps"];
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"Apps" action:nil keyEquivalent:@""] autorelease];
    [item setSubmenu:appMenu_];
    [[NSApp mainMenu] addItem:item];
  }
  [self removeAllItemsOf:appMenu_];
  [self buildTree:@"/Applications" intoMenu:appMenu_ depth:0];
}

- (void)rebuildMenus {
  isIgnoringParentheses_ = [[NSUserDefaults standardUserDefaults] boolForKey:@"ignoringParens"];
  if (nil == kqueues_) {
    kqueues_ = [[NSMutableArray alloc] init];
  }
  [kqueues_ removeAllObjects];
  [self rebuildAppMenu];
  [self replaceAllItemsOfDockMenuWithAllItemsOfAppMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [self rebuildMenus];
}


// app will call this to get the dock menu.
- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
  return dockMenu_;
}

@end
// The following was documented as putting an icon in a dock menu item, but I couldn't get it to work:
//http://developer.apple.com/documentation/Carbon/Conceptual/customizing_docktile/tasks/chapter_3_section_5.html
//SetMenuItemIconHandle (myMenu,  // <- menu ref
//                        2,  // <- ones based index.
//                        kMenuIconResourceType,
//                        (Handle) CFSTR("mySpecialIcon.icns") ); // normally a partial path to a .icns file.
//example: (doesn't work)
//MenuRef menu = GetApplicationDockTileMenu();
//SetMenuItemIconHandle(menu,  // <- menu ref
//                        CountMenuItems(menu),  // <- ones based index.
//                        kMenuIconResourceType,
//                        (Handle) CFSTR("/Applications/Address Book.app/Contents/Resources/AddressBook.icns") ); 
