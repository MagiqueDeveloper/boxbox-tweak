# BoxBox

Enhance your Box Box Club experience. A lightweight iOS dylib that provides additional features. Works with TrollStore and sideloading.

## Quick Start

```sh
# Install dependencies
brew install xcodegen insert-dylib ideviceinstaller

# Build the dylib
make build

# Inject into Box Box Club
./scripts/inject.sh BoxBoxClub.ipa
```

Releases on GitHub provide pre-built binaries for all users.

## Features

- Enhances Box Box Club app functionality
- No jailbreak required
- Works on iOS 15.0+

## How it works

1. **Build**: Compile the dylib for arm64 iOS devices
2. **Inject**: Insert dylib into Box Box Club's binary
3. **Load**: On app launch, BoxBox hooks into the app and activates enhancements

## Disclaimer

BoxBox is a community-developed project and is **not affiliated with Box Box Club**.

Please support the developers by downloading Box Box Club from the official App Store:
- [Download Box Box Club: Racing Companion on iOS App Store](https://apps.apple.com/us/app/box-box-club-racing-companion/id1621241916)

## Requirements

- iOS 15.0+ device with TrollStore or sideloading
- macOS for building
- Xcode 14.0+
- macOS Homebrew packages: `xcodegen`, `insert-dylib`, `ideviceinstaller`

## Release Notes

See release tags for version updates and changes.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for details.

## License

MIT License - see [`LICENSE`](LICENSE) for details
