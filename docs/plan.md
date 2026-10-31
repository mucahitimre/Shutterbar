# MacShot v1: ShareX'ten Mac'e minimum region capture planı ve Claude Code devir bloğu

Dört isteğin hepsi macOS 14+ hedefiyle, ScreenCaptureKit ve AppKit kullanılarak ve sandbox açık hâlde yapılabilir. Kritik nokta şu: ekranı "dondurmak" için ayrı bir API yok. Hotkey'e basıldığı anda her ekranın tam görüntüsü bir kez alınıyor, seçim bu donmuş görüntü üzerinde yapılıyor ve son PNG yeni bir capture'dan değil, bu görüntüden kesilerek üretiliyor. Tek ciddi risk, istediğin varsayılan hotkey'ler (⌥⇧4 ve ⌥⇧5). Sandbox'lı uygulamalarda yalnızca Option+Shift kullanan kısayollar macOS 15.0 ve 15.1'de çalışmıyordu, 15.2'de bu kısıtlama geri alındı.\[1\]\[2\] Bu yüzden devir bloğu kayıt hatasını yakalayıp bir yedek kısayola geçmeyi zorunlu tutuyor.

## TL;DR
- **Mimari:** ShareX'in varsayılan region capture'ı gibi önce dondur, sonra seç. Her ekran `SCScreenshotManager.captureImage(contentFilter:configuration:)` ile alınıyor (macOS 14+). Kendi pencerelerimiz `SCContentFilter(display:excludingApplications:exceptingWindows:)`\[3\]\[4\] ile dışarıda bırakılıyor. Retina ekranda keskin sonuç için çıktı genişliği "point × `pointPixelScale`" olarak ayarlanıyor. Kırpma donmuş `CGImage` üzerinde yapılıyor. `CGWindowListCreateImage` macOS 15 SDK'sında "obsoleted", yani hiç kullanılmayacak.\[5\]
- **ShareX'i geçen nokta "Last region":** ShareX'te son region yalnızca bellekte tutuluyor (eski kaynak koda dayanan çıkarım) ve overlay'de önceden gösterilmiyor. Bizde region, ekran UUID'si ve point rect olarak kalıcı saklanacak, overlay'de soluk biçimde önceden çizilecek ve overlay açmadan çeken ayrı bir hotkey olacak. Bu, macOS'un Cmd+Shift+5 "Remember Last Selection", CleanShot X'in "Capture Previous Area" ve Shottr'ın "Repeat Area" özelliklerinin birleşimi.\[6\]\[7\]
- **Scope M:** dört faz artı bir cila fazı, tek CC oturumunda sırayla yapılabilir, subagent gerekmiyor. CC önce API teyidi, scope değerlendirmesi ve açık sorularla duruyor, GO gelmeden kod yazmıyor.

## A) ShareX'ten alınacak minimum davranışlar (senin dört maddene göre)

**1. Region capture.** ShareX'in resmî region capture dokümanına göre akış şöyle: sol tuşla sürükleyerek dikdörtgen çizilir. Quick capture açıkken, ki varsayılan budur, fare bırakıldığı anda capture tamamlanır. Quick capture kapalıyken seçim taşınabilir ve köşelerden yeniden boyutlandırılabilir; capture Enter ya da seçimin içine çift tıklamayla bitirilir. Bu ayar Task settings → Capture → Region capture altında.\[8\] Alacağımız kısayollar dokümandaki tablodan:
- Esc: iptal.\[8\]
- Shift (çizerken): kare seçim.\[8\]
- Ctrl (çizime başladıktan sonra): seçimi çizerken taşıma.\[8\] Mac'te bunun karşılığı olarak Space-drag yerine ⌃ veya ⌥ önerilir, açık soru olarak bırakıldı.
- Ok tuşları: imleci 1 px oynatır; Shift+ok 10 px oynatır.\[8\]
- Delete: seçimi temizler.\[8\]
- Space: tüm ekranlar (fullscreen) capture.\[8\]
- ~: aktif monitör capture.\[8\]

Keybinds sayfası ayrıca fare tekerleğiyle büyüteç boyutunu değiştirmeyi ve 1…0 tuşlarıyla belirli bir monitörü almayı listeliyor; ikisi de MVP dışında.\[9\] ShareX'in kaynak kodundaki `RegionCaptureOptions` sınıfında büyüteç için `ShowMagnifier`, `MagnifierPixelCount` ve `MagnifierPixelSize`, pencere ve kontrol algılama için `DetectWindows` ve `DetectControls` seçenekleri var.\[10\] Window/control detection (fareyle üzerine gelinen pencereye snap) v1 kapsamı dışında.

**2. After capture tasks.** ShareX'te bu bir `[Flags]` enum'u (`AfterCaptureTasks`), yani birden fazla görev aynı anda seçilebiliyor. Kaynak kodun 2019 tarihli bir kopyasında `CopyImageToClipboard = 1 << 4`, `SaveImageToFile = 1 << 6` ve `ShowInExplorer = 1 << 12` değerleri görülüyor.\[11\] Seçim ana pencerede ve tray menüsünde checkbox'lı "After capture tasks" menüsünden yapılıyor. Hotkey bazında da `TaskSettings` üzerinden ayrı bir set atanabiliyor (`UseDefaultAfterCaptureJob`).\[12\] Örnek bir config'te `"AfterCaptureJob": "CopyImageToClipboard, SaveImageToFile, ShowInExplorer"` görülüyor.\[13\] Bizim v1 karşılığımız kalıcı ve checkbox'lı bir liste: Dosyaya kaydet (PNG), Panoya kopyala, Bildirim göster ve Finder'da göster. Bu liste tüm hotkey'ler için ortak olacak; hotkey bazında ayrı set v2'ye kalıyor.

Dosya adı ve klasör: ShareX 12.3.0'dan beri yeni kurulumlarda varsayılan ad pattern'i `%pn_%ra{10}` (rastgele). Eski tarih-saat pattern'i `%pn_%y-%mo-%d_%h-%mi-%s` idi.\[14\] Alt klasör pattern'i ise `ApplicationConfig.cs` içinde `SaveImageSubFolderPattern = "%y-%mo"`, yani yyyy-MM.\[15\] Biz okunabilir ve sıralanabilir olduğu için tarih-saat yolunu seçiyoruz: `~/Pictures/<AppName>/yyyy-MM/Screenshot_yyyy-MM-dd_HH-mm-ss.png`.

