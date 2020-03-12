//
//  AppleCrashReportGenerator.m
//
//  Created by Karl Stenerud on 2012-02-24.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//


#import "AppleCrashReportGenerator.h"

#import <inttypes.h>
#import <mach/machine.h>
#import <KZCrash/KSCrash.h>

#import "KSJSONCodecObjC.h"

#import "CrashOpsController.h"

// https://github.com/kstenerud/KSCrash/issues/86
#define KZAppleRedactedText @"<redacted>"

#define KZCrashField_DumpEnd               "dump_end"
#define KZCrashField_DumpStart             "dump_start"

#define KZCrashExcType_CPPException        "cpp_exception"
#define KZCrashExcType_Deadlock            "deadlock"
#define KZCrashExcType_Mach                "mach"
#define KZCrashExcType_NSException         "nsexception"
#define KZCrashExcType_Signal              "signal"
#define KZCrashExcType_User                "user"

#define KZCrashField_Error                 "error"

#define KZCrashField_Backtrace             "backtrace"
#define KZCrashField_Code                  "code"
#define KZCrashField_CodeName              "code_name"
#define KZCrashField_CPPException          "cpp_exception"
#define KZCrashField_ExceptionName         "exception_name"
#define KZCrashField_Mach                  "mach"
#define KZCrashField_NSException           "nsexception"
#define KZCrashField_Reason                "reason"
#define KZCrashField_Signal                "signal"
#define KZCrashField_Subcode               "subcode"
#define KZCrashField_UserReported          "user_reported"

#define KZCrashField_LastDeallocedNSException "last_dealloced_nsexception"
#define KZCrashField_ProcessState             "process"

#define KZCrashField_Incomplete            "incomplete"
#define KZCrashField_RecrashReport         "recrash_report"

#define KZCrashField_CPUSubType            "cpu_subtype"
#define KZCrashField_CPUType               "cpu_type"
#define KZCrashField_ImageAddress          "image_addr"
#define KZCrashField_ImageVmAddress        "image_vmaddr"
#define KZCrashField_ImageSize             "image_size"
#define KZCrashField_ImageMajorVersion     "major_version"
#define KZCrashField_ImageMinorVersion     "minor_version"
#define KZCrashField_ImageRevisionVersion  "revision_version"

#define KZCrashField_AppStartTime          "app_start_time"
#define KZCrashField_AppUUID               "app_uuid"
#define KZCrashField_BootTime              "boot_time"
#define KZCrashField_BundleID              "CFBundleIdentifier"
#define KZCrashField_BundleName            "CFBundleName"
#define KZCrashField_BundleShortVersion    "CFBundleShortVersionString"
#define KZCrashField_BundleVersion         "CFBundleVersion"
#define KZCrashField_CPUArch               "cpu_arch"
#define KZCrashField_CPUType               "cpu_type"
#define KZCrashField_CPUSubType            "cpu_subtype"
#define KZCrashField_BinaryCPUType         "binary_cpu_type"
#define KZCrashField_BinaryCPUSubType      "binary_cpu_subtype"
#define KZCrashField_DeviceAppHash         "device_app_hash"
#define KZCrashField_Executable            "CFBundleExecutable"
#define KZCrashField_ExecutablePath        "CFBundleExecutablePath"
#define KZCrashField_Jailbroken            "jailbroken"
#define KZCrashField_KernelVersion         "kernel_version"
#define KZCrashField_Machine               "machine"
#define KZCrashField_Model                 "model"
#define KZCrashField_OSVersion             "os_version"
#define KZCrashField_ParentProcessID       "parent_process_id"
#define KZCrashField_ProcessID             "process_id"
#define KZCrashField_ProcessName           "process_name"
#define KZCrashField_Size                  "size"
#define KZCrashField_Storage               "storage"
#define KZCrashField_SystemName            "system_name"
#define KZCrashField_SystemVersion         "system_version"
#define KZCrashField_TimeZone              "time_zone"
#define KZCrashField_BuildType             "build_type"

#define KZCrashField_CrashedThread         "crashed_thread"

#define KZCrashField_AppStats              "application_stats"
#define KZCrashField_BinaryImages          "binary_images"
#define KZCrashField_System                "system"
#define KZCrashField_Memory                "memory"
#define KZCrashField_Threads               "threads"
#define KZCrashField_User                  "user"
#define KZCrashField_ConsoleLog            "console_log"

#define KZCrashField_Backtrace             "backtrace"
#define KZCrashField_Basic                 "basic"
#define KZCrashField_Crashed               "crashed"
#define KZCrashField_CurrentThread         "current_thread"
#define KZCrashField_DispatchQueue         "dispatch_queue"
#define KZCrashField_NotableAddresses      "notable_addresses"
#define KZCrashField_Registers             "registers"
#define KZCrashField_Skipped               "skipped"
#define KZCrashField_Stack                 "stack"

#define KZCrashField_InstructionAddr       "instruction_addr"
#define KZCrashField_LineOfCode            "line_of_code"
#define KZCrashField_ObjectAddr            "object_addr"
#define KZCrashField_ObjectName            "object_name"
#define KZCrashField_SymbolAddr            "symbol_addr"
#define KZCrashField_SymbolName            "symbol_name"

