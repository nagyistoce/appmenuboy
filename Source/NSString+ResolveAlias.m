//
//  NSString+ResolveAlias.m
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

#import "NSString+ResolveAlias.h"

// returns YES on success
static BOOL NSStringPathToFSRef(NSString *s, FSRef *outRefp) {
  BOOL val = NO;
  CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)s, kCFURLPOSIXPathStyle, NO /*isDirectory*/);
  if (url) {
    val = CFURLGetFSRef(url, outRefp);
    CFRelease(url);
  }
  return val;
}

@implementation NSString(ResolveAlias)
- (BOOL)isAliasFile {
  BOOL val = NO;
  FSRef fsRef;
  Boolean isAlias, isFolder;
  if (NSStringPathToFSRef(self, &fsRef) &&
      noErr == FSIsAliasFile(&fsRef, &isAlias, &isFolder)) {

    val = isAlias;
  }
  return val;
}

- (NSString *)resolveAliasFile {
  NSString *val = nil;
  FSRef fsRef;
  if (NSStringPathToFSRef(self, &fsRef)) {
    Boolean targetIsFolder, wasAliased;
    if (noErr == FSResolveAliasFile (&fsRef, true /*resolveAliasChains*/, &targetIsFolder, &wasAliased) && wasAliased) {
      CFURLRef resolvedUrl = CFURLCreateFromFSRef(kCFAllocatorDefault, &fsRef);
      if (resolvedUrl) {
        CFStringRef path = CFURLCopyFileSystemPath(resolvedUrl, kCFURLPOSIXPathStyle);
        if (path) {
          val = [NSString stringWithString:(NSString *)path];
          CFRelease(path);
        }
        CFRelease(resolvedUrl);
      }
    }
  }
  return val;
}
@end
