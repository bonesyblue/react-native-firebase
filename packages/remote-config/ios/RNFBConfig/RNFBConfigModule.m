/**
 * Copyright (c) 2016-present Invertase Limited & Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this library except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import <Firebase/Firebase.h>
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>

#import "RNFBConfigModule.h"
#import "RNFBSharedUtils.h"

static NSString *const ON_CONFIG_UPDATED_EVENT = @"on_config_updated";

static __strong NSMutableDictionary *configUpdateHandlers;

@implementation RNFBConfigModule
#pragma mark -
#pragma mark Converters

NSString *convertFIRRemoteConfigFetchStatusToNSString(FIRRemoteConfigFetchStatus value) {
  switch (value) {
    case FIRRemoteConfigFetchStatusNoFetchYet:
      return @"no_fetch_yet";
    case FIRRemoteConfigFetchStatusSuccess:
      return @"success";
    case FIRRemoteConfigFetchStatusThrottled:
      return @"throttled";
    case FIRRemoteConfigFetchStatusFailure:
      return @"failure";
    default:
      return @"unknown";
  }
}

NSString *convertFIRRemoteConfigFetchStatusToNSStringDescription(FIRRemoteConfigFetchStatus value) {
  switch (value) {
    case FIRRemoteConfigFetchStatusThrottled:
      return @"fetch() operation cannot be completed successfully, due to throttling.";
    case FIRRemoteConfigFetchStatusNoFetchYet:
    default:
      return @"fetch() operation cannot be completed successfully.";
  }
}

NSString *convertFIRRemoteConfigSourceToNSString(FIRRemoteConfigSource value) {
  switch (value) {
    case FIRRemoteConfigSourceDefault:
      return @"default";
    case FIRRemoteConfigSourceRemote:
      return @"remote";
    case FIRRemoteConfigSourceStatic:
      return @"static";
    default:
      return @"unknown";
  }
}

NSString *convertFIRRemoteConfigUpdateErrorToNSString(FIRRemoteConfigUpdateError value) {
  switch (value) {
    case FIRRemoteConfigUpdateErrorStreamError:
      return @"config_update_stream_error";
    case FIRRemoteConfigUpdateErrorMessageInvalid:
      return @"config_update_message_invalid";
    case FIRRemoteConfigUpdateErrorNotFetched:
      return @"config_update_not_fetched";
    case FIRRemoteConfigUpdateErrorUnavailable:
      return @"config_update_unavailable";
    default:
      return @"internal";
  }
}

NSDictionary *convertFIRRemoteConfigValueToNSDictionary(FIRRemoteConfigValue *value) {
  return @{
    @"value" : (id)value.stringValue ?: [NSNull null],
    @"source" : convertFIRRemoteConfigSourceToNSString(value.source)
  };
}

#pragma mark -
#pragma mark Module Setup

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue {
  return dispatch_get_main_queue();
}

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

- (id)init {
  self = [super init];
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    configUpdateHandlers = [[NSMutableDictionary alloc] init];
  });
  return self;
}

- (void)dealloc {
  [self invalidate];
}

- (void)invalidate {
  for (NSString *key in configUpdateHandlers) {
    FIRConfigUpdateListenerRegistration *registration = [configUpdateHandlers objectForKey:key];
    [registration remove];
  }

  [configUpdateHandlers removeAllObjects];
}

#pragma mark -
#pragma mark Firebase Config Methods

RCT_EXPORT_METHOD(ensureInitialized
                  : (FIRApp *)firebaseApp
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  FIRRemoteConfigInitializationCompletion completionHandler = ^(NSError *__nullable error) {
    if (error) {
      [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
    } else {
      resolve([self resultWithConstants:[NSNull null] firebaseApp:firebaseApp]);
    }
  };

  [[FIRRemoteConfig remoteConfigWithApp:firebaseApp]
      ensureInitializedWithCompletionHandler:completionHandler];
}

RCT_EXPORT_METHOD(fetch
                  : (FIRApp *)firebaseApp
                  : (nonnull NSNumber *)expirationDuration
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  FIRRemoteConfigFetchCompletion completionHandler =
      ^(FIRRemoteConfigFetchStatus status, NSError *__nullable error) {
        if (error) {
          [RNFBSharedUtils
              rejectPromiseWithUserInfo:reject
                               userInfo:[@{
                                 @"code" : convertFIRRemoteConfigFetchStatusToNSString(status),
                                 @"message" :
                                     convertFIRRemoteConfigFetchStatusToNSStringDescription(status)
                               } mutableCopy]];
        } else {
          resolve([self resultWithConstants:[NSNull null] firebaseApp:firebaseApp]);
        }
      };

  if (expirationDuration.integerValue == -1) {
    [[FIRRemoteConfig remoteConfigWithApp:firebaseApp]
        fetchWithCompletionHandler:completionHandler];
  } else {
    [[FIRRemoteConfig remoteConfigWithApp:firebaseApp]
        fetchWithExpirationDuration:expirationDuration.doubleValue
                  completionHandler:completionHandler];
  }
}

RCT_EXPORT_METHOD(fetchAndActivate
                  : (FIRApp *)firebaseApp
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  FIRRemoteConfigFetchAndActivateCompletion completionHandler =
      ^(FIRRemoteConfigFetchAndActivateStatus status, NSError *__nullable error) {
        if (error) {
          if (error.userInfo && error.userInfo[@"ActivationFailureReason"] != nil &&
              [error.userInfo[@"ActivationFailureReason"] containsString:@"already activated"]) {
            resolve([self resultWithConstants:@([RCTConvert BOOL:@(YES)]) firebaseApp:firebaseApp]);
          } else {
            [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
          }
        } else {
          if (status == FIRRemoteConfigFetchAndActivateStatusSuccessFetchedFromRemote) {
            resolve([self resultWithConstants:@([RCTConvert BOOL:@(YES)]) firebaseApp:firebaseApp]);
            return;
          }
          // if no data fetched remotely, return false
          resolve([self resultWithConstants:@([RCTConvert BOOL:@(NO)]) firebaseApp:firebaseApp]);
        }
      };

  [[FIRRemoteConfig remoteConfig] fetchAndActivateWithCompletionHandler:completionHandler];
}

RCT_EXPORT_METHOD(activate
                  : (FIRApp *)firebaseApp
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  [[FIRRemoteConfig remoteConfigWithApp:firebaseApp] activateWithCompletion:^(
                                                         BOOL changed, NSError *_Nullable error) {
    if (error) {
      if (error.userInfo && error.userInfo[@"ActivationFailureReason"] != nil &&
          [error.userInfo[@"ActivationFailureReason"] containsString:@"already activated"]) {
        resolve([self resultWithConstants:@([RCTConvert BOOL:@(NO)]) firebaseApp:firebaseApp]);
      } else {
        [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
      }
    } else {
      resolve([self resultWithConstants:@([RCTConvert BOOL:@(changed)]) firebaseApp:firebaseApp]);
    }
  }];
}

RCT_EXPORT_METHOD(setConfigSettings
                  : (FIRApp *)firebaseApp
                  : (NSDictionary *)configSettings
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  FIRRemoteConfigSettings *remoteConfigSettings = [[FIRRemoteConfigSettings alloc] init];

  if ([configSettings objectForKey:@"minimumFetchInterval"]) {
    remoteConfigSettings.minimumFetchInterval =
        [configSettings[@"minimumFetchInterval"] doubleValue];
  }

  if ([configSettings objectForKey:@"fetchTimeout"]) {
    remoteConfigSettings.fetchTimeout = [configSettings[@"fetchTimeout"] doubleValue];
  }

  [FIRRemoteConfig remoteConfigWithApp:firebaseApp].configSettings = remoteConfigSettings;
  resolve([self resultWithConstants:[NSNull null] firebaseApp:firebaseApp]);
}

RCT_EXPORT_METHOD(setDefaults
                  : (FIRApp *)firebaseApp
                  : (NSDictionary *)defaults
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  [[FIRRemoteConfig remoteConfigWithApp:firebaseApp] setDefaults:defaults];
  resolve([self resultWithConstants:[NSNull null] firebaseApp:firebaseApp]);
}
RCT_EXPORT_METHOD(setDefaultsFromResource
                  : (FIRApp *)firebaseApp
                  : (NSString *)fileName
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  if ([[NSBundle mainBundle] pathForResource:fileName ofType:@"plist"] != nil) {
    [[FIRRemoteConfig remoteConfigWithApp:firebaseApp] setDefaultsFromPlistFileName:fileName];
    resolve([self resultWithConstants:[NSNull null] firebaseApp:firebaseApp]);
  } else {
    [RNFBSharedUtils rejectPromiseWithUserInfo:reject
                                      userInfo:[@{
                                        @"code" : @"resource_not_found",
                                        @"message" : @"The specified resource name was not found."
                                      } mutableCopy]];
  }
}

RCT_EXPORT_METHOD(onConfigUpdated : (FIRApp *)firebaseApp) {
  if (![configUpdateHandlers valueForKey:firebaseApp.name]) {
    FIRConfigUpdateListenerRegistration *newRegistration =
        [[FIRRemoteConfig remoteConfigWithApp:firebaseApp]
            addOnConfigUpdateListener:^(FIRRemoteConfigUpdate *_Nonnull configUpdate,
                                        NSError *_Nullable error) {
              if (error != nil) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];

                [userInfo setValue:@"error" forKey:@"resultType"];
                [userInfo setValue:convertFIRRemoteConfigUpdateErrorToNSString(error.code)
                            forKey:@"code"];
                [userInfo setValue:error.localizedDescription forKey:@"message"];
                [userInfo setValue:error.localizedDescription forKey:@"nativeErrorMessage"];
                [RNFBSharedUtils sendJSEventForApp:firebaseApp
                                              name:ON_CONFIG_UPDATED_EVENT
                                              body:userInfo];
                return;
              }

              NSMutableDictionary *results = [NSMutableDictionary dictionary];

              [results setValue:@"success" forKey:@"resultType"];
              [results setValue:[configUpdate.updatedKeys allObjects] forKey:@"updatedKeys"];

              [RNFBSharedUtils sendJSEventForApp:firebaseApp
                                            name:ON_CONFIG_UPDATED_EVENT
                                            body:results];
            }];

    configUpdateHandlers[firebaseApp.name] = newRegistration;
  }
}

RCT_EXPORT_METHOD(removeConfigUpdateRegistration : (FIRApp *)firebaseApp) {
  if ([configUpdateHandlers valueForKey:firebaseApp.name]) {
    [[configUpdateHandlers objectForKey:firebaseApp.name] remove];
    [configUpdateHandlers removeObjectForKey:firebaseApp.name];
  }
}

RCT_EXPORT_METHOD(setCustomSignals
                  : (FIRApp *)firebaseApp
                  : (NSDictionary *)customSignals
                  : (RCTPromiseResolveBlock)resolve
                  : (RCTPromiseRejectBlock)reject) {
  [[FIRRemoteConfig remoteConfigWithApp:firebaseApp]
      setCustomSignals:customSignals
        withCompletion:^(NSError *_Nullable error) {
          if (error != nil) {
            [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
          } else {
            resolve([self resultWithConstants:[NSNull null] firebaseApp:firebaseApp]);
          }
        }];
}

#pragma mark -
#pragma mark Internal Helper Methods

- (NSDictionary *)resultWithConstants:(id)result firebaseApp:(FIRApp *)firebaseApp {
  NSMutableDictionary *responseDict = [NSMutableDictionary new];
  responseDict[@"result"] = result;
  responseDict[@"constants"] = [self getConstantsForApp:firebaseApp];
  return responseDict;
}

- (NSDictionary *)getConstantsForApp:(FIRApp *)firebaseApp {
  FIRRemoteConfig *remoteConfig = [FIRRemoteConfig remoteConfigWithApp:firebaseApp];

  NSDate *lastFetchTime = remoteConfig.lastFetchTime;
  NSString *lastFetchStatus =
      convertFIRRemoteConfigFetchStatusToNSString(remoteConfig.lastFetchStatus);
  double minimumFetchInterval =
      [RCTConvert double:@([remoteConfig configSettings].minimumFetchInterval)];
  double fetchTimeout = [RCTConvert double:@([remoteConfig configSettings].fetchTimeout)];

  NSMutableDictionary *values = [NSMutableDictionary new];
  NSSet *keys = [[FIRRemoteConfig remoteConfigWithApp:firebaseApp] keysWithPrefix:nil];
  for (NSString *key in keys) {
    FIRRemoteConfigValue *value =
        [[FIRRemoteConfig remoteConfigWithApp:firebaseApp] configValueForKey:key];
    values[key] = convertFIRRemoteConfigValueToNSDictionary(value);
  }

  NSArray *defaultKeys = [remoteConfig allKeysFromSource:FIRRemoteConfigSourceDefault];
  for (NSString *key in defaultKeys) {
    if ([values valueForKey:key] == nil) {
      FIRRemoteConfigValue *value =
          [[FIRRemoteConfig remoteConfigWithApp:firebaseApp] configValueForKey:key];
      values[key] = convertFIRRemoteConfigValueToNSDictionary(value);
    }
  }

  return @{
    @"values" : values,
    @"lastFetchStatus" : lastFetchStatus,
    @"lastFetchTime" : @(round([lastFetchTime timeIntervalSince1970] * 1000.0)),
    @"minimumFetchInterval" : @(minimumFetchInterval),
    @"fetchTimeout" : @(fetchTimeout)
  };
}

@end