#define KZCrashField_Address               "address"
#define KZCrashField_Contents              "contents"
#define KZCrashField_Exception             "exception"
#define KZCrashField_FirstObject           "first_object"
#define KZCrashField_Index                 "index"
#define KZCrashField_Ivars                 "ivars"
#define KZCrashField_Language              "language"
#define KZCrashField_Name                  "name"
#define KZCrashField_UserInfo              "userInfo"
#define KZCrashField_ReferencedObject      "referenced_object"
#define KZCrashField_Type                  "type"
#define KZCrashField_UUID                  "uuid"
#define KZCrashField_Value                 "value"

#define KZCrashField_Crash                 "crash"
#define KZCrashField_Debug                 "debug"
#define KZCrashField_Diagnosis             "diagnosis"
#define KZCrashField_ID                    "id"
#define KZCrashField_ProcessName           "process_name"
#define KZCrashField_Report                "report"
#define KZCrashField_Timestamp             "timestamp"
#define KZCrashField_Version               "version"

#define KZAPLFMT_CPU_SUBTYPE_ARM64E              ((cpu_subtype_t) 2)

#if defined(__LP64__)
    #define KZ_FMT_LONG_DIGITS "16"
    #define KZ_FMT_RJ_SPACES "18"
#else
    #define KZ_FMT_LONG_DIGITS "8"
    #define KZ_FMT_RJ_SPACES "10"
#endif

#define KZ_FMT_PTR_SHORT        @"0x%" PRIxPTR
#define KZ_FMT_PTR_LONG         @"0x%0" KZ_FMT_LONG_DIGITS PRIxPTR
#define KZ_FMT_PTR_RJ           @"%#" KZ_FMT_RJ_SPACES PRIxPTR
#define KZ_FMT_OFFSET           @"%" PRIuPTR
#define KZ_FMT_TRACE_PREAMBLE       @"%-4d%-31s " KZ_FMT_PTR_LONG
#define KZ_FMT_TRACE_UNSYMBOLICATED KZ_FMT_PTR_SHORT @" + " KZ_FMT_OFFSET
#define KZ_FMT_TRACE_SYMBOLICATED   @"%@ + " KZ_FMT_OFFSET

#define kExpectedMajorVersion 3

@interface AppleCrashReportGenerator ()

/** Determine the major CPU type.
 *
 * @param CPUArch The CPU architecture name.
 *
 * @return the major CPU type.
 */
+ (NSString*) CPUType:(NSString*) CPUArch;

/** Determine the CPU architecture based on major/minor CPU architecture codes.
 *
 * @param majorCode The major part of the code.
 *
 * @param minorCode The minor part of the code.
 *
 * @return The CPU architecture.
 */
+ (NSString*) CPUArchForMajor:(cpu_type_t) majorCode minor:(cpu_subtype_t) minorCode;

/** Take a UUID string and strip out all the dashes.
 *
 * @param uuid the UUID.
 *
 * @return the UUID in compact form.
 */
+ (NSString*) toCompactUUID:(NSString*) uuid;

@end

@implementation AppleCrashReportGenerator

/** Date formatter for Apple date format in crash reports. */
static NSDateFormatter* g_dateFormatter;

static KZAppleReportStyle AppleCrashReportGeneratorReportStyle;

/** Date formatter for RFC3339 date format. */
static NSDateFormatter* g_rfc3339DateFormatter;

/** Printing order for registers. */
static NSDictionary* g_registerOrders;

+ (void)load {
    NSLog(@"initialized");
}

