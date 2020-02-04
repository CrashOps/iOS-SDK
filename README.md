# CrashOps iOS SDK

This SDK will help you monitor your iOS app's crashes.


## Install via CocoaPods

You want to add `pod 'CrashOps'` similar to the following to your Podfile:
```
target 'MyApp' do
  pod 'CrashOps'
end
```
Then run a `pod install` inside your terminal, or from CocoaPods.app.


### How do I switch off / on the SDK?
By default, the SDK runs automatically as your app runs  (plug n' play) but you always can control and enable / disable its behavior with two approaches: dynamically or statically.

**Dynamically:** Programmatically change the value (using code) of the variable `isEnabled` as demonstrated here:
```
// Swift
CrashOps.shared().isEnabled = false // The default value is 'true'

// Objective-C
[CrashOps shared].isEnabled = NO; // The default value is 'YES'

```


**Statically:** Add a [CrashOps-info.plist file](https://github.com/CrashOps/iOS-SDK/blob/0.0.66/CrashOps/SupportingFiles/example-for-optional-info-plist/CrashOps-info.plist) to your project and the SDK will read it in every app launch (using this method can still be overridden by the dynamic approach).

Enjoy!
