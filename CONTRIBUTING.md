# Contributing to BoxBox

Contributions are welcome! Here's how you can help:

## Development Setup

1. Clone the repository
2. Install dependencies:
   ```sh
   brew install xcodegen insert-dylib ideviceinstaller
   ```

3. Build the dylib:
   ```sh
   make build
   ```

## Writing Hooks

To add a new hook:

1. Add your `bb_` prefixed method to `src/BoxBox.m`
2. Register it in `BoxBoxInit()` using `BBSwizzle` / `BBSwizzleClass`
3. Log with `BBLog` for debugging
4. Use `BBDumpMethods` for discovering target classes

Example:
```objc
Class target = NSClassFromString(@"SomeViewController");
BBSwizzle(target, @selector(viewDidLoad), @selector(bb_viewDidLoad));
```

## Testing

1. Build an injected IPA:
   ```sh
   ./scripts/inject.sh Foo.ipa
   ```

2. Install to device:
   ```sh
   ./scripts/install.sh Foo-injected.ipa
   ```

3. Check logs:
   ```sh
   ./scripts/logs.sh
   ```

## Code Style

- Use plain strings over arrays to avoid bash errors
- Prefer `printf`-based helpers over `echo`
- Scripts must be idempotent and safe to run twice

## Creating a Release

1. Update version in `project.yml`
2. Build and verify:
   ```sh
   make build
   ```
3. Publish tagged release with:
   - `BoxBox.dylib` (binary)
   - Release notes

**Note:** The injected .ipa files are not published in releases—users build their own.
