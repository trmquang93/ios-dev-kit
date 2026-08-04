# UIKit — UIButton.Configuration (iOS 15+)

Modern replacement for the legacy UIButton setter API (`setTitle`, `setImage`, `contentEdgeInsets`, `titleEdgeInsets`, `imageEdgeInsets`, `tintColor`, etc.). All of those setters continue to compile on iOS 15+ but are **ignored at runtime** once a configuration is assigned. Several (`contentEdgeInsets`, `titleEdgeInsets`, `imageEdgeInsets`) are now deprecated with a warning explicitly referencing `UIButtonConfiguration`.

## When to use

- Deployment target ≥ iOS 15: prefer `UIButton.Configuration` for all new buttons.
- Deployment target includes iOS 14 or earlier: keep the legacy setter API (or branch with `@available(iOS 15, *)`).

## Base styles

```swift
var config = UIButton.Configuration.plain()    // no background
// or .filled() / .tinted() / .gray() / .borderless() / .bordered() / .borderedTinted() / .borderedProminent()
```

Each style seeds sensible defaults for background, corner radius, content insets, and highlight behavior. Customize from there.

## Mapping legacy → Configuration

| Legacy API | Configuration replacement |
|---|---|
| `btn.setTitle("X", for: .normal)` | `config.title = "X"` |
| `btn.setAttributedTitle(...)` | `config.attributedTitle = AttributedString(...)` (Foundation `AttributedString`, not `NSAttributedString`) |
| `btn.setImage(img, for: .normal)` | `config.image = img` |
| `btn.tintColor = .white` | `config.baseForegroundColor = .white` |
| `btn.backgroundColor = .red` | `config.baseBackgroundColor = .red` (on `.filled()`/`.tinted()`) or `config.background.backgroundColor` |
| `btn.contentEdgeInsets = UIEdgeInsets(...)` | `config.contentInsets = NSDirectionalEdgeInsets(top:, leading:, bottom:, trailing:)` |
| `btn.titleEdgeInsets` / `btn.imageEdgeInsets` | Gone — use `config.imagePadding` for gap between image & title, `config.imagePlacement` for side |
| `btn.layer.cornerRadius = N` | `config.background.cornerRadius = N` or `config.cornerStyle = .capsule/.large/.medium/.small/.fixed` |
| `btn.titleLabel?.font = ...` | Use `config.attributedTitle` with a font attribute, **or** `config.titleTextAttributesTransformer` |

### Font via transformer

```swift
config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
    var out = incoming
    out.font = TextStyle.bold.dynamicFont(size: 16)
    return out
}
```

### Construct

```swift
let btn = UIButton(configuration: config)
// or assign to existing button: btn.configuration = config
```

## Image sizing — the non-obvious part

Configuration has no generic "image size" property. It sizes based on what the image is:

### 1. SF Symbol → `preferredSymbolConfigurationForImage`

```swift
config.image = UIImage(systemName: "xmark")
config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
    pointSize: 20,
    weight: .regular,
    scale: .medium
)
```

### 2. Raster image (PNG/JPEG) → pre-resize at init time

Configuration renders the `UIImage` at its intrinsic pt size (= pixel size ÷ scale factor). A 72×72px `@3x` PNG renders at 24pt, not 20pt. There is no `config.image.size = ...` equivalent. Resize the image once:

```swift
let targetSize = CGSize(width: 20, height: 20)
let resized = UIGraphicsImageRenderer(size: targetSize).image { _ in
    original.draw(in: CGRect(origin: .zero, size: targetSize))
}
config.image = resized
```

`UIGraphicsImageRenderer` uses the screen's native scale, so the resized image stays crisp on @2x/@3x displays.

## Hit-target bigger than visible icon

When RN (or a design spec) asks for an icon that looks small but has a larger tap area (RN's `hitSlop`), two idiomatic options:

### Option A — outer size constraints + zero `contentInsets`

```swift
// Constrain the button to the hit area (e.g. 32×40)
btn.snp.makeConstraints { make in
    make.width.equalTo(32)
    make.height.equalTo(40)
}
// Pre-resize the image to the visible icon size (e.g. 20×20)
// Assign config.image = resized  +  config.contentInsets = .zero
// Configuration centers the smaller image in the larger bounds automatically.
```

### Option B — match button to icon, expand hit test externally

Use a subclass like `HitTestExpandedButton` (common pattern) that overrides `point(inside:with:)` to honor a `hitTestExpansion` inset. The button size matches the icon, but taps outside bounds still register. Maps most literally to RN's `hitSlop`.

Option A is preferred when the spec treats the larger container as a real layout element with its own position; Option B is preferred when the larger area is purely for touch forgiveness.

## State-based updates

Legacy `btn.setImage(_:for: .highlighted)` / `.disabled` doesn't apply in Configuration. Use `configurationUpdateHandler` instead:

```swift
btn.configurationUpdateHandler = { button in
    guard var updated = button.configuration else { return }
    switch button.state {
    case .highlighted: updated.baseBackgroundColor = .systemGray
    case .disabled:    updated.baseForegroundColor = .tertiaryLabel
    default:           updated.baseBackgroundColor = .systemBlue
    }
    button.configuration = updated
}
```

Trigger an update manually after external state changes via `btn.setNeedsUpdateConfiguration()`.

## Activity indicator built in

```swift
config.showsActivityIndicator = true   // replaces spinner-swap boilerplate
```

## Common pitfalls

- **Mixing legacy setters with Configuration.** Once `btn.configuration != nil`, setters like `contentEdgeInsets`, `setImage(_:for:)`, `setTitle(_:for:)`, `tintColor` are ignored. Don't half-migrate a button — it's confusing to debug. Full Configuration or full legacy.
- **Forgetting `.zero` contentInsets.** `.plain()` has small default insets that can make a button appear offset. Set explicitly when pairing with outer size constraints.
- **Using `NSAttributedString` instead of `AttributedString`.** Configuration expects Foundation `AttributedString` for `attributedTitle`. Convert with `AttributedString(nsAttributedString)`.
- **Assuming Configuration resizes raster images.** It does not. Pre-resize, or switch to SF Symbols if the icon is swappable.
- **Subclassing UIButton with Configuration.** Works, but avoid overriding `layoutSubviews` to position the imageView — Configuration owns that layout. Customize via `configurationUpdateHandler` or a plain `UIView` wrapper if you need unusual layout.

## Reference

- Apple docs: https://developer.apple.com/documentation/UIKit/UIButton/Configuration-swift.struct
- Apple TN3106 — "Customizing UIButton configurations"
