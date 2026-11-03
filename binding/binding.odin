package binding

// OdinBinder contract. These declarations are parsed by tools/odinbinder;
// they are not compiled into the app. Implement exports in app/bridge.odin.

@(odinbinder={
    name = "bridge",
    android_package = "dev.alfayez.odinsokol",
    android_class = "OdinBridge",
    ios_module = "OdinBridge",
})
_config :: struct {}

@(odinbinder={direction="export"})
hello :: proc "c" () -> cstring

@(odinbinder={direction="import", thread="ui"})
show_toast :: proc "c" (msg: cstring)
