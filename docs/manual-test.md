# Manuel test checklist'i

Ortam: macOS 27.0 (Darwin 27.0.0), tek Retina ekran (dahili). Build: Debug, Apple Development imzalı, sandbox açık.
İşaretler: `[x]` koşuldu ve geçti · `[ ]` manuel bekliyor · not satırında kim/nasıl.

- [x] Tek Retina ekran: region capture çalışıyor, dosya kaydediliyor — kullanıcı 31.10.2026 doğruladı (610×228 ve 652×621 px PNG)
- [x] F4 build genel kullanım — kullanıcı 31.10.2026 "çalışıyor" dedi (madde madde değil; aşağıdaki işaretsizler ayrıca teyit bekliyor)
- [ ] Kesimin piksel doğruluğu (bilinen boyutlu UI öğesiyle karşılaştırma) — manuel bekliyor; unit test 1x/2x/1.5x kapsıyor
- [ ] Retina dahili + 1x harici ekran: iki ekranda capture, keskinlik, doğru boyut — harici ekran yok, manuel bekliyor
- [ ] Harici ekran ana ekranın soluna/üstüne (negatif koordinat) — manuel bekliyor; unit test kapsıyor
- [ ] İki ekran arasında sürükleme → başlangıç ekranına clamp — manuel bekliyor
- [ ] Farklı bir Space'te capture — manuel bekliyor
- [ ] Full-screen uygulama (Safari, Keynote sunumu) üzerinde overlay ve capture — manuel bekliyor
- [ ] Açık menü ve tooltip/hover dondurulmuş karede yakalanıyor — manuel bekliyor
- [ ] Overlay, menu bar menüsü, ayarlar penceresi çıktıda görünmüyor — manuel bekliyor
- [ ] Esc ile iptal: dosya ve pano değişmiyor — manuel bekliyor
- [ ] Quick capture kapalı (varsayılan): taşıma, boyutlandırma, Enter, çift tık — manuel bekliyor
- [ ] ⌘C: yalnız pano, dosya oluşmuyor; son bölge güncelleniyor — manuel bekliyor
- [ ] Quick capture açık: bırakınca anında capture — manuel bekliyor
- [ ] Space ve ~ kısayolları — manuel bekliyor
- [ ] Büyüteç: 15×15 px, 8x, ızgara, merkez piksel kırmızı; ekran kenarında yön değiştiriyor; ayardan kapanıyor — manuel bekliyor
- [ ] After capture: menü checkbox'ları ve ayarlar aynı durumu gösteriyor; Finder'da göster; bildirim ve bildirime tıklayınca Finder — manuel bekliyor
- [ ] Hiç task seçili değil uyarısı (oturumda bir kez) — manuel bekliyor
- [ ] ⌥⇧5: overlay açılmadan aynı bölge — manuel bekliyor
- [ ] ⌥⇧5: harici ekran çıkarılmışken overlay + HUD fallback — harici ekran yok, manuel bekliyor
- [ ] Uygulama yeniden başlatıldıktan sonra last region korunuyor — manuel bekliyor
- [ ] İzin kaldırıldığında boş görüntü kaydedilmiyor, onboarding açılıyor — manuel bekliyor
- [ ] Klasör Pictures dışına taşındı, uygulama yeniden başladı, kayıt hâlâ çalışıyor (bookmark) — manuel bekliyor
- [ ] Launch at login açık/kapalı, reboot sonrası — manuel bekliyor
- [ ] Hotkey kaydı başarısız senaryosu ve yedek kısayol — macOS 15.0/15.1 makine yok, manuel bekliyor

## Claude'un koştuğu otomatik kontroller

- [x] `xcodebuild build` ve `test`: 62/62 test yeşil, koddan gelen uyarı yok
- [x] İmza: Apple Development (Team 4SFTG4T5YD); entitlement'lar: app-sandbox, assets.pictures.read-write, files.user-selected.read-write, files.bookmarks.app-scope
- [x] Legacy capture API taraması (`CGWindowListCreateImage`, `CGDisplayCreateImage`): kullanım yok
- [x] Gecikme (hotkey → overlay görünür), 1 ekran: ilk 160 ms, sonraki 72 ms (hedef 2 ekranda < 250 ms; 2 ekran ölçülemedi)
