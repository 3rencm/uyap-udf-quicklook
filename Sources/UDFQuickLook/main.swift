import Cocoa

// UYAP UDF Önizleme — ana uygulama.
//
// Uygulama, QuickLook Preview Extension'ı barındırır ve açılışta eklentiyi
// PlugInKit'e kendisi kaydeder; kullanıcıdan hiçbir terminal komutu gerekmez.
//
// Uygulamanın sandbox'lanmaması bilinçlidir: sandbox'lanan bir süreç,
// `pluginkit` aracılığıyla PlugInKit daemon'ına (com.apple.pluginkit.pkd)
// bağlanamaz. Extension'ın kendisi (appex) ayrıca sandbox'lıdır.

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