**3. Ekran değişmemeli (freeze).** ShareX'in varsayılan region modu donmuş ekran üzerinde çalışıyor. Bunun dolaylı kanıtı, ShareX'in ayrıca "Region (Transparent)" diye bir mod sunması; README bu modu "Allows you to do rectangle capture from non frozen screen" diye tanımlıyor.\[16\]\[17\] Mac tarafında da aynı yöntem kullanılır: hotkey anında her ekranı tek kare olarak çek, bu kareyi overlay penceresinin arka planı yap, seçimi onun üzerinde yaptır ve PNG'yi bu kareden kes. Açık kaynak referanslar bunun hızlı yapılabildiğini gösteriyor. Mio "her ekranı 80 ms'den kısa sürede donduruyor" diyor.\[18\] Shotty'nin 9 Ekim 2026 tarihli PR #21'i (markusjura/shotty) ekranları pencerelerden önce dondurduklarını anlatıyor: "Displays now freeze first and on their own, within about 100 ms of the shortcut, however many windows are open"; önceden 22 pencere açıkken bu süre bir saniyeyi aşıyormuş.

**4. Last region.** ShareX'te "Capture → Last region" aynı alanı tekrar çeker.\[8\]\[19\] 2015 dönemi kaynakta son region `public static GraphicsPath LastRegionFillPath` alanında, yani process belleğinde tutuluyor.\[20\] Buna dayanarak uygulama yeniden başlayınca kaybolduğunu varsayıyoruz; güncel kodda teyit edilemedi. Overlay açılırken son region'ın gösterilmesi ShareX'te yok; issue #1663'te bu özellik zaten istenmiş.\[21\] Bizde bu nedenle üç davranış olacak:
- Region kalıcı saklanacak: ekran UUID'si ve point cinsinden rect.
- Normal region hotkey'inde son region overlay'de soluk biçimde çizilecek ve Enter ile kabul edilebilecek.
- Ayrı bir "Last region" hotkey'i overlay açmadan doğrudan capture yapacak.

Mac'teki karşılıklar: macOS Cmd+Shift+5 seçeneklerindeki "Remember Last Selection", CleanShot X'in "Capture Previous Area" komutu ve Shottr'ın özelleştirilebilir kısayolu olan "Repeat Area" (`shottr://grab/repeat`). \[6\]\[7\]\[22\]\[23\]\[24\]

## B) Plan v1

**Scope tahmini: M.** Kod tek bir uygulama, yaklaşık 15–25 Swift dosyası ve bir harici paket. Zor kısımlar algoritma değil, platform ayrıntıları: koordinat dönüşümü (NSScreen'in sol-alt orijinli global koordinatları ile CG/ScreenCaptureKit'in sol-üst orijinli koordinatları), karışık Retina ve non-Retina ekranlar, TCC izinleri ve overlay'in full-screen Space'lerin üstüne çıkması. Annotation editor eklenseydi scope L olurdu.

