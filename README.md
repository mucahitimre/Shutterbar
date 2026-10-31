# MacShot

ShareX'in region capture akışını macOS'a taşıyan minimum menu bar uygulaması: ekranı dondur, bölge seç, after-capture task'larını çalıştır, son bölgeyi hatırla.

Plan ve gereksinimler: [docs/plan.md](docs/plan.md)

## Kurulum

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MacShot.xcodeproj -scheme MacShot -derivedDataPath build/DD build
open build/DD/Build/Products/Debug/MacShot.app
```

- macOS 14.0+, Xcode 16+ (Swift 6).
- İmza: `project.yml` içinde `DEVELOPMENT_TEAM`. Ad-hoc imzalı build'de Ekran Kaydı izni her build'de kaybolur; sabit bir Apple Development kimliği kullanın.
- Uygulama adı ve bundle id `project.yml` içindeki `APP_NAME` / `BUNDLE_ID_PREFIX` sabitlerinden türetilir.

## Test

```bash
xcodebuild -project MacShot.xcodeproj -scheme MacShot -derivedDataPath build/DD test
```

Saf mantık (geometri, seçim durum makinesi, dosya adı, last region kararı) `MacShotCore` framework'ünde ve host uygulama olmadan test edilir.