+ (void) initialize
{
    g_dateFormatter = [[NSDateFormatter alloc] init];
    [g_dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [g_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS ZZZ"];

    g_rfc3339DateFormatter = [[NSDateFormatter alloc] init];
    [g_rfc3339DateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [g_rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSSSSS'Z'"];
    [g_rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    NSArray* armOrder = [NSArray arrayWithObjects:
                         @"r0", @"r1", @"r2", @"r3", @"r4", @"r5", @"r6", @"r7",
                         @"r8", @"r9", @"r10", @"r11", @"ip",
                         @"sp", @"lr", @"pc", @"cpsr",
                         nil];

    NSArray* x86Order = [NSArray arrayWithObjects:
                         @"eax", @"ebx", @"ecx", @"edx",
                         @"edi", @"esi",
                         @"ebp", @"esp", @"ss",
                         @"eflags", @"eip",
                         @"cs", @"ds", @"es", @"fs", @"gs",
                         nil];

    NSArray* x86_64Order = [NSArray arrayWithObjects:
                            @"rax", @"rbx", @"rcx", @"rdx",
                            @"rdi", @"rsi",
                            @"rbp", @"rsp",
                            @"r8", @"r9", @"r10", @"r11", @"r12", @"r13",
                            @"r14", @"r15",
                            @"rip", @"rflags",
                            @"cs", @"fs", @"gs",
                            nil];

    g_registerOrders = [[NSDictionary alloc] initWithObjectsAndKeys:
                        armOrder, @"arm",
                        armOrder, @"armv6",
                        armOrder, @"armv7",
                        armOrder, @"armv7f",
                        armOrder, @"armv7k",
                        armOrder, @"armv7s",
                        x86Order, @"x86",
                        x86Order, @"i386",
                        x86Order, @"i486",
                        x86Order, @"i686",
                        x86_64Order, @"x86_64",
                        nil];
}

//+ (AppleCrashReportGenerator*) filterWithReportStyle:(KZAppleReportStyle) reportStyle {
//    return [[self alloc] initWithReportStyle:reportStyle];
//}

+ (int) majorVersion:(NSDictionary*) report
{
    NSDictionary* info = [AppleCrashReportGenerator infoReport:report];
    NSString* version = [info objectForKey: @KZCrashField_Version];
    if ([version isKindOfClass:[NSDictionary class]])
    {
        NSDictionary *oldVersion = (NSDictionary *)version;
        version = oldVersion[@"major"];
    }

    if([version respondsToSelector:@selector(intValue)])
    {
        return version.intValue;
    }
    return 0;
}


+ (NSString*) CPUType:(NSString*) CPUArch
{
    if([CPUArch rangeOfString:@"arm64"].location == 0)
    {
        return @"ARM-64";
    }
    if([CPUArch rangeOfString:@"arm"].location == 0)
    {
        return @"ARM";
    }
    if([CPUArch isEqualToString:@"x86"])
    {
        return @"X86";
    }
    if([CPUArch isEqualToString:@"x86_64"])
    {
        return @"X86_64";
    }
    return @"Unknown";
}

+ (NSString*) CPUArchForMajor:(cpu_type_t) majorCode minor:(cpu_subtype_t) minorCode
{
    switch(majorCode)
    {
        case CPU_TYPE_ARM:
        {
            switch (minorCode)
            {
                case CPU_SUBTYPE_ARM_V6:
                    return @"armv6";
                case CPU_SUBTYPE_ARM_V7:
                    return @"armv7";
                case CPU_SUBTYPE_ARM_V7F:
                    return @"armv7f";
                case CPU_SUBTYPE_ARM_V7K:
                    return @"armv7k";
#ifdef CPU_SUBTYPE_ARM_V7S
                case CPU_SUBTYPE_ARM_V7S:
                    return @"armv7s";
#endif
            }
            return @"arm";
        }
#ifdef CPU_TYPE_ARM64
        case CPU_TYPE_ARM64:
        {
            switch (minorCode)
            {
#ifdef KZAPLFMT_CPU_SUBTYPE_ARM64E
                case CPU_SUBTYPE_ARM64E:
                    return @"arm64e";
#endif
            }
            return @"arm64";
        }
#endif
        case CPU_TYPE_X86:
            return @"i386";
        case CPU_TYPE_X86_64:
            return @"x86_64";
    }
    return [NSString stringWithFormat:@"unknown(%d,%d)", majorCode, minorCode];
}

/** Convert a backtrace to a string.
 *
 * @param backtrace The backtrace to convert.
 *
 * @param reportStyle The style of report being generated.
 *
 * @param mainExecutableName Name of the app executable.
 *
 * @return The converted string.
 */
+ (NSString*) backtraceString:(NSDictionary*) backtrace
                  reportStyle:(KZAppleReportStyle) reportStyle
           mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    int traceNum = 0;
    for(NSDictionary* trace in [backtrace objectForKey:@KZCrashField_Contents])
    {
        uintptr_t pc = (uintptr_t)[[trace objectForKey:@KZCrashField_InstructionAddr] longLongValue];
        uintptr_t objAddr = (uintptr_t)[[trace objectForKey:@KZCrashField_ObjectAddr] longLongValue];
        NSString* objName = [[trace objectForKey:@KZCrashField_ObjectName] lastPathComponent];
        uintptr_t symAddr = (uintptr_t)[[trace objectForKey:@KZCrashField_SymbolAddr] longLongValue];
        NSString* symName = [trace objectForKey:@KZCrashField_SymbolName];
        bool isMainExecutable = mainExecutableName && [objName isEqualToString:mainExecutableName];
        KZAppleReportStyle thisLineStyle = reportStyle;
        if(thisLineStyle == KZAppleReportStylePartiallySymbolicated)
        {
            thisLineStyle = isMainExecutable ? KZAppleReportStyleUnsymbolicated : KZAppleReportStyleSymbolicated;
        }

        NSString* preamble = [NSString stringWithFormat:KZ_FMT_TRACE_PREAMBLE, traceNum, [objName UTF8String], pc];
        NSString* unsymbolicated = [NSString stringWithFormat:KZ_FMT_TRACE_UNSYMBOLICATED, objAddr, pc - objAddr];
        NSString* symbolicated = @"(null)";
        if(thisLineStyle != KZAppleReportStyleUnsymbolicated && [symName isKindOfClass:[NSString class]])
        {
            symbolicated = [NSString stringWithFormat:KZ_FMT_TRACE_SYMBOLICATED, symName, pc - symAddr];
        }
        else
        {
            thisLineStyle = KZAppleReportStyleUnsymbolicated;
        }


        // Apple has started replacing symbols for any function/method
        // beginning with an underscore with "<redacted>" in iOS 6.
        // No, I can't think of any valid reason to do this, either.
        if(thisLineStyle == KZAppleReportStyleSymbolicated &&
           [symName isEqualToString: KZAppleRedactedText]) {
            thisLineStyle = KZAppleReportStyleUnsymbolicated;
        }

        switch (thisLineStyle)
        {
            case KZAppleReportStyleSymbolicatedSideBySide:
                [str appendFormat:@"%@ %@ (%@)\n", preamble, unsymbolicated, symbolicated];
                break;
            case KZAppleReportStyleSymbolicated:
                [str appendFormat:@"%@ %@\n", preamble, symbolicated];
                break;
            case KZAppleReportStylePartiallySymbolicated: // Should not happen
            case KZAppleReportStyleUnsymbolicated:
                [str appendFormat:@"%@ %@\n", preamble, unsymbolicated];
                break;
        }
        traceNum++;
    }

    return str;
}

+ (NSString*) toCompactUUID:(NSString*) uuid
{
    return [[uuid lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

+ (NSString*) stringFromDate:(NSDate*) date
{
    if(![date isKindOfClass:[NSDate class]])
    {
        return nil;
    }

    return [g_dateFormatter stringFromDate:date];
}

+ (NSDictionary*) recrashReport:(NSDictionary*) report
{
    return [report objectForKey:@KZCrashField_RecrashReport];
}

+ (NSDictionary*) systemReport:(NSDictionary*) report
{
    return [report objectForKey:@KZCrashField_System];
}

+ (NSDictionary*) infoReport:(NSDictionary*) report
{
    return [report objectForKey:@KZCrashField_Report];
}

+ (NSDictionary*) processReport:(NSDictionary*) report
{
    return [report objectForKey:@KZCrashField_ProcessState];
}

+ (NSDictionary*) crashReport:(NSDictionary*) report
{
    return [report objectForKey:@KZCrashField_Crash];
}

+ (NSArray*) binaryImagesReport:(NSDictionary*) report
{
    return [report objectForKey:@KZCrashField_BinaryImages];
}

+ (NSDictionary*) crashedThread:(NSDictionary*) report
{
    NSDictionary* crash = [AppleCrashReportGenerator crashReport:report];
    NSArray* threads = [crash objectForKey:@KZCrashField_Threads];
    for(NSDictionary* thread in threads)
    {
        BOOL crashed = [[thread objectForKey:@KZCrashField_Crashed] boolValue];
        if(crashed)
        {
            return thread;
        }
    }

    return [crash objectForKey:@KZCrashField_CrashedThread];
}

+ (NSString*) mainExecutableNameForReport:(NSDictionary*) report
{
    NSDictionary* info = [AppleCrashReportGenerator infoReport:report];
    return [info objectForKey:@KZCrashField_ProcessName];
}

+ (NSString*) cpuArchForReport:(NSDictionary*) report
{
    NSDictionary* system = [AppleCrashReportGenerator systemReport:report];
    cpu_type_t cpuType = [[system objectForKey:@KZCrashField_BinaryCPUType] intValue];
    cpu_subtype_t cpuSubType = [[system objectForKey:@KZCrashField_BinaryCPUSubType] intValue];
    return [AppleCrashReportGenerator CPUArchForMajor:cpuType minor:cpuSubType];
}

+ (NSDate*) crashDate:(NSDictionary*) report {
    NSDictionary* reportInfo = [AppleCrashReportGenerator infoReport:report];
    NSNumber *timestampMicroseconds = [reportInfo objectForKey:@KZCrashField_Timestamp];
    NSDate* crashTime = [NSDate dateWithTimeIntervalSince1970: timestampMicroseconds.longValue / 1000000];

    return crashTime;
}

+ (NSString*) reportId:(NSDictionary*) report {
    NSDictionary* reportInfo = [AppleCrashReportGenerator infoReport:report];
    NSString *reportID = [reportInfo objectForKey:@KZCrashField_ID];

    return reportID;
}

+ (NSString*) headerStringForReport:(NSDictionary*) report {
    NSDictionary* system = [AppleCrashReportGenerator systemReport:report];
    NSDictionary* reportInfo = [AppleCrashReportGenerator infoReport:report];
    NSString *reportID = [reportInfo objectForKey:@KZCrashField_ID];
    NSDate* crashTime = [AppleCrashReportGenerator crashDate: report];

    return [AppleCrashReportGenerator headerStringForSystemInfo:system reportID:reportID crashTime:crashTime];
}

+ (NSString*)headerStringForSystemInfo:(NSDictionary*)system reportID:(NSString*)reportID crashTime:(NSDate*)crashTime
{
    NSMutableString* str = [NSMutableString string];
    NSString* executablePath = [system objectForKey:@KZCrashField_ExecutablePath];
    NSString* cpuArch = [system objectForKey:@KZCrashField_CPUArch];
    NSString* cpuArchType = [AppleCrashReportGenerator CPUType:cpuArch];

    [str appendFormat:@"Incident Identifier: %@\n", reportID];
    [str appendFormat:@"CrashReporter Key:   %@\n", [system objectForKey:@KZCrashField_DeviceAppHash]];
    [str appendFormat:@"Hardware Model:      %@\n", [system objectForKey:@KZCrashField_Machine]];
    [str appendFormat:@"Process:         %@ [%@]\n",
     [system objectForKey:@KZCrashField_ProcessName],
     [system objectForKey:@KZCrashField_ProcessID]];
    [str appendFormat:@"Path:            %@\n", executablePath];
    [str appendFormat:@"Identifier:      %@\n", [system objectForKey:@KZCrashField_BundleID]];
    [str appendFormat:@"Version:         %@ (%@)\n",
     [system objectForKey:@KZCrashField_BundleVersion],
     [system objectForKey:@KZCrashField_BundleShortVersion]];
    [str appendFormat:@"Code Type:       %@\n", cpuArchType];
    [str appendFormat:@"Parent Process:  ? [%@]\n",
     [system objectForKey:@KZCrashField_ParentProcessID]];
    [str appendFormat:@"\n"];
    [str appendFormat:@"Date/Time:       %@\n", [AppleCrashReportGenerator stringFromDate:crashTime]];
    [str appendFormat:@"OS Version:      %@ %@ (%@)\n",
     [system objectForKey:@KZCrashField_SystemName],
     [system objectForKey:@KZCrashField_SystemVersion],
     [system objectForKey:@KZCrashField_OSVersion]];
    [str appendFormat:@"Report Version:  104\n"];

    return str;
}

+ (NSString*) binaryImagesStringForReport:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];

    NSArray* binaryImages = [AppleCrashReportGenerator binaryImagesReport:report];
    NSDictionary* system = [AppleCrashReportGenerator systemReport:report];
    NSString* executablePath = [system objectForKey:@KZCrashField_ExecutablePath];

    [str appendString:@"\nBinary Images:\n"];
    if(binaryImages)
    {
        NSMutableArray* images = [NSMutableArray arrayWithArray:binaryImages];
        [images sortUsingComparator:^NSComparisonResult(id obj1, id obj2)
         {
             NSNumber* num1 = [(NSDictionary*)obj1 objectForKey:@KZCrashField_ImageAddress];
             NSNumber* num2 = [(NSDictionary*)obj2 objectForKey:@KZCrashField_ImageAddress];
             if(num1 == nil || num2 == nil)
             {
                 return NSOrderedSame;
             }
             return [num1 compare:num2];
         }];
        for(NSDictionary* image in images)
        {
            cpu_type_t cpuType = [[image objectForKey:@KZCrashField_CPUType] intValue];
            cpu_subtype_t cpuSubtype = [[image objectForKey:@KZCrashField_CPUSubType] intValue];
            uintptr_t imageAddr = (uintptr_t)[[image objectForKey:@KZCrashField_ImageAddress] longLongValue];
            uintptr_t imageSize = (uintptr_t)[[image objectForKey:@KZCrashField_ImageSize] longLongValue];
            NSString* path = [image objectForKey:@KZCrashField_Name];
            NSString* name = [path lastPathComponent];
            NSString* uuid = [AppleCrashReportGenerator toCompactUUID:[image objectForKey:@KZCrashField_UUID]];
            NSString* isBaseImage = (path && [executablePath isEqualToString:path]) ? @"+" : @" ";

            [str appendFormat:KZ_FMT_PTR_RJ @" - " KZ_FMT_PTR_RJ @" %@%@ %@  <%@> %@\n",
             imageAddr,
             imageAddr + imageSize - 1,
             isBaseImage,
             name,
             [AppleCrashReportGenerator CPUArchForMajor:cpuType minor:cpuSubtype],
             uuid,
             path];
        }
    }

    return str;
}

+ (NSString*) crashedThreadCPUStateStringForReport:(NSDictionary*) report
                                           cpuArch:(NSString*) cpuArch
{
    NSDictionary* thread = [AppleCrashReportGenerator crashedThread:report];
    if(thread == nil)
    {
        return @"";
    }
    int threadIndex = [[thread objectForKey:@KZCrashField_Index] intValue];

    NSString* cpuArchType = [AppleCrashReportGenerator CPUType:cpuArch];

    NSMutableString* str = [NSMutableString string];

    [str appendFormat:@"\nThread %d crashed with %@ Thread State:\n",
     threadIndex, cpuArchType];

    NSDictionary* registers = [(NSDictionary*)[thread objectForKey:@KZCrashField_Registers] objectForKey:@KZCrashField_Basic];
    NSArray* regOrder = [g_registerOrders objectForKey:cpuArch];
    if(regOrder == nil)
    {
        regOrder = [[registers allKeys] sortedArrayUsingSelector:@selector(compare:)];
    }
    NSUInteger numRegisters = [regOrder count];
    NSUInteger i = 0;
    while(i < numRegisters)
    {
        NSUInteger nextBreak = i + 4;
        if(nextBreak > numRegisters)
        {
            nextBreak = numRegisters;
        }
        for(;i < nextBreak; i++)
        {
            NSString* regName = [regOrder objectAtIndex:i];
            uintptr_t addr = (uintptr_t)[[registers objectForKey:regName] longLongValue];
            [str appendFormat:@"%6s: " KZ_FMT_PTR_LONG @" ",
             [regName cStringUsingEncoding:NSUTF8StringEncoding],
             addr];
        }
        [str appendString:@"\n"];
    }

    return str;
}

+ (NSString*) extraInfoStringForReport:(NSDictionary*) report
                    mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    [str appendString:@"\nExtra Information:\n"];

    NSDictionary* system = [AppleCrashReportGenerator systemReport:report];
    NSDictionary* crash = [AppleCrashReportGenerator crashReport:report];
    NSDictionary* error = [crash objectForKey:@KZCrashField_Error];
    NSDictionary* nsexception = [error objectForKey:@KZCrashField_NSException];
    NSDictionary* referencedObject = [nsexception objectForKey:@KZCrashField_ReferencedObject];
    if(referencedObject != nil)
    {
        [str appendFormat:@"Object referenced by NSException:\n%@\n", [AppleCrashReportGenerator JSONForObject:referencedObject]];
    }

    NSDictionary* crashedThread = [AppleCrashReportGenerator crashedThread:report];
    if(crashedThread != nil)
    {
        NSDictionary* stack = [crashedThread objectForKey:@KZCrashField_Stack];
        if(stack != nil)
        {
            [str appendFormat:@"\nStack Dump (" KZ_FMT_PTR_LONG "-" KZ_FMT_PTR_LONG "):\n\n%@\n",
             (uintptr_t)[[stack objectForKey:@KZCrashField_DumpStart] unsignedLongLongValue],
             (uintptr_t)[[stack objectForKey:@KZCrashField_DumpEnd] unsignedLongLongValue],
             [stack objectForKey:@KZCrashField_Contents]];
        }

        NSDictionary* notableAddresses = [crashedThread objectForKey:@KZCrashField_NotableAddresses];
        if(notableAddresses != nil)
        {
            [str appendFormat:@"\nNotable Addresses:\n%@\n", [AppleCrashReportGenerator JSONForObject:notableAddresses]];
        }
    }

    NSDictionary* lastException = [[AppleCrashReportGenerator processReport:report] objectForKey:@KZCrashField_LastDeallocedNSException];
    if(lastException != nil)
    {
        uintptr_t address = (uintptr_t)[[lastException objectForKey:@KZCrashField_Address] unsignedLongLongValue];
        NSString* name = [lastException objectForKey:@KZCrashField_Name];
        NSString* reason = [lastException objectForKey:@KZCrashField_Reason];
        referencedObject = [lastException objectForKey:@KZCrashField_ReferencedObject];
        [str appendFormat:@"\nLast deallocated NSException (" KZ_FMT_PTR_LONG "): %@: %@\n",
         address, name, reason];
        if(referencedObject != nil)
        {
            [str appendFormat:@"Referenced object:\n%@\n", [AppleCrashReportGenerator JSONForObject:referencedObject]];
        }
        [str appendString:
         [AppleCrashReportGenerator backtraceString:[lastException objectForKey:@KZCrashField_Backtrace]
                   reportStyle: AppleCrashReportGeneratorReportStyle
            mainExecutableName:mainExecutableName]];
    }

    NSDictionary* appStats = [system objectForKey:@KZCrashField_AppStats];
    if(appStats != nil)
    {
        [str appendFormat:@"\nApplication Stats:\n%@\n", [AppleCrashReportGenerator JSONForObject:appStats]];
    }

    NSDictionary* crashReport = [report objectForKey:@KZCrashField_Crash];
    NSString* diagnosis = [crashReport objectForKey:@KZCrashField_Diagnosis];
    if(diagnosis != nil)
    {
        [str appendFormat:@"\nCrashDoctor Diagnosis: %@\n", diagnosis];
    }

    return str;
}

+ (NSString*) metadataForReport:(NSDictionary*) report {
    NSDictionary* userInfo = report[@KZCrashExcType_User];
    if (!userInfo) {
        userInfo = @{};
    }

    return [AppleCrashReportGenerator JSONForObject: userInfo];
}

+ (NSString*) JSONForObject:(id) object
{
    NSError* error = nil;
    NSData* encoded = [KSJSONCodec encode:object
                                  options:KSJSONEncodeOptionPretty |
                       KSJSONEncodeOptionSorted
                                    error:&error];
    if(error != nil)
    {
        return [NSString stringWithFormat:@"Error encoding JSON: %@", error];
    }
    else
    {
        return [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    }
}

+ (BOOL) isZombieNSException:(NSDictionary*) report
{
    NSDictionary* crash = [AppleCrashReportGenerator crashReport:report];
    NSDictionary* error = [crash objectForKey:@KZCrashField_Error];
    NSDictionary* mach = [error objectForKey:@KZCrashField_Mach];
    NSString* machExcName = [mach objectForKey:@KZCrashField_ExceptionName];
    NSString* machCodeName = [mach objectForKey:@KZCrashField_CodeName];
    if(![machExcName isEqualToString:@"EXC_BAD_ACCESS"] ||
       ![machCodeName isEqualToString:@"KERN_INVALID_ADDRESS"])
    {
        return NO;
    }

    NSDictionary* lastException = [[AppleCrashReportGenerator processReport:report] objectForKey:@KZCrashField_LastDeallocedNSException];
    if(lastException == nil)
    {
        return NO;
    }
    NSNumber* lastExceptionAddress = [lastException objectForKey:@KZCrashField_Address];

    NSDictionary* thread = [AppleCrashReportGenerator crashedThread:report];
    NSDictionary* registers = [(NSDictionary*)[thread objectForKey:@KZCrashField_Registers] objectForKey:@KZCrashField_Basic];

    for(NSString* reg in registers)
    {
        NSNumber* address = [registers objectForKey:reg];
        if(lastExceptionAddress && [address isEqualToNumber:lastExceptionAddress])
        {
            return YES;
        }
    }

    return NO;
}

+ (NSString*) errorInfoStringForReport:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];

    NSDictionary* thread = [AppleCrashReportGenerator crashedThread:report];
    NSDictionary* crash = [AppleCrashReportGenerator crashReport:report];
    NSDictionary* error = [crash objectForKey:@KZCrashField_Error];
    NSDictionary* type = [error objectForKey:@KZCrashField_Type];

    NSDictionary* nsexception = [error objectForKey:@KZCrashField_NSException];
    NSDictionary* cppexception = [error objectForKey:@KZCrashField_CPPException];
    NSDictionary* lastException = [[AppleCrashReportGenerator processReport:report] objectForKey:@KZCrashField_LastDeallocedNSException];
    NSDictionary* userException = [error objectForKey:@KZCrashField_UserReported];
    NSDictionary* mach = [error objectForKey:@KZCrashField_Mach];
    NSDictionary* signal = [error objectForKey:@KZCrashField_Signal];

    NSString* machExcName = [mach objectForKey:@KZCrashField_ExceptionName];
    if(machExcName == nil)
    {
        machExcName = @"0";
    }
    NSString* signalName = [signal objectForKey:@KZCrashField_Name];
    if(signalName == nil)
    {
        signalName = [[signal objectForKey:@KZCrashField_Signal] stringValue];
    }
    NSString* machCodeName = [mach objectForKey:@KZCrashField_CodeName];
    if(machCodeName == nil)
    {
        machCodeName = @"0x00000000";
    }

    [str appendFormat:@"\n"];
    [str appendFormat:@"Exception Type:  %@ (%@)\n", machExcName, signalName];
    [str appendFormat:@"Exception Codes: %@ at " KZ_FMT_PTR_LONG @"\n",
     machCodeName,
     (uintptr_t)[[error objectForKey:@KZCrashField_Address] longLongValue]];

    [str appendFormat:@"Crashed Thread:  %d\n",
     [[thread objectForKey:@KZCrashField_Index] intValue]];

    if(nsexception != nil)
    {
        [str appendString:[AppleCrashReportGenerator stringWithUncaughtExceptionName:[nsexception objectForKey:@KZCrashField_Name]
                                                         reason:[error objectForKey:@KZCrashField_Reason]]];
    }
    else if([AppleCrashReportGenerator isZombieNSException:report])
    {
        [str appendString:[AppleCrashReportGenerator stringWithUncaughtExceptionName:[lastException objectForKey:@KZCrashField_Name]
                                                         reason:[lastException objectForKey:@KZCrashField_Reason]]];
        [str appendString:@"NOTE: This exception has been deallocated! Stack trace is crash from attempting to access this zombie exception.\n"];
    }
    else if(userException != nil)
    {
        [str appendString:[AppleCrashReportGenerator stringWithUncaughtExceptionName:[userException objectForKey:@KZCrashField_Name]
                                                         reason:[error objectForKey:@KZCrashField_Reason]]];
        NSString* trace = [AppleCrashReportGenerator userExceptionTrace:userException];
        if(trace.length > 0)
        {
            [str appendFormat:@"\n%@\n", trace];
        }
    }
    else if([type isEqual:@KZCrashExcType_CPPException])
    {
        [str appendString:[AppleCrashReportGenerator stringWithUncaughtExceptionName:[cppexception objectForKey:@KZCrashField_Name]
                                                         reason:[error objectForKey:@KZCrashField_Reason]]];
    }

    NSString* crashType = [error objectForKey:@KZCrashField_Type];
    if(crashType && [@KZCrashExcType_Deadlock isEqualToString:crashType])
    {
        [str appendFormat:@"\nApplication main thread deadlocked\n"];
    }

    return str;
}

+ (NSString*) stringWithUncaughtExceptionName:(NSString*) name reason:(NSString*) reason
{
    return [NSString stringWithFormat:
            @"\nApplication Specific Information:\n"
            @"*** Terminating app due to uncaught exception '%@', reason: '%@'\n",
            name, reason];
}

+ (NSString*) userExceptionTrace:(NSDictionary*)userException
{
    NSMutableString* str = [NSMutableString string];
    NSString* line = [userException objectForKey:@KZCrashField_LineOfCode];
    if(line != nil)
    {
        [str appendFormat:@"Line: %@\n", line];
    }
    NSArray* backtrace = [userException objectForKey:@KZCrashField_Backtrace];
    for(NSString* entry in backtrace)
    {
        [str appendFormat:@"%@\n", entry];
    }

    if(str.length > 0)
    {
        return [@"Custom Backtrace:\n" stringByAppendingString:str];
    }

    return @"";
}

+ (NSString*) threadStringForThread:(NSDictionary*) thread
                 mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    [str appendFormat:@"\n"];
    BOOL crashed = [[thread objectForKey:@KZCrashField_Crashed] boolValue];
    int index = [[thread objectForKey:@KZCrashField_Index] intValue];
    NSString* name = [thread objectForKey:@KZCrashField_Name];
    NSString* queueName = [thread objectForKey:@KZCrashField_DispatchQueue];

    if(name != nil)
    {
        [str appendFormat:@"Thread %d name:  %@\n", index, name];
    }
    else if(queueName != nil)
    {
        [str appendFormat:@"Thread %d name:  Dispatch queue: %@\n", index, queueName];
    }

    if(crashed)
    {
        [str appendFormat:@"Thread %d Crashed:\n", index];
    }
    else
    {
        [str appendFormat:@"Thread %d:\n", index];
    }

    [str appendString:
     [AppleCrashReportGenerator backtraceString:[thread objectForKey:@KZCrashField_Backtrace]
               reportStyle: AppleCrashReportGeneratorReportStyle
        mainExecutableName:mainExecutableName]];

    return str;
}

+ (NSString*) threadListStringForReport:(NSDictionary*) report
                     mainExecutableName:(NSString*) mainExecutableName
{
    NSMutableString* str = [NSMutableString string];

    NSDictionary* crash = [AppleCrashReportGenerator crashReport:report];
    NSArray* threads = [crash objectForKey:@KZCrashField_Threads];

    for(NSDictionary* thread in threads)
    {
        [str appendString:[AppleCrashReportGenerator threadStringForThread:thread mainExecutableName:mainExecutableName]];
    }

    return str;
}

+ (NSString*) crashReportString:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];
    NSString* executableName = [AppleCrashReportGenerator mainExecutableNameForReport:report];

    [str appendString:[AppleCrashReportGenerator headerStringForReport:report]];
    [str appendString:[AppleCrashReportGenerator errorInfoStringForReport:report]];
    [str appendString:[AppleCrashReportGenerator threadListStringForReport:report mainExecutableName:executableName]];
    [str appendString:[AppleCrashReportGenerator crashedThreadCPUStateStringForReport:report cpuArch:[AppleCrashReportGenerator cpuArchForReport:report]]];
    [str appendString:[AppleCrashReportGenerator binaryImagesStringForReport:report]];
    [str appendString:[AppleCrashReportGenerator extraInfoStringForReport:report mainExecutableName:executableName]];
    [str appendString:[AppleCrashReportGenerator metadataForReport:report]];

    return str;
}