**Subagent kullanımı: gerek yok.** Fazlar birbirine bağımlı (overlay → kesim → task'lar → last region). Paralel iş çıkarmak, sağladığı kazançtan çok bağlam bölünmesi yaratır. Tek CC oturumunda sırayla build, test ve commit yeterli.

**Teknik kararlar**
- **Minimum hedef macOS 14.0.** `SCScreenshotManager.captureImage(contentFilter:configuration:)` ve `SCContentFilter.pointPixelScale` 14.0 ile geliyor. `SCScreenshotManager.captureImage(in:)`, yani display'den bağımsız point rect ile capture, macOS 15.2+ gerektiriyor\[25\]\[26\] ve tüm akış donmuş kareden kesildiği için ona ihtiyaç yok.
- **Dil ve UI:** Swift 5.10+/6, AppKit overlay (borderless `NSPanel`, her ekran için bir tane), SwiftUI ayarlar penceresi, menu bar app (`LSUIElement = YES`, `NSStatusItem`).
- **Proje üretimi XcodeGen ile** (`project.yml`). `.xcodeproj` repoya commit edilmez ya da üretilmiş hâliyle commit edilir; CC bunu GO aşamasında sorar.
- **Sandbox açık.** Entitlement'lar: `com.apple.security.app-sandbox`, `com.apple.security.assets.pictures.read-write`, `com.apple.security.files.user-selected.read-write` ve `com.apple.security.files.bookmarks.app-scope`.\[27\] Kullanıcı Pictures dışında bir klasör seçerse security-scoped bookmark saklanır. Bookmark çözüldükten sonra `startAccessingSecurityScopedResource()` çağrılır ve stop ile dengelenir; bookmark stale olursa yenilenir.\[28\]\[29\]
- **Capture yöntemi:** `SCShareableContent` → her `SCDisplay` için `SCContentFilter(display:excludingApplications:[kendi app'imiz], exceptingWindows:[])`. `SCStreamConfiguration.width/height` = display point boyutu × `filter.pointPixelScale`. Bunun nedeni `SCDisplay.width`'ün point, `SCStreamConfiguration.width`'ün piksel cinsinden olması; çarpılmazsa Retina'da yarım çözünürlük çıkar ve bu hata gerçek projelerde (flutter-webrtc #2241) yaşanmış.\[30\]\[31\]\[32\] `showsCursor = false`.
- **Overlay penceresi:** `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `isOpaque = false`, `hidesOnDeactivate = false`. Key event alabilmesi için `canBecomeKey = true` olan bir `NSPanel` alt sınıfı kullanılır. Full-screen bir uygulamanın ayrı Space'inde görünmek için `canJoinAllSpaces` ve `fullScreenAuxiliary` birlikte gerekiyor.\[33\]\[34\]\[35\]
- **Global hotkey için `sindresorhus/KeyboardShortcuts`.** Paket Carbon `RegisterEventHotKey` üzerine kurulu, README'ye göre "fully sandboxed and Mac App Store compatible"\[2\]\[36\] ve Accessibility veya Input Monitoring izni istemiyor. Kayıt sırasında Option+Shift sorunu ele alınmalı (aşağıdaki Caveats bölümüne bak).
- **Launch at login:** `SMAppService.mainApp.register()` / `unregister()` (macOS 13+). Kayıt yapıldığında sistem kullanıcıya "login item eklendi" bildirimi gösterir.\[37\]\[38\]
- **Kalıcı ekran kimliği:** `CGDisplayCreateUUIDFromDisplayID`. `CGDirectDisplayID` yeniden bağlanmada değişebiliyor (bir projede Sidecar ekranı art arda 6, 7 ve 13 ID'leriyle geri geldi, UUID ise aynı kaldı).\[39\] Bir başka proje UUID'nin reboot sonrasında da değişebildiğini bildiriyor.\[40\] Bu yüzden kural basit: UUID bulunamazsa overlay açılır.
- **İzin:** `CGPreflightScreenCaptureAccess()` ve `CGRequestScreenCaptureAccess()`. Apple Developer Forums'taki 732726 numaralı konuda bir geliştirici, preflight'ın ilk sonucu false ise "it will continue to return false, even if the app has been given permission" diye bildiriyor; yani uygulama yeniden başlatılana kadar false dönebiliyor. Onboarding bu yüzden "izni verdikten sonra uygulamayı yeniden başlat" adımını içermeli. TCC kaydının her build'de kaybolmaması için sabit bir Apple Development imzası kullanılmalı. CapSoftware/Cap issue #1722'ye göre Sequoia'da "CGPreflightScreenCaptureAccess() always returns false for ad-hoc signed or unsigned binaries regardless of what permissions are granted in System Settings".

**MVP dışı bırakılanlar:** annotation editor, window/control snapping, scrolling capture, video ve GIF kaydı, upload, OCR, pin to screen, hotkey bazında ayrı after-capture seti, 1…0 tuşlarıyla monitör seçimi, multi-region, JPEG/HEIC çıktısı.

**Fazlar**
- **F0 – İskelet, izin, hotkey:** XcodeGen projesi, menu bar ikonu ve menüsü (Capture region, Capture last region, Settings…, Quit). Entitlement'lar, KeyboardShortcuts SPM paketi, ⌥⇧4 kaydı ve kayıt hatasının tespiti. İzin onboarding penceresi. Unit test target'ı.
- **F1 – Dondur, overlay, seç, kes, kaydet:** ScreenCaptureKit ile tüm ekranları paralel çek, ekran başına bir overlay paneli aç, sürükleyerek seç, boyut/koordinat etiketini göster, Esc ile iptal et, kesip PNG olarak kaydet (geçici olarak sabit task). Seçim tek ekrana clamp edilir. Saf matematik `CaptureGeometry` modülünde yer alır ve testlenir.
- **F2 – After-capture tasks ve ayarlar:** `AfterCaptureTask` OptionSet'i, menüde checkbox'lar ve SwiftUI ayarlar penceresi. Dosya adı üretici, çakışmada `_2`, `_3` eki, klasör seçici ve bookmark. Bildirim (UserNotifications), panoya kopyala (`NSPasteboard`, PNG ve TIFF), Finder'da göster (`NSWorkspace.activateFileViewerSelecting`). Task'lar birbirinden izole çalışır.
- **F3 – Last region:** `LastRegionStore` (UserDefaults içinde JSON: displayUUID, rect, kayıt zamanı). Overlay'de soluk ön çizim ve Enter ile kabul. ⌥⇧5 ile overlay açmadan capture: yalnızca ilgili ekran çekilir ve kesilir. Ekran yoksa veya rect sınır dışındaysa overlay açılır.
- **F4 – Cila:** büyüteç (imleç çevresinin piksel ızgaralı zoom'u), ok tuşlarıyla 1/10 px hareket, quick capture toggle (kapalıyken taşıma, yeniden boyutlandırma ve Enter/çift tık ile bitirme), Space ve ~ kısayolları, launch at login, manuel test checklist'inin koşulması.

## C) Claude Code devir bloğu

**Ne yaptırıyorum:** CC'ye macOS için minimum bir ShareX alternatifinin (region capture, after-capture tasks, freeze, last region) tamamını fazlar hâlinde devrediyorum. CC önce planı ve API'leri teyit edip GO bekleyecek, sonra fazları build, test ve commit ile kendi başına bitirecek.

**Durum:** (gönderilmedi)

```text
CC-MacShot-1

=== AMAÇ ===
macOS için Windows'taki ShareX'in minimum bir alternatifini yaz. Çalışma adı "MacShot" (kesin ad açık soruda; değişirse bundle id, klasör adı ve ürün adı tek bir sabitten türetilsin). v1'de yalnızca dört şey var: (1) region screenshot, (2) önceden seçilmiş after-capture task'ları, (3) seçim sırasında ekranın donması, (4) son region'ın hatırlanması. Menu bar uygulaması olacak, Dock ikonu olmayacak.

=== ORTAM VE KURALLAR ===
- Yeni ve boş bir git reposunda çalış. Repo kökünde README.md, project.yml (XcodeGen), Sources/, Tests/ olsun.
- Her faz sonunda build ve testler yeşilse commit at. Mesaj formatı: "F<n>: <kısa özet>". Faz içinde ara commit serbest.
- push, tag, release, notarization, App Store yükleme YOK. Uzak repo ekleme.
- CGWindowListCreateImage, CGDisplayCreateImage veya başka bir legacy CoreGraphics capture API'si KULLANMA. Capture yalnızca ScreenCaptureKit ile yapılacak. (CGWindowListCreateImage macOS 15 SDK'da "obsoleted".)
- Tek izinli harici bağımlılık: sindresorhus/KeyboardShortcuts (SPM). Başka bir paket eklemeden ÖNCE sor ve gerekçesini yaz.
- Minimum deployment target: macOS 14.0. Swift 5.10+ (Swift 6 strict concurrency tercih edilir; sorun çıkarsa gerekçesiyle 5 modunda kal).
- UI: overlay AppKit ile (NSPanel/NSView), ayarlar penceresi SwiftUI ile. Info.plist'te LSUIElement = YES.
- XcodeGen ile proje üret. xcodegen kurulu değilse kurmadan önce sor (Homebrew ile mi, yoksa Mint ile mi?).
- App Sandbox AÇIK. Entitlement'lar: com.apple.security.app-sandbox, com.apple.security.assets.pictures.read-write, com.apple.security.files.user-selected.read-write, com.apple.security.files.bookmarks.app-scope. Başka bir entitlement gerekiyorsa sor.
- İmza: TCC (Screen Recording) izninin her build'de kaybolmaması için sabit bir "Apple Development" kimliğiyle imzala. DEVELOPMENT_TEAM değerini bana sor; ad-hoc imzayla devam etme.
- Lisans: ShareX GPL v3 lisanslı. Oradan kod KOPYALAMA, yalnızca davranışı referans al. Açık kaynak Mac projelerinden de (Mio GPL-3.0; Screenshot Pro, shotty ve ScreenCap MIT) kod kopyalama; fikir alabilirsin.

