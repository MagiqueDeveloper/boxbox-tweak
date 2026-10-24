# Release Notes

## Version 1.0.0

Initial release of BoxBox dylib injection framework.

### Features:
- Lightweight iOS dylib injection
- Ad-hoc signing for non-jailbroken devices (TrollStore/sideloaded)
- Objective-C method swizzling support
- C function hooking capabilities
- Clean, minimal API design

### Requirements:
- iOS 15.0+
- Xcode 14.0+
- macOS for building

## Usage

```sh
make build                      # Build BoxBox.dylib
./scripts/inject.sh Foo.ipa     # Inject into target
./scripts/install.sh Foo-injected.ipa
```

---

Future releases will add more features and improvements.