+ (NSString*) recrashReportString:(NSDictionary*) report
{
    NSMutableString* str = [NSMutableString string];
    
    NSDictionary* recrashReport = [AppleCrashReportGenerator recrashReport:report];
    NSDictionary* system = [AppleCrashReportGenerator systemReport:recrashReport];
    NSString* executablePath = [system objectForKey:@KZCrashField_ExecutablePath];
    NSString* executableName = [executablePath lastPathComponent];
    NSDictionary* crash = [AppleCrashReportGenerator crashReport:report];
    NSDictionary* thread = [crash objectForKey:@KZCrashField_CrashedThread];

    [str appendString:@"\nHandler crashed while reporting:\n"];
    [str appendString:[AppleCrashReportGenerator errorInfoStringForReport:report]];
    [str appendString:[AppleCrashReportGenerator threadStringForThread:thread mainExecutableName:executableName]];
    [str appendString:[AppleCrashReportGenerator crashedThreadCPUStateStringForReport:report
                                                         cpuArch:[AppleCrashReportGenerator cpuArchForReport:recrashReport]]];
    NSString* diagnosis = [crash objectForKey:@KZCrashField_Diagnosis];
    if(diagnosis != nil)
    {
        [str appendFormat:@"\nRecrash Diagnosis: %@", diagnosis];
    }

    return str;
}

