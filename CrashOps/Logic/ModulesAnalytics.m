//
//  ModulesAnalytics.m
//  CrashOps
//
//  Created by CrashOps on 02/12/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ModulesAnalytics.h"
#import "ZZZipArchive.h"

#import <CommonCrypto/CommonDigest.h>
#import <zlib.h>
#import <MobileCoreServices/MobileCoreServices.h>

#define CODebugLog(msg) if (ModulesAnalytics.isDebugModeEnabled) { NSLog(@"[CrashOps] %@", msg); }
#define CODebugLogArgs(msg, args) if (ModulesAnalytics.isDebugModeEnabled) { NSLog(@"[CrashOps] %@", [NSString stringWithFormat: msg, args]); }

#define COAssertToast(condition, message) COAssert(condition, message, YES)

#define COAssertLog(condition, message) COAssert(condition, message, NO)

#define COAssert(condition, message, shouldToast)    \
    if (__builtin_expect(!(condition), 0)) {        \
        if (shouldToast)\
            [co_ToastMessage show: [NSString stringWithFormat:@"Assertion Error!\n%@", message] delayInSeconds: 2 onDone: nil]; \
            NSLog(@"Assertion Error!\n%@", message); \
    }

@interface NSFileManager (ModulesAnalytics_NSFileManager)

-(NSUInteger) totalSizeOfFolder:(NSString *)atPath;

@end

@interface NSString (ModulesAnalytics)
// From: https://stackoverflow.com/questions/1524604/md5-algorithm-in-objective-c
- (NSString *) md5String;
@end

@interface NSData(ModulesAnalytics)
// From: https://stackoverflow.com/questions/1524604/md5-algorithm-in-objective-c
- (NSString *) md5String;
- (NSString *) toString;
- (NSString *) toString: (NSStringEncoding)encoding;
@end

@interface ModulesAnalytics()

@property (nonatomic, strong) NSOperationQueue* analyticsOperationQueue;
@property (nonatomic, strong) CrashOpsController* crashOpsController;
@property (nonatomic, strong) NSString *uploadedHistoryPath;
@property (nonatomic, strong) NSString *sentHistoryPath;

@end

@implementation ModulesAnalytics

@synthesize analyticsOperationQueue;
@synthesize crashOpsController;

// Singleton implementation in Objective-C
__strong static ModulesAnalytics *_shared;
+ (ModulesAnalytics *) shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[ModulesAnalytics alloc] initWithCoder: nil];
    });
    
    return _shared;
}

- (instancetype) init {
    return [ModulesAnalytics shared];
}

- (instancetype)initWithCoder:(NSCoder *) coder {
    if (self = [super init]) {
        analyticsOperationQueue = [[NSOperationQueue alloc] init];
        analyticsOperationQueue.name = @"CrashOps_ModulesAnalytics";
    }

    return self;
}

+(NSString *) encode:(NSString *) original {
    NSData *sha256Data = [ModulesAnalytics doSha256:[original dataUsingEncoding: NSUTF8StringEncoding]];
    return [sha256Data md5String];
}

+(NSData *) doSha256:(NSData *)dataIn {
    NSMutableData *macOut = [NSMutableData dataWithLength: CC_SHA256_DIGEST_LENGTH];
    unsigned char *result = CC_SHA256(dataIn.bytes, dataIn.length, macOut.mutableBytes);
    CODebugLog([NSString stringWithCharacters: result length: dataIn.length]);
    return macOut;
}

/// Indicator for debug mode, it also can be turned on via config PLIST file
+(BOOL) isDebugModeEnabled {
    return [CrashOpsController isDebugModeEnabled];
}

