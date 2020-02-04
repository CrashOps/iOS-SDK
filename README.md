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


### How do I choose to disable / enable the SDK?
By default, the SDK works automatically (plug n' play) as your app runs but you always can control it dynamically or statically to enable / disable its behavior.

**Dynamically:** Programmatically change the value (using code) of the variable:
```
CrashOps.shared().isEnabled = false // it's true by default
```


**Statically:** Add a [CrashOps-info.plist file](https://github.com/CrashOps/iOS-SDK/blob/0.0.66/CrashOps/SupportingFiles/example-for-optional-info-plist/CrashOps-info.plist) to your project and the SDK will read it in every app launch (using this method may be overridden by the dynamic approach).