// was an instance method
+ (NSString*) toAppleFormat:(NSDictionary*) report withStyle:(KZAppleReportStyle) style {
    AppleCrashReportGeneratorReportStyle = style;

    NSMutableString* str = [NSMutableString string];
    
    NSDictionary* recrashReport = report[@KZCrashField_RecrashReport];
    if (recrashReport) {
        [str appendString:[AppleCrashReportGenerator crashReportString:recrashReport]];
        [str appendString:[AppleCrashReportGenerator recrashReportString:report]];
    } else {
        [str appendString:[AppleCrashReportGenerator crashReportString:report]];
    }

    return str;
}

+ (NSString *) generateIpsFile:(NSURL *)originalJsonReportPath {
    NSString *fileName = [[[originalJsonReportPath lastPathComponent] componentsSeparatedByString:@"."] firstObject];
    if (!fileName || ![fileName length]) {
        return nil;
    }

    NSString *filePath = [[CrashOpsController ipsFilesLibraryPath] stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.ips", fileName]];

    if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
        return filePath;
    }

    NSString *reportJson = [[NSString alloc] initWithData: [NSData dataWithContentsOfURL: originalJsonReportPath] encoding: NSUTF8StringEncoding];
    NSDictionary *jsonDictionary = [CrashOpsController toJsonDictionary: reportJson];

    NSString *ipsFileContent = [AppleCrashReportGenerator toAppleFormat:jsonDictionary withStyle: KZAppleReportStyleSymbolicatedSideBySide];

    NSError *error;
    BOOL didSave = [[ipsFileContent dataUsingEncoding: NSUTF8StringEncoding] writeToFile: filePath options: NSDataWritingAtomic error: &error];
    if (!didSave || error) {
        return nil;
    } else {
        return filePath;
    }
}

@end