+ (void)initiateWithController:(CrashOpsController *) controller {
    [ModulesAnalytics shared].crashOpsController = controller;
    [ModulesAnalytics aggregateNewAvailableFrameworks:^(NSDictionary *binaryImages) {
        [[[ModulesAnalytics shared] analyticsOperationQueue] addOperationWithBlock:^{
            NSMutableArray *binaryImagesArray = [NSMutableArray new];

            NSArray *allKeys = [binaryImages.allKeys copy];
            for (NSString *key in allKeys) {
                NSNumber *size = binaryImages[key];
                [binaryImagesArray addObject:@{@"name":key,@"size":size}]; // in the response "path" will be "name"
            }

            [[ModulesAnalytics shared] sendBinaryInfo: binaryImagesArray callback:^(NSArray *requestedBinaryImages) {
                [[[ModulesAnalytics shared] analyticsOperationQueue] addOperationWithBlock:^{
                    NSMutableArray *filteredImages = [NSMutableArray new];
                    NSMutableArray *hashes = [NSMutableArray new];
                    
                    NSData *sha256Data;
                    NSFileManager *fileManager = [NSFileManager defaultManager];


                    for (NSDictionary *pathAndSize in requestedBinaryImages) {
                        NSString *path = [pathAndSize[@"name"] description];
                        if (![pathAndSize[@"size"] isKindOfClass: [NSNumber class]]) {
                            continue;
                        }
                        NSInteger sizeInBytes = [((NSNumber *)pathAndSize[@"size"]) longValue];
                        NSNumber *actualSize = [binaryImages objectForKey: path];
                        
                        if ([actualSize isKindOfClass: [NSNumber class]] && actualSize.integerValue == sizeInBytes) {
                            NSString *pathAndSizeString = [NSString stringWithFormat:@"%@+%ld", path, (long)sizeInBytes];
                            sha256Data = [ModulesAnalytics doSha256:[pathAndSizeString dataUsingEncoding: NSUTF8StringEncoding]];
                            NSString *uploadRecordPath = [[[ModulesAnalytics shared] uploadedHistoryPath] stringByAppendingPathComponent: [sha256Data md5String]];
                            
                            BOOL isDir = YES;
                            if(![fileManager fileExistsAtPath: uploadRecordPath isDirectory: &isDir]) {
                                // "Never" been uploaded from this device (unless someone deleted this app's folders content)
                                [hashes addObject: sha256Data];
                                [filteredImages addObject: @{@"name": path, @"size":[NSNumber numberWithInteger:sizeInBytes]}];
                            }
                        }
                        
                        
                        CODebugLogArgs(@"Sending requested binary images: %@", [filteredImages description]);
                        
                    }

                    if ([filteredImages count]) {
                        [[ModulesAnalytics shared] uploadBinaryImages: filteredImages callback:^(NSArray *responses) {
                            CODebugLogArgs(@"All upload responses: %@", responses);
                            NSFileManager *fileManager = [NSFileManager defaultManager];
                            [responses enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                                NSURLResponse *response = obj;
                                
                                BOOL wasRequestSuccessful = NO;
                                NSInteger responseStatusCode = 100;
                                if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
                                    responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
                                    wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
                                }

                                if (wasRequestSuccessful) {
                                    NSData *sha256Data = hashes[idx];
                                    NSString *uploadRecordPath = [[[ModulesAnalytics shared] uploadedHistoryPath] stringByAppendingPathComponent: [sha256Data md5String]];

                                    BOOL isDir = YES;
                                    BOOL isCreated = NO;

                                    if(![fileManager fileExistsAtPath: uploadRecordPath isDirectory: &isDir]) {
                                        if(![fileManager createDirectoryAtPath: uploadRecordPath withIntermediateDirectories:YES attributes:nil error:NULL]) {
                                            CODebugLogArgs(@"Error: Failed to create folder %@", uploadRecordPath);
                                        } else {
                                            isCreated = YES;
                                        }
                                    } else {
                                        isCreated = YES;
                                    }
                                } else {
                                    CODebugLogArgs(@"Error: Failed upload %@", response);
                                }
                            }];
                        }];
                    } else {
                        // Quit gracefully...
                    }
                }];
            }];
        }];
    }];
}

+ (BOOL) didAlreadySend:(NSString *) encoded {
    NSString *sentImageRecordPath = [[[ModulesAnalytics shared] sentHistoryPath] stringByAppendingPathComponent: encoded];

    BOOL isDir = YES;
    return [[NSFileManager defaultManager] fileExistsAtPath: sentImageRecordPath isDirectory: &isDir];
}

+ (BOOL) didAlreadyUpload:(NSData *) hash {
    NSString *uploadRecordPath = [[[ModulesAnalytics shared] uploadedHistoryPath] stringByAppendingPathComponent: [hash md5String]];

    BOOL isDir = YES;
    return [[NSFileManager defaultManager] fileExistsAtPath: uploadRecordPath isDirectory: &isDir];
}

