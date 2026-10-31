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

## Kullanım

| Kısayol | İş |
|---|---|
| ⌘⇧X | Capture region: ekranlar donar, bölge seçilir |
| ⌥⇧5 | Capture last region: overlay açmadan son bölgeyi alır |

Kısayollar Ayarlar'dan değiştirilebilir. Overlay içinde:

| Tuş / fare | İş |
|---|---|
| Sürükle | Seçim. Quick capture kapalıyken (varsayılan) seçim kalır; içinden sürükleyerek taşınır, 8 tutamaçla boyutlandırılır |
| Enter / seçim içine çift tık | Yakala ve seçili after-capture task'larını çalıştır |
| ⌘C | Yakala ve **yalnız panoya** al (after-capture task'ları çalışmaz) |
| Esc / sağ tık | İptal; dosya ve pano değişmez |
| Shift (çizerken) | Kare |
| ⌥ (çizerken) | Seçimi taşı |
| Ok / Shift+Ok | İmleci ya da seçimi 1 / 10 piksel kaydır |
| Delete | Seçimi temizle |
| Space | Tüm ekranlar (her ekran ayrı dosya) |
| ~ / ` | İmlecin bulunduğu ekran |

After-capture task'ları (menü > After capture ya da Ayarlar), çalışma sırası: dosyaya kaydet → panoya kopyala (PNG + TIFF) → Finder'da göster → bildirim. Varsayılan: kaydet + pano. Bir task hata verirse diğerleri yine çalışır, hatalar tek bildirimde özetlenir. Dosyalar `~/Pictures/MacShot/yyyy-MM/Screenshot_yyyy-MM-dd_HH-mm-ss.png`; klasör Ayarlar'dan değiştirilebilir (security-scoped bookmark, erişilemezse varsayılana döner).

Son bölge: her region capture'dan sonra ekran UUID'si ve rect saklanır (yeniden başlatmada korunur). Region overlay'inde soluk kesikli çizilir, Enter ile kabul edilir. Ekran bağlı değilse ya da rect artık sığmıyorsa ⌥⇧5 overlay'i "Son bölge bu ekran düzeninde geçerli değil" mesajıyla açar. Space / ~ son bölgeyi değiştirmez.

## İzin

İlk açılışta Ekran Kaydı izni istenir: onboarding penceresinde **İzin iste → Sistem Ayarları'nı aç → Uygulamayı yeniden başlat**. macOS izin sonucunu process ömrü boyunca önbelleğe alabildiği için yeniden başlatma şarttır. İzin yoksa ya da capture hata verirse boş/siyah görüntü kaydedilmez. macOS Sequoia ve sonrası izni periyodik olarak yeniden sorabilir; bu bir hata değildir.

## Hotkey riski

macOS 15.0–15.1'de sandbox'lı uygulamalarda yalnız Option / Option+Shift kullanan kısayollar kaydedilemiyordu (`-9868`, 15.2'de düzeldi). KeyboardShortcuts kayıt hatasını bildirmediği için açılışta aynı kombinasyon Carbon ile denenir; başarısızsa Ayarlar'da uyarı ve tek tıkla yedek (⌃⇧4 / ⌃⇧5) çıkar. Secure input açıkken (ör. parola alanı) kısayollar tetiklenmeyebilir.

## Mimari

```
Sources/MacShotCore/   saf mantık, host'suz test edilir
  CaptureGeometry        global ↔ display-local ↔ piksel ↔ Quartz, yuvarlama, clamp
  SelectionStateMachine  overlay fare/klavye davranışı
  AfterCapture           task seti + hata izoleli runner
  LastRegion             model, UserDefaults store, geçerlilik kararı
  FileNamer, ImageCropper (PNGEncoder), HotkeyRegistration
Sources/MacShot/
  App/         AppDelegate, menu bar, hotkey'ler, tercihler
  Capture/     ScreenSnapshotService (ScreenCaptureKit), CaptureCoordinator
  Overlay/     ekran başına NSPanel, OverlayView, MagnifierView
  Output/      CaptureOutput, Clipboard, SaveFolder, Notifier
  Settings/    SwiftUI ayarlar, LoginItem (SMAppService)
  Onboarding/  izin akışı
```

Freeze: hotkey'de tüm ekranlar `SCScreenshotManager` ile paralel çekilir, overlay ancak sonra gösterilir; kesim bu donmuş kareden yapılır, ikinci capture yoktur. Legacy `CGWindowListCreateImage` kullanılmaz.

## Bilinen sınırlar

- Çok ekranlı birleşik seçim yok; seçim başladığı ekrana clamp edilir.
- Pencere / kontrol algılama (snap) yok.
- Launch at login Debug build'de `build/` altından da çalışır, ama uygulama taşınırsa yeniden açılması gerekir; kalıcı kullanım için `/Applications` önerilir.

## Açık kaynak

GitHub'da açık kaynak yayınlanması planlanıyor (önce private repo). Lisans ve katkı rehberi yayın öncesi eklenecek.
