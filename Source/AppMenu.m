//
//  AppMenu.m
//  AppMenu
//
//  Created by David Oster on 1/20/08.
//  Copyright 2008 Google Inc.
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
//    This function is broken in OS X 10.5. This app has a dock menu that shows
//    your applications. It also puts a copy in the menu bar, with small icons.
//
//
// Theory of operation:
//   awakeFromNib calls two more awakeFunctions to build the menus.
//  
// - (void)buildTree:(NSString *)path into:(NSMenu *)menu depth:(int)depth;
//   does the actual work of building a directory into amenu.
// It loops over all the files in the directory, for each file, categorizing, 
//    then dispatching to a handler.
//
// There are four handlers, each making a menu item:
// - (void)appBundle:(NSString *)file path:(NSString *)path into:(NSMenu *)menu;
// - (void)carbonApp:(NSString *)file path:(NSString *)path into:(NSMenu *)menu;
//
// Makes a sub menu menu item for following subfolders.
// - (void)subDir:(NSString *)file path:(NSString *)path  into:(NSMenu *)menu depth:(int)depth;
//
// The O.S. handles hard links and soft links automatically, but Finder Alias
//    Files require us to do some work. 
//
// The "depth" parameter artificially restricts the submenu tree to being at 
//    most N deep.


// TODO:
// * rebuild the menu if the directory changes.

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
// 1.0.x 

#import "AppMenu.h"
#import <Carbon/Carbon.h>
#import "NSString+ResolveAlias.h"

typedef enum  {
  kIgnore,
  kAppBundle,
  kSubDir,
  kCarbonApp
} FileCategoryEnum;

@interface AppMenu(ForwardDeclarations)
// main routine of this program: loop over a directory building menus
- (void)buildTree:(NSString *)path into:(NSMenu *)menu depth:(int)depth;
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

#pragma mark -
// an ordinary OS X app.
- (void)appBundle:(NSString *)file path:(NSString *)fullPath into:(NSMenu *)menu {
   NSString *trimmedFile = file;
  NSRange matchRange = [trimmedFile rangeOfString:@".app" options:NSCaseInsensitiveSearch|NSBackwardsSearch|NSAnchoredSearch];
  if (0 != matchRange.length) {
    trimmedFile = [trimmedFile substringToIndex:matchRange.location];
  }
  NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:trimmedFile action:@selector(openAppItem:) keyEquivalent:@""] autorelease];
  [item setRepresentedObject:fullPath];
  [menu addItem:item];
  [self setImagePath:fullPath forItem:item];
}

// a subdirectory
- (void)subDir:(NSString *)file path:(NSString *)fullPath  into:(NSMenu *)menu depth:(int)depth {
  NSMenu *subMenu = [[[NSMenu alloc] initWithTitle:file] autorelease];
  if (depth < 6) {  // limit recursion depth.
    [self buildTree:fullPath into:subMenu depth:1+depth];
  }
  if (0 < [subMenu numberOfItems]) {
    NSMenuItem *item = nil;
    if (1 == [subMenu numberOfItems]) {
      item = [subMenu itemAtIndex:0];
      [[item retain] autorelease];
      [subMenu removeItemAtIndex:0];
    } else {
      item = [[[NSMenuItem alloc] initWithTitle:file action:@selector(openAppItem:) keyEquivalent:@""] autorelease];
      [item setRepresentedObject:fullPath];
      [menu setSubmenu:subMenu forItem:item];
      [self setImagePath:fullPath forItem:item];
    }
    [menu addItem:item];
  }
}

// a all in one file GUI app.
- (void)carbonApp:(NSString *)file path:(NSString *)fullPath into:(NSMenu *)menu {
  NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:file action:@selector(openAppItem:) keyEquivalent:@""] autorelease];
  [item setRepresentedObject:fullPath];
  [menu addItem:item];
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
- (void)buildTree:(NSString *)path into:(NSMenu *)menu depth:(int)depth {
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
    case kAppBundle: [self appBundle:file path:fullPath into:menu]; break;
    case kSubDir:    [self subDir:file path:fullPath into:menu depth:depth + 1]; break;
    case kCarbonApp: [self carbonApp:file path:fullPath into:menu];break;
    default:
    case kIgnore:    break;
    }
  }
}

- (void)awakeDockMenu {
  [self removeAllItemsOf:dockMenu_];
  [self buildTree:@"/Applications" into:dockMenu_ depth:0];
}

- (void)awakeAppMenu {
  NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"Apps"] autorelease];
  [self removeAllItemsOf:appMenu];
  [self buildTree:@"/Applications" into:appMenu depth:0];
  NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"Apps" action:nil keyEquivalent:@""] autorelease];
  NSMenu *mainMenu = [NSApp mainMenu];
  [mainMenu addItem:item];
  [mainMenu setSubmenu:appMenu forItem:item];
}

- (void)awakeFromNib {
  [self awakeDockMenu];
  [self awakeAppMenu];
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