+(void) aggregateNewAvailableFrameworks:(void(^)(NSDictionary * binaryImages)) completion {
    if (!completion) { return; }

     NSFileManager *fileManager = [NSFileManager defaultManager];
    
    [[[ModulesAnalytics shared] analyticsOperationQueue] addOperationWithBlock:^{
        NSArray *allFrameworks = [NSBundle allFrameworks];
        NSMutableDictionary *binaryImages = [NSMutableDictionary new];
        
        for (NSBundle *framework in allFrameworks) {
            NSString *moduleName = [[framework.bundlePath lastPathComponent] lowercaseString];
            if (!moduleName) continue;
            
            NSInteger frameworkSize = [fileManager totalSizeOfFolder: framework.bundlePath];
            // Check if it was already sent, before adding
            NSString *pathAndSizeString = [NSString stringWithFormat:@"%@+%ld", framework.resourcePath, (long) frameworkSize];
            NSString *encoded = [ModulesAnalytics encode: pathAndSizeString];

            BOOL isNew = ![self didAlreadySend: encoded];
            if (isNew) {
                binaryImages[framework.resourcePath] = [NSNumber numberWithInteger: frameworkSize];
            }
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completion(binaryImages);
        }];
    }];
}

+ (NSMutableURLRequest *) prepareRequestWithBody:(NSDictionary *) bodyDictionary forEndpoint: (NSString *) apiEndpoint {
    NSData *postBody = [CrashOpsController toJsonData: bodyDictionary];
    if (![postBody length]) {
        return nil;
    }

    NSMutableURLRequest *request = [ModulesAnalytics prepareRequestWithEndpoint: apiEndpoint];

    [request setHTTPBody: postBody];

    return request;
}

+ (NSMutableURLRequest *) prepareRequestWithEndpoint:(NSString *) apiEndpoint {
    return [self prepareRequestWithEndpoint:apiEndpoint contentType: @"application/json; charset=utf-8"];
}

+ (NSMutableURLRequest *) prepareRequestWithEndpoint:(NSString *) apiEndpoint contentType:(NSString *) contentType {
    NSString *serverUrlString = [NSString stringWithFormat: @"https://crashops.com/api/%@", apiEndpoint];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: serverUrlString]];
    
    [request setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies: NO];
    [request setTimeoutInterval: 60];
    [request setHTTPMethod: @"POST"];
    [request setValue: @"gzip" forHTTPHeaderField: @"Accept-Encoding"];
    
    [request setValue: contentType forHTTPHeaderField:@"Content-Type"];
    
    return request;
}

-(NSString *) sentHistoryPath {
    if (_sentHistoryPath != nil) {
        return _sentHistoryPath;
    }

    NSString *path = [crashOpsController.crashOpsLibraryPath stringByAppendingPathComponent: @"Sent"];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            CODebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        _sentHistoryPath = path;
    }

    return _sentHistoryPath;
}

-(NSString *) uploadedHistoryPath {
    if (_uploadedHistoryPath != nil) {
        return _uploadedHistoryPath;
    }

    NSString *path = [crashOpsController.crashOpsLibraryPath stringByAppendingPathComponent: @"Uploaded"];

    BOOL isDir = YES;
    BOOL isCreated = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath: path isDirectory: &isDir]) {
        if(![fileManager createDirectoryAtPath: path withIntermediateDirectories:YES attributes:nil error:NULL]) {
            CODebugLogArgs(@"Error: Failed to create folder %@", path);
        } else {
            isCreated = YES;
        }
    } else {
        isCreated = YES;
    }

    if (isCreated) {
        _uploadedHistoryPath = path;
    }

    return _uploadedHistoryPath;
}

-(void) sendBinaryInfo:(NSArray *) binaryImages callback: (void(^)(NSArray * requestedBinaryImages)) callback {
    if (!callback) return;
    if (![self crashOpsController].isEnabled) return;
    if (![[self crashOpsController].appKey length]) return;

    NSMutableDictionary *sessionDetails = [[[self crashOpsController] generateSessionDetails] mutableCopy];
    [sessionDetails co_setOptionalObject: binaryImages forKey:@"binaryImages"];

    NSMutableURLRequest *request = [ModulesAnalytics prepareRequestWithBody: sessionDetails forEndpoint: @"binaryImages/info"];

    if (!request) {
        [CrashOpsController logInternalError: [NSString stringWithFormat:@"Failed to make request for sending ping: %@", sessionDetails]];
        return;
    }

    [request addValue: [self crashOpsController].appKey forHTTPHeaderField:@"crashops-application-key"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request completionHandler:^(NSData * _Nullable returnedData, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSString *responseString = [[NSString alloc] initWithData: returnedData encoding: NSUTF8StringEncoding];

        CODebugLogArgs(@"Binary info sent with result: %@", responseString);

        BOOL wasRequestSuccessful = NO;
        NSInteger responseStatusCode = 100;
        if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
            responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
            wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
        }

        if (wasRequestSuccessful) {
            NSArray *requestedBinaryImages = [[CrashOpsController toJsonDictionary: responseString] objectForKey: @"requestedBinaryImages"];
            if (!requestedBinaryImages) {
                requestedBinaryImages = @[];
            }

            NSFileManager *fileManager = [NSFileManager defaultManager];

            for (NSDictionary *sentDetails in binaryImages) {
                NSString *path = sentDetails[@"name"];
                NSInteger frameworkSize = [sentDetails[@"size"] integerValue];
                NSString *pathAndSizeString = [NSString stringWithFormat:@"%@+%ld", path, (long) frameworkSize];

                BOOL isDir = YES;
                BOOL isCreated = NO;

                NSString *encoded = [ModulesAnalytics encode: pathAndSizeString];
                NSString *sentRecordPath = [[[ModulesAnalytics shared] sentHistoryPath] stringByAppendingPathComponent: encoded];

                if(![fileManager fileExistsAtPath: sentRecordPath isDirectory: &isDir]) {
                    if(![fileManager createDirectoryAtPath: sentRecordPath withIntermediateDirectories:YES attributes:nil error:NULL]) {
                        CODebugLogArgs(@"Error in saving sent record: Failed to create folder %@", sentRecordPath);
                    } else {
                        isCreated = YES;
                    }
                } else {
                    isCreated = YES;
                }
            }

            callback(requestedBinaryImages);
        } else {
            callback(@[]);
        }
    }];

    [task resume];
}