=== ÇALIŞMA AKIŞI ===
AŞAMA 0 – Teyit ve GO (KOD YAZMA):
1. Bu planı oku. Aşağıdaki API'lerin güncel SDK'daki imzasını ve availability bilgisini Xcode'un SDK header'larından veya Apple dokümantasyonundan teyit et:
   SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:) veya .current,
   SCContentFilter(display:excludingApplications:exceptingWindows:),
   SCContentFilter.pointPixelScale ve contentRect,
   SCScreenshotManager.captureImage(contentFilter:configuration:),
   SCStreamConfiguration.width/height/showsCursor,
   CGPreflightScreenCaptureAccess / CGRequestScreenCaptureAccess,
   CGDisplayCreateUUIDFromDisplayID,
   SMAppService.mainApp,
   KeyboardShortcuts'ın son sürümü ve kayıt hatasını bildirip bildirmediği.
2. Scope değerlendirmesi yap (S/M/L/XL). Benim tahminim M; katılmıyorsan nedenini yaz.
3. Açık soruları ve varsayımlarını numaralı liste hâlinde yaz.
4. DUR ve "GO" bekle. GO gelmeden dosya oluşturma ve kod yazma.

GO SONRASI:
- F0 → F4 fazlarını sırayla tamamla. Her faz için: implementasyon → xcodebuild build → xcodebuild test → commit → kısa rapor.
- Faz raporu formatı (en fazla 10 satır): yapılanlar, eklenen testler ve sonuçları, bilinen sorunlar, manuel test edilmesi gerekenler.
- Fazlar arasında onay bekleme, yalnızca BLOCKER'da dur. BLOCKER sayılanlar: izin, imza veya team gerekiyorsa; yeni bir paket ya da entitlement gerekiyorsa; bir gereksinim teknik olarak imkânsızsa veya iki gereksinim çelişiyorsa; build 3 denemede düzelmiyorsa.

=== FONKSİYONEL GEREKSİNİMLER ===

