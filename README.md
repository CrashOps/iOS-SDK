# CrashOps iOS SDK
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) [![](https://img.shields.io/cocoapods/p/CrashOps.svg?style=flat)](https://cocoapods.org/pods/CrashOps)

This SDK will help you monitor your iOS app's crashes.


## Install via CocoaPods
[![](https://img.shields.io/cocoapods/v/CrashOps.svg?style=flat)](https://cocoapods.org/pods/CrashOps)

You want to add `pod 'CrashOps'` similar to the following to your Podfile:
```
target 'MyApp' do
  pod 'CrashOps'
end
```
Then run a `pod install` inside your terminal, or from CocoaPods.app.


### How do I switch off / on the SDK?
By default, the SDK is enabled and it runs automatically as your app runs  (plug n' play) but you always can control and enable / disable its behavior with two approaches: dynamically or statically.

**Dynamically:** Programmatically change the value (using code) of the variable `isEnabled` as demonstrated here:
```swift
// Swift
CrashOps.shared().isEnabled = false // The default value is 'true'
```

```objective-c
// Objective-C
[CrashOps shared].isEnabled = NO; // The default value is 'YES'

```

**Statically:** Add a [CrashOpsConfig-info.plist file](https://github.com/CrashOps/iOS-SDK/blob/v0.0.68/CrashOps/SupportingFiles/example-for-optional-info-plist/CrashOpsConfig-info.plist) to your project and the SDK will read it in every app launch (using this method can still be overridden by the dynamic approach).


## Acknowledgments

This SDK produces advanced error crash reports by using [KZCrash](https://github.com/perrzick/KZCrash) which originally forked from the awesome [KSCrash](https://github.com/kstenerud/KSCrash) library.



Enjoy!