-(void) uploadBinaryImages:(NSArray *) binaryImages callback: (void(^)(NSArray *responses)) callback {
    if (!callback) return;
    if (![self crashOpsController].isEnabled) return;
    if (![[self crashOpsController].appKey length]) return;
    
    NSMutableArray *results = [NSMutableArray new];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *libraryPath = [[self crashOpsController] crashOpsLibraryPath];

    [CrashOpsController asyncLoopArray:binaryImages iterationBody:^(id element, VoidCallback carryOn) {
        CODebugLogArgs(@"Currently uploading: %@", [element description]);
        NSString *zipFilePath = @"";
        NSString *imagePath = [element[@"name"] description];
        NSInteger sizeInBytes = [element[@"size"] longValue];

        if ([imagePath length] && sizeInBytes > 0) {
            zipFilePath = [libraryPath stringByAppendingPathComponent:[NSString stringWithFormat: @"%@.zip", imagePath.lastPathComponent]];
            BOOL didCreateZipFile = [ZZZipArchive createZipFileAtPath: zipFilePath withContentsOfDirectory: imagePath];
            if (!didCreateZipFile) {
                zipFilePath = @"";
            }
        }

        if ([zipFilePath length]) {
            NSString *deviceId = [CrashOpsController deviceId];
            //name=\"%@\"; file=\"%@\"; appDeviceId=\"%@; size=\"%ld\"\r\n", zipFilePath, imagePath, fileName, deviceId, sizeInBytes
            [self uploadRequestMultipartDataWithFiles:@[zipFilePath] andParameters:@{@"name":imagePath,@"appDeviceId": deviceId, @"size": [NSNumber numberWithInteger:sizeInBytes]} callback:^(NSData *data, NSURLResponse *response) {
                if (data) {
                    NSString *dataString = [[NSString alloc] initWithData: data encoding:NSUTF8StringEncoding];
                    CODebugLogArgs(@"upload request with multipart got response data (stringified) = %@", dataString);
                } else {
                    CODebugLogArgs(@"error with response = %@", response);
                }

                [fileManager removeItemAtPath: [zipFilePath stringByReplacingOccurrencesOfString: @"file://" withString: @""] error: nil];
        
                BOOL wasRequestSuccessful = NO;
                NSInteger responseStatusCode = 100;
                if (response && [response isKindOfClass: [NSHTTPURLResponse class]]) {
                    responseStatusCode = ((NSHTTPURLResponse *)response).statusCode;
                    wasRequestSuccessful = responseStatusCode >= 200 && responseStatusCode < 300;
                }
        
                [results addObject:response];
                if (carryOn) {
                    carryOn();
                }
            }];
        } else {
            [results addObject:[NSURLResponse init]];

            if (carryOn) {
                carryOn();
            }
        }
    } onDone:^{
        CODebugLog(@"Done uploading all images!");
        callback(results);
    }];
}