R1 – Region capture (freeze ile)
R1.1 Hotkey'e basıldığında önce TÜM bağlı ekranların görüntüsünü ScreenCaptureKit ile paralel al (async let veya TaskGroup), overlay'i ancak ondan sonra göster. Her ekran için:
     filter = SCContentFilter(display: d, excludingApplications: [kendi SCRunningApplication'ımız; bundleIdentifier veya processID ile eşle], exceptingWindows: [])
     config.width  = Int((d.width  * filter.pointPixelScale).rounded())
     config.height = Int((d.height * filter.pointPixelScale).rounded())
     config.showsCursor = false
     image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
R1.2 Donmuş görüntü: overlay her ekranda kendi donmuş CGImage'ını arka plan olarak çizer, seçim dışını yarı saydam karartır. Sonuç PNG'si bu donmuş görüntüden kesilir; ikinci bir capture YAPILMAZ.
R1.3 Kendi pencerelerimiz (overlay, menü, ayarlar, onboarding) capture'a girmemeli. Filter'daki excludingApplications buna ek bir güvencedir; asıl güvence, overlay'in capture tamamlanmadan gösterilmemesidir.
R1.4 Overlay penceresi: her NSScreen için bir borderless NSPanel alt sınıfı (canBecomeKey = true). level = .screenSaver; collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]; isOpaque = false; hidesOnDeactivate = false. Frame tam olarak screen.frame olsun. Overlay açıkken uygulama aktive edilsin (NSApp.activate) ki klavye olayları gelsin. Kapanınca önceki uygulamaya odak geri dönsün.
R1.5 Piksel doğruluğu: kesim rect'i point → piksel dönüşümüyle hesaplanır. pikselRect = (rectInDisplayPoints × scale), tamsayıya yuvarlanır (origin floor, maxX/maxY ceil) ve görüntü sınırına clamp edilir. Karışık Retina (2x) ve non-Retina (1x) monitörlerde her ekran kendi scale değerini kullanır. NSScreen (sol-alt orijin, global) ile display-local sol-üst orijin arasındaki dönüşüm TEK bir saf fonksiyonda yapılır ve test edilir. Scale olarak NSScreen.backingScaleFactor değil, filter.pointPixelScale (veya image.width / display point width) esas alınır; ikisi uyuşmazsa logla.
R1.6 Tek ekrana clamp: seçim, sürüklemenin başladığı ekranla sınırlıdır. Fare başka bir ekrana geçerse rect o ekranın kenarında kesilir. Çok ekranlı birleşik capture v1'de yok.
R1.7 Seçim UI'si: 1 px beyaz çerçeve ve kesikli iç çizgi; seçimin yanında "W × H" etiketi (piksel cinsinden) ve imleç yanında x,y koordinatı. Çizim sırasında crosshair imleç.
R1.8 Klavye ve fare (ShareX davranışı):
     - Sol tuşla sürükle: seçim. Quick capture AÇIK (varsayılan) ise bırakınca capture.
     - Quick capture KAPALI ise: seçim taşınabilir (içinden sürükle) ve 8 tutamaçla yeniden boyutlandırılabilir. Enter veya seçim içine çift tık ile capture.
     - Esc veya sağ tık: iptal (dosya yok, task yok).
     - Shift (çizerken): kare.
     - Ok tuşları: imleç veya seçim 1 px; Shift+ok: 10 px (F4).
     - Delete: mevcut seçimi temizle.
     - Space: tüm ekranlar fullscreen capture (v1'de her ekran ayrı bir dosya olarak kaydedilir; birleştirme yok).
     - ~ (ve ` tuşu; klavye düzeninden bağımsız olarak keyCode ile): imlecin bulunduğu monitörün tamamını capture.
     - Çok küçük seçim (< 3×3 pt) tıklama sayılır ve yok sayılır.
R1.9 Büyüteç (F4): imlecin yanında, imleç çevresindeki yaklaşık 15×15 pikselin 8x büyütülmüş, ızgaralı ve merkez pikseli vurgulu görünümü. Ayarlardan kapatılabilir.
R1.10 Performans hedefi: hotkey'den overlay görünene kadar 2 ekranda 250 ms'den kısa sürmeli. Ölç ve faz raporunda yaz.

R2 – After-capture tasks
R2.1 OptionSet AfterCaptureTask: saveToFile, copyToClipboard, showNotification, revealInFinder. Seçim kalıcıdır (UserDefaults). Menu bar menüsünde "After capture" alt menüsünde checkbox olarak gösterilir, ayarlar penceresinde de aynısı bulunur.
R2.2 Varsayılan: saveToFile + copyToClipboard (açık soruya göre değişebilir).
R2.3 saveToFile: PNG (ImageIO, CGImageDestination). Varsayılan yol ~/Pictures/<AppName>/yyyy-MM/Screenshot_yyyy-MM-dd_HH-mm-ss.png. Alt klasör yoksa oluştur. Aynı ad varsa _2, _3, … eki eklenir. Saat yerel saat dilimine göre ve 24 saat formatında.
R2.4 Klasör ayarlardan değiştirilebilir (NSOpenPanel, canChooseDirectories). Pictures dışı bir klasör seçilirse security-scoped bookmark saklanır. Her yazımda bookmark çözülür, startAccessing/stopAccessing dengelenir, stale ise yenilenir. Bookmark çözülemezse varsayılana dönülür ve kullanıcı bildirimle uyarılır.
R2.5 copyToClipboard: NSPasteboard.general'e PNG verisi yaz (ve TIFF temsilini de ekle). saveToFile da seçiliyse dosya URL'si de eklenebilir; bu davranışı açık soru olarak sor.
R2.6 showNotification: UserNotifications. İzin ilk kullanımda istenir. Bildirim metni dosya adını ya da "Panoya kopyalandı" bilgisini içerir. Bildirime tıklanınca dosya Finder'da gösterilir.
R2.7 revealInFinder: NSWorkspace.shared.activateFileViewerSelecting([url]). saveToFile seçili değilse bu task atlanır ve bu loglanır.
R2.8 Hiçbir task seçili değilse capture yine yapılır, ama kullanıcı bir kez uyarılır ("Hiçbir after-capture task seçili değil").
R2.9 Hata izolasyonu: her task ayrı do/catch içinde çalışır; biri hata verirse diğerleri devam eder. Hatalar os.Logger ile loglanır ve tek bir özet bildirimiyle gösterilir.
R2.10 Sıra: saveToFile → copyToClipboard → revealInFinder → showNotification.

R3 – Son region'ı hatırlama
R3.1 Başarılı her region capture sonrasında şunlar saklanır: displayUUID (CGDisplayCreateUUIDFromDisplayID ile alınan string), rect (display-local, sol-üst orijinli, point cinsinden), display point boyutu ve zaman damgası. UserDefaults içinde Codable JSON olarak tutulur. Space ve ~ ile yapılan tam ekran capture'lar last region'ı GÜNCELLEMEZ.
R3.2 Normal region hotkey'inde overlay açılınca, last region varsa ve ekranı bağlıysa ilgili ekranda soluk (yaklaşık %40 opak, kesikli) çizilir. Enter ile bu rect kabul edilir ve capture yapılır. Yeni bir sürükleme ön çizimi geçersiz kılar. Quick capture kapalıysa ön çizim doğrudan düzenlenebilir seçim olarak gelir.
R3.3 Ayrı "Capture last region" hotkey'i, varsayılan ⌥⇧5: overlay AÇMADAN yalnızca ilgili ekranı çeker (R1.1 ile aynı yol), saklı rect'i keser ve after-capture task'larını çalıştırır. Menüde de aynı komut bulunur.
R3.4 Fallback: UUID'ye ait ekran bağlı değilse, ya da rect güncel ekran sınırlarının dışına taşıyorsa (ör. çözünürlük değişmişse), doğrudan capture YAPILMAZ. Bunun yerine normal overlay açılır ve kısa bir HUD metni gösterilir ("Son bölge bu ekran düzeninde geçerli değil").
R3.5 Last region yoksa ⌥⇧5 normal overlay'i açar.

R4 – İzin onboarding
R4.1 İlk açılışta ve her capture denemesinden önce CGPreflightScreenCaptureAccess() kontrol edilir. false ise onboarding penceresi açılır: neden gerektiğini anlatan bir metin, "İzin iste" (CGRequestScreenCaptureAccess), "Sistem Ayarları'nı aç" (x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture) ve "Uygulamayı yeniden başlat" butonları. Preflight sonucu process ömrü boyunca değişmeyebileceği için relaunch adımı ŞART.
R4.2 İzin yokken veya capture hata verdiğinde boş, siyah ya da yalnızca duvar kağıdı içeren bir görüntü KAYDEDİLMEZ, panoya da yazılmaz. SCScreenshotManager hatası yakalanır ve kullanıcıya anlaşılır bir mesaj gösterilir.
R4.3 macOS Sequoia ve sonrasında sistem periyodik olarak yeniden onay isteyebilir. Bu bir hata değildir; README'de belirt.

R5 – Ayarlar penceresi (SwiftUI)
R5.1 Hotkey'ler: KeyboardShortcuts.Recorder ile "Capture region" (varsayılan ⌥⇧4) ve "Capture last region" (varsayılan ⌥⇧5).
R5.2 Kayıt klasörü: mevcut yol, "Değiştir…" ve "Varsayılana dön" butonları.
R5.3 After-capture checkbox'ları (R2.1 ile aynı state).
R5.4 Quick capture toggle (varsayılan açık), Büyüteç toggle (varsayılan açık).
R5.5 Launch at login toggle: SMAppService.mainApp.register() / unregister(). Gösterilen durum SMAppService.mainApp.status'tan okunur; requiresApproval durumunda kullanıcıya açıklama yapılır.
R5.6 İzin durumu satırı ve "Onboarding'i aç" butonu.

HOTKEY RİSKİ (zorunlu ele alınacak):
macOS 15.0–15.1'de sandbox'lı uygulamalarda yalnızca Option veya Option+Shift modifier'ı kullanan RegisterEventHotKey kayıtları çalışmıyordu (-9868 hatası). Bu kısıtlama 15.2'de geri alındı. Secure input açıkken de bu tür kısayollar tetiklenmeyebilir. Yapılacaklar:
- Kayıt sonrasında kısayolun gerçekten kaydedilip kaydedilmediğini tespit et. KeyboardShortcuts bunu bildirmiyorsa, aynı kombinasyonu açılışta tek seferlik bir RegisterEventHotKey/UnregisterEventHotKey denemesiyle doğrulayan küçük bir yardımcı yaz.
- Kayıt başarısızsa ayarlarda uyarı göster ve tek tıkla yedek kısayola geç: ⌃⇧4 ve ⌃⇧5.
- ⌘⇧3/4/5 sistem kısayollarıyla çakışma uyarısı KeyboardShortcuts.Recorder'dan gelir; buna dokunma.

=== MİMARİ ÖNERİSİ (CC değiştirebilir, gerekçe yazarak) ===
App/ (AppDelegate, StatusItemController, Hotkeys)
Capture/ (ScreenSnapshotService: SCK ile ekran başına CGImage alır; DisplayInfo: id, uuid, frame, scale)
Overlay/ (OverlayPanel, OverlayView, SelectionStateMachine (saf, testlenebilir), MagnifierView)
Geometry/ (CaptureGeometry: koordinat dönüşümü, clamp, piksel yuvarlama; saf fonksiyonlar)
Output/ (FileNamer, ImageWriter, AfterCaptureRunner, ClipboardWriter, Notifier)
Persistence/ (SettingsStore, LastRegionStore, FolderBookmarkStore)
Settings/ (SwiftUI görünümleri)
Onboarding/

=== TEST GEREKSİNİMLERİ ===
Unit test (XCTest veya Swift Testing):
- Koordinat ve scale dönüşümü: global NSScreen rect ↔ display-local sol-üst point rect ↔ piksel rect. 1x, 2x ve kesirli scale (ör. 1.5 veya scaled modlar); negatif origin'li ikincil ekran (sola veya üste yerleştirilmiş monitör); dikey yerleşim.
- Kesim matematiği: yuvarlama kuralı (floor/ceil), görüntü sınırına clamp, sıfır veya negatif boyutun reddi, tek ekrana clamp (çapraz sürükleme).
- Selection state machine: quick capture açık/kapalı; Shift ile kare; ok tuşlarıyla 1/10 px; Esc; Enter; Delete.
- Dosya adı üretimi: sabit Date ve TimeZone ile beklenen ad ve yyyy-MM klasörü; çakışmada _2, _3; yıl ve ay sınırı.
- Region persistence: encode/decode; UUID eşleşmesi; ekran yokken fallback kararı; rect sınır dışındayken fallback kararı; tam ekran capture'ın last region'ı güncellememesi.
- AfterCaptureRunner: bir task hata verdiğinde diğerlerinin çalışması (mock'larla); saveToFile kapalıyken revealInFinder'ın atlanması.

Manuel test checklist'i (repo içinde docs/manual-test.md olarak oluştur ve F4 sonunda doldur):
[ ] Tek Retina ekran: region, kesimin piksel doğruluğu (bilinen bir UI öğesinin boyutuyla karşılaştır)
[ ] Retina dahili ekran + 1x harici ekran: her iki ekranda capture, keskinlik, doğru boyut
[ ] Harici ekran ana ekranın soluna/üstüne yerleştirilmiş (negatif koordinat)
[ ] İki ekran arasında sürükleme → başlangıç ekranına clamp
[ ] Farklı bir Space'te capture
[ ] Full-screen bir uygulamanın (Safari, Keynote sunumu) üzerinde overlay görünüyor ve capture çalışıyor
[ ] Açık bir menü (ör. bir uygulamanın File menüsü) ve tooltip/hover durumu dondurulmuş karede yakalanıyor
[ ] Overlay, menu bar menüsü veya ayarlar penceresi çıktıda görünmüyor
[ ] Esc ile iptal edildiğinde dosya ve pano değişmiyor
[ ] Quick capture kapalı: taşıma, boyutlandırma, Enter, çift tık
[ ] Space ve ~ kısayolları
[ ] ⌥⇧5: overlay açılmadan aynı bölge; harici ekran çıkarılmışken overlay fallback
[ ] Uygulama yeniden başlatıldıktan sonra last region'ın korunması
[ ] İzin kaldırıldığında boş görüntü kaydedilmemesi ve onboarding'in açılması
[ ] Klasörün Pictures dışına taşınması, uygulamanın yeniden başlatılması, kaydın hâlâ çalışması (bookmark)
[ ] Launch at login açık/kapalı, reboot sonrası
[ ] Hotkey kaydı başarısız senaryosu (macOS 15.0/15.1 makine varsa) ve yedek kısayol

=== DEFINITION OF DONE ===
- R1–R5'in tamamı karşılanmış; F0–F4 ayrı commit'lerde.
- xcodebuild build ve test, uyarı patlaması olmadan yeşil; unit testler yukarıdaki listeyi kapsıyor.
- docs/manual-test.md oluşturulmuş; CC'nin kendi makinesinde koşabildiği maddeler işaretli, koşamadıkları "manuel bekliyor" olarak listelenmiş.
- README: kurulum (xcodegen generate, team ayarı), izin akışı, hotkey riski, bilinen sınırlar, mimari özeti.
- CGWindowListCreateImage veya legacy capture API'si kod tabanında yok (grep ile doğrula ve raporda belirt).
- KeyboardShortcuts dışında bağımlılık yok.
- Son raporda: yapılanlar, ölçülen overlay gecikmesi, bilinen sorunlar, v2 önerileri (window snapping, hotkey bazında task seti, annotation).
```

## D) Açık sorular

1. **Uygulamanın adı ne olsun?** Seçenekler: (a) "MacShot" kalsın; (b) başka bir ad (yaz); (c) şimdilik "MacShot", sonra değiştiririz. Bundle id `com.<senin-alan-adın>.<ad>` olacak; alan adını da yaz.
2. **Dağıtım hedefi ne?** (a) Yalnızca kişisel kullanım: sandbox açık kalır ama App Store kurallarına uyma zorunluluğu yok; (b) ileride Mac App Store: sandbox zorunlu, varsayılan hotkey atanmaz, kullanıcıya ilk açılışta seçtirilir (KeyboardShortcuts README'si yayınlanan uygulamalarda varsayılan kısayol atamamayı öneriyor);\[36\] (c) App Store dışında notarize edilmiş dağıtım: sandbox'ı kapatma seçeneği açılır.
3. **Varsayılan hotkey'ler ne olsun?** (a) Region ⌥⇧4, last region ⌥⇧5; macOS 15.0–15.1'de çalışmazsa otomatik olarak ⌃⇧4 ve ⌃⇧5'e düşülür; (b) baştan ⌃⇧4 ve ⌃⇧5 (her sürümde güvenli); (c) sistemin ⌘⇧4'ünü kapatıp onu kullanmak (sistem ayarından elle kapatman gerekir); (d) başka (yaz). Seçim sırasında "taşıma" modifier'ı ShareX'teki Ctrl'nin karşılığı olarak ⌃ mı olsun, ⌥ mi?
4. **Varsayılan after-capture seçimi ne olsun?** (a) Kaydet + panoya kopyala; (b) yalnızca kaydet; (c) yalnızca panoya kopyala; (d) kaydet + panoya kopyala + bildirim göster. Ek olarak: hem kaydet hem kopyala seçiliyken panoya görüntüyle birlikte dosya referansı da eklensin mi (evet/hayır)?
5. **CC fazlar arasında onay beklesin mi?** (a) Hayır, yalnızca blocker'da dursun (bloktaki varsayılan); (b) evet, her faz sonunda rapor verip GO beklesin; (c) yalnızca F1 sonunda dursun (freeze ve kesimi elle doğrulamak için), sonrasını kendi bitirsin.
6. **Xcode projesi repoya commit edilsin mi?** (a) Hayır, yalnızca `project.yml` commit edilir ve `.xcodeproj` gitignore'a eklenir; (b) evet, üretilmiş `.xcodeproj` da commit edilir.
7. **Apple Developer Team ID'n var mı?** (a) Evet (değeri ver); (b) yalnızca ücretsiz Apple ID ile "Personal Team"; (c) yok. TCC izninin her build'de sıfırlanmaması için en az (b) gerekiyor.

## Caveats

- **Option+Shift hotkey kısıtlaması:** Apple'ın bir Frameworks mühendisi Developer Forums'taki 763878 numaralı konuda bu kısıtlamayı şöyle açıkladı: "This was an intentional change in macOS Sequoia to limit the ability of key-logging malware to observe keys in other applications". Gerekçe, Shift+Option ile parolalarda Ø gibi alternatif karakterler üretilebilmesi. Feedback Assistant kaydı (FB15168205) "Fixed" olarak kapandı. Matthias Gansrigler de Eternal Storms blogundaki güncellenmiş yazısında "option-based keyboard shortcuts are allowed again for sandboxed 3rd-party apps on macOS Sequoia 15.2" diyor. Geliştirici fifafu ise sindresorhus/KeyboardShortcuts issue #176'da (24.10.2024) şunu bildiriyor: "While secure input mode is active even non-sandboxed apps can not make use of shortcuts that consist of single keys, opt+key or shift+opt+key anymore." Bu yüzden yedek kısayol mantığı zorunlu tutuldu.
- **TCC davranışı:** Preflight'ın relaunch'a kadar false dönmesi Apple'ın resmî referansında yazmıyor. Developer Forums'taki bir geliştirici raporuna ve 2026 tarihli bağımsız GitHub testlerine dayanıyor.\[41\]\[42\] Sequoia'daki periyodik yeniden onay 15.0'da aylık olarak geldi. 15.1'de Apple, beta 6 sürüm notlarında (9to5Mac'in 07.10.2024 tarihli aktarımı) bunu gevşetti: "Users will see fewer dialogs if they regularly use apps in which they have already acknowledged and accepted the risks." Kesin süre Apple tarafından belgelenmedi.
- **ShareX "Last region" kalıcılığı:** Son region'ın yalnızca oturum boyunca tutulduğu, 2015 dönemi kaynaktaki static alana dayanan bir çıkarım.\[20\] Güncel `CaptureLastRegion.cs` okunamadı. Bu, planı etkilemiyor çünkü bizim gereksinimimiz zaten kalıcı saklama.
- **Display UUID kararlılığı:** UUID'nin reboot sonrasında değişebildiği tek bir üçüncü taraf projenin iddiası.\[40\] R3.4'teki overlay fallback'i bu riski kullanıcı açısından zararsız hâle getiriyor.
- **Açık kaynak referanslar:** Screenshot Pro (MIT, ScreenCaptureKit, freeze-frame overlay, last region, SMAppService; macOS 15+), macshot (Swift + AppKit, hotkey ile ekranı donduruyor), Mio (GPL-3.0, macOS 15+) ve shotty (MIT, yaklaşık 400 satır tek dosya) mimari fikir için faydalı.\[18\]\[43\]\[44\]\[45\] GPL lisanslı kodun kopyalanmaması bloğa kural olarak yazıldı.
- **Shottr'ın freeze modu:** Shottr'ın donduran area capture'ı geliştiricisine göre "experimental". Shottr asıl olarak tam ekran alıp sonra kırpma akışı üzerine kurulu.\[46\]\[47\] Yani bizim freeze yaklaşımımız ticari bir rakibe göre de bilinçli bir tercih, ama F1 sonunda gecikmeyi ölçmek önemli.

## Sources

1. [Keyboard Shortcuts using Option and/or Shift Modifiers Only No Longer Allowed on macOS Sequoia \[Updated for macOS 15.2\]](https://blog.eternalstorms.at/2024/09/23/keyboard-shortcuts-using-option-and-or-shift-modifiers-only-no-longer-allowed-on-macos-sequoia/)
2. [FB15168205: Global keyboard shortcuts (RegisterEventHotKey) with only Option or Option+Shift as modifiers do not work on macOS 15 · Issue #552 · feedback-assistant/reports · GitHub](https://github.com/feedback-assistant/reports/issues/552)
3. [GitHub - Fidetro/CapturingScreenContentInMacOS: Capturing Screen Content In MacOS Apple sample code · GitHub](https://github.com/Fidetro/CapturingScreenContentInMacOS)
4. [developer.apple.com](<https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:excludingapplications:exceptingwindows:).md>)
5. [\[FIXED\] JUCE not compiling in sequoia 15.0 - MacOSX and iOS - JUCE](https://forum.juce.com/t/fixed-juce-not-compiling-in-sequoia-15-0/62868)
6. [Shottr](https://shottr.cc/)
7. [App to take repeated screen shots](https://forums.macrumors.com/threads/app-to-take-repeated-screen-shots.2413823/)
8. [Region Capture - ShareX](https://getsharex.com/docs/region-capture)
9. [Keybinds - ShareX](https://getsharex.com/docs/keybinds)
10. [Region Capture](https://deepwiki.com/ShareX/ShareX/3.1-region-capture)
11. [github.com](https://github.com/danielbisson56/ShareXBetterCodeHub/blob/master/Enums.cs)
12. [Feature request : Audio only capture · Issue #7816 · ShareX/ShareX · GitHub](https://github.com/ShareX/ShareX/issues/7816)
13. [gist.github.com](https://gist.github.com/AlanD20/64242de46e36c98b8f8d683190bd8669)
14. [request: date in file names · Issue #8143 · ShareX/ShareX · GitHub](https://github.com/ShareX/ShareX/issues/8143)
15. [ShareX/ShareX/ApplicationConfig.cs at master · ShareX/ShareX · GitHub](https://github.com/ShareX/ShareX/blob/master/ShareX/ApplicationConfig.cs)
16. [ShareX/README.md at master · Upload/ShareX · GitHub](https://github.com/Upload/ShareX/blob/master/README.md)
17. [Website: getsharex.com](https://github.com/k3d3/ShareX)
18. [GitHub - iSoldLeo/Mio: A native macOS screenshot tool that freezes every display in under 80 ms when you press the hotkey — pick a window, a region, or a whole screen from still frames. Window captures keep their transparent rounded corners. Built-in editor for annotations. Menu bar only, fully offline. · GitHub](https://github.com/iSoldLeo/Mio)
19. [github.com](https://github.com/banksymate/ShareX)
20. [ShareX/ShareX.ScreenCaptureLib/Forms/Surface.cs at master · Upload/ShareX · GitHub](https://github.com/Upload/ShareX/blob/master/ShareX.ScreenCaptureLib/Forms/Surface.cs)
21. [github.com](https://github.com/ShareX/ShareX/issues/1663)
22. [How to Screenshot on Mac Beyond Simply Holding ⇧, ⌘, 3 or 4](https://www.raycast.com/resources/how-to-screenshot-on-mac)
23. [Test on macOS: Record Screen picker (CleanShot-style) · Issue #55 · jsonify/skreener2 · GitHub](https://github.com/jsonify/skreener2/issues/55)
24. [URL Scheme (deeplinks)](https://shottr.cc/kb/urlschemes)
25. [developer.apple.com](<https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(in:completionhandler:).md>)
26. [screencapturekit - Rust](https://doom-fish.github.io/screencapturekit-rs/screencapturekit/)
27. [github.com](https://github.com/vinceglb/FileKit/issues/590)
28. [stopAccessingSecurityScopedResource](https://developer.apple.com/forums/thread/84951)
29. [Understanding File System Access in macOS Sandboxed Applications](https://codebit-inc.com/blog/mastering-file-access-macos-sandboxed-apps/)
30. [\[macOS\] Screen capture is half resolution on Retina displays (ScreenCaptureKit is configured in points) · Issue #2241 · flutter-webrtc/flutter-webrtc · GitHub](https://github.com/flutter-webrtc/flutter-webrtc/issues/2241)
31. [fix(screenshot): Retina 屏幕下 ScreenCaptureKit 截图分辨率按逻辑点输出导致模糊 · Issue #8 · Danyhug/DH-TransShot · GitHub](https://github.com/Danyhug/DH-TransShot/issues/8)
32. [fix(macos): capture ScreenCaptureKit screens at their pixel size by FlyHubs · Pull Request #2242 · flutter-webrtc/flutter-webrtc · GitHub](https://github.com/flutter-webrtc/flutter-webrtc/pull/2242)
33. [fix(macos): keep the overlay visible over full-screen presentations by matteobaccan · Pull Request #10 · matteobaccan/Ritardometro · GitHub](https://github.com/matteobaccan/Ritardometro/pull/10)
34. [collectionbehavior swift.struct](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct.md)
35. [Overlay on macOS Full-Screen Apps with AppKit \[Fixed\]](https://www.technetexperts.com/macos-python-fullscreen-overlay-fix/)
36. [KeyboardShortcuts/readme.md at main · sindresorhus/KeyboardShortcuts · GitHub](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/readme.md)
37. [Add launch at login setting to a macOS app](https://nilcoalescing.com/blog/LaunchAtLoginSetting/)
38. [Manage login items and background tasks on Mac - Apple Support (GU)](https://support.apple.com/en-gu/guide/deployment/depdca572563/web)
39. [feat(M1-22): let Show on pick a connected display, Sidecar iPads included by taroj1205 · Pull Request #159 · taroj1205/mado · GitHub](https://github.com/taroj1205/mado/pull/159)
40. [GitHub - KevinLogan84/Window-Minder: Menu bar app that saves and restores window positions for each display setup. · GitHub](https://github.com/KevinLogan84/Window-Minder)
41. [feat: macOS capture, input and permission checks (#72) by mendsec · Pull Request #140 · barahn/remotekit · GitHub](https://github.com/barahn/remotekit/pull/140)
42. [Understanding CGRequestScreenCaptu…](https://developer.apple.com/forums/thread/732726)
43. [GitHub - CreativeLyons/screenshot-pro: Free, open source screenshot tool for macOS on Apple silicon: capture, annotate, share. · GitHub](https://github.com/CreativeLyons/screenshot-pro)
44. [GitHub - uuu4/shotty: Open source screenshot tool for macOS in 393 lines of Swift. Freeze the screen, select an area, draw on it before it is copied anywhere, and OCR it with the indentation intact. No dependencies, no account, no network calls. · GitHub](https://github.com/uuu4/shotty)
45. [github.com](https://github.com/sw33tLie/macshot)
46. [Shottr Mac Screenshot Tool: Fast, Free, Pixel-Perfect (2026)](https://www.bitdoze.com/shottr-mac-screenshot-tool/)
47. [Frequently Asked Questions](https://shottr.cc/kb/faq)
