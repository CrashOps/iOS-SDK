# CrashOps iOS SDK
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) [![](https://img.shields.io/cocoapods/p/CrashOps.svg?style=flat)](https://cocoapods.org/pods/CrashOps)

This library will help you monitor your iOS app's crashes.


## Installation
### 🔌 & ▶️
### Install via CocoaPods
[![](https://img.shields.io/cocoapods/v/CrashOps.svg?style=flat)](https://cocoapods.org/pods/CrashOps)

You want to add `pod 'CrashOps'` similar to the following to your Podfile:
```
target 'MyApp' do
  pod 'CrashOps', '0.2.17'
end
```
Then run a `pod install` in your terminal, or from CocoaPods app.

## Usage

### Set Application Key

To recognize your app in CrashOps servers you need an application key, you can set it via code (programmatically) either via config file.

#### Set an application key via code
```Swift
import CrashOps

// Swift
CrashOps.shared().appKey = "app's-key-received-from-CrashOps-support"
```

```Objective-C
#import <CrashOps/CrashOps.h>

// Objective-C
[CrashOps shared].appKey = @"app's-key-received-from-CrashOps-support";
```

#### Set an application key via config file

Use the [CrashOpsConfig-info.plist file](https://github.com/CrashOps/iOS-SDK/blob/v0.1.0-going-live/CrashOps/SupportingFiles/example-for-optional-info-plist/CrashOpsConfig-info.plist#L11) and place it in your project.


### How do I turn CrashOps off / on?
By default, CrashOps is enabled and it runs automatically as your app runs  (plug n' play) but you always can control and enable / disable its behavior with two approaches: dynamically or statically.

**Dynamically:** Programmatically change the value (using code) of the variable `isEnabled` as demonstrated here:
```Swift
import CrashOps

// Swift
CrashOps.shared().isEnabled = false // The default value is 'true'
```

```Objective-C
#import <CrashOps/CrashOps.h>

// Objective-C
[CrashOps shared].isEnabled = NO; // The default value is 'YES'
```

**Statically:** Add a [CrashOpsConfig-info.plist file](https://github.com/CrashOps/iOS-SDK/blob/v0.1.0-going-live/CrashOps/SupportingFiles/example-for-optional-info-plist/CrashOpsConfig-info.plist#L11) to your project and CrashOps will read it in every app launch (using this method can still be overridden by the dynamic approach).


## Acknowledgments

CrashOps iOS library produces advanced error crash reports by using [KZCrash](https://github.com/perrzick/KZCrash) which originally forked from the awesome [KSCrash](https://github.com/kstenerud/KSCrash) library.



Enjoy!