///From:  https://stackoverflow.com/questions/24250475/post-multipart-form-data-with-objective-c
-(void) uploadRequestMultipartDataWithFiles:(NSArray *)filePaths andParameters: (NSDictionary *)params callback: (void(^)(NSData *data, NSURLResponse *response)) callback {
    if (!callback) return;

    NSString *boundary = [ModulesAnalytics generateBoundaryString];

    NSString *apiEndpoint = @"binaryImages/upload";
    NSString *serverUrlString = [NSString stringWithFormat: @"https://crashops.com/api/%@", apiEndpoint];
    
    NSURL *url = [NSURL URLWithString: serverUrlString];
    
    // configure the request
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL: url];
    [request addValue: [crashOpsController appKey] forHTTPHeaderField:@"crashops-application-key"];
    [request setHTTPMethod:@"POST"];

    // set content type
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue: contentType forHTTPHeaderField: @"Content-Type"];

    NSData *httpBody = [self createBodyWithBoundary:boundary parameters: params paths: filePaths fieldName: @"file"];

    NSURLSessionTask *task = [[NSURLSession sharedSession] uploadTaskWithRequest: request fromData: httpBody completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            CODebugLogArgs(@"error = %@", error);
            callback(nil, response);
        } else {
            callback(data, response);
        }
    }];

    [task resume];
}

- (NSData *)createBodyWithBoundary:(NSString *)boundary
                        parameters:(NSDictionary *)parameters
                             paths:(NSArray *)paths
                         fieldName:(NSString *)fieldName {
    NSMutableData *httpBody = [NSMutableData data];

    // add params (all params are strings)

    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *parameterKey, NSString *parameterValue, BOOL *stop) {
        [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", parameterKey] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"%@\r\n", parameterValue] dataUsingEncoding:NSUTF8StringEncoding]];
    }];

    // add image data

    for (NSString *path in paths) {
        NSString *filename  = [path lastPathComponent];
        NSData   *data      = [NSData dataWithContentsOfFile:path];
        NSString *mimetype  = [self mimeTypeForPath:path];

        [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fieldName, filename] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", mimetype] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:data];
        [httpBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }

    [httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    return httpBody;
}

- (NSString *)mimeTypeForPath:(NSString *)path {
    // get a mime type for an extension using MobileCoreServices.framework

    CFStringRef extension = (__bridge CFStringRef)[path pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, extension, NULL);
    assert(UTI != NULL);

    NSString *mimetype = CFBridgingRelease(UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType));
    assert(mimetype != NULL);

    CFRelease(UTI);

    return mimetype;
}

+(NSString *) generateBoundaryString {
    return [NSString stringWithFormat:@"crashops.boundary-%@", [[NSUUID UUID] UUIDString]];
}

@end

@implementation NSFileManager (ModulesAnalytics_NSFileManager)

-(NSUInteger)totalSizeOfFolder:(NSString *)atPath {
    NSUInteger accumulatedBytesSize = 0;
    NSArray *subItems = [self contentsOfDirectoryAtPath: atPath error: nil];
    if (![subItems count]) return  accumulatedBytesSize;
    for (NSString *subItem in subItems) {
        NSString *absolutePath = [atPath stringByAppendingPathComponent: subItem];
        NSArray *itemsInsideIrectory = [self contentsOfDirectoryAtPath: absolutePath error: nil];
        if (itemsInsideIrectory) {
            accumulatedBytesSize += [self totalSizeOfFolder: absolutePath];
        } else {
            NSDictionary *attributes = [self attributesOfItemAtPath: absolutePath error: nil];
            if (attributes) {
                NSNumber *fileSizeInBytes = attributes[NSFileSize];
                if (fileSizeInBytes) {
                    accumulatedBytesSize += fileSizeInBytes.longValue;
                }
            }
        }
    }

    return accumulatedBytesSize;
}

@end

@implementation NSString (ModulesAnalytics)
- (NSString *)md5String {
    const char *cStr = [self UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (int)strlen(cStr), result ); // This is the md5 call
    return [NSString stringWithFormat:
        @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
        result[0], result[1], result[2], result[3],
        result[4], result[5], result[6], result[7],
        result[8], result[9], result[10], result[11],
        result[12], result[13], result[14], result[15]
        ];
}

@end

@implementation NSData(ModulesAnalytics)
- (NSString*) md5String {
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(self.bytes, (int)self.length, result ); // This is the md5 call
    return [NSString stringWithFormat:
        @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
        result[0], result[1], result[2], result[3],
        result[4], result[5], result[6], result[7],
        result[8], result[9], result[10], result[11],
        result[12], result[13], result[14], result[15]
        ];
}

- (NSString *)toString {
    return [self toString: NSUTF8StringEncoding];
}

- (NSString *)toString:(NSStringEncoding)encoding {
    NSString* dataAsString = [[NSString alloc] initWithData: self encoding: encoding];
    return dataAsString;
}

@end
